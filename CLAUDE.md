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

## Architecture

### Actor Model (Theater framework)

The app uses the **Theater** pod — an actor-model framework. Actors communicate exclusively via messages (the `!` operator sends a message). All state transitions happen inside actor message handlers, never on the main thread (asserted in code).

Key actors (registered under `RemoteCamSystem.shared`):
- **`RemoteCamSession`** (`RemoteCam/user/RemoteCam Session`) — Central session actor managing the state machine. Subclasses `ViewCtrlActor<DeviceScannerViewController>`. Handles MultipeerConnectivity session and routes all remote commands.
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
- **`RemoteCmd`** (RemoteCmds.swift) — Messages serialized via `NSCoding` and sent over MultipeerConnectivity between devices. Use `@objc` name annotations for stable serialization (e.g., `@objc(_TtCC10ActorsDemo9RemoteCmd7TakePic)`).
- **`UICmd`** (UICmds.swift) — Local messages between actors and view controllers within a single device.

When adding new remote commands, you **must** implement `NSCoding` (`encode`/`init?(coder:)`) and add an `@objc` class name annotation for backward compatibility.

### UI Architecture

The app is migrating from UIKit (Storyboards) to SwiftUI:
- **DeviceScannerViewController** — UIKit + Storyboard, entry point
- **RolePickerController** — UIKit, role selection after connection
- **CameraViewController** — UIKit, manages `AVCaptureSession` for the camera device
- **MonitorViewController** — UIKit host that embeds `MonitorView` (SwiftUI) via `UIHostingController`
- **MonitorView / MonitorViewModel** — SwiftUI view and ObservableObject view model for the monitor UI
- **CameraViewModel** — ObservableObject for camera-side progress overlays

The `^{ }` prefix operator (defined in Theater) dispatches a closure to the main thread — you'll see it used extensively for UI updates from actor message handlers.

### P2P Communication

Uses Apple's **MultipeerConnectivity** framework (service type: `"RemoteCam"`). Messages are serialized with `NSKeyedArchiver`/`NSKeyedUnarchiver` and sent via `MCSession.send()`. Video files use `MCSession.sendResource()` for large transfers with progress tracking.

### Dependencies (CocoaPods)

- **Theater** (~1.1) — Actor model framework
- **Starscream** (~4.0.8) — WebSocket client (used by Theater)
- **Google-Mobile-Ads-SDK** (~11.0) — Ad monetization
- **GoogleUserMessagingPlatform** (~2.0) — GDPR consent
- **SwiftLint** (~0.41.0) — Linting

Note: Theater's DEBUG logging is intentionally disabled in Podfile `post_install` to prevent excessive frame message spam.

### Feature Flags

Centralized in `FeatureFlags.swift`. Check existing flags before adding new ones.

### In-App Purchases

Managed by `PKIAPHandler.swift` (`InAppPurchasesManager`). Product IDs: `05` (remove ads), `06` (enable video), `07` (enable torch), `08` (enable video only).
