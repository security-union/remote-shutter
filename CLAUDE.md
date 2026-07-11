# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Remote Shutter is an iOS app (Swift, UIKit + SwiftUI) that turns two Apple devices into a remote-controlled camera system via peer-to-peer connectivity. One device acts as the **camera**, the other as the **monitor** (remote control). Published on the App Store.

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

# Release (via fastlane)
fastlane release
```

Always use `RemoteShutter.xcworkspace` (not `.xcodeproj`) due to CocoaPods. The scheme is `RemoteCam`. Minimum deployment target is iOS 15.0.

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
- **`RemoteCmd`** (RemoteCmds.swift) — Messages sent over MultipeerConnectivity between devices, serialized as **FlatBuffers** (`RemoteCmdFlatBuffers.swift` + schemas in `FlatBufferSchemas.fbs`).
- **`UICmd`** (UICmds.swift) — Local messages from screens into the session coordinator within a single device.

When adding new remote commands, add a table to `FlatBufferSchemas.fbs`, regenerate `FlatBufferSchemas_generated.swift` with `flatc`, and wire the encode/decode paths in `RemoteCmdFlatBuffers.swift`. All FlatBuffer enums must have `Unknown = 0` as the default.

### UI Architecture

Every screen is a SwiftUI view hosted by a thin UIKit shell (no storyboards or xibs; the window is built programmatically in `SceneDelegate`):
- **WelcomeViewController** — entry point (root of the nav controller), hosts `WelcomeView`
- **RolePickerController** — role selection, hosts `RolePickerView`
- **DeviceScannerViewController** — peer discovery, hosts `DeviceScannerView`; owns the `SessionCoordinator` + `FrameSender` lifecycle
- **MonitorViewController** — hosts `MonitorView`; implements `MonitorDisplay`, the protocol seam through which `MonitorPresenter` drives the screen
- **CameraHostController** — hosts `CameraScreenView` (preview + chrome) and owns a `CameraRig`, which holds the capture stack (`CaptureEngine` + `RecordingPipeline` + `FrameStreamingCoordinator`)
- **WatchRemoteCameraController** — Watch-remote mode, embeds the camera screen and bridges `WCSession` commands into the coordinator
- View models (`WelcomeViewModel`, `DeviceScannerViewModel`, `MonitorViewModel`, `CameraViewModel`) are ObservableObjects; all `@Published` writes happen on main

Threading: the coordinator serializes via its actor inbox; `CaptureEngine` state is confined to its `sessionQueue`; recording state to the single `dataOutputQueue` (which delivers both video and audio frames); the few per-frame cross-domain values use `Locked<T>`. The full test suite runs clean under Thread Sanitizer — keep it that way.

### P2P Communication

Uses Apple's **MultipeerConnectivity** framework (service type: `"RemoteCam"`), encapsulated in `MultipeerService` (`MultipeerServiceProtocol` is the test seam). Messages are serialized as FlatBuffers and sent via `MCSession.send()`. Video files use `MCSession.sendResource()` for large transfers with progress tracking.

### Dependencies (CocoaPods)

- **SwiftLint** (~0.41.0) — Linting
- **FlatBuffers** (local podspec) — Wire-protocol serialization (iOS + watchOS targets)

The session uses Swift's native `actor` for concurrency (see `Docs/ARCHITECTURE.md`).

### Feature Flags

Centralized in `FeatureFlags.swift`. Check existing flags before adding new ones.

### App Store Metadata (Fastlane)

Metadata lives in `fastlane/metadata/<locale>/`. When editing `keywords.txt` files, **keywords must be 100 characters or fewer** (including commas). App Store Connect will reject the upload if any locale exceeds this limit. Always verify with `wc -c` before committing. Other field limits: app name 30 chars, subtitle 30 chars, promotional text 170 chars, description 4000 chars.

### App Store Screenshots

Screenshots for all 10 locales are generated by `store_assets/screenshot-pipeline/` (see its README for full docs). Rendering is deterministic — headless Chrome over `manifest.js` (layouts/quads) + `translations.js` (all localized strings); **no AI calls at render time**.

- Regenerate everything: `cd store_assets/screenshot-pipeline && ./ship-locales.sh` (writes `fastlane/screenshots/<locale>/`; keeps Watch captures).
- Change a caption/translation: edit `translations.js`, re-run `./ship-locales.sh [locale...]`.
- New scenes need the `AI_STUDIO` env var (Google AI Studio key) and `generate.mjs` (Nano Banana); screens are generated black/off and the pipeline composites **real app UI** captures (App Review 2.3.3). Quads are measured with `tools.py detect`/`overlay` — always verify overlays visually.
- Rules: iPad screenshots show iPads; the camera device's orientation must match the remote's live-preview aspect; the subject shown on screens must match the scene (same object, same orientation).
- Event banners land in `out/<locale>/event_card_3840x2160.png` — uploaded manually in App Store Connect (In-App Events), not via fastlane.

### In-App Purchases

Managed by `PKIAPHandler.swift` (`InAppPurchasesManager`). Product IDs: `05` (remove ads), `06` (enable video), `07` (enable torch), `08` (enable video only).

IAP display names/descriptions for all locales live in `fastlane/iap_localizations.json`; sync them to App Store Connect with the "Sync IAP Localizations" GitHub workflow or `bundle exec fastlane ios sync_iap` (needs ASC key env vars). Limits: name ≤30 chars, description ≤45 chars.
