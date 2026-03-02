---
name: ios-testing
description: Testing expert for Remote Shutter's actor-based architecture. Use when writing unit tests, working with XCTest, testing state machines, or debugging test failures.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash
---

# Remote Shutter Testing Expert

## Context
Unit tests live in `RemoteCamTests/` directory under the `RemoteShutterTests` target. Tests use hosted bundle loading (BUNDLE_LOADER).

## Key Import Patterns
```swift
@testable import RemoteShutter  // App module (NOT RemoteCam)
@testable import Theater         // For Weak, statesStack, etc.
```

## Test Infrastructure

### TestableRemoteCamSession
A test subclass that overrides network operations:
- `sendMessage` — Captures sent messages instead of using MultipeerConnectivity
- `sendCommandOrGoToScanning` — Prevents real network calls
- `startScanning` — No-op to avoid storyboard dependencies

### TestDeviceScannerViewController
Overrides `viewDidLoad`, `stopScanning`, `startScanning` to avoid nil IBOutlet crashes during testing.

### waitForMailbox Helper
Adds an operation to an actor's serial mailbox and waits via `XCTestExpectation`. This ensures all previously queued messages have been processed before assertions.

## Important Notes
- `DeviceScannerViewController` eagerly initializes actors in `RemoteCamSystem.shared` at construction — this cannot be avoided in tests
- The `connected` state's `OnEnter` dispatches `lobby.stopScanning()` to main thread via `^{}`
- Use no-op scanning state (not real `scanning()`) since real one accesses storyboard outlets
- App product is `RemoteShutter.app`, module name is `RemoteShutter`

## Build & Run Tests
```bash
xcodebuild -workspace RemoteShutter.xcworkspace -scheme RemoteCam \
  -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' \
  -configuration Debug test \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Rules
1. Always use `@testable import RemoteShutter` (not RemoteCam)
2. Use `TestableRemoteCamSession` to avoid real network calls
3. Use `waitForMailbox` to synchronize with actor message processing
4. Test state transitions by checking `statesStack`
5. Never compile app sources directly in the test target — rely on BUNDLE_LOADER
