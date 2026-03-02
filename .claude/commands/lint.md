---
description: Run SwiftLint on the project
allowed-tools: Bash, Read
---

# Lint

Run SwiftLint to check code quality:

```bash
cd /Users/darioalessandro/Documents/remote-shutter && Pods/SwiftLint/swiftlint lint --reporter emoji 2>&1 | tail -50
```

After running:
1. Summarize the total number of warnings and errors
2. Group issues by rule
3. For errors (not warnings), suggest specific fixes
