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
import MPCCompat
import PeerMesh

@testable import RemoteShutter

// MARK: - Fakes

private final class FakeEncoder: FrameEncoding {
    let codec: RemoteCmd.StreamCodec
    var result: FrameEncodeResult
    private(set) var encodeCount = 0

    init(codec: RemoteCmd.StreamCodec, result: Data?) {
        self.codec = codec
        self.result = result.map(FrameEncodeResult.encoded) ?? .failed
    }

    func encode(pixelBuffer: CVPixelBuffer) -> FrameEncodeResult {
        encodeCount += 1
        return result
    }
}

/// Unwraps `.encoded` payload bytes for assertions on the real encoders.
func encodedData(_ result: FrameEncodeResult) -> Data? {
    if case .encoded(let data) = result { return data }
    return nil
}

/// Fake stateful VP9 encoder: records encode + forceKeyframe calls so the
/// streamer's lazy-encode and keyframe wiring can be asserted without the codec.
private final class FakeVideoEncoder: StreamVideoEncoding {
    let codec: RemoteCmd.StreamCodec = .vp9
    var result: FrameEncodeResult
    private(set) var encodeCount = 0
    private(set) var forceKeyframeCount = 0

    init(result: FrameEncodeResult = .encoded(Data([9]))) { self.result = result }

    func encode(pixelBuffer: CVPixelBuffer) -> FrameEncodeResult {
        encodeCount += 1
        return result
    }
    func forceKeyframe() { forceKeyframeCount += 1 }
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
        peerId: PeerID(displayName: "peer"),
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

    // MARK: - VP9 path (always-on when available + lazy credit gate + keyframe)

    /// - Parameter vp9: the VP9 encoder the factory returns; nil models VP9
    ///   unavailable at runtime (the dev-only stills fallback).
    private func makeVP9Streamer(vp9: FakeVideoEncoder?,
                                 stillEncoders: [FrameEncoding],
                                 creditAvailable: @escaping () -> Bool = { true },
                                 takeKeyframeRequest: @escaping () -> Bool = { false }) -> FrameStreamer {
        var config = StreamingConfig.default
        config.frameDivisor = 1
        return FrameStreamer(
            config: config,
            encoders: stillEncoders,
            creditAvailable: creditAvailable,
            takeKeyframeRequest: takeKeyframeRequest,
            makeVideoEncoder: { vp9 }
        ) { [weak self] frame in self?.sentFrames.append(frame) }
    }

    func testStreamsVP9WhenTheEncoderIsAvailable() {
        let vp9 = FakeVideoEncoder()
        let streamer = makeVP9Streamer(vp9: vp9, stillEncoders: [FakeEncoder(codec: .heic, result: Data([1]))])

        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        XCTAssertEqual(vp9.encodeCount, 1, "a new camera streams VP9 to every (version-gated) monitor")
        XCTAssertEqual(sentFrames.map(\.codec), [.vp9])
    }

    /// Dev-only fallback: when VP9 is unavailable at runtime (factory returns
    /// nil) the stream stays alive on stills. No per-peer negotiation involved.
    func testFallsBackToStillsWhenVP9Unavailable() {
        let streamer = makeVP9Streamer(vp9: nil, stillEncoders: [FakeEncoder(codec: .heic, result: Data([1]))])

        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        XCTAssertEqual(sentFrames.map(\.codec), [.heic])
    }

    /// The core stateful-stream invariant: with no credit, VP9 must NOT be
    /// encoded (encoding-then-dropping would corrupt every later delta frame).
    func testVP9IsNotEncodedWithoutCredit() {
        let vp9 = FakeVideoEncoder()
        var credit = false
        let streamer = makeVP9Streamer(vp9: vp9, stillEncoders: [FakeEncoder(codec: .heic, result: Data([1]))],
                                       creditAvailable: { credit })

        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        XCTAssertEqual(vp9.encodeCount, 0, "no credit: the encoder must not even see the frame")
        XCTAssertTrue(sentFrames.isEmpty, "no frame goes out under back-pressure")

        credit = true
        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        XCTAssertEqual(vp9.encodeCount, 1)
        XCTAssertEqual(sentFrames.map(\.codec), [.vp9])
    }

    func testVP9SkippedResultSendsNothingButKeepsStream() {
        let vp9 = FakeVideoEncoder(result: .skipped)
        let streamer = makeVP9Streamer(vp9: vp9, stillEncoders: [FakeEncoder(codec: .heic, result: Data([1]))])
        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        XCTAssertEqual(vp9.encodeCount, 1)
        XCTAssertTrue(sentFrames.isEmpty, "a buffered (skipped) frame produces no wire frame")
    }

    func testKeyframeRequestForcesKeyframeBeforeEncode() {
        let vp9 = FakeVideoEncoder()
        var pending = true
        let streamer = makeVP9Streamer(vp9: vp9, stillEncoders: [FakeEncoder(codec: .heic, result: Data([1]))],
                                       takeKeyframeRequest: { defer { pending = false }; return pending })

        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        XCTAssertEqual(vp9.forceKeyframeCount, 1, "a pending request forces a keyframe")
        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        XCTAssertEqual(vp9.forceKeyframeCount, 1, "consumed once — not re-forced every frame")
    }

    func testVP9PermanentFailureLatchesToStills() {
        let vp9 = FakeVideoEncoder(result: .failed)
        let still = FakeEncoder(codec: .heic, result: Data([2]))
        let streamer = makeVP9Streamer(vp9: vp9, stillEncoders: [still])

        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)
        streamer.handle(pixelBuffer: makePixelBuffer(), position: .back, orientation: .portrait, fps: 30)

        XCTAssertEqual(vp9.encodeCount, 1, "a failed VP9 encoder is latched off, never retried")
        XCTAssertEqual(sentFrames.map(\.codec), [.heic, .heic], "the stream falls back to stills")
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

    /// Old-camera → new-monitor: an old camera streams stills tagged JPEG (a
    /// legacy sender's absent codec also decodes as JPEG). The monitor must keep
    /// rendering them through the still path even though it also has a VP9
    /// decoder — no keyframe request is raised for a still.
    func testLegacyStillFrameStillRendersOnNewMonitor() {
        var keyframeRequests = 0
        receiver.onKeyframeNeeded = { keyframeRequests += 1 }

        deliver(makeOnFrame(data: validJPEG, codec: .jpeg, sequenceNumber: 1))

        XCTAssertEqual(images.count, 1, "a JPEG still from an old camera must render")
        XCTAssertEqual(keyframeRequests, 0, "stills never trigger a VP9 keyframe request")
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
        let data = try XCTUnwrap(encodedData(encoder.encode(pixelBuffer: makePixelBuffer(width: 400, height: 200))))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 100)
    }

    func testHEICEncoderProducesDecodableDownscaledImage() throws {
        let encoder = HEICFrameEncoder(maxLongEdge: 100, quality: 0.5)
        let data = encodedData(encoder.encode(pixelBuffer: makePixelBuffer(width: 400, height: 200)))
        try XCTSkipIf(data == nil, "HEVC encoder unavailable on this simulator/host")
        let image = try XCTUnwrap(UIImage(data: data!))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 100)
    }

    func testSmallFrameIsNotUpscaled() throws {
        let encoder = JPEGFrameEncoder(maxLongEdge: 960, quality: 0.6)
        let data = try XCTUnwrap(encodedData(encoder.encode(pixelBuffer: makePixelBuffer(width: 64, height: 32))))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(image.size.width, image.size.height), 64)
    }
}

// MARK: - HEVC peer preview codec

final class HEVCStreamingTests: XCTestCase {

    /// The self-describing wire container survives a pack/unpack round trip for
    /// both keyframes (parameter sets present) and inter frames (none).
    func testHEVCFrameContainerRoundTrip() throws {
        let params = Data([1, 2, 3, 4, 5])
        let frame = Data([9, 8, 7, 6])

        let keyframe = try XCTUnwrap(HEVCFrameContainer.unpack(
            HEVCFrameContainer.pack(parameterSets: params, frame: frame)))
        XCTAssertEqual(keyframe.parameterSets, params)
        XCTAssertEqual(keyframe.frame, frame)

        let interFrame = try XCTUnwrap(HEVCFrameContainer.unpack(
            HEVCFrameContainer.pack(parameterSets: nil, frame: frame)))
        XCTAssertNil(interFrame.parameterSets, "inter frames carry no parameter sets")
        XCTAssertEqual(interFrame.frame, frame)
    }

    /// A truncated header or a length that overruns the buffer is rejected rather
    /// than read out of bounds (FlatBuffers `Data` may be unaligned).
    func testHEVCFrameContainerRejectsMalformed() {
        XCTAssertNil(HEVCFrameContainer.unpack(Data([0, 0])), "header shorter than 4 bytes")
        XCTAssertNil(HEVCFrameContainer.unpack(Data([0xFF, 0xFF, 0xFF, 0xFF, 0])), "param length overruns buffer")
    }

    /// Alignment-safe UInt32 read at a non-zero (unaligned) offset — the exact
    /// crash the little-endian helpers exist to prevent.
    func testUInt32LEReadAtUnalignedOffset() {
        var data = Data([0xAA])              // 1-byte pad → next read is unaligned
        data.appendUInt32LE(0x0403_0201)
        XCTAssertEqual(data.readUInt32LE(at: 1), 0x0403_0201)
    }

    /// End-to-end: the HEVC encoder's keyframe decodes back to an image at the
    /// downscaled size. Hardware HEVC encode is A10+/host-dependent — and the iOS
    /// simulator can create a session but emit nothing — so this skips whenever
    /// the encode produces no frame, exactly as the sibling HEIC test does.
    func testHEVCEncodeDecodeRoundTrip() throws {
        let encoder = HEVCFrameEncoder(
            maxLongEdge: 128,
            settings: HEVCSettings(bitrateKbps: 300, fps: 30, keyframeInterval: 30))
        let decoder = PeerHEVCPreviewDecoder()

        // A fresh session's first frame is a keyframe carrying VPS/SPS/PPS.
        let payload = encodedData(encoder.encode(pixelBuffer: makePixelBuffer(width: 256, height: 128)))
        try XCTSkipIf(payload == nil, "HEVC hardware encode unavailable on this simulator/host")

        let parts = try XCTUnwrap(HEVCFrameContainer.unpack(payload!))
        XCTAssertNotNil(parts.parameterSets, "keyframe must carry parameter sets so the monitor can re-sync")

        let image = try XCTUnwrap(decoder.decode(payload!), "keyframe should decode to an image")
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 128)
    }
}
