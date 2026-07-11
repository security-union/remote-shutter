import XCTest
import AVFoundation
@testable import RemoteShutter

/// Exercises the device-free surface of `RecordingPipeline`: asset-writer input
/// setup (including the even-rounded crop rect for non-16:9 aspect ratios), the
/// stop-while-idle guard, and — with the single data queue — the full frame
/// sequencing path, deterministically: feed synthetic video/audio buffers on
/// the pipeline's own queue and assert exactly one start-ack fires.
final class RecordingPipelineTests: XCTestCase {

    private func makeWriter() throws -> AVAssetWriter {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingPipelineTests-\(UUID().uuidString).mov")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try AVAssetWriter(outputURL: url, fileType: .mov)
    }

    private func makeVideoFormatDescription(width: Int32, height: Int32) throws -> CMVideoFormatDescription {
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: width,
            height: height,
            extensions: nil,
            formatDescriptionOut: &formatDescription)
        XCTAssertEqual(status, noErr)
        return try XCTUnwrap(formatDescription)
    }

    private func makeAudioFormatDescription() throws -> CMAudioFormatDescription {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger, mBytesPerPacket: 2,
            mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0)
        var formatDescription: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &formatDescription), noErr)
        return try XCTUnwrap(formatDescription)
    }

    /// A pixel-buffer-backed video sample buffer, as the capture output would deliver.
    private func makeVideoSampleBuffer(seconds: Double) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(
            kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_32BGRA,
            nil, &pixelBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)

        var videoFormat: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescriptionOut: &videoFormat), noErr)

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
            decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil,
            formatDescription: try XCTUnwrap(videoFormat),
            sampleTiming: &timing, sampleBufferOut: &sampleBuffer), noErr)
        return try XCTUnwrap(sampleBuffer)
    }

    /// A data-less audio sample buffer: `processFrame`'s audio leg only reads
    /// the format description until the writer is ready.
    private func makeAudioSampleBuffer() throws -> CMSampleBuffer {
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 44100),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid)
        XCTAssertEqual(CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil,
            formatDescription: try makeAudioFormatDescription(),
            sampleCount: 0, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer), noErr)
        return try XCTUnwrap(sampleBuffer)
    }

    // MARK: - Asset writer inputs

    func testVideoInputFourThreeCachesEvenCropRectAndAdaptor() throws {
        let engine = CaptureEngine()
        let pipeline = RecordingPipeline(engine: engine)
        pipeline.recordingAspectRatio = .fourThree
        let writer = try makeWriter()

        let didSetup = pipeline.setupAssetWriterVideoInput(
            try makeVideoFormatDescription(width: 1920, height: 1080),
            assetWriter: writer)

        XCTAssertTrue(didSetup)
        let cropRect = try XCTUnwrap(pipeline.cachedVideoCropRect)
        // 4:3 of 1080p → 1440x1080, centered at x=240; all dimensions even.
        XCTAssertEqual(cropRect, CGRect(x: 240, y: 0, width: 1440, height: 1080))
        XCTAssertEqual(Int(cropRect.width) % 2, 0)
        XCTAssertEqual(Int(cropRect.origin.x) % 2, 0)
        // Cropping goes through the pixel-buffer adaptor pool.
        XCTAssertNotNil(pipeline.pixelBufferAdaptor)
        XCTAssertEqual(writer.inputs.count, 1)
        XCTAssertEqual(writer.inputs.first?.mediaType, .video)
    }

    func testVideoInputSixteenNineNeedsNoCropOrAdaptor() throws {
        let engine = CaptureEngine()
        let pipeline = RecordingPipeline(engine: engine)
        let writer = try makeWriter()

        let didSetup = pipeline.setupAssetWriterVideoInput(
            try makeVideoFormatDescription(width: 1920, height: 1080),
            assetWriter: writer)

        XCTAssertTrue(didSetup)
        XCTAssertNil(pipeline.cachedVideoCropRect)
        XCTAssertNil(pipeline.pixelBufferAdaptor)
        XCTAssertEqual(writer.inputs.count, 1)
    }

    func testAudioInputSetup() throws {
        let engine = CaptureEngine()
        let pipeline = RecordingPipeline(engine: engine)
        let writer = try makeWriter()

        XCTAssertTrue(pipeline.setupAssetWriterAudioInput(try makeAudioFormatDescription(), assetWriter: writer))
        XCTAssertEqual(writer.inputs.count, 1)
        XCTAssertEqual(writer.inputs.first?.mediaType, .audio)
    }

    // MARK: - Sequencing (single data queue)

    private final class DummyAudioDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {}

    /// The "became ready" edge must fire exactly once no matter how many
    /// frames follow — the regression test for the double-ack race that
    /// existed while video and audio delivered on separate queues.
    func testRecordingStartAcksExactlyOnce() throws {
        let engine = CaptureEngine()
        let pipeline = RecordingPipeline(engine: engine)
        // Audio "available": the edge must wait for the first audio frame.
        pipeline.configureAudio = { _ in true }

        var acks: [Message] = []
        let firstAck = expectation(description: "start ack relayed")
        pipeline.sendMessage = { message in
            acks.append(message)
            if acks.count == 1 { firstAck.fulfill() }
        }

        pipeline.startRecording(audioSampleBufferDelegate: DummyAudioDelegate())
        engine.dataOutputQueue.sync {} // drain: writer created, flags set

        let videoBuffer = try makeVideoSampleBuffer(seconds: 0)
        let audioBuffer = try makeAudioSampleBuffer()
        engine.dataOutputQueue.sync {
            pipeline.processFrame(engine.videoDataOutput, didOutput: videoBuffer)
            pipeline.processFrame(engine.audioDataOutput, didOutput: audioBuffer)
        }
        // More frames after the edge — none of these may re-ack.
        engine.dataOutputQueue.sync {
            for i in 1...5 {
                pipeline.processFrame(engine.videoDataOutput, didOutput: try! self.makeVideoSampleBuffer(seconds: Double(i) / 30.0))
            }
        }

        wait(for: [firstAck], timeout: 2.0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        XCTAssertTrue(pipeline.isRecording)
        XCTAssertEqual(acks.count, 1, "the ready edge must produce exactly one StartRecordingVideoAck")
        XCTAssertTrue(acks.first is RemoteCmd.StartRecordingVideoAck)
    }

    /// With no audio device (the simulator, mic-less hardware), recording must
    /// still start from video frames alone — the audio leg is pre-satisfied at
    /// start, since no audio frame will ever arrive to satisfy it.
    func testRecordingStartsWithVideoOnlyWhenAudioUnavailable() throws {
        let engine = CaptureEngine()
        let pipeline = RecordingPipeline(engine: engine)
        // No audio device: the edge must fire from video frames alone.
        pipeline.configureAudio = { _ in false }

        var acks: [Message] = []
        let firstAck = expectation(description: "start ack relayed")
        pipeline.sendMessage = { message in
            acks.append(message)
            if acks.count == 1 { firstAck.fulfill() }
        }

        pipeline.startRecording(audioSampleBufferDelegate: DummyAudioDelegate())
        engine.dataOutputQueue.sync {}

        // Video frames only — no synthetic audio buffer this time.
        engine.dataOutputQueue.sync {
            pipeline.processFrame(engine.videoDataOutput, didOutput: try! self.makeVideoSampleBuffer(seconds: 0))
        }

        wait(for: [firstAck], timeout: 2.0)
        XCTAssertTrue(pipeline.isRecording, "video-only recording must reach isRecording")
        XCTAssertTrue(acks.first is RemoteCmd.StartRecordingVideoAck)
    }

    func testStopWhileIdleSendsNothingAndStaysIdle() {
        let engine = CaptureEngine()
        let pipeline = RecordingPipeline(engine: engine)
        var sentMessages: [Message] = []
        pipeline.sendMessage = { sentMessages.append($0) }
        var stoppedFired = false
        pipeline.onRecordingStopped = { stoppedFired = true }

        pipeline.stopRecording(true)
        engine.dataOutputQueue.sync {} // deterministic drain — no sleeps

        XCTAssertFalse(pipeline.isRecording)
        XCTAssertFalse(pipeline.recordingWillBeStopped)
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertFalse(stoppedFired)
    }

    func testDoubleStartIsIgnored() {
        let engine = CaptureEngine()
        let pipeline = RecordingPipeline(engine: engine)

        pipeline.startRecording(audioSampleBufferDelegate: DummyAudioDelegate())
        pipeline.startRecording(audioSampleBufferDelegate: DummyAudioDelegate())
        engine.dataOutputQueue.sync {}

        XCTAssertTrue(pipeline.recordingWillBeStarted)
        XCTAssertFalse(pipeline.isRecording)
    }

    // MARK: - Concurrency hammer

    /// Slams the engine's entry points from many concurrent tasks at once
    /// while config-mutating calls churn. Deadlock shows up as a hang (test
    /// timeout); a confinement mistake shows up under Thread Sanitizer.
    func testEngineEntryPointsSurviveConcurrentHammering() async {
        let engine = CaptureEngine()

        await withTaskGroup(of: Void.self) { group in
            for iteration in 0..<200 {
                group.addTask {
                    switch iteration % 7 {
                    case 0: _ = await engine.setAspectRatio(iteration % 2 == 0 ? .fourThree : .sixteenNine)
                    case 1: _ = engine.currentAspectRatioValue()
                    case 2: _ = engine.statusSnapshot()
                    case 3: _ = await engine.getZoomStops()
                    case 4: _ = await engine.getCurrentLensType()
                    case 5: _ = engine.desiredTorchOn
                    case 6: _ = await engine.setPhotoQuality(format: .jpeg, hdrMode: iteration % 2 == 0 ? .on : .off)
                    default: break
                    }
                }
            }
        }

        // The queue is still alive and consistent after the storm.
        let finalRatio = await engine.setAspectRatio(.sixteenNine)
        XCTAssertEqual(finalRatio, .sixteenNine)
    }
}
