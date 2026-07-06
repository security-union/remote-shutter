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

### Actor Model (Theater framework)

The app uses the **Theater** pod — an actor-model framework. Actors communicate exclusively via messages (the `!` operator sends a message). All state transitions happen inside actor message handlers, never on the main thread (asserted in code).

Key actors (registered under `RemoteCamSystem.shared`):
- **`RemoteCamSession`** (`RemoteCam/user/RemoteCam Session`) — Central session actor managing the state machine. Plain Theater `Actor` bound to the scanner screen through the `ScannerLobby` protocol (`SetScannerLobby` message). Handles MultipeerConnectivity session and routes all remote commands.
- **`MonitorActor`** (`RemoteCam/user/MonitorActor`) — Bridge between session and `MonitorViewController`. Created/destroyed with the monitor screen lifecycle.
- **`FrameSender`** (`RemoteCam/user/FrameSender`) — Manages camera frame streaming with back-pressure (waits for ack before sending next frame).

Actor references are retrieved via: `RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/<name>")`

### State Machine

`RemoteCamSession` implements a hierarchical state machine using Theater's `become`/`unbecome`/`popToState` pattern. States are defined in `RemoteCamStates` (States.swift) and implemented across multiple files:

- **RemoteCamScanning.swift** — `scanning` state: peer discovery via MultipeerConnectivity
- **RemoteCamConnected.swift** — `connected` state: role selection (camera vs monitor)
- **CamStates.swift** — `camera`, `cameraTakingPic`, `cameraRecordingVideo` states
- **MonitorStates.swift** — `monitorTogglingFlash`, `monitorTogglingCamera`, `monitorSwitchingLens` states
- **MonitorPhotoStates.swift** — `monitorPhotoMode`, `monitorTakingPicture` states
- **MonitorVideoStates.swift** — `monitorVideoMode`, `monitorRecordingVideo` states
- **CameraVideoStates.swift** — Camera-side video recording states

### Message Protocol

Two message hierarchies handle communication:
- **`RemoteCmd`** (RemoteCmds.swift) — Messages sent over MultipeerConnectivity between devices, serialized as **FlatBuffers** (`RemoteCmdFlatBuffers.swift` + schemas in `FlatBufferSchemas.fbs`).
- **`UICmd`** (UICmds.swift) — Local messages between actors and view controllers within a single device.

When adding new remote commands, add a table to `FlatBufferSchemas.fbs`, regenerate `FlatBufferSchemas_generated.swift` with `flatc`, and wire the encode/decode paths in `RemoteCmdFlatBuffers.swift`. All FlatBuffer enums must have `Unknown = 0` as the default.

### UI Architecture

The app is migrating from UIKit to SwiftUI (no storyboards or xibs remain; the window is built programmatically in `SceneDelegate`). See `Docs/UI_MODERNIZATION.md` for the migration plan. Most screens are SwiftUI views hosted by thin UIKit shells via `UIHostingController`:
- **WelcomeViewController** — entry point (root of the nav controller), hosts `WelcomeView`
- **RolePickerController** — role selection, hosts `RolePickerView` (`RemoteCamSystem.shared` is declared in `RemoteCamSystem.swift`)
- **DeviceScannerViewController** — peer discovery, hosts `DeviceScannerView`; owns the actor lifecycle
- **MonitorViewController** — hosts `MonitorView`; implements `MonitorDisplay`, the protocol seam through which `MonitorActor` (MonitorActor.swift) drives the screen
- **CameraViewController** — pure UIKit, manages `AVCaptureSession` for the camera device (no SwiftUI view yet)
- **WatchRemoteCameraController** — Watch-remote mode, embeds `CameraViewController` as a child
- View models (`WelcomeViewModel`, `DeviceScannerViewModel`, `MonitorViewModel`, `CameraViewModel`) are ObservableObjects bridging actors to SwiftUI

The `^{ }` prefix operator (defined in Theater) dispatches a closure to the main thread — you'll see it used extensively for UI updates from actor message handlers.

### P2P Communication

Uses Apple's **MultipeerConnectivity** framework (service type: `"RemoteCam"`), encapsulated in `MultipeerService` (`MultipeerServiceProtocol` is the test seam). Messages are serialized as FlatBuffers and sent via `MCSession.send()`. Video files use `MCSession.sendResource()` for large transfers with progress tracking.

### Dependencies (CocoaPods)

- **SwiftLint** (~0.41.0) — Linting
- **FlatBuffers** (local podspec) — Wire-protocol serialization (iOS + watchOS targets)

The Theater actor framework is no longer a pod — the used subset is internalized at `RemoteCam/Theater/` (see `Docs/MODERNIZATION.md`).

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
