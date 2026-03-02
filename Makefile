.PHONY: lint test

lint:
	./Pods/SwiftLint/swiftlint lint

test: 
	xcodebuild -workspace RemoteShutter.xcworkspace -scheme RemoteCam \
		-destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' \
		-configuration Debug test \
		CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
