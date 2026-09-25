//
//  CinematicMovieRecorder.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation
import AVFoundation

/// One take's file writer, as the recording pipeline sees it when the take
/// is NOT written by its own asset writer. The pipeline owns the whole
/// lifecycle (arming, the ack, the stop protocol, saving and sending, the
/// failure funnel); a take only starts, stops, and reports back through the
/// two callbacks it was built with.
protocol MovieTakeRecording: AnyObject {
    /// Stamps `metadata` into the file and starts writing. The file output
    /// takes its metadata before the first sample, so anything learned later
    /// (the first frame's time) cannot ride inside the .mov.
    func start(metadata: [AVMetadataItem]?)
    /// Stops writing. The finish callback follows once the file is complete.
    /// Harmless when not recording.
    func stop()
}

/// Records an Editable Cinematic take through the engine's movie file output:
/// the clean video, the disparity track and the Cinematic metadata that
/// Photos re-focuses. The blur is not rendered into this file — that is the
/// Baked output, which goes through the pipeline's asset writer instead.
///
/// Callbacks fire on AVFoundation's own queue; the pipeline hops them home.
final class CinematicMovieRecorder: NSObject, MovieTakeRecording, AVCaptureFileOutputRecordingDelegate {

    private let output: AVCaptureMovieFileOutput
    private let url: URL
    /// The output is confined to the engine's session queue; every call into
    /// it hops there.
    private let sessionQueue: DispatchQueue
    private let onStarted: (_ startPTS: CMTime) -> Void
    private let onFinished: (_ error: Error?, _ fileIsComplete: Bool) -> Void

    init(output: AVCaptureMovieFileOutput,
         url: URL,
         sessionQueue: DispatchQueue,
         onStarted: @escaping (_ startPTS: CMTime) -> Void,
         onFinished: @escaping (_ error: Error?, _ fileIsComplete: Bool) -> Void) {
        self.output = output
        self.url = url
        self.sessionQueue = sessionQueue
        self.onStarted = onStarted
        self.onFinished = onFinished
    }

    func start(metadata: [AVMetadataItem]?) {
        sessionQueue.async { [self] in
            // Replaces any previous take's items; nil clears them, so a
            // single-camera take never inherits a rig take's alignment keys.
            // The Cinematic intent key is added by AVFoundation itself.
            output.metadata = metadata
            output.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stop() {
        sessionQueue.async { [output] in
            if output.isRecording { output.stopRecording() }
        }
    }

    // MARK: AVCaptureFileOutputRecordingDelegate

    /// iOS 18.2+: the first written frame's time on the session's
    /// synchronization clock. Cinematic needs iOS 26, so this always exists
    /// on this path; implementing it replaces the variant without a time.
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    startPTS: CMTime, from connections: [AVCaptureConnection]) {
        onStarted(startPTS)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        onFinished(error, Self.isFileComplete(error))
    }

    /// A finish error can still mean a complete, playable file (disk full,
    /// max duration): AVFoundation says so with
    /// `AVErrorRecordingSuccessfullyFinishedKey`. Whether that ends the take
    /// as a success or a failure is the pipeline's call (did it ask to stop?).
    static func isFileComplete(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return true }
        return (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
    }
}
