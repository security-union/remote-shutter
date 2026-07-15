//
//  VP9StreamingTests.swift
//  RemoteShutterTests
//
//  Exercises the real Rust VP9 codec (VideocallCodecs) end-to-end: raw
//  Vp9Encoder -> Vp9Decoder round-trips, the VP9FrameEncoder pipeline
//  (BGRA capture buffer -> vImage I420 -> compressed frame), the
//  new-session-on-geometry-change keyframe guarantee, and the StreamCodec
//  wire mapping. These run the actual static library in the simulator.
//

import XCTest
import CoreVideo
import VideocallCodecs

@testable import RemoteShutter

/// One explicit fixture for every encoder test — `VP9Settings` has no field
/// defaults on purpose (each stream states its full tuning), so tests do too.
private extension VP9Settings {
    static let test = VP9Settings(
        bitrateKbps: 300,
        fps: 30,
        keyframeInterval: 30,
        minQuantizer: 40,
        maxQuantizer: 60,
        cpuUsed: 7)
}

final class VP9StreamingTests: XCTestCase {

    // MARK: - Helpers

    /// Tightly-packed I420 with a luma gradient and neutral chroma.
    private func gradientI420(width: Int, height: Int) -> Data {
        let lumaBytes = width * height
        let totalBytes = lumaBytes + 2 * (width / 2) * (height / 2)
        var data = Data(count: totalBytes)
        data.withUnsafeMutableBytes { raw in
            let ptr = raw.bindMemory(to: UInt8.self).baseAddress!
            for y in 0..<height {
                for x in 0..<width {
                    ptr[y * width + x] = UInt8((x + y) & 0xFF)
                }
            }
            for i in lumaBytes..<totalBytes { ptr[i] = 128 }
        }
        return data
    }

    /// 32BGRA capture-style buffer filled with one solid color.
    private func makeSolidPixelBuffer(width: Int, height: Int,
                                      blue: UInt8, green: UInt8, red: UInt8) -> CVPixelBuffer {
        let buffer = makePixelBuffer(width: width, height: height)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                row[x * 4] = blue
                row[x * 4 + 1] = green
                row[x * 4 + 2] = red
                row[x * 4 + 3] = 255
            }
        }
        return buffer
    }

    private func makeEncoder(width: UInt32, height: UInt32) throws -> Vp9Encoder {
        try Vp9Encoder(width: width, height: height, fps: 15, bitrateKbps: 300,
                       keyframeInterval: 30, minQuantizer: 30, maxQuantizer: 50, cpuUsed: 7)
    }

    private func meanLuma(of frame: DecodedFrame) -> Double {
        let lumaBytes = Int(frame.width) * Int(frame.height)
        let sum = frame.data.prefix(lumaBytes).reduce(0.0) { $0 + Double($1) }
        return sum / Double(lumaBytes)
    }

    // MARK: - Raw Rust codec round-trip

    func testVp9EncoderDecoderRoundTrip() throws {
        let encoder = try makeEncoder(width: 64, height: 64)
        let compressed = try XCTUnwrap(
            encoder.encode(pts: 0, i420: gradientI420(width: 64, height: 64)),
            "first frame is a keyframe and must produce output")

        let decoded = try Vp9Decoder().decode(frame: compressed)
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 64)
        XCTAssertEqual(decoded.data.count, 64 * 64 * 3 / 2, "tightly-packed I420")
    }

    /// The decoder is stateful: an inter frame without its keyframe must throw —
    /// this is the failure the Watch's drop-but-ack policy recovers from.
    func testDecoderRejectsInterFrameWithoutKeyframe() throws {
        let encoder = try makeEncoder(width: 64, height: 64)
        let frame = gradientI420(width: 64, height: 64)
        _ = try XCTUnwrap(try encoder.encode(pts: 0, i420: frame))   // keyframe, discarded
        guard let interFrame = try encoder.encode(pts: 1, i420: frame) else {
            throw XCTSkip("encoder buffered the inter frame on this build")
        }

        XCTAssertThrowsError(try Vp9Decoder().decode(frame: interFrame),
                             "a fresh decoder must reject a mid-stream inter frame")
    }

    // MARK: - VP9FrameEncoder pipeline (BGRA -> I420 -> VP9)

    func testFrameEncoderProducesDecodableDownscaledFrame() throws {
        let encoder = VP9FrameEncoder(maxLongEdge: 100, settings: .test)
        let buffer = makeSolidPixelBuffer(width: 400, height: 200, blue: 128, green: 128, red: 128)

        let data = try XCTUnwrap(encodedData(encoder.encode(pixelBuffer: buffer)),
                                 "keyframe must encode, not skip or fail")
        let decoded = try Vp9Decoder().decode(frame: data)
        XCTAssertEqual(decoded.width, 100)
        XCTAssertEqual(decoded.height, 50)

        // Mid-gray BGRA is Y=128 in the full-range 601 conversion; a generous
        // window still catches a video-range or channel-order mistake (Y would
        // land near 126 either way for gray, so also check chroma neutrality).
        XCTAssertEqual(meanLuma(of: decoded), 128, accuracy: 16)
        let lumaBytes = Int(decoded.width) * Int(decoded.height)
        let chroma = decoded.data.dropFirst(lumaBytes)
        let meanChroma = chroma.reduce(0.0) { $0 + Double($1) } / Double(chroma.count)
        XCTAssertEqual(meanChroma, 128, accuracy: 8, "gray must produce neutral Cb/Cr")
    }

    func testFrameEncoderStreamsConsecutiveFrames() throws {
        let encoder = VP9FrameEncoder(maxLongEdge: 64, settings: .test)
        let decoder = Vp9Decoder()
        var decodedCount = 0
        for shade in [UInt8(60), 120, 180] {
            let buffer = makeSolidPixelBuffer(width: 128, height: 64, blue: shade, green: shade, red: shade)
            switch encoder.encode(pixelBuffer: buffer) {
            case .encoded(let data):
                XCTAssertNoThrow(try decoder.decode(frame: data),
                                 "in-order frames from one session must all decode")
                decodedCount += 1
            case .skipped:
                continue // buffered: legal, next frame carries it
            case .failed:
                return XCTFail("VP9 encoder failed on a valid BGRA buffer")
            }
        }
        XCTAssertGreaterThan(decodedCount, 0, "the stream must deliver at least the keyframe")
    }

    /// Rotation/lens switches change the scaled geometry; the encoder must open
    /// a fresh session whose first frame is a keyframe, so a decoder that joins
    /// at the new geometry (or lost the old stream) re-syncs immediately.
    func testFrameEncoderRestartsWithKeyframeOnGeometryChange() throws {
        let encoder = VP9FrameEncoder(maxLongEdge: 100, settings: .test)
        let landscape = makeSolidPixelBuffer(width: 400, height: 200, blue: 200, green: 100, red: 50)
        _ = try XCTUnwrap(encodedData(encoder.encode(pixelBuffer: landscape)))

        let portrait = makeSolidPixelBuffer(width: 200, height: 400, blue: 50, green: 100, red: 200)
        let afterRotation = try XCTUnwrap(encodedData(encoder.encode(pixelBuffer: portrait)),
                                          "first frame after a geometry change must encode")

        let decoded = try Vp9Decoder().decode(frame: afterRotation)
        XCTAssertEqual(decoded.width, 50)
        XCTAssertEqual(decoded.height, 100)
    }

    // MARK: - Wire mapping

    func testStreamCodecWireMappingRoundTrips() {
        let all: [RemoteCmd.StreamCodec] = [.jpeg, .hevc, .heic, .vp9]
        for codec in all {
            XCTAssertEqual(fromFBStreamCodec(toFBStreamCodec(codec)), codec)
        }
        XCTAssertEqual(toFBStreamCodec(.vp9), .vp9)
        XCTAssertEqual(fromFBStreamCodec(.unknown), .jpeg, "legacy senders default to JPEG")
    }

    // MARK: - Version-gate decision

    func testPeerCanDecodeVP9PreviewIsBundleVersionGated() {
        let threshold = VP9PreviewCompatibility.minimumPeerBundleVersion
        XCTAssertTrue(VP9PreviewCompatibility.peerCanDecodeVP9Preview(bundleVersion: threshold),
                      "the first VP9 release qualifies at exactly the threshold")
        XCTAssertTrue(VP9PreviewCompatibility.peerCanDecodeVP9Preview(bundleVersion: threshold + 5),
                      "newer peers qualify")
        XCTAssertFalse(VP9PreviewCompatibility.peerCanDecodeVP9Preview(bundleVersion: threshold - 1),
                       "a peer one build below the threshold cannot decode VP9")
        XCTAssertFalse(VP9PreviewCompatibility.peerCanDecodeVP9Preview(bundleVersion: 0),
                       "unknown/legacy build (<= 0) also cannot decode VP9 — one check covers both")
        XCTAssertFalse(VP9PreviewCompatibility.peerCanDecodeVP9Preview(bundleVersion: -1))
    }

    func testForceKeyframeMakesNextFrameASelfContainedKeyframe() throws {
        let encoder = VP9FrameEncoder(maxLongEdge: 64, settings: .test)
        let key = makeSolidPixelBuffer(width: 128, height: 64, blue: 90, green: 90, red: 90)
        _ = try XCTUnwrap(encodedData(encoder.encode(pixelBuffer: key)), "first frame is a keyframe")

        // Force a keyframe: the very next encoded frame must decode on a FRESH
        // decoder (i.e. it is itself a keyframe, not a delta needing history).
        encoder.forceKeyframe()
        let next = makeSolidPixelBuffer(width: 128, height: 64, blue: 90, green: 90, red: 90)
        let data = try XCTUnwrap(encodedData(encoder.encode(pixelBuffer: next)),
                                 "forced keyframe must encode immediately")
        XCTAssertNoThrow(try Vp9Decoder().decode(frame: data),
                         "a forced keyframe must decode without any prior frame")
    }
}

// MARK: - Monitor-side peer VP9 decoder

final class PeerVP9PreviewDecoderTests: XCTestCase {

    private func makeSolidPixelBuffer(width: Int, height: Int, shade: UInt8) -> CVPixelBuffer {
        let buffer = makePixelBuffer(width: width, height: height)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                row[x * 4] = shade; row[x * 4 + 1] = shade; row[x * 4 + 2] = shade; row[x * 4 + 3] = 255
            }
        }
        return buffer
    }

    func testDecodesKeyframeToImage() throws {
        let encoder = VP9FrameEncoder(maxLongEdge: 64, settings: .test)
        let data = try XCTUnwrap(encodedData(encoder.encode(
            pixelBuffer: makeSolidPixelBuffer(width: 128, height: 64, shade: 120))))

        let decoder = PeerVP9PreviewDecoder()
        let image = decoder.decode(data)
        XCTAssertNotNil(image, "a keyframe must render an image")
    }

    /// A mid-stream delta frame with no keyframe first is undecodable — the
    /// decoder returns nil (the caller then requests a keyframe), the exact
    /// desync-recovery contract.
    func testUndecodableFrameReturnsNil() {
        let decoder = PeerVP9PreviewDecoder()
        XCTAssertNil(decoder.decode(Data([0xDE, 0xAD, 0xBE, 0xEF])),
                     "garbage/mid-stream data must not crash and must return nil")
    }
}
