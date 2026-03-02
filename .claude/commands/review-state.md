---
description: Review a state machine state for correctness
argument-hint: <state-name e.g. monitorPhotoMode>
allowed-tools: Read, Grep, Glob
---

# Review State: $ARGUMENTS

Analyze the state machine state `$ARGUMENTS`:

1. Find the state implementation file
2. Check the state's `OnEnter` handler
3. Verify all message handlers cover expected cases
4. Check error/disconnect handling (should fall back to scanning)
5. Verify `become`/`unbecome`/`popToState` transitions are correct
6. Look for potential race conditions or missing state transitions
7. Check that UI updates use the `^{ }` operator for main thread dispatch

Report findings with specific line references.
