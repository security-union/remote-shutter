---
description: Build Remote Shutter for iOS Simulator
allowed-tools: Bash
---

# Build Remote Shutter

Build the project using the xcworkspace (required for CocoaPods):

```bash
xcodebuild -workspace RemoteShutter.xcworkspace -scheme RemoteCam \
  -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' \
  -configuration Debug clean build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Report any build errors with suggested fixes. If there are warnings, summarize them but focus on errors first.
