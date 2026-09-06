# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Remote Shutter is an iOS + Mac Catalyst app (Swift, UIKit + SwiftUI) that turns two Apple devices into a remote-controlled camera system via peer-to-peer connectivity. One device acts as the **camera**, the other as the **monitor** (remote control). A Mac can take either role; it selects among N attached cameras (built-in, Continuity, USB) rather than front/back. Published on the App Store (iOS).

## Build & Run

```bash
# Build (uses xcworkspace because of CocoaPods)
xcodebuild -workspace RemoteShutter.xcworkspace -scheme RemoteCam \
  -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' \
  -configuration Debug clean build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild -workspace RemoteShutter.xcworkspace -scheme RemoteCam \
  -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' \
  -configuration Debug test \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Build for Mac Catalyst (build-only in CI; tests run on the iOS Simulator)
xcodebuild -workspace RemoteShutter.xcworkspace -scheme RemoteCam \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Release (via fastlane)
fastlane release
```

Always use `RemoteShutter.xcworkspace` (not `.xcodeproj`) due to CocoaPods. The scheme is `RemoteCam`. Minimum deployment target is iOS 15.0; the same target builds for Mac Catalyst ("Optimize for Mac" idiom, device family `1,2,6`).

## Deployment

Releases are deployed via GitHub Actions CI. The workflow is:
1. Commit and push the branch to GitHub
2. Create a PR to `master`
3. CI runs `fastlane release` which builds, signs (via `match`), and uploads to App Store Connect

Never attempt to run `fastlane release` locally — it requires CI environment variables (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`, `MATCH_GIT_URL`) and `setup_ci`. Always push to GitHub and let CI handle it.

## Architecture

### Session state machine (SessionCoordinator)

See `Docs/ARCHITECTURE.md` for the readable overview. The session is a Swift
`actor` — **`SessionCoordinator`** (SessionCoordinator.swift) — holding the
complete state space as the `SessionState` enum (~20 states across the
scanning/connected, camera, monitor, and watch families) plus all per-state
message handlers in the same file. Messages enter through `tell(_:)` (or the
`coordinator ! msg` operator sugar) into a FIFO `AsyncStream` inbox and are
processed one at a time; state context (peer, lobby, `CameraControlling` ctrl,
`MonitorPresenter`) lives in actor-isolated properties.

Key collaborators (plain objects, injected by the screen that owns the session):
- **`MonitorPresenter`** — routes session results to the monitor screen's
  `MonitorDisplay`/view model, hopping to main internally.
- **`FrameSender`** — queue-confined preview-frame streamer with credit-window
  back-pressure (only sends when the monitor has acked).
- **`CameraRig`** — the camera device as one non-UI object; the production
  `CameraControlling` conformer (an `async throws` protocol).

Ownership: `DeviceScannerViewController` creates the coordinator + FrameSender
pair and injects them into the camera/monitor screens; the Watch-remote screen
owns its own pair. Transient request states arm 10-second generation-counted
timeouts; long-lived states (recording, modes) deliberately have none.

### Message Protocol

Two message hierarchies (both subclassing the app's `Message` base in
Messages.swift) handle communication:
- **`RemoteCmd`** (RemoteCmds.swift) — Messages sent between devices over the peer session, serialized as **FlatBuffers** (`RemoteCmdFlatBuffers.swift` + schemas in `FlatBufferSchemas.fbs`).
- **`UICmd`** (UICmds.swift) — Local messages from screens into the session coordinator within a single device.

When adding new remote commands, add a table to `FlatBufferSchemas.fbs`, regenerate `FlatBufferSchemas_generated.swift` with `flatc`, and wire the encode/decode paths in `RemoteCmdFlatBuffers.swift`. All FlatBuffer enums must have `Unknown = 0` as the default.

### UI Architecture

Every screen is a SwiftUI view hosted by a thin UIKit shell (no storyboards or xibs; the window is built programmatically in `SceneDelegate`):
- **WelcomeViewController** — upgrade/paywall screen, hosts `WelcomeView`; no longer part of the launch flow (Settings has its own separate purchase UI); kept for its test coverage but not currently pushed anywhere in the app
- **RolePickerController** — entry point (root of the nav controller), role selection, hosts `RolePickerView`
- **DeviceScannerViewController** — peer discovery, hosts `DeviceScannerView`; owns the `SessionCoordinator` + `FrameSender` lifecycle
- **MonitorViewController** — hosts `MonitorView`; implements `MonitorDisplay`, the protocol seam through which `MonitorPresenter` drives the screen
- **CameraHostController** — hosts `CameraScreenView` (preview + chrome) and owns a `CameraRig`, which holds the capture stack (`CaptureEngine` + `RecordingPipeline` + `FrameStreamingCoordinator`)
- **WatchRemoteCameraController** — Watch-remote mode, embeds the camera screen and bridges `WCSession` commands into the coordinator
- View models (`WelcomeViewModel`, `DeviceScannerViewModel`, `MonitorViewModel`, `CameraViewModel`) are ObservableObjects; all `@Published` writes happen on main

Threading: the coordinator serializes via its actor inbox; `CaptureEngine` state is confined to its `sessionQueue`; recording state to the single `dataOutputQueue` (which delivers both video and audio frames); the few per-frame cross-domain values use `Locked<T>`. The full test suite runs clean under Thread Sanitizer — keep it that way.

### P2P Communication

Uses **Stormo** (github.com/security-union/Stormo — QUIC over Network.framework, pinned exact 2.0.0) via its MPCCompat drop-in API; app code keeps the legacy MC type names through app-local typealiases in `MultipeerCompatAliases.swift`. Service type `"remotecam"` (bare MPC style; MPCCompat translates it to `_remotecam._udp` — must match `NSBonjourServices` in Info.plist). Encapsulated in `MultipeerService` (`MultipeerServiceProtocol` is the test seam); messages are FlatBuffers via `MCSession.send()`, video files via `MCSession.sendResource()` with progress. Requires the Keychain Sharing entitlement (TLS identity lives in the data-protection keychain; advertising fails at startup without it on Catalyst). `QUIC_DEBUG=1` in the scheme makes the transport narrate to the console; both devices must run Stormo builds (no wire interop with MPC-era versions). See Stormo's CLAUDE.md for transport failure modes.

### Dependencies (CocoaPods)

- **SwiftLint** (~0.41.0) — Linting
- **FlatBuffers** (local podspec) — Wire-protocol serialization (iOS + watchOS targets)

The session uses Swift's native `actor` for concurrency (see `Docs/ARCHITECTURE.md`).

### macOS (Mac Catalyst)

The Mac build is the same app target. Rules that matter when touching platform-y code:
- Camera identity is `uniqueID`-based (`CameraDeviceDescriptor`, `CameraControlling.selectCameraDevice`); Mac cameras report `.unspecified` position, which serializes as `Back + has_unspecified_position` on the wire.
- A monitor may only send `RemoteCmd.SelectCameraDevice` to a peer whose capabilities carried a non-empty `camera_devices` list. The gate lives in `SessionCoordinator` and is pinned by a loopback test. (`CommandAction.Unknown = 0`, so an action a peer doesn't know is ignored, not misread — the gate is about not sending meaningless commands.)
- WatchConnectivity does not exist on Catalyst: `WatchSessionManager` has a stub branch; keep new Watch code behind it.
- Macs don't rotate: `getOrientation()` returns `.landscapeRight` on Catalyst; don't add rotation handling outside the `#if !targetEnvironment(macCatalyst)` paths.
- Platform shims (sleep, System Settings deep links) use `#if targetEnvironment(macCatalyst)` — extend those branches rather than adding UIKit-only calls.
- Preview frames are ALWAYS sent `.unreliable` (never `.reliable` — live preview drops, never queues); the transport's datagram channel is warmed with a no-op ping at peer connect. Frame durations must be clamped into the `AVFrameRateRange`'s own CMTimes (`CaptureEngine.resolveFrameRate`), never rebuilt as `CMTimeMake(1, fps)`.
- Hardware integration tests (real cameras, skip on simulator/CI): `xcodebuild test … -destination 'platform=macOS,variant=Mac Catalyst' -only-testing:RemoteShutterTests/CaptureIntegrationTests`.

### Feature Flags

Centralized in `FeatureFlags.swift`. Check existing flags before adding new ones.

### App Store Metadata (Fastlane)

Metadata lives in `fastlane/metadata/<locale>/`. When editing `keywords.txt` files, **keywords must be 100 characters or fewer** (including commas). App Store Connect will reject the upload if any locale exceeds this limit. Always verify with `wc -m` (characters, not bytes — CJK keyword sets legitimately exceed 100 *bytes*) before committing. Other field limits: app name 30 chars, subtitle 30 chars, promotional text 170 chars, description 4000 chars.

Search indexing (cross-localization): each storefront indexes exactly two locales — its own language plus a designated secondary. Most European storefronts (France, Germany, Italy, …) index **English (U.K.)**, not en-US; the US storefront indexes en-US + es-MX. For this reason `en-GB` is a byte-for-byte copy of `en-US`, and `es-ES` of `es-MX` — **keep them in sync whenever the source locale changes**. Keywords never combine across locales (a word in en-US can't form a phrase with a word in fr-FR), so every locale's keyword set must stand alone. The app *name* is indexed on every storefront and outranks the keyword field — brand queries ("remote shutter") match everywhere regardless of keywords. Screenshots for en-GB/es-ES are not duplicated; ASC falls back to the primary locale's media. Product-name rule from the 6.0.10 rejection (5.2.5): Apple product names ("Apple Watch", "iPhone") are compatibility-context-only — fine in descriptions, **never in app name or subtitles**. Metadata must not contradict in-app requirements (2.3.1): the app requires the Wi-Fi radio ON, so say "no router / no Wi-Fi network needed", never "no WiFi".

### App Store Screenshots

Screenshots for all 10 locales are generated by `store_assets/screenshot-pipeline/` (see its README for full docs). Rendering is deterministic — headless Chrome over `manifest.js` (layouts/quads) + `translations.js` (all localized strings); **no AI calls at render time**.

- Regenerate everything: `cd store_assets/screenshot-pipeline && ./ship-locales.sh` (writes iPhone/iPad shots to `fastlane/screenshots/<locale>/`, Mac shots to `fastlane/screenshots_mac/<locale>/`; keeps Watch captures). The trees are separate because deliver uploads everything in its screenshots_path to one platform — APP_DESKTOP display types are rejected on the iOS version and vice versa.
- Change a caption/translation: edit `translations.js`, re-run `./ship-locales.sh [locale...]`.
- New scenes need the `AI_STUDIO` env var (Google AI Studio key) and `generate.mjs` (Nano Banana); screens are generated black/off and the pipeline composites **real app UI** captures (App Review 2.3.3). Quads are measured with `tools.py detect`/`overlay` — always verify overlays visually.
- Rules: iPad screenshots show iPads; the camera device's orientation must match the remote's live-preview aspect; the subject shown on screens must match the scene (same object, same orientation).
- Event banners land in `out/<locale>/event_card_3840x2160.png` — uploaded manually in App Store Connect (In-App Events), not via fastlane.

#### Nano Banana prompting rules (learned 2026-08; follow every time)

Per Google's official guidance (cloud.google.com "Ultimate prompting guide for
Nano Banana", blog.google Nano Banana Pro prompt tips):

- **Positive framing only — never negatives.** Gemini-family image models have
  no negative-prompt mechanism; the whole prompt is one semantic target, so
  "no cars" mostly injects *cars*. Describe the desired state instead:
  "empty street with clear pavement", "bare brushed-metal bezel", "pure glossy
  black switched-off screen", "her hair smooth and continuous". This applies
  to artifact fixes too — describe what the clean region looks like, not the
  blemish to remove.
- **Iterate, don't re-roll.** When a candidate is ~80% right, EDIT that
  candidate (`node generate.mjs edit <candidate> <out> "<prompt>"`) with
  targeted changes instead of regenerating from the base scene — a re-roll
  gambles away everything that already landed well.
- **Re-anchor what must not change.** In edit prompts, close by re-describing
  the elements that stay (subject, devices, mounts, lighting) — that is what
  keeps an edit from drifting.
- **Generate 2–3 candidates and reject; record the keeper in `CHOSEN`.**
  Prompt clauses reduce but never guarantee; the rejection pass is the real
  quality gate.
- **Recurring failure modes to inspect at full res before accepting:** brand
  text on device bezels ("MacBook Pro"), fake logos/glow on "off" screens
  (screens must read black), floating artifact shapes (check hair/skin
  especially), merged/overlapping devices, Apple logos anywhere.
- Structure new base-scene prompts on the five-part formula already noted in
  `generate.mjs`: [Cinematography] + [Subject] + [Action] + [Context] +
  [Style & Ambiance]; use concrete camera/lighting vocabulary ("85mm f/2.8",
  "soft daylight", "over-the-shoulder").

### In-App Purchases

Managed by `PKIAPHandler.swift` (`InAppPurchasesManager`). Product IDs: `05` (remove ads), `06` (enable video), `07` (enable torch), `08` (enable video only).

IAP display names/descriptions for all locales live in `fastlane/iap_localizations.json`; sync them to App Store Connect with the "Sync IAP Localizations" GitHub workflow or `bundle exec fastlane ios sync_iap` (needs ASC key env vars). Limits: name ≤30 chars, description ≤45 chars.
