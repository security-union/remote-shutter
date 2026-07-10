import XCTest
import AVFoundation
@testable import RemoteShutter

/// Exercises the device-free surface of `RecordingPipeline`: asset-writer input
/// setup (including the even-rounded crop rect for non-16:9 aspect ratios) and
/// the stop-while-idle guard. The live capture path needs a real device and
/// stays covered by the loopback round-trip tests against the fake camera.
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
        return formatDescription!
    }

    func testVideoInputFourThreeCachesEvenCropRectAndAdaptor() throws {
        let engine = CaptureEngine()
        _ = engine.setAspectRatio(.fourThree)
        let pipeline = RecordingPipeline(engine: engine)
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

        XCTAssertTrue(pipeline.setupAssetWriterAudioInput(formatDescription!, assetWriter: writer))
        XCTAssertEqual(writer.inputs.count, 1)
        XCTAssertEqual(writer.inputs.first?.mediaType, .audio)
    }

    func testStopWhileIdleSendsNothingAndStaysIdle() {
        let engine = CaptureEngine()
        let pipeline = RecordingPipeline(engine: engine)
        var sentMessages: [Actor.Message] = []
        pipeline.sendMessage = { sentMessages.append($0) }
        var stoppedFired = false
        pipeline.onRecordingStopped = { stoppedFired = true }

        pipeline.stopRecording(true)

        // stopRecording hops to the writing queue — give it time to (not) act.
        let quiesce = expectation(description: "writing queue drained")
        quiesce.isInverted = true
        wait(for: [quiesce], timeout: 0.3)

        XCTAssertFalse(pipeline.isRecording)
        XCTAssertFalse(pipeline.recordingWillBeStopped)
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertFalse(stoppedFired)
    }
}
