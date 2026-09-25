//
//  CinematicProbeTests.swift
//  RemoteShutterTests
//
//  Hardware probe for Cinematic video (iOS 26+). Answers, on a real iPhone,
//  what the SDK headers cannot:
//    1. which camera devices expose Cinematic formats (inventory)
//    3. whether BGRA video-data-output frames carry the blur
//    4. whether our AVAssetWriter can write the iOS 27 editable metadata
//       track, full-frame and square-cropped
//    5. what a movie file output produces, as the baseline
//  (2 — our real engine session — lives in CaptureIntegrationTests.)
//
//  Everything prints with a 🎬 prefix and lands in
//  Documents/CinematicProbe/ (frames, clips, report.txt) in the host app's
//  container. Skips on simulator and CI.
//

import XCTest
import AVFoundation
import CoreImage
import Cinematic

@testable import RemoteShutter

enum CinematicProbe {
    static let directory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CinematicProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let reportLock = NSLock()

    static func log(_ line: String) {
        print("🎬 \(line)")
        reportLock.lock()
        defer { reportLock.unlock() }
        let url = directory.appendingPathComponent("report.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
    }

    static func describe(_ format: AVCaptureDevice.Format) -> String {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let fps = format.videoSupportedFrameRateRanges.map { Int($0.maxFrameRate) }.max() ?? 0
        let subtype = fourCC(CMFormatDescriptionGetMediaSubType(format.formatDescription))
        return "\(dims.width)x\(dims.height)@\(fps) \(subtype)"
    }

    static func skipIfHeadless() throws {
        if ProcessInfo.processInfo.environment["CI"] != nil { throw XCTSkip("headless CI") }
        #if targetEnvironment(simulator)
        throw XCTSkip("simulator has no cameras")
        #endif
    }

    static func requireCameraAccess() async throws {
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            status = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        }
        guard status == .authorized else { throw XCTSkip("no camera permission") }
    }
}

/// A bare capture session shaped like ours (BGRA video data output + photo
/// output) with Cinematic on, plus a metadata output and an optional
/// AVAssetWriter that records video and the Cinematic metadata track.
@available(iOS 26.0, *)
final class CinematicProbeSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                                   AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "cinematic probe")
    let videoOutput = AVCaptureVideoDataOutput()
    let photoOutput = AVCapturePhotoOutput()
    let metadataOutput = AVCaptureMetadataOutput()
    private(set) var input: AVCaptureDeviceInput!

    private let ciContext = CIContext()
    private let grabRequest = Locked<((CIImage) -> Void)?>(nil)
    let frameCount = Locked(0)
    let metadataTypesSeen = Locked<[String: Int]>([:])

    // Writer state, queue-confined.
    private var writer: AVAssetWriter?
    private var writerVideo: AVAssetWriterInput?
    private var writerMetadata: AVAssetWriterInputMetadataAdaptor?
    private var sessionStart: CMTime?
    private var squareCrop = false
    let metadataGroupsWritten = Locked(0)

    /// Builds the session on `device` with a Cinematic format; returns false
    /// (with the reason logged) when Cinematic cannot be enabled.
    func configure(device: AVCaptureDevice) -> Bool {
        queue.sync {
            let formats = device.formats.filter { $0.isCinematicVideoCaptureSupported }
            // Prefer 1080p 8-bit (what our pipeline records), else anything.
            guard let format = formats.first(where: {
                let dims = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let sub = CinematicProbe.fourCC(CMFormatDescriptionGetMediaSubType($0.formatDescription))
                return dims.width == 1920 && dims.height == 1080 && sub.hasPrefix("420")
            }) ?? formats.first else {
                CinematicProbe.log("session: \(device.localizedName) has no Cinematic format")
                return false
            }
            guard let input = try? AVCaptureDeviceInput(device: device) else { return false }
            self.input = input
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoOutput.setSampleBufferDelegate(self, queue: queue)

            session.beginConfiguration()
            session.sessionPreset = .inputPriority
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            if (try? device.lockForConfiguration()) != nil {
                device.activeFormat = format
                device.unlockForConfiguration()
            }
            session.commitConfiguration()

            CinematicProbe.log("session: \(device.localizedName) format=\(CinematicProbe.describe(format)) "
                               + "inputSupports=\(input.isCinematicVideoCaptureSupported)")
            guard input.isCinematicVideoCaptureSupported else { return false }

            // The metadata output's types must equal the required set by the
            // time the enable commits, so all three land in one configuration.
            session.beginConfiguration()
            input.isCinematicVideoCaptureEnabled = true
            if session.canAddOutput(metadataOutput) { session.addOutput(metadataOutput) }
            let required = metadataOutput.requiredMetadataObjectTypesForCinematicVideoCapture
            metadataOutput.metadataObjectTypes = required
            session.commitConfiguration()

            let available = metadataOutput.availableMetadataObjectTypes
            CinematicProbe.log("metadata: required=\(required.map(\.rawValue))")
            CinematicProbe.log("metadata: available=\(available.map(\.rawValue))")
            if #available(iOS 27.0, *) {
                CinematicProbe.log("metadata: cinematicVideoMetadata required=\(required.contains(.cinematicVideoMetadata)) "
                                   + "available=\(available.contains(.cinematicVideoMetadata)) "
                                   + "formatSupportsMetadata=\(device.activeFormat.isCinematicVideoMetadataCaptureSupported)")
            }
            metadataOutput.setMetadataObjectsDelegate(self, queue: queue)
            CinematicProbe.log("session: enabled=\(input.isCinematicVideoCaptureEnabled) aperture=f/\(input.simulatedAperture) "
                               + "range=f/\(format.minSimulatedAperture)…f/\(format.maxSimulatedAperture)")
            return input.isCinematicVideoCaptureEnabled
        }
    }

    func start() { queue.sync { session.startRunning() } }
    func stop() { queue.sync { session.stopRunning() } }

    func setAperture(_ aperture: Float) {
        queue.sync { input.simulatedAperture = aperture }
    }

    func setCinematic(_ enabled: Bool) {
        queue.sync {
            session.beginConfiguration()
            input.isCinematicVideoCaptureEnabled = enabled
            session.commitConfiguration()
        }
    }

    /// The next delivered frame, as a CIImage.
    func grabFrame(timeout: TimeInterval = 5) async -> CIImage? {
        await withCheckedContinuation { continuation in
            let once = Locked(false)
            grabRequest.value = { image in
                once.mutate { done in
                    guard !done else { return }
                    done = true
                    continuation.resume(returning: image)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [grabRequest] in
                once.mutate { done in
                    guard !done else { return }
                    done = true
                    grabRequest.value = nil
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func saveJPEG(_ image: CIImage, name: String) {
        let url = CinematicProbe.directory.appendingPathComponent(name)
        try? ciContext.writeJPEGRepresentation(of: image, to: url,
                                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    /// Grayscale thumbnail bytes for comparing frames.
    func luma(_ image: CIImage, width: Int = 192, height: Int = 108) -> [UInt8] {
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width,
                                                             y: CGFloat(height) / image.extent.height))
        var bytes = [UInt8](repeating: 0, count: width * height)
        ciContext.render(scaled, toBitmap: &bytes, rowBytes: width, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                         format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        return bytes
    }

    // MARK: Writer

    func startWriting(to url: URL, squareCrop: Bool) throws {
        try queue.sync {
            try? FileManager.default.removeItem(at: url)
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let dims = CMVideoFormatDescriptionGetDimensions(input.device.activeFormat.formatDescription)
            let side = Int(min(dims.width, dims.height))
            var settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: squareCrop ? side : Int(dims.width),
                AVVideoHeightKey: squareCrop ? side : Int(dims.height),
            ]
            if squareCrop { settings[AVVideoScalingModeKey] = AVVideoScalingModeResizeAspectFill }
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            video.expectsMediaDataInRealTime = true
            writer.add(video)

            if #available(iOS 27.0, *),
               let hint = AVMetadataCinematicVideoMetadataObject.cinematicVideoMetadataFormatDescription {
                let metadata = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: hint)
                metadata.expectsMediaDataInRealTime = true
                metadata.addTrackAssociation(withTrackOf: video, type: AVAssetTrack.AssociationType.metadataReferent.rawValue)
                writer.add(metadata)
                writerMetadata = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadata)
            } else {
                CinematicProbe.log("writer: no cinematic metadata format description")
            }
            self.writer = writer
            self.writerVideo = video
            self.squareCrop = squareCrop
            self.sessionStart = nil
            metadataGroupsWritten.value = 0
            guard writer.startWriting() else { throw writer.error ?? NSError(domain: "startWriting", code: 0) }
        }
    }

    func finishWriting() async -> Error? {
        let writer: AVAssetWriter? = queue.sync {
            let current = self.writer
            self.writer = nil
            writerVideo?.markAsFinished()
            writerMetadata?.assetWriterInput.markAsFinished()
            writerVideo = nil
            writerMetadata = nil
            return current
        }
        guard let writer else { return NSError(domain: "no writer", code: 0) }
        await writer.finishWriting()
        return writer.status == .completed ? nil : writer.error
    }

    // MARK: Delegates

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameCount.mutate { $0 += 1 }
        if let request = grabRequest.value, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) {
            grabRequest.value = nil
            request(CIImage(cvPixelBuffer: pixels))
        }
        guard let writer, let video = writerVideo, writer.status == .writing else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if sessionStart == nil {
            writer.startSession(atSourceTime: pts)
            sessionStart = pts
        }
        if video.isReadyForMoreMediaData { video.append(sampleBuffer) }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        metadataTypesSeen.mutate { seen in
            for object in metadataObjects { seen[object.type.rawValue, default: 0] += 1 }
        }
        guard #available(iOS 27.0, *), let adaptor = writerMetadata, let start = sessionStart,
              writer?.status == .writing else { return }
        for case let object as AVMetadataCinematicVideoMetadataObject in metadataObjects {
            guard let group = object.timedMetadataGroup,
                  CMTimeCompare(group.timeRange.start, start) >= 0,
                  adaptor.assetWriterInput.isReadyForMoreMediaData else { continue }
            if adaptor.append(group) { metadataGroupsWritten.mutate { $0 += 1 } }
        }
    }
}

final class CinematicProbeTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        try CinematicProbe.skipIfHeadless()
        guard #available(iOS 26.0, *) else { throw XCTSkip("Cinematic needs iOS 26") }
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Cinematic probe is for iPhone")
        #endif
        try await CinematicProbe.requireCameraAccess()
        CinematicProbe.log("===== \(name) on \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)")
    }

    /// 1. Which devices have Cinematic formats, and what the engine opens.
    func test1_Inventory() throws {
        guard #available(iOS 26.0, *) else { return }
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
                                                    .builtInWideAngleCamera, .builtInUltraWideCamera,
                                                    .builtInTelephotoCamera, .builtInTrueDepthCamera]
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        for device in devices {
            let cinematic = device.formats.filter { $0.isCinematicVideoCaptureSupported }
            CinematicProbe.log("inventory: \(device.localizedName) [\(device.deviceType.rawValue)] pos=\(device.position.rawValue) "
                               + "cinematic=\(cinematic.count)/\(device.formats.count)")
            for format in cinematic {
                var line = "    \(CinematicProbe.describe(format)) f/\(format.minSimulatedAperture)…\(format.maxSimulatedAperture) "
                    + "default f/\(format.defaultSimulatedAperture) "
                    + "zoom \(format.videoMinZoomFactorForCinematicVideo)…\(format.videoMaxZoomFactorForCinematicVideo) "
                    + "fps \(format.videoFrameRateRangeForCinematicVideo.map { "\($0.minFrameRate)…\($0.maxFrameRate)" } ?? "nil")"
                if #available(iOS 27.0, *) { line += " metadataCapture=\(format.isCinematicVideoMetadataCaptureSupported)" }
                CinematicProbe.log(line)
            }
        }
        let engine = CaptureEngine()
        for position in [AVCaptureDevice.Position.back, .front] {
            let preferred = engine.preferredCamera(for: position)
            CinematicProbe.log("inventory: engine opens \(preferred?.localizedName ?? "nil") "
                               + "[\(preferred?.deviceType.rawValue ?? "-")] for position \(position.rawValue)")
        }
    }

    /// 3. Do BGRA video-data frames carry the blur? Same scene, phone still:
    /// frames with Cinematic off, at the widest and the narrowest aperture.
    /// Point the back camera at something close with a background behind it.
    func test3_BlurInVideoDataOutputFrames() async throws {
        guard #available(iOS 26.0, *) else { return }
        let probe = CinematicProbeSession()
        guard let device = CaptureEngine().preferredCamera(for: .back), probe.configure(device: device) else {
            return XCTFail("Cinematic could not be enabled — see report")
        }
        probe.start()
        defer { probe.stop() }
        try await Task.sleep(nanoseconds: 3_000_000_000)   // let focus + the effect settle
        let format = device.activeFormat

        func capture(_ label: String) async throws -> [UInt8]? {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            guard let first = await probe.grabFrame(), let second = await probe.grabFrame() else {
                CinematicProbe.log("blur: \(label) — no frame"); return nil
            }
            probe.saveJPEG(first, name: "frame_\(label).jpg")
            let a = probe.luma(first), b = probe.luma(second)
            CinematicProbe.log("blur: \(label) sharpness=\(Self.sharpness(a)) noise=\(Self.meanAbsDiff(a, b))")
            return a
        }

        probe.setAperture(format.minSimulatedAperture)
        let wide = try await capture("on_f\(format.minSimulatedAperture)")
        probe.setAperture(format.maxSimulatedAperture)
        let narrow = try await capture("on_f\(format.maxSimulatedAperture)")
        probe.setCinematic(false)
        try await Task.sleep(nanoseconds: 3_000_000_000)   // the pipeline rebuild delivers black frames first
        let off = try await capture("off")
        if let wide, let narrow, let off {
            CinematicProbe.log("blur: diff(wide,narrow)=\(Self.meanAbsDiff(wide, narrow)) diff(wide,off)=\(Self.meanAbsDiff(wide, off))")
        }
        CinematicProbe.log("blur: frames=\(probe.frameCount.value) metadata=\(probe.metadataTypesSeen.value)")
    }

    /// 4. iOS 27: can our AVAssetWriter write the editable metadata track,
    /// full frame and square-cropped (what the aspect-ratio crop does)?
    func test4_WriterCinematicMetadataTrack() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("writer metadata track needs iOS 27") }
        CinematicProbe.log("resources: status=\(CNAssetInfo.resourceStatus().rawValue) (0 ready, 1 needs download)")
        for square in [false, true] {
            let probe = CinematicProbeSession()
            guard let device = CaptureEngine().preferredCamera(for: .back), probe.configure(device: device) else {
                return XCTFail("Cinematic could not be enabled — see report")
            }
            probe.start()
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let url = CinematicProbe.directory.appendingPathComponent(square ? "writer_square.mov" : "writer_169.mov")
            try probe.startWriting(to: url, squareCrop: square)
            try await Task.sleep(nanoseconds: 4_000_000_000)
            let error = await probe.finishWriting()
            probe.stop()
            CinematicProbe.log("writer \(square ? "square" : "16:9"): error=\(String(describing: error)) "
                               + "metadataGroups=\(probe.metadataGroupsWritten.value) seen=\(probe.metadataTypesSeen.value)")
            await Self.inspect(url, label: square ? "writer square" : "writer 16:9", preprocess: true)
        }
    }

    /// 5. Baseline: what a movie file output records with Cinematic on.
    func test5_MovieFileOutputBaseline() async throws {
        guard #available(iOS 26.0, *) else { return }
        let probe = CinematicProbeSession()
        guard let device = CaptureEngine().preferredCamera(for: .back), probe.configure(device: device) else {
            return XCTFail("Cinematic could not be enabled — see report")
        }
        let movie = AVCaptureMovieFileOutput()
        probe.queue.sync {
            probe.session.beginConfiguration()
            let added = probe.session.canAddOutput(movie)
            if added { probe.session.addOutput(movie) }
            probe.session.commitConfiguration()
            CinematicProbe.log("movie: added=\(added) cinematicStillEnabled=\(probe.input.isCinematicVideoCaptureEnabled)")
            if #available(iOS 27.0, *) {
                CinematicProbe.log("movie: metadataCaptureSupported=\(movie.isCinematicVideoMetadataCaptureSupported) "
                                   + "enabled=\(movie.isCinematicVideoMetadataCaptureEnabled)")
            }
        }
        probe.start()
        defer { probe.stop() }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let url = CinematicProbe.directory.appendingPathComponent("movie_output.mov")
        try? FileManager.default.removeItem(at: url)
        let recorder = MovieRecorder()
        movie.startRecording(to: url, recordingDelegate: recorder)
        try await Task.sleep(nanoseconds: 4_000_000_000)
        movie.stopRecording()
        let error = await recorder.finished()
        CinematicProbe.log("movie: error=\(String(describing: error))")
        await Self.inspect(url, label: "movie output", preprocess: false)
    }

    // MARK: Helpers

    private final class MovieRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
        private let result = Locked<(Error?)?>(nil)
        func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                        from connections: [AVCaptureConnection], error: Error?) {
            result.value = .some(error)
        }
        func finished() async -> Error? {
            for _ in 0..<100 {
                if let done = result.value { return done }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return NSError(domain: "movie output never finished", code: 0)
        }
    }

    /// Tracks, movie metadata and the Cinematic framework's verdict.
    private static func inspect(_ url: URL, label: String, preprocess: Bool) async {
        let asset = AVURLAsset(url: url)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        CinematicProbe.log("\(label): \(url.lastPathComponent) \(size / 1024) KB")
        for track in (try? await asset.load(.tracks)) ?? [] {
            let formats = (try? await track.load(.formatDescriptions)) ?? []
            let subtypes = formats.map { CinematicProbe.fourCC(CMFormatDescriptionGetMediaSubType($0)) }
            let natural = (try? await track.load(.naturalSize)) ?? .zero
            CinematicProbe.log("    track \(track.trackID) \(track.mediaType.rawValue) \(subtypes) \(Int(natural.width))x\(Int(natural.height))")
        }
        for item in (try? await asset.load(.metadata)) ?? [] {
            let value = try? await item.load(.value)
            CinematicProbe.log("    meta \(item.identifier?.rawValue ?? "?") = \(String(describing: value))")
        }
        guard #available(iOS 27.0, *) else { return }
        let capability = await CNAssetInfo.cinematicCapability(for: asset)
        CinematicProbe.log("    CNCinematicCapability=\(capability.rawValue) (0 none, 1 renderable, 2 needs preprocessing)")
        guard preprocess, capability == .needsPreprocessing else { return }
        do {
            var info = try await CNAssetInfo(asset: asset)
            if info.resourceStatus == .needsDownloading {
                CinematicProbe.log("    downloading Cinematic resources…")
                info = try await info.downloadResources()
            }
            let out = url.deletingPathExtension().appendingPathExtension("preprocessed.mov")
            try? FileManager.default.removeItem(at: out)
            let processed = try await info.preprocessAsset(configuration: CNAssetPreprocessConfiguration(destinationAssetURL: out))
            CinematicProbe.log("    preprocessed: capability=\(processed.cinematicCapability.rawValue) "
                               + "disparity=\(processed.cinematicDisparityTrack.isEnabled)")
        } catch {
            CinematicProbe.log("    preprocess failed: \(error)")
        }
    }

    private static func sharpness(_ luma: [UInt8], width: Int = 192) -> Int {
        var total = 0
        for index in 1..<luma.count where index % width != 0 {
            total += abs(Int(luma[index]) - Int(luma[index - 1]))
        }
        return total * 100 / luma.count
    }

    private static func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Int {
        zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) } * 100 / max(a.count, 1)
    }
}
