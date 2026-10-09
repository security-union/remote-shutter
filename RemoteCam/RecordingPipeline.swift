//
//  RecordingPipeline.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation
import AVFoundation
import Photos
import CoreImage

/// Single-point storage policy for recording video. Pure, pinned by unit
/// tests — the one place a free-space number becomes a go/no-go decision.
enum RecordingStoragePolicy {
    /// Minimum available capacity to start a video recording.
    static let minimumFreeBytesToStart: Int64 = 100_000_000

    /// `freeBytes` is `volumeAvailableCapacityForImportantUsage` — the space
    /// the system will actually grant a user-initiated write (raw free blocks
    /// plus purgeable space it reclaims on demand), which is also the number
    /// Settings shows the user. nil = the capacity could not be read; that
    /// never blocks the user (fail open — the writer-death funnel is the
    /// backstop if the disk really is full).
    static func canStart(freeBytes: Int64?) -> Bool {
        guard let freeBytes else { return true }
        return freeBytes >= minimumFreeBytesToStart
    }
}

/**
 Owns the video-recording path: the asset writer, its inputs, the recording
 state machine, per-frame writing/cropping, and saving/sending the finished
 movie. Non-UI — the frame streaming coordinator feeds it sample buffers, and
 the rig/shell reach back in through the closure seams below.

 One lifecycle, two ways to write the file. Every take is written by our
 asset writer, except Editable Cinematic, which the engine's movie file
 output writes (`MovieTakeRecording`) because only it records the disparity
 and Cinematic metadata Photos re-focuses. Arming, the start ack, the stop
 protocol, the watchdogs, saving/sending and the failure funnel are shared;
 only "start writing" and "finish the file" differ.

 Threading: ALL recording state lives on the engine's `dataOutputQueue` — the
 same serial queue that delivers both video and audio sample buffers, so
 `processFrame` is naturally serialized. Record start syncs once into the
 engine's `sessionQueue` for the audio-input configuration (one-way; the
 session queue never syncs back). The only cross-queue reads are through
 `recordingStartedAt`/`isRecording`, backed by one `Locked<Date?>`.
 */
class RecordingPipeline {

    /// The capture session, outputs, queues and configuration live on the engine.
    private let engine: CaptureEngine

    private var dataQueue: DispatchQueue { engine.dataOutputQueue }

    // MARK: - UI/actor seams

    /// Relays actor messages (`StartRecordingVideoAck`, `StopRecordingVideoResp`,
    /// `SendVideoResource`) — the pipeline never touches the actor system directly.
    var sendMessage: ((Message) -> Void)?
    /// Recording actually began (first frames written). Main thread. The ack to the
    /// monitor is sent through `sendMessage` right after this fires.
    var onRecordingStarted: ((Date) -> Void)?
    /// Recording is stopping — clear the timer display. Main thread.
    var onRecordingStopped: (() -> Void)?
    /// Chrome update: `idle == true` → idle mode, else video-recording mode. Main thread.
    var onModeChanged: ((_ idle: Bool) -> Void)?
    /// Unrecoverable start failure ("Unable to start recording"). Fires on the
    /// data queue — hop to main before touching UIKit.
    var onError: ((String) -> Void)?
    /// Photos-library access denied while saving the finished movie. Main thread.
    var onPhotosAccessDenied: (() -> Void)?

    // MARK: - Recording state (dataQueue-confined)

    /// The recording's real start instant — non-nil exactly while the writer
    /// is accepting frames, and the ONLY stored recording truth. Everything
    /// else derives from it: `isRecording`, the wire's
    /// `recording_start_unix_ms` (nil ⇔ 0), the cross-queue readers
    /// (`shouldAutorotate` on main, `setVideoQuality`'s guard on the actor
    /// mailbox, watch snapshots), and both timers. Lock-backed so those
    /// readers never touch the data queue.
    private let recordingStartShared = Locked<Date?>(nil)
    var isRecording: Bool { recordingStartShared.value != nil }
    var recordingStartedAt: Date? { recordingStartShared.value }

    private(set) var recordingWillBeStarted: Bool = false
    private(set) var recordingWillBeStopped: Bool = false
    private var readyToRecordVideo: Bool = false
    private var readyToRecordAudio: Bool = false
    /// Ties each arming watchdog to its own start, so a stale timer can never
    /// fail a later take. dataQueue-confined.
    private var armingGeneration = 0
    private static let armingTimeout: TimeInterval = 5
    /// Fragmented writing keeps finalize cheap — a healthy one is sub-second;
    /// ten covers a struggling disk without stalling the user forever.
    /// Instance-var so tests can shrink the watchdog window.
    var finalizeTimeout: TimeInterval = 10

    /// Finalize seam: production calls the writer's own `finishWriting`;
    /// tests swap in a closure that never calls back to reproduce the
    /// suspended-finalize shape (the process slept mid-finalize and the
    /// completion was lost with it) deterministically.
    lazy var finalizeWriter: (AVAssetWriter, @escaping () -> Void) -> Void = { writer, done in
        writer.finishWriting(completionHandler: done)
    }

    /// What writes the current take's file: our asset writer (every take,
    /// Baked Cinematic included) or, for Editable Cinematic, a movie take on
    /// the engine's movie file output. Exactly one is set while a take is
    /// armed or rolling; everything else in the lifecycle is shared.
    private var assetWriter: AVAssetWriter?
    private var movieTake: MovieTakeRecording?
    /// Whether the stop in flight should send the clip to the peer — held
    /// for the movie take, whose finish arrives through its own callback.
    private var stopSendsVideo = false
    private(set) var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private(set) var cachedVideoCropRect: CGRect? // Computed once at recording start, reused per frame

    /// Aspect ratio snapshotted from the engine when recording starts — the
    /// writer geometry must not chase a mid-recording aspect change.
    var recordingAspectRatio: AspectRatio = .sixteenNine

    /// Set for a synced multicam recording only: embeds the shot's alignment
    /// fields as QuickTime metadata in the .mov and names the saved clip
    /// `RS_<sess>_<cap>_cam<k>.mov`. Nil for ordinary single-camera recording,
    /// which writes and saves exactly as before. Consumed (cleared) when the
    /// clip is saved.
    var pendingSyncMetadata: CaptureSyncMetadata?

    private let videoCropContext = CIContext(options: [.useSoftwareRenderer: false])

    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput!

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    /// Seam for the audio-configuration leg. Tests pin it (simulators differ
    /// on whether an audio capture device exists); production configures the
    /// engine's audio input on its session queue.
    lazy var configureAudio: (AVCaptureAudioDataOutputSampleBufferDelegate) -> Bool = { [weak self] delegate in
        self?.engine.configureAudioForRecording(delegate: delegate) ?? false
    }

    /// Seam for the storage gate (tests pin the refusal deterministically);
    /// production reads the recording volume's important-usage capacity.
    lazy var freeSpaceForRecording: () -> Int64? = {
        RecordingPipeline.availableCapacity(at: movieUrl())
    }

    /// Seam for the recorder choice: the engine's movie file output while
    /// Editable Cinematic is on, else nil (the asset writer records). Read
    /// once per take; the engine hops into the session queue, which owns it.
    lazy var cinematicMovieOutput: () -> AVCaptureMovieFileOutput? = { [weak self] in
        self?.engine.cinematicMovieOutputForRecording()
    }

    /// Seam for the Editable take (tests substitute a fake). The callbacks
    /// may fire on any queue.
    lazy var makeMovieTake: (_ output: AVCaptureMovieFileOutput, _ url: URL,
                             _ onStarted: @escaping (CMTime) -> Void,
                             _ onFinished: @escaping (Error?, Bool) -> Void) -> MovieTakeRecording
        = { [weak self] output, url, onStarted, onFinished in
            CinematicMovieRecorder(output: output, url: url,
                                   sessionQueue: self?.engine.sessionQueue ?? DispatchQueue(label: "orphaned movie take"),
                                   onStarted: onStarted, onFinished: onFinished)
        }

    /// The clock capture timestamps are on — for the first-frame sync
    /// offset. nil = host time.
    lazy var sessionClock: () -> CMClock? = { [weak self] in
        guard let session = self?.engine.captureSession else { return nil }
        if #available(iOS 15.4, macCatalyst 15.4, *) { return session.synchronizationClock }
        return nil
    }

    // MARK: - Start / stop

    /// Configures the audio leg (on the engine's session queue) and starts
    /// recording. The caller's coordinator remains the audio delegate.
    func startRecording(audioSampleBufferDelegate: AVCaptureAudioDataOutputSampleBufferDelegate) {
        // Timestamped BEFORE the enqueue, so the console separates "enqueued
        // late" from "enqueued promptly but the queue was blocked" — the
        // begin tap below closes the bracket.
        SessionDebug.pipelinePhase("start: enqueuing to data queue")
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            SessionDebug.pipelinePhase("start: begin")
            if self.recordingWillBeStarted || self.isRecording {
                SessionDebug.pipelinePhase("start: ignored — already started/starting")
                return
            }

            // Refuse to start on a nearly full disk — the writer would die
            // mid-take instead of failing cleanly here. One upfront check, no
            // polling; the writer-death funnel below covers the disk filling
            // AFTER a legitimate start.
            guard RecordingStoragePolicy.canStart(freeBytes: self.freeSpaceForRecording()) else {
                self.failRecording(Self.localizedRecordingError("insufficient_storage_error"),
                                   hasClip: false)
                return
            }

            // One-way hop: data queue may sync into the session queue, never
            // the reverse. No usable microphone (hardware missing, or the
            // audio session is held — e.g. an active phone call): refuse to
            // record rather than silently produce soundless video the user
            // only discovers at playback. The session states route this to
            // error acks on the remote and an error alert on the camera.
            SessionDebug.pipelinePhase("start: storage ok, configuring audio")
            guard self.configureAudio(audioSampleBufferDelegate) else {
                let message = NSLocalizedString("Unable to record audio", comment: "")
                self.sendMessage?(UICmd.MicrophoneAccessDenied(error: NSError(
                    domain: "RemoteShutterError", code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: message])))
                self.onError?(message)
                return
            }
            SessionDebug.pipelinePhase("start: audio configured")
            self.recordingAspectRatio = self.engine.currentAspectRatioValue()

            self.startVideoRecordingProcess()
        }
    }

    private func startVideoRecordingProcess() {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        if self.recordingWillBeStarted || self.isRecording {
            return
        }

        // A previous take that was never reaped — its finalize completion
        // died with a suspension — leaves ALL its per-take state behind: the
        // stop latch (which would silently swallow THIS take's stop), the
        // ready-edge flags (which would keep this take's writer from ever
        // being configured), and the dead writer itself. Arming a new take
        // reclaims the whole carcass with the one shared reset; the finalize
        // completion is identity-guarded, so a zombie completion arriving
        // later can never corrupt this take.
        if self.recordingWillBeStopped {
            self.resetRecordingState()
        }
        self.recordingWillBeStarted = true

        // Arming watchdog: if the ready edge never comes (an interrupted
        // audio session after backgrounding can starve the audio leg), fail
        // loudly instead of arming forever — the failure funnel resets state,
        // tells the coordinator, and the camera settles back to idle able to
        // record again.
        armingGeneration += 1
        let generation = armingGeneration
        dataQueue.asyncAfter(deadline: .now() + Self.armingTimeout) { [weak self] in
            guard let self, self.armingGeneration == generation,
                  self.recordingWillBeStarted, !self.isRecording else { return }
            self.failRecording(Self.localizedRecordingError("Unable to start recording"),
                               hasClip: false)
        }

        // Remove the file if one with the same name already exists
        let outputFilePath = movieUrl()
        cleanupFileAt(outputFilePath)
        // Editable Cinematic: the movie file output writes this take. It
        // reports its own start; the arming watchdog above covers it too.
        if let movieOutput = cinematicMovieOutput() {
            armMovieTake(on: movieOutput, url: outputFilePath)
            SessionDebug.pipelinePhase("start: movie take armed, awaiting its start")
            OperationQueue.main.addOperation { [weak self] in
                self?.onModeChanged?(false)
            }
            return
        }
        // Create an asset writer
        do {
            let writer = try AVAssetWriter(outputURL: outputFilePath, fileType: .mov)
            // Fragmented QuickTime: without this an interrupted take (disk
            // full, crash, kill) has no moov atom and is unplayable — with it
            // the file stays playable up to the last written fragment, so
            // footage that was written is never lost.
            writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
            // Synced multicam: embed the shot's alignment fields in the file so
            // an editor can group and time-align the angles. The anchor rides
            // as an opaque numeric key, not a wall-clock date.
            if let metadata = pendingSyncMetadata {
                writer.metadata = metadata.quickTimeMetadataItems()
            }
            self.assetWriter = writer
        } catch {
            failRecording(Self.localizedRecordingError("Unable to start recording"), hasClip: false)
            return
        }
        SessionDebug.pipelinePhase("start: writer armed, awaiting first frames")
        OperationQueue.main.addOperation { [weak self] in
            self?.onModeChanged?(false)
        }
    }

    // MARK: - Movie take (Editable Cinematic)

    /// Builds and starts the take. Its callbacks hop onto the data queue and
    /// are identity-guarded, so a late callback from a take that was already
    /// reset can never touch a newer one.
    private func armMovieTake(on output: AVCaptureMovieFileOutput, url: URL) {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        final class WeakTake { weak var take: MovieTakeRecording? }
        let ref = WeakTake()
        let take = makeMovieTake(output, url, { [weak self] startPTS in
            self?.dataQueue.async { self?.movieTakeStarted(ref.take, startPTS: startPTS) }
        }, { [weak self] error, fileIsComplete in
            self?.dataQueue.async {
                self?.movieTakeFinished(ref.take, error: error, fileIsComplete: fileIsComplete)
            }
        })
        ref.take = take
        movieTake = take
        take.start(metadata: pendingSyncMetadata?.quickTimeMetadataItems())
    }

    /// The movie output wrote its first frame: the take is rolling.
    private func movieTakeStarted(_ take: MovieTakeRecording?, startPTS: CMTime) {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        guard let take, take === movieTake, recordingWillBeStarted, !isRecording else { return }
        if let metadata = pendingSyncMetadata {
            let stamped = metadata.withFirstFrame(
                uptimeNanos: CaptureClockConversion.uptimeNanos(of: startPTS, on: sessionClock()))
            pendingSyncMetadata = stamped
            // The file took its metadata before the first frame, so the
            // offset can't ride inside it; the sidecar keeps the record.
            if stamped.firstFrameOffsetMillis != nil {
                do {
                    try stamped.writeSidecar(in: Self.syncSidecarDirectory)
                } catch {
                    logWarning("recording: sync sidecar not written — \(error)")
                }
            }
        }
        markRecordingStarted()
    }

    /// The movie output finished its file — asked to (a stop) or on its own
    /// (interruption, disk full, a start that never took).
    private func movieTakeFinished(_ take: MovieTakeRecording?, error: Error?, fileIsComplete: Bool) {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        guard let take, take === movieTake else { return }
        if recordingWillBeStopped {
            SessionDebug.pipelinePhase("stop: movie take finished")
            completeStop(finalizeError: fileIsComplete ? nil : Self.recordingFailureError(error))
        } else if isRecording {
            SessionDebug.pipelinePhase("recording: movie take ended on its own")
            failRecording(Self.recordingFailureError(error), hasClip: true)
        } else {
            failRecording(Self.localizedRecordingError("Unable to start recording"), hasClip: false)
        }
    }

    /// Where Editable clips' alignment records go (see `movieTakeStarted`).
    static var syncSidecarDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyncMetadata", isDirectory: true)
    }

    /// THE recording-started instant, for either kind of take: everything
    /// downstream — both timers, the monitor's ack, the wire's
    /// `recording_start_unix_ms`, and `isRecording` itself — derives from
    /// this one stamp.
    private func markRecordingStarted() {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        SessionDebug.pipelinePhase("start: RECORDING")
        recordingWillBeStarted = false
        let startTime = Date()
        recordingStartShared.value = startTime

        // Start recording timer and notify monitor
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onRecordingStarted?(startTime)

            // Tell the remote the recording is rolling.
            self.sendMessage?(RemoteCmd.StartRecordingVideoAck(sender: nil))
        }
    }

    func stopRecording(_ shouldSendVideo: Bool) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            SessionDebug.pipelinePhase("stop: begin")
            if self.recordingWillBeStopped {
                SessionDebug.pipelinePhase("stop: ignored — finalize already in flight")
                return
            }
            // The stop raced the ARMING phase: a writer exists but no frame
            // was ever written, so there is no footage and nothing to
            // finalize. A silent return here would leave
            // `recordingWillBeStarted` latched — and every future start a
            // silent no-op ("the camera never records again"). Cancel the
            // arming and answer the stop as an empty take.
            if self.recordingWillBeStarted && !self.isRecording {
                SessionDebug.pipelinePhase("stop: cancelled arming (empty take)")
                // A movie take may still be starting; its late callbacks
                // are identity-guarded against the reset below.
                self.movieTake?.stop()
                self.resetRecordingState()
                cleanupFileAt(movieUrl())
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingStopped?()
                    self?.onModeChanged?(true)
                }
                self.sendMessage?(RemoteCmd.StopRecordingVideoResp())
                return
            }
            if !self.isRecording {
                SessionDebug.pipelinePhase("stop: ignored — not recording")
                return
            }
            // A writer that already died (disk full) cannot be finalized —
            // `finishWriting` traps on a failed writer. The funnel salvages
            // the fragmented file instead.
            if let writer = self.assetWriter, writer.status == .failed {
                self.failRecording(Self.writerFailureError(writer), hasClip: true)
                return
            }
            // The stop raced the ready edge: no frame was ever written, so the
            // writer never started (`finishWriting` traps on .unknown) and
            // there is no footage. Reset and answer the stop as an empty take.
            if let writer = self.assetWriter, writer.status == .unknown {
                self.resetRecordingState()
                cleanupFileAt(movieUrl())
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingStopped?()
                    self?.onModeChanged?(true)
                }
                self.sendMessage?(RemoteCmd.StopRecordingVideoResp())
                return
            }
            guard let take = self.currentTake else {
                // isRecording without a take is unreachable by construction;
                // if it ever happens, answer rather than wedge.
                self.resetRecordingState()
                self.sendMessage?(RemoteCmd.StopRecordingVideoResp())
                return
            }
            self.recordingStartShared.value = nil
            self.recordingWillBeStopped = true
            self.stopSendsVideo = shouldSendVideo

            // Stop recording timer
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingStopped?()
            }
            // Finalize watchdog, symmetric to the arming watchdog: a finalize
            // whose completion never comes back (the process suspended
            // mid-finalize; media services die and the callback is lost) must
            // not leave the machine unanswered — salvage the file and report
            // the truth. Identity-keyed to THIS take so a slow but successful
            // finalize (or a later take) can never be failed by a stale timer.
            self.dataQueue.asyncAfter(deadline: .now() + self.finalizeTimeout) { [weak self] in
                guard let self, self.currentTake === take else { return }
                SessionDebug.pipelinePhase("stop: finalize WATCHDOG fired")
                self.failRecording(Self.localizedRecordingError("Unable to save video"),
                                   hasClip: true)
            }
            SessionDebug.pipelinePhase("stop: finalizing")
            if let movieTake = self.movieTake {
                // The finish arrives through `movieTakeFinished`.
                movieTake.stop()
            } else if let writer = self.assetWriter {
                self.finalizeWriter(writer) { [weak self] in
                    // The writer calls back on its own queue — hop home before
                    // touching recording state.
                    self?.dataQueue.async { [weak self] in
                        // Identity guard: this completion belongs to the take
                        // it finalized. If the state was already reset
                        // (watchdog fired, or a new take armed after a
                        // suspension), a late completion must not touch it.
                        guard let self, self.assetWriter === writer else { return }
                        SessionDebug.pipelinePhase("stop: finalized")
                        self.completeStop(finalizeError: writer.status == .completed
                                          ? nil : Self.writerFailureError(writer))
                    }
                }
            }
            OperationQueue.main.addOperation { [weak self] in
                self?.onModeChanged?(true)
            }
        }
    }

    /// Identity of the take that is armed or rolling, whichever kind it is.
    /// Held strongly by the watchdog so `===` can never match a newer take
    /// that happens to reuse a freed address.
    private var currentTake: AnyObject? {
        (assetWriter as AnyObject?) ?? (movieTake as AnyObject?)
    }

    /// The end of a requested stop, for either kind of take: the file is
    /// final (or as final as it will get).
    private func completeStop(finalizeError: NSError?) {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        let sendVideo = stopSendsVideo
        resetRecordingState()
        if let finalizeError {
            // Finalize failed under the stop — the file is still playable up
            // to what was written: save what exists and report the truth
            // instead of pretending the stop succeeded.
            saveMovieToPhotosApp()
            onError?(finalizeError.localizedDescription)
            sendMessage?(UICmd.RecordingTerminated(error: finalizeError))
        } else {
            saveMovieToPhotosAppAndRemotePeer(sendVideo)
        }
    }

    /// Tears down every piece of per-recording state — the phase flags, the
    /// writer references, and the shared truth — leaving the pipeline idle.
    /// The one reset used by the stop completion, the empty-take stop, and
    /// the failure funnel, so no path can forget a field. Data queue only.
    private func resetRecordingState() {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        recordingWillBeStarted = false
        recordingWillBeStopped = false
        readyToRecordVideo = false
        readyToRecordAudio = false
        assetWriter = nil
        movieTake = nil
        stopSendsVideo = false
        pixelBufferAdaptor = nil
        cachedVideoCropRect = nil
        recordingStartShared.value = nil
    }

    // MARK: - Failure funnel

    /// Every abnormal end of a recording lands here, on the data queue: the
    /// storage gate refusing a start, a writer that cannot start, and a
    /// writer that dies mid-take (disk full). One funnel so no path can leave
    /// the flags wedged or the peers believing a dead recording is rolling:
    /// state is reset, salvageable footage is saved to Photos (`hasClip`),
    /// the user sees the error, and the coordinator gets
    /// `UICmd.RecordingTerminated` to route the truth to the remote.
    private func failRecording(_ error: NSError, hasClip: Bool) {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        // Dropping a failed writer is safe — it is not mid-finalize (a failed
        // writer cannot be finalized at all); the fragmented file on disk is
        // the recording. A movie take is told to stop (a no-op when it
        // already ended); its late finish is identity-guarded out.
        movieTake?.stop()
        resetRecordingState()
        DispatchQueue.main.async { [weak self] in
            self?.onRecordingStopped?()
            self?.onModeChanged?(true)
        }
        if hasClip { saveMovieToPhotosApp() }
        onError?(error.localizedDescription)
        sendMessage?(UICmd.RecordingTerminated(error: error))
    }

    /// A user-facing error for a dead writer: names the storage cause when
    /// that is what killed it (the overwhelmingly common case), otherwise a
    /// generic recording failure carrying the system's description.
    private static func writerFailureError(_ writer: AVAssetWriter?) -> NSError {
        recordingFailureError(writer?.error)
    }

    /// The same classification for any recorder's underlying error.
    private static func recordingFailureError(_ error: Error?) -> NSError {
        let underlying = error as NSError?
        let diskFull = underlying?.domain == AVFoundationErrorDomain
            && underlying?.code == AVError.diskFull.rawValue
        return localizedRecordingError(
            diskFull ? "recording_stopped_disk_full_error" : "recording_failed_error")
    }

    /// The message rides in BOTH the domain and the localized description:
    /// the monitor's two error-display conventions read one or the other.
    private static func localizedRecordingError(_ key: String) -> NSError {
        let message = NSLocalizedString(key, comment: "")
        return NSError(domain: message, code: 0,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// `volumeAvailableCapacityForImportantUsage` for the volume holding the
    /// recording's output file. nil when unreadable.
    private static func availableCapacity(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    // MARK: - Saving / sending the finished movie

    private func saveMovieToPhotosAppAndRemotePeer(_ sendVideoToPeer: Bool) {
        // Send video to the monitor using resource transfer if requested
        if sendVideoToPeer {
            sendVideoAsResource(movieUrl())
        } else {
            // Send empty response when not sending video
            sendMessage?(RemoteCmd.StopRecordingVideoResp())
        }
        saveMovieToPhotosApp()
    }

    /// Saves the movie file to Photos. Also the salvage half of the failure
    /// funnel: with fragmented writing, a dead writer's file is playable up to
    /// its last fragment and is saved like any finished clip.
    private func saveMovieToPhotosApp() {
        let outputFileURL = movieUrl()

        // Check the authorization status.
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            if status == .authorized {
                // Save the movie file to the photo library and cleanup.
                let syncMetadata = self?.pendingSyncMetadata
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    // A multicam clip is COPIED (not moved) so the temp file
                    // survives the staggered/retried auto-collect transfer to
                    // the director; the next recording cleans it up.
                    options.shouldMoveFile = (syncMetadata == nil)
                    // Synced clip: name it under the shared RS_ group.
                    if let syncMetadata { options.originalFilename = syncMetadata.videoFilename() }
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                }, completionHandler: { [weak self] success, error in
                    if !success {
                        logWarning("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                        // A failed save is a lost clip — never just a log line.
                        self?.onError?(NSLocalizedString("Unable to save video", comment: ""))
                    }
                    if syncMetadata == nil { cleanupFileAt(outputFileURL) }
                }
                )
                self?.pendingSyncMetadata = nil
            } else {
                DispatchQueue.main.async {
                    self?.onPhotosAccessDenied?()
                }
                cleanupFileAt(outputFileURL)
            }
        }
    }

    private func sendVideoAsResource(_ videoURL: URL) {
        // Send message to RemoteCamSession actor to handle video resource transfer
        let sendVideoMsg = UICmd.SendVideoResource(
            videoURL: videoURL,
            peers: [], // Will be populated by the actor from its session
            shouldSendToPeer: true,
            sender: nil
        )

        sendMessage?(sendVideoMsg)
    }

    // MARK: - Asset writer inputs

    func setupAssetWriterVideoInput(_ formatDescription: CMVideoFormatDescription,
                                    assetWriter: AVAssetWriter) -> Bool {
        // Ask for settings that are COHERENT with the codec we want, rather than taking
        // the generic recommendation and overwriting AVVideoCodecKey. The recommendation
        // carries compression properties keyed to the codec it chose: on a Mac it returns
        // avc1 with H.264 profile levels, so patching HEVC over the top produced a
        // dictionary `canApply` refused — the video input was never added,
        // readyToRecordVideo never flipped, recording never started, and `stopRecording`
        // then early-returned in silence while the monitor waited forever. (On iPhone the
        // recommendation is already HEVC, so the overwrite was a no-op and it worked.)
        // Fall back to the plain recommendation where HEVC isn't offered: a recording in
        // the device's preferred codec beats no recording at all.
        var videoSettings = self.engine.videoDataOutput.recommendedVideoSettings(
            forVideoCodecType: .hevc, assetWriterOutputFileType: .mov)
            ?? self.engine.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)

        let dims = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let sourceWidth = CGFloat(dims.width)
        let sourceHeight = CGFloat(dims.height)

        // Compute and cache the crop rect once — reused for every frame
        let needsCrop = recordingAspectRatio != .sixteenNine
        if needsCrop, let rawRect = CaptureEngine.cropRect(sourceWidth: sourceWidth, sourceHeight: sourceHeight, aspectRatio: recordingAspectRatio) {
            // Round to even for codec compatibility
            let evenRect = CGRect(
                x: floor(rawRect.origin.x / 2) * 2,
                y: floor(rawRect.origin.y / 2) * 2,
                width: floor(rawRect.width / 2) * 2,
                height: floor(rawRect.height / 2) * 2
            )
            cachedVideoCropRect = evenRect

            if var settings = videoSettings {
                settings[AVVideoWidthKey] = Int(evenRect.width)
                settings[AVVideoHeightKey] = Int(evenRect.height)
                videoSettings = settings
            }
        } else {
            cachedVideoCropRect = nil
        }

        if assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) {
            videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true

            if let cropRect = cachedVideoCropRect {
                // Pool attributes match output dimensions — avoids per-frame CVPixelBufferCreate
                let poolAttrs: [String: Any] = [
                    kCVPixelBufferWidthKey as String: Int(cropRect.width),
                    kCVPixelBufferHeightKey as String: Int(cropRect.height),
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: poolAttrs)
            } else {
                pixelBufferAdaptor = nil
            }

            if assetWriter.canAdd(videoInput) {
                assetWriter.add(videoInput)
            } else {
                debugLog("❌ recording: asset writer refused the video input")
                return false
            }
        } else {
            debugLog("❌ recording: video settings rejected by canApply — \(String(describing: videoSettings))")
            return false
        }
        return true
    }

    func setupAssetWriterAudioInput(_ formatDescription: CMFormatDescription,
                                    assetWriter: AVAssetWriter) -> Bool {
        let audioSettings = [AVFormatIDKey: kAudioFormatMPEG4AAC]
        if assetWriter.canApply(outputSettings: audioSettings, forMediaType: .audio) {
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: formatDescription)
            audioInput.expectsMediaDataInRealTime = true

            if assetWriter.canAdd(audioInput) {
                assetWriter.add(audioInput)
            } else {
                logWarning("Cannot add audio input to asset writer")
                return false
            }
        } else {
            logWarning("Cannot apply audio settings to asset writer")
            return false
        }
        return true
    }

    // MARK: - Per-frame path (dataQueue: both delegates deliver here)

    func processFrame(_ captureOutput: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer) {
        dispatchPrecondition(condition: .onQueue(dataQueue))

        if let assetWriter = self.assetWriter {
            let wasReadyToRecord = (readyToRecordAudio && readyToRecordVideo)
            if captureOutput === self.engine.videoDataOutput {
                if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer), !readyToRecordVideo {
                    readyToRecordVideo = self.setupAssetWriterVideoInput(formatDescription, assetWriter: assetWriter)
                    if readyToRecordVideo { SessionDebug.pipelinePhase("start: video leg ready (first video frame)") }
                }

                if readyToRecordVideo && readyToRecordAudio {
                    self.writeSampleBuffer(sampleBuffer: sampleBuffer, ofType: .video)
                }
            } else if captureOutput === self.engine.audioDataOutput {
                if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer), !readyToRecordAudio {
                    readyToRecordAudio = self.setupAssetWriterAudioInput(formatDescription,
                                                                         assetWriter: assetWriter)
                    if readyToRecordAudio { SessionDebug.pipelinePhase("start: audio leg ready (first audio frame)") }
                }

                if readyToRecordAudio && readyToRecordVideo {
                    self.writeSampleBuffer(sampleBuffer: sampleBuffer, ofType: .audio)
                }
            }
            let isReadyToRecord = readyToRecordAudio && readyToRecordVideo
            if !wasReadyToRecord && isReadyToRecord {
                SessionDebug.pipelinePhase("start: both legs ready")
                markRecordingStarted()
            }
        }
    }

    private func writeSampleBuffer(sampleBuffer: CMSampleBuffer,
                                   ofType mediaType: AVMediaType) {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        if !isRecording {
            return
        }
        guard let assetWriter = self.assetWriter else {
            return
        }
        if assetWriter.status == .unknown {
            let firstPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            // Synced multicam: the first frame is now known, and the writer
            // takes metadata until it starts — so the first-frame offset
            // rides inside the file with the rest of the alignment keys.
            if let metadata = pendingSyncMetadata {
                let stamped = metadata.withFirstFrame(
                    uptimeNanos: CaptureClockConversion.uptimeNanos(of: firstPTS, on: sessionClock()))
                pendingSyncMetadata = stamped
                assetWriter.metadata = stamped.quickTimeMetadataItems()
            }
            if assetWriter.startWriting() {
                assetWriter.startSession(atSourceTime: firstPTS)
            } else {
                failRecording(Self.writerFailureError(assetWriter), hasClip: false)
                return
            }
        }

        if mediaType == .video, let adaptor = self.pixelBufferAdaptor {
            // Crop video frame for non-16:9 aspect ratios
            if self.videoInput.isReadyForMoreMediaData,
               let croppedBuffer = self.cropSampleBuffer(sampleBuffer) {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                adaptor.append(croppedBuffer, withPresentationTime: pts)
            }
        } else if let input = (mediaType == .video) ? self.videoInput : self.audioInput {
            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }

        // Disk-full and other write failures surface HERE, not as thrown
        // errors: appends silently no-op once the writer is `.failed`, so
        // the status is the only signal.
        if assetWriter.status == .failed {
            failRecording(Self.writerFailureError(assetWriter), hasClip: true)
        }
    }

    /// Crops a video frame using the cached crop rect and the adaptor's pixel buffer pool.
    /// Called on every video frame during recording — must be fast.
    private func cropSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        // No crop needed — pass through the original buffer
        guard let cropRect = cachedVideoCropRect,
              let pool = pixelBufferAdaptor?.pixelBufferPool else {
            return pixelBuffer
        }

        // Get a buffer from the pool (reuses memory, no per-frame allocation)
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
        videoCropContext.render(ciImage, to: output)
        return output
    }
}
