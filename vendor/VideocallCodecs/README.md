# VideocallCodecs — pure-Rust VP9 for RemoteShutter

Swift bindings for the pure-Rust VP9 **encoder + decoder** (from `videocall-rs`,
crate `videocall-codecs`). No libvpx, no C, no browser/VideoToolbox dependency.
Ships as a static `.xcframework` + a generated Swift wrapper, vendored via a local
CocoaPod. This is the guide for the agent wiring VP9 into the app's video path.

## Status / how it's already wired in

- `Vendor/VideocallCodecs/` holds the `.xcframework`, the generated
  `videocall_codecs.swift`, and `VideocallCodecs.podspec`.
- The `Podfile` adds `pod 'VideocallCodecs', :path => 'Vendor/VideocallCodecs'`
  to **both** `RemoteShutter` (iOS / Mac Catalyst) and `RemoteShutterWatch`.
- Verified building: **iOS Simulator, Mac Catalyst, and the embedded watchOS app.**
- Use it from Swift with: `import VideocallCodecs`

Do **not** add a loose `module.modulemap` for `videocall_codecsFFI` — the
xcframework already carries one per slice; a second copy causes
`redefinition of module 'videocall_codecsFFI'`.

## The Swift API

```swift
import VideocallCodecs

// --- Encoder (camera side) ---
let enc = try Vp9Encoder(
    width: 640, height: 480,     // MUST be even, MUST match every frame you feed
    fps: 30,
    bitrateKbps: 500,
    keyframeInterval: 150,        // a keyframe is emitted at least this often
    minQuantizer: 40, maxQuantizer: 60,
    cpuUsed: 7                    // 0..8 speed/quality; 7-8 = realtime
)
// Feed frames IN ORDER with a monotonically-increasing pts.
// Returns the compressed VP9 frame, or nil if the encoder buffered this input.
let packet: Data? = try enc.encode(pts: Int64(frameIndex), i420: i420Data)
try enc.updateBitrate(kbps: 800)  // adapt to link conditions at runtime

// --- Decoder (monitor / phone / watch side) ---
let dec = Vp9Decoder()
let frame = try dec.decode(frame: packet)   // -> DecodedFrame
// frame.data   : Data   (raw I420, tightly packed — see below)
// frame.width  : UInt32
// frame.height : UInt32
```

Errors are thrown as `CodecError`: `.InvalidConfig(message:)`, `.Encode(message:)`,
`.Decode(message:)`, `.Internal(message:)`. Always `try`/`catch` — the decoder
returns an error (never crashes) on a malformed/undecodable packet.

## The pixel format is I420 (this is the important part)

Both `encode(i420:)` and `DecodedFrame.data` use **8-bit planar YUV 4:2:0 (I420)**,
tightly packed, no row padding:

```
[ Y plane: width*height bytes                    ]  (stride = width)
[ U plane: (width/2)*(height/2) bytes            ]  (stride = width/2)
[ V plane: (width/2)*(height/2) bytes            ]  (stride = width/2)
total = width * height * 3 / 2
```

The camera produces `CVPixelBuffer`s (BGRA or `'420v'`/`'420f'`), and the current
preview path ships JPEG. So the integration is two conversions:

- **Camera → encode:** `CVPixelBuffer` → I420 `Data` → `enc.encode(...)`.
  If the capture format is already bi-planar 4:2:0 (`420v`/`420f`), you interleave
  the CbCr plane into separate U/V planes; if it's BGRA, do a color convert
  (vImage `vImageConvert_ARGB8888To420Yp8_CbCr8` then split, or an accelerate/Metal
  path). Keep width/height even and constant per encoder instance.
- **Decode → display:** `DecodedFrame.data` (I420) → `CVPixelBuffer`/`CGImage`/`UIImage`
  (vImage `vImageConvert_420Yp8_Cb8_Cr8ToARGB8888`, or build a `CVPixelBuffer` of
  type `kCVPixelFormatType_420YpCbCr8Planar` and copy the three planes in).

A small `PixelBufferI420` helper (CVPixelBuffer <-> I420 Data) is the natural first
utility to add; both directions are pure memory shuffles.

## Statefulness & frame ordering (do not skip this)

Both objects are **stateful and order-dependent** — VP9 inter frames reference the
previous frame:

- **One encoder / one decoder per stream.** Don't share across independent streams.
- **Feed frames strictly in capture/transmit order**, monotonically increasing `pts`.
- **The decoder must receive every frame in order.** If an inter frame is lost or
  reordered, the decoder desyncs and every following frame decodes wrong **until the
  next keyframe**. Over a lossy channel you must either (a) use a reliable/ordered
  transport for the video stream, or (b) detect loss and wait for the next keyframe
  (dropping frames until then). The encoder emits a keyframe every
  `keyframeInterval` frames; the first `encode` call is always a keyframe.
- **Known gap:** there is no "force keyframe on demand" call exposed yet, so
  recovery latency after loss is bounded by `keyframeInterval`. If the app needs
  fast recovery (e.g. the Watch reconnecting mid-stream), lower `keyframeInterval`,
  or request adding a `forceKeyframe()` to the FFI (the Rust encoder already has
  `force_keyframe()` internally). For a reliable WCSession preview this is a non-issue.

## Threading

- `Vp9Decoder` runs the actual decoder on a **dedicated worker thread**; calls are
  serialized behind it (which also preserves the required frame order). It's safe to
  call `decode` from any thread, but calls don't run in parallel. Decode off the main
  thread (as the current JPEG preview path already does).
- `Vp9Encoder` is a plain object guarded by a lock; encode off the capture thread.
- One caveat inherited from the FFI: if the decoder worker ever dies, that decoder
  instance is done — create a fresh `Vp9Decoder` (the next keyframe recovers). The
  decoder is audited panic-free on arbitrary input, so this is defense-in-depth.

## Where to plug it into RemoteShutter

Today the camera streams **per-frame JPEG/HEIC** (`RemoteCam/{FrameCodecs,
JPEGFrameEncoder,HEICFrameEncoder,FrameStreamer}.swift`) and the Watch renders a JPEG
preview (`RemoteShutterWatch/WatchSessionDelegate.swift` → `WatchPreviewFrameEncoder`).
The VP9 swap:

1. **Camera device (encode):** where a frame is currently JPEG-encoded before send,
   instead run it through a single long-lived `Vp9Encoder` (CVPixelBuffer → I420 →
   `encode`). Send the returned `Data` packet. This is where the bandwidth win is —
   VP9 inter-frames vs independent JPEGs.
2. **Monitor / Watch (decode):** where a received frame is currently JPEG-decoded to a
   `UIImage`, instead feed the packet to a single long-lived `Vp9Decoder`
   (`decode` → I420 → `UIImage`/`CVPixelBuffer`). The Watch preview path
   (`renderPreview(jpeg:)`) becomes `renderPreview(vp9:)`.
3. Keep JPEG as a fallback/negotiated codec initially (a `FrameCodec` enum case) so
   you can A/B and roll back — mirror how the codec is already abstracted in
   `FrameCodecs.swift`.

## Regenerating / updating the framework

The framework is built from `videocall-rs`:
`videocall-codecs/build_ios.sh` (see `videocall-codecs/README-ios.md`). It produces
`target/VideocallCodecs.xcframework` with 6 slices — ios device/sim,
**ios-maccatalyst**, macos, watchos device (arm64_32+arm64), watchos-sim — plus the
Swift bindings in `target/swift-codecs/`. To update this vendored copy:

```sh
# in videocall-rs:
./videocall-codecs/build_ios.sh
# then copy into this dir (overwrite the xcframework + the .swift):
cp -R target/VideocallCodecs.xcframework  <remote-shutter>/Vendor/VideocallCodecs/
cp    target/swift-codecs/videocall_codecs.swift <remote-shutter>/Vendor/VideocallCodecs/
# then: bundle exec pod install
```

## Known caveats

- **Simulator slices are arm64-only.** Fine on Apple Silicon (the default Debug build
  uses only the active arch). An Intel Mac, or a Release/`archive` that builds *all*
  simulator archs, would need x86_64 simulator slices added to the xcframework
  (`x86_64-apple-ios` is easy Tier-2; `x86_64-apple-watchos-sim` is Tier-3/build-std).
  Device + Catalyst builds are unaffected.
- **watchOS build of the framework requires a nightly Rust toolchain** (Tier-3
  `-Zbuild-std`); see `videocall-codecs/README-ios.md`.
- VP9 **profile 0 only** (8-bit 4:2:0) — which is exactly what camera capture is.
