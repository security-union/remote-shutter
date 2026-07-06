# UI Modernization Plan

Companion to [MODERNIZATION.md](MODERNIZATION.md) (Theater/actor removal). That doc is about
the concurrency layer; this one is about the UI layer: killing the last UIKit shells,
Objective-C files, and dead code left over from the storyboard era.

Each PR below is a small, independently shippable slice. The **worklog** at the bottom
collects raw material (numbers, before/after, war stories) for a blog post about
modernizing this app with Claude (Fable).

## Where the app actually is (inventory, 2026-07-05)

Better than expected:

- **Zero storyboards, zero xibs.** Launch screen is the `UILaunchScreen` plist dict.
- **UIScene lifecycle fully adopted**; `AppDelegate` is minimal, window built in `SceneDelegate`.
- **Deprecated-API greps come back clean**: no `keyWindow`, `statusBarOrientation`,
  `UIAlertView`, `AVCaptureStillImageOutput`, `openURL(_:)`.
- **Four of five screens are already SwiftUI**, hosted by thin UIKit shells:
  `WelcomeView`, `RolePickerView`, `DeviceScannerView`, `MonitorView`.

What's left:

| Surface | Size | Blocker |
|---|---|---|
| Dead code (old permission system, orphaned IB controller, stubs, unused extensions) | ~10 files | none — delete |
| Objective-C: `CPSoundManager`, `RCTimer` (+ app bridging header) | 3 files | none — trivial ports |
| UIKit shells: `WelcomeViewController`, `RolePickerController` | ~320 lines | thin coordinators |
| `DeviceScannerViewController` | 367 lines | owns actor lifecycle; is `ViewCtrlActor<Self>` target |
| `MonitorViewController` + glue | ~820 lines | `MonitorActor: ViewCtrlActor<MonitorViewController>` calls the concrete VC |
| `CameraViewController` | 1729 lines | AVFoundation capture graph; no SwiftUI view exists |
| `WatchRemoteCameraController` | 322 lines | embeds CameraViewController as child |

The structural blocker for the hard tier is Theater's `ViewCtrlActor<ConcreteVC>` generic
binding — actors are type-welded to UIKit view controllers. That work overlaps with
MODERNIZATION.md Phases 4–5.

## PR sequence

### PR 1: Dead code sweep — **shipped (#122)**
Pure deletion, no behavior change.

Files deleted (all verified zero callers):
- `CameraAccess.swift` — the pre-`PermissionManager` permission system, entirely superseded
- `RolePickerOptionController.swift` — IBOutlet controller whose xib died long ago
- `PopoverController.swift` — SwiftUI "Hello, World!" stub
- `TorchTest.swift` — diagnostic scaffolding
- `UIOrientationHelpers.swift` — literally empty (header comment + import)
- `CGImage.swift` — unused `rotated(by:)`
- `UIViewController.swift` — unused child-VC helpers (call sites use `addChild` directly)
- `UIButton.swift` — `styleButton`, only caller was `RolePickerOptionController`
- `UIView.swift` — `roundCorners`/`styleEmbeddedView`, only caller was `styleButton`
- `UIImage+ImageProcessing.h/.m` — old ObjC frame path, replaced by `JPEGFrameEncoder`/`HEICFrameEncoder`
- `RemoteShutterTests-Bridging-Header.h`, `RemoteShutterUITests-Bridging-Header.h` — empty

Members trimmed from live files:
- `OrientationUtils`: `transformToUIKit`, `transformToUIImage`, `transformOrientationToImage`
- `UIImage+gif`: `gifImageWithURL`

Plus: drop `UIImage+ImageProcessing.h` from the app bridging header, clear the test
targets' `SWIFT_OBJC_BRIDGING_HEADER` settings, fix stale storyboard claims in CLAUDE.md.

### PR 2: Retire the Objective-C — **shipped (#123)**
Port `CPSoundManager` (countdown beeps, `AVAudioPlayer`) and `RCTimer`
(recursive-`dispatch_after` countdown) to small Swift types; delete
`RemoteCam-Bridging-Header.h`. Zero ObjC left in the app target.

### PR 3: Test hardening + collapse the easy shells — **shipped (#124)**
Two layers of integration tests written FIRST (against pre-refactor behavior), then
the refactor under them:

**Tests**
- `ControllerWiringTests` — instantiates the real shell controllers in the hosted test
  app and pins their contract: SwiftUI host embedded and pinned, navigation pushes,
  actor registration in viewDidLoad, actor teardown in deinit.
- `LoopbackSessionTests` — two `RemoteCamSession` actors wired through
  `LoopbackMultipeerService`, an in-process transport that passes every message
  through the real FlatBuffers encode/decode. Full protocol round trips across both
  state machines: role handshake, take-picture, toggle-flash, start-recording, zoom,
  peer disconnect.

**Refactor**
- Delete `iAdViewController`/`BaseViewController.swift` (`showError` moved to
  `UIAlertPresenter.swift`; `MonitorViewController` now subclasses `UIViewController`)
- `RemoteCamSystem.shared` moved out of `RolePickerController` into `RemoteCamSystem.swift`
- New `UIViewController+SwiftUIHosting.swift`: `embedSwiftUIView` + `presentHelpSheet`
  replace 5 copies of the embed boilerplate and 4 copies of the help-sheet code
- Dead `connectedPrompt`, `pinchGestureRecognizer`, `lastPinchScale` removed

### PR 4: Decouple MonitorActor from MonitorViewController — **this PR**
- New `MonitorDisplay` protocol — everything the actor needs from the monitor screen
  (mode configuration, view-model updates, frame routing, exit navigation).
- `MonitorActor` moved out of MonitorViewController.swift into `MonitorActor.swift` and
  rebuilt as a plain `Actor` bound via `SetMonitorDisplay` + a weak display box —
  no longer `ViewCtrlActor<MonitorViewController>`. (Swift won't accept a protocol
  existential as a class-constrained generic argument, and a plain actor matches the
  MODERNIZATION.md Phase 5 target anyway.)
- `MonitorViewController` conforms to `MonitorDisplay`; `navigationController?.pop`
  became `exitMonitor()` on the protocol.
- New `MonitorActorTests` (8) drive the actor against `FakeMonitorDisplay` — the first
  time this actor has ever been testable without a live UIKit controller.
- `RemoteCamSession`'s `ViewCtrlActor<DeviceScannerViewController>` binding is the
  remaining coupling — PR 5.

### PR 5: Decouple RemoteCamSession from DeviceScannerViewController
Re-target the session's lobby binding at a protocol/coordinator (same recipe as PR 4).
Unblocks shrinking the DeviceScanner shell.

### PR 6+: Camera surface
SwiftUI chrome around a `UIViewRepresentable` preview layer for `CameraViewController`;
`WatchRemoteCameraController` follows.

## Worklog (blog raw material)

### PR 1 — dead code sweep
- Inventory ran as two parallel read-only agents: one walked every view controller,
  the other chased ObjC/bridging headers/deprecated APIs. ~30 min wall clock.
- Expected storyboards to hunt; found none. The docs said "DeviceScannerViewController —
  UIKit + Storyboard, entry point" — the code said otherwise. Docs lie, greps don't.
- Best find: an entire permission system (`CameraAccess.swift`) still compiling,
  fully replaced, zero callers — each method politely apologizing in comments that
  the new system had taken over.
- Dead-code cascade: deleting one orphaned IB controller made `UIButton.swift` dead,
  which made `UIView.swift` dead. Delete one leaf, the branch comes with it.
- Two "dead" files (`PopoverController.swift`, `TorchTest.swift`) turned out not to be
  in the pbxproj at all — orphaned on disk, never even compiling.
- Plot twist: removing `UIImage+ImageProcessing.h` from the bridging header broke the
  build in 10 files that never imported UIKit. Its `#import <UIKit/UIKit.h>` had been
  silently granting UIKit to every Swift file in the target for years. The dead code
  was load-bearing — not for what it did, but for what it imported. Fix: explicit
  `import UIKit` in the 10 files that were freeloading.
- Net: 27 files changed, +143/−557 lines; 13 files deleted; 348/348 tests green.

### PR 2 — retire the Objective-C
- `CPSoundManager` (2012, "Clapmera", `__MyCompanyName__` copyright header) and
  `RCTimer` (2013) were the last app-target ObjC. 139 lines of ObjC across 4 files
  → ~100 lines of Swift in 2 files (`SoundManager`, `CountdownTimer`), same semantics.
- The bridging-header lesson from PR 1 repeated on cue: deleting the header removed the
  free `AVFoundation` import that `CPSoundManager.h` had been granting the whole target —
  `RemoteCmds.swift`/`UICmds.swift` (which serialize `AVCaptureDevice` positions over the
  wire) never imported it. Two more explicit imports.
- `CountdownTimer` is pure Swift now, so it got what the ObjC never had: unit tests
  (tick sequence, zero-duration sync completion, cancel).
- 351/351 tests green (348 + 3 new).

### PR 3 — test hardening + shell collapse
- Wrote the tests FIRST against unrefactored code (characterization), then refactored
  under them. The wiring tests instantiate the app's real view controllers inside the
  hosted test bundle — possible only because PR 1 confirmed everything is programmatic
  (no storyboards to inflate).
- The loopback harness is the fun one: two full session state machines in one process,
  every message crossing a fake wire through the real FlatBuffers encode/decode.
  A take-picture round trip (UICmd → state transition → encode → decode → peer state
  machine → error response → encode → decode → pop + alert) runs in ~0.8s in CI.
  Closest thing to a two-device test without two devices.
- Gotcha: deinit-based teardown assertions need `autoreleasepool {}` around the
  controller's lifetime — UIKit autoreleases references to the VC, so without it
  deinit doesn't run until the test method returns and the assertions read stale state.
- Along the way the docs lied again: CLAUDE.md still said the wire protocol was
  NSCoding/NSKeyedArchiver (it's FlatBuffers) and listed four CocoaPods that no longer
  exist (Theater, Starscream, Google Ads, UMP — actual: SwiftLint + FlatBuffers).
- Net: 14 files changed, +593/−164; 12 new integration tests; 363/363 green, and the
  new tests passed unchanged across the refactor — which was the whole point.

### PR 4 — MonitorActor decoupling
- The plan was to loosen Theater's `ViewCtrlActor<A: UIViewController>` to
  `A: AnyObject` and bind the actor to `any MonitorDisplay`. The compiler said no:
  "'ViewCtrlActor' requires that 'any MonitorDisplay' be a class type" — a
  class-constrained existential still isn't a class type to generics.
- Plan B was better anyway: MonitorActor became a plain `Actor` with an explicit
  `SetMonitorDisplay` message and a hand-rolled weak box. Fewer generics, less
  framework, and exactly what MODERNIZATION.md Phase 5 prescribed.
- The payoff: `MonitorActorTests` drives the full message surface (render modes,
  flash/torch/zoom/lens responses, video-transfer progress, become-monitor-failed)
  against a fake display object. Before this PR that required a live UIKit controller.
- PR 3's wiring + loopback tests passed unchanged across the swap — the safety net
  did its job on the first PR it was built for.
