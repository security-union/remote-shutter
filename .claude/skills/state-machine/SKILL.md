---
name: state-machine
description: Expert in RemoteCamSession's hierarchical state machine. Use when working with state transitions, `become`/`unbecome`/`popToState`, adding new states, or debugging state flow issues.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# RemoteCamSession State Machine Expert

## Context
`RemoteCamSession` implements a hierarchical state machine using Theater's `become`/`unbecome`/`popToState` pattern.

## State Hierarchy

States are defined in `RemoteCamStates` (States.swift):

```
scanning
  └── connected (role selection)
        ├── camera
        │     ├── cameraTakingPic
        │     └── cameraRecordingVideo
        └── monitorPhotoMode
              ├── monitorTakingPicture
              ├── monitorTogglingFlash
              ├── monitorTogglingCamera
              ├── monitorSwitchingLens
              └── monitorVideoMode
                    └── monitorRecordingVideo
```

## State Files
- **RemoteCamScanning.swift** — `scanning`: peer discovery via MultipeerConnectivity
- **RemoteCamConnected.swift** — `connected`: role selection (camera vs monitor)
- **CamStates.swift** — `camera`, `cameraTakingPic`, `cameraRecordingVideo`
- **MonitorStates.swift** — `monitorTogglingFlash`, `monitorTogglingCamera`, `monitorSwitchingLens`
- **MonitorPhotoStates.swift** — `monitorPhotoMode`, `monitorTakingPicture`
- **MonitorVideoStates.swift** — `monitorVideoMode`, `monitorRecordingVideo`
- **CameraVideoStates.swift** — Camera-side video recording states

## Key Patterns

### State Transitions
- `become(stateName, state)` — Push a new state onto the stack
- `unbecome()` — Pop current state, return to previous
- `popToState(stateName)` — Pop states until reaching the named state

### OnEnter Handlers
- Each state can define an `OnEnter` block that runs when the state is entered
- Common pattern: `OnEnter` dispatches UI setup to main thread via `^{ }`

### Error Recovery
- Most error conditions trigger `popToState("scanning")` to reset to discovery
- `sendCommandOrGoToScanning` helper sends a remote command and falls back to scanning on failure

## Rules
1. Always define new states in `RemoteCamStates` enum (States.swift)
2. Implement state behavior in the appropriate state file
3. Handle the error/disconnect case — usually pop back to scanning
4. Use `OnEnter` for state initialization, not the message handler
5. Test state transitions using `statesStack` assertions
