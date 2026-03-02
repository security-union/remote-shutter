---
description: Run Remote Shutter unit tests
allowed-tools: Bash
---

# Run Tests

Run the unit test suite:

```bash
xcodebuild -workspace RemoteShutter.xcworkspace -scheme RemoteCam \
  -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' \
  -configuration Debug test \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

After running:
1. Report test results (pass/fail counts)
2. For any failures, show the failing test name, assertion, and relevant code
3. Suggest fixes for failing tests
