//
//  FrameStreamingTests.swift
//  RemoteShutterTests
//
//  Tests for the camera-side FrameStreamer (pacing, codec fallback, sequence
//  numbering), the monitor-side FrameStreamReceiver (decode, stall watchdog,
//  gap tracking), and the real JPEG/HEIC encoders against a synthetic pixel
//  buffer.
//

import XCTest
import CoreVideo
import MultipeerConnectivity

@testable import RemoteShutter

// MARK: - Fakes

private final class FakeEncoder: FrameEncoding {
    let codec: RemoteCmd.StreamCodec
    var result: Data?
    private(set) var encodeCount = 0

    init(codec: RemoteCmd.StreamCodec, result: Data?) {
        self.codec = codec
        self.result = result
    }

    func encode(pixelBuffer: CVPixelBuffer) -> Data? {
        encodeCount += 1
        return result
    }
}

// MARK: - Helpers

func makePixelBuffer(width: Int = 64, height: Int = 32) -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
        [kCVPixelBufferCGImageCompatibilityKey: true,
         kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
        &pixelBuffer)
    precondition(status == kCVReturnSuccess, "CVPixelBufferCreate failed: \(status)")
    return pixelBuffer!
}

private func makeOnFrame(data: Data = Data([1]),
                         codec: RemoteCmd.StreamCodec = .jpeg,
                         sequenceNumber: UInt32) -> RemoteCmd.OnFrame {
    RemoteCmd.OnFrame(
        data: data,
        sender: nil,
        peerId: MCPeerID(displayName: "peer"),
        fps: 30,
        camPosition: .back,
        camOrientation: .portrait,
        codec: codec,
        sequenceNumber: sequenceNumber
    )
}

// MARK: - FrameStreamer

final class FrameStreamerTests: XCTestCase {

    private var sentFrames: [RemoteCmd.SendFrame] = []

    private func makeStreamer(encoders: [FrameEncoding],
                              frameDivisor: Int = 1) -> FrameStreamer {
        var config = StreamingConfig.default
        config.frameDivisor = frameDivisor
        return FrameStreamer(config: config, encoders: encoders) { [weak self] frame in
            self?.sentFrames.append(frame)
        }
    }

    func testPacingSkipsFramesPerDivisor() {
        let encoder = FakeEncoder(codec: .jpeg, result: Data([1]))
        let streamer = makeStreamer(encoders: [encoder], frameDivisor: 2)

        for _ in 0..<6 {
            streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        }

        XCTAssertEqual(sentFrames.count, 3, "divisor 2 sends every other capture callback")
        XCTAssertEqual(encoder.encodeCount, 3, "skipped frames must not be encoded")
    }

    func testSequenceNumbersAreMonotonicFromOne() {
        let streamer = makeStreamer(encoders: [FakeEncoder(codec: .heic, result: Data([1]))])

        for _ in 0..<3 {
            streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        }

        XCTAssertEqual(sentFrames.map(\.sequenceNumber), [1, 2, 3])
        XCTAssertEqual(sentFrames.map(\.codec), [.heic, .heic, .heic])
    }

    func testFallsBackPermanentlyWhenEncoderFails() {
        let heic = FakeEncoder(codec: .heic, result: nil)
        let jpeg = FakeEncoder(codec: .jpeg, result: Data([2]))
        let streamer = makeStreamer(encoders: [heic, jpeg])

        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)

        XCTAssertEqual(sentFrames.count, 2)
        XCTAssertEqual(sentFrames.map(\.codec), [.jpeg, .jpeg])
        XCTAssertEqual(heic.encodeCount, 1, "failed encoder must be dropped from the chain, not retried")
        XCTAssertEqual(streamer.activeCodec, .jpeg)
    }

    func testDropsFrameWhenAllEncodersFail() {
        let streamer = makeStreamer(encoders: [FakeEncoder(codec: .jpeg, result: nil)])

        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)

        XCTAssertTrue(sentFrames.isEmpty)
        XCTAssertNil(streamer.activeCodec)
    }

    func testFrameCarriesCameraMetadata() {
        let streamer = makeStreamer(encoders: [FakeEncoder(codec: .jpeg, result: Data([7]))])

        streamer.handle(pixelBuffer: makePixelBuffer(), position: .front, orientation: .landscapeRight, fps: 24)

        XCTAssertEqual(sentFrames.count, 1)
        XCTAssertEqual(sentFrames[0].camPosition, .front)
        XCTAssertEqual(sentFrames[0].camOrientation, .landscapeRight)
        XCTAssertEqual(sentFrames[0].fps, 24)
        XCTAssertEqual(sentFrames[0].data, Data([7]))
    }
}

// MARK: - FrameStreamReceiver

final class FrameStreamReceiverTests: XCTestCase {

    private var clock: TimeInterval = 1000
    private var receiver: FrameStreamReceiver!
    private var images: [UIImage] = []
    private var stallCount = 0

    override func setUp() {
        super.setUp()
        receiver = FrameStreamReceiver(now: { [weak self] in self?.clock ?? 0 })
        receiver.onImage = { [weak self] in self?.images.append($0) }
        receiver.onStall = { [weak self] in self?.stallCount += 1 }
    }

    override func tearDown() {
        receiver.invalidate()
        receiver = nil
        super.tearDown()
    }

    /// Runs the receive on the decode queue and waits for it.
    private func deliver(_ frame: RemoteCmd.OnFrame) {
        receiver.receive(frame)
        receiver.decodeQueue.sync {}
    }

    private func checkForStallAndWait() {
        receiver.decodeQueue.sync { receiver.checkForStall() }
    }

    private var validJPEG: Data {
        UIImage(cgImage: {
            let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return context.makeImage()!
        }()).jpegData(compressionQuality: 0.8)!
    }

    func testDecodesFrameAndEmitsImage() {
        deliver(makeOnFrame(data: validJPEG, sequenceNumber: 1))
        XCTAssertEqual(images.count, 1)
    }

    func testUndecodableFrameEmitsNothingButCountsAsActivity() {
        deliver(makeOnFrame(data: Data([0xDE, 0xAD]), sequenceNumber: 1))
        XCTAssertTrue(images.isEmpty)

        // The broken frame still proves the link is alive — no stall.
        clock += 1.0
        checkForStallAndWait()
        XCTAssertEqual(stallCount, 0)
    }

    func testStallFiresAfterTimeoutAndRateLimits() {
        deliver(makeOnFrame(data: validJPEG, sequenceNumber: 1))

        clock += 2.5
        checkForStallAndWait()
        XCTAssertEqual(stallCount, 1)

        // Still stalled but within the rate-limit window: no second report.
        clock += 1.0
        checkForStallAndWait()
        XCTAssertEqual(stallCount, 1)

        // Past the window and still stalled: report again (retries the request).
        clock += 1.5
        checkForStallAndWait()
        XCTAssertEqual(stallCount, 2)
    }

    func testFrameArrivalResetsStallClock() {
        deliver(makeOnFrame(data: validJPEG, sequenceNumber: 1))
        clock += 1.5
        deliver(makeOnFrame(data: validJPEG, sequenceNumber: 2))
        clock += 1.5
        checkForStallAndWait()
        XCTAssertEqual(stallCount, 0, "2s stall timeout is measured from the LAST frame")
    }

    func testSequenceGapsAreCounted() {
        deliver(makeOnFrame(data: validJPEG, sequenceNumber: 1))
        deliver(makeOnFrame(data: validJPEG, sequenceNumber: 2))
        deliver(makeOnFrame(data: validJPEG, sequenceNumber: 5))
        deliver(makeOnFrame(data: validJPEG, sequenceNumber: 6))

        receiver.decodeQueue.sync {
            XCTAssertEqual(receiver.sequenceGapCount, 1)
        }
    }

    func testLegacyFramesWithoutSequenceNumbersNeverCountGaps() {
        deliver(makeOnFrame(data: validJPEG, sequenceNumber: 0))
        deliver(makeOnFrame(data: validJPEG, sequenceNumber: 0))

        receiver.decodeQueue.sync {
            XCTAssertEqual(receiver.sequenceGapCount, 0)
        }
    }
}

// MARK: - Real encoders

final class FrameEncoderTests: XCTestCase {

    func testJPEGEncoderProducesDecodableDownscaledImage() throws {
        let encoder = JPEGFrameEncoder(maxLongEdge: 100, quality: 0.6)
        let data = try XCTUnwrap(encoder.encode(pixelBuffer: makePixelBuffer(width: 400, height: 200)))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 100)
    }

    func testHEICEncoderProducesDecodableDownscaledImage() throws {
        let encoder = HEICFrameEncoder(maxLongEdge: 100, quality: 0.5)
        let data = encoder.encode(pixelBuffer: makePixelBuffer(width: 400, height: 200))
        try XCTSkipIf(data == nil, "HEVC encoder unavailable on this simulator/host")
        let image = try XCTUnwrap(UIImage(data: data!))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 100)
    }

    func testSmallFrameIsNotUpscaled() throws {
        let encoder = JPEGFrameEncoder(maxLongEdge: 960, quality: 0.6)
        let data = try XCTUnwrap(encoder.encode(pixelBuffer: makePixelBuffer(width: 64, height: 32)))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(image.size.width, image.size.height), 64)
    }
}
