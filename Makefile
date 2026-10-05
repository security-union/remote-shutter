.PHONY: lint test model runner rig multicam check demo

lint:
	./Pods/SwiftLint/swiftlint lint

test: 
	xcodebuild -workspace RemoteShutter.xcworkspace -scheme RemoteCam \
		-destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' \
		-configuration Debug test \
		CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# The session model's own tests: the checker over every world a person can
# drive, in a few seconds, with no simulator.
model:
	swift test --package-path SessionModel

# Walk the machine by hand. Note the bare `--`: `swift run` parses flags it
# recognises before the program sees them, so without it `--rig` disappears.
#   make runner ARGS="--paired --recordings 1"
runner:
	swift run --package-path SessionModel session-runner -- $(ARGS)

# A remote and two cameras, nothing paired yet: invite them both.
rig:
	swift run --package-path SessionModel session-runner -- --rig $(ARGS)

# A remote already holding both cameras: one tap, two cameras.
multicam:
	swift run --package-path SessionModel session-runner -- --multicam $(ARGS)

# Explore from the starting world and print the report, no interaction.
check:
	swift run --package-path SessionModel session-runner -- --check $(ARGS)

# Replay two walks by name: pairing then a photo, then recording a clip
# including the echo the camera waits for. Names rather than numbers, because
# move numbers shift whenever the model changes and names do not.
demo:
	@echo "=== pairing, then a photo ==="
	@swift run --package-path SessionModel session-runner -- \
		--script "remote invites;link up on camera;link up on remote;deliver peerBecameCamera;\
shutter on remote;deliver takePic;takePicture → ok;deliver takePicAck;deliver takePicResp"
	@echo "=== recording a clip, and the echo that releases the camera ==="
	@swift run --package-path SessionModel session-runner -- --paired --recordings 1 \
		--script "record on remote;deliver startRecording;startRecording → ok;deliver startRecordingAck;\
stop recording on remote;deliver stopRecording;stopRecording → ok;deliver videoArrived;\
deliver videoReceivedEcho;deliver stopRecordingResp"
	@echo "=== assembling a two-camera rig, then one tap for both ==="
	@swift run --package-path SessionModel session-runner -- --rig --shutter 1 \
		--script "remote invites camera;link up on remote;link up on camera;deliver peerBecameCamera;\
remote invites camera2;link up on remote;link up on camera2;deliver peerBecameCamera;\
shutter on remote;deliver takePic(sendMediaToPeer: true) remote→camera;takePicture → ok on camera;\
deliver takePic(sendMediaToPeer: true) remote→camera2;takePicture → ok on camera2;\
deliver takePicAck camera→remote;deliver takePicResp(failed: false, carriesMedia: true) camera→remote;\
deliver takePicAck camera2→remote;deliver takePicResp(failed: false, carriesMedia: true) camera2→remote"
