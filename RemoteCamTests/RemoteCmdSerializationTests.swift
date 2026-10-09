//
//  RemoteCmdSerializationTests.swift
//  RemoteShutterTests
//
//  Round-trip FlatBuffers serialization tests for every RemoteCmd subclass.
//  Uses the exact same encode/decode path as production (MultipeerService).
//

import XCTest
import AVFoundation
import FlatBuffers

@testable import RemoteShutter

final class RemoteCmdSerializationTests: XCTestCase {

    // MARK: - Helper

    /// Encodes via toFlatBuffer(), decodes via RemoteCmd.fromFlatBuffer().
    /// Mirrors the production path in MultipeerService.
    private func roundTrip<T: RemoteShutter.Message>(_ original: T) -> T {
        let data = toFlatBufferData(original)

        guard let decoded = RemoteCmd.fromFlatBuffer(data) else {
            XCTFail("fromFlatBuffer returned nil for \(T.self)")
            fatalError()
        }

        guard let result = decoded as? T else {
            XCTFail("Decoded object is \(type(of: decoded)), expected \(T.self)")
            fatalError()
        }
        return result
    }

    /// Dispatches to the correct toFlatBuffer() extension based on runtime type.
    private func toFlatBufferData(_ msg: RemoteShutter.Message) -> Data {
        switch msg {
        case let m as RemoteCmd.StartRecordingVideo: return m.toFlatBuffer()
        case let m as RemoteCmd.StartRecordingVideoAck: return m.toFlatBuffer()
        case let m as RemoteCmd.StopRecordingVideo: return m.toFlatBuffer()
        case let m as RemoteCmd.StopRecordingVideoAck: return m.toFlatBuffer()
        case let m as RemoteCmd.StopRecordingVideoResp: return m.toFlatBuffer()
        case let m as RemoteCmd.TakePic: return m.toFlatBuffer()
        case let m as RemoteCmd.TakePicAck: return m.toFlatBuffer()
        case let m as RemoteCmd.TakePicResp: return m.toFlatBuffer()
        case let m as RemoteCmd.SendFrame: return m.toFlatBuffer()
        case let m as RemoteCmd.RequestFrame: return m.toFlatBuffer()
        case let m as RemoteCmd.RequestKeyframe: return m.toFlatBuffer()
        case let m as RemoteCmd.ClockSyncPing: return m.toFlatBuffer()
        case let m as RemoteCmd.ClockSyncPong: return m.toFlatBuffer()
        case let m as RemoteCmd.ScheduledCapture: return m.toFlatBuffer()
        case let m as RemoteCmd.ScheduledCaptureAck: return m.toFlatBuffer()
        case let m as RemoteCmd.ScheduledStartRecording: return m.toFlatBuffer()
        case let m as RemoteCmd.ScheduledStopRecording: return m.toFlatBuffer()
        case let m as RemoteCmd.ScheduledRecordingAck: return m.toFlatBuffer()
        case let m as RemoteCmd.SetStreamProfile: return m.toFlatBuffer()
        case let m as RemoteCmd.RequestVideoResend: return m.toFlatBuffer()
        case let m as RemoteCmd.SetZoom: return m.toFlatBuffer()
        case let m as RemoteCmd.SetExposure: return m.toFlatBuffer()
        case let m as RemoteCmd.SetCinematic: return m.toFlatBuffer()
        case let m as RemoteCmd.SetCinematicFocus: return m.toFlatBuffer()
        case let m as RemoteCmd.CinematicSubjects: return m.toFlatBuffer()
        case let m as RemoteCmd.FocusAtPoint: return m.toFlatBuffer()
        case let m as RemoteCmd.SetCameraPreviewMode: return m.toFlatBuffer()
        case let m as RemoteCmd.CameraCapabilitiesResp: return m.toFlatBuffer()
        case let m as RemoteCmd.SwitchLens: return m.toFlatBuffer()
        case let m as RemoteCmd.PeerBecameCamera: return m.toFlatBuffer()
        case let m as RemoteCmd.PeerBecameMonitor: return m.toFlatBuffer()
        case let m as RemoteCmd.ToggleFlash: return m.toFlatBuffer()
        case let m as RemoteCmd.ToggleTorch: return m.toFlatBuffer()
        case let m as RemoteCmd.ToggleCamera: return m.toFlatBuffer()
        case let m as RemoteCmd.SelectCameraDevice: return m.toFlatBuffer()
        case let m as RemoteCmd.RequestCameraCapabilities: return m.toFlatBuffer()
        case let m as RemoteCmd.CameraStateReport: return m.toFlatBuffer()
        case let m as RemoteCmd.SetVideoQuality: return m.toFlatBuffer()
        case let m as RemoteCmd.SetPhotoQuality: return m.toFlatBuffer()
        case let m as RemoteCmd.TimerCountdown: return m.toFlatBuffer()
        case let m as RemoteCmd.SetAspectRatio: return m.toFlatBuffer()
        default:
            XCTFail("No toFlatBuffer() for \(type(of: msg))")
            fatalError()
        }
    }

    // MARK: - 1. StartRecordingVideo

    func testStartRecordingVideo_roundTrip() {
        let original = RemoteCmd.StartRecordingVideo(sender: nil)
        let decoded: RemoteCmd.StartRecordingVideo = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - 2. StartRecordingVideoAck

    func testStartRecordingVideoAck_roundTrip() {
        let original = RemoteCmd.StartRecordingVideoAck(sender: nil)
        let decoded: RemoteCmd.StartRecordingVideoAck = roundTrip(original)
        XCTAssertNil(decoded.error)
    }

    func testStartRecordingVideoAck_withError() {
        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "recording failed"])
        let original = RemoteCmd.StartRecordingVideoAck(sender: nil, error: error)
        let decoded: RemoteCmd.StartRecordingVideoAck = roundTrip(original)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.localizedDescription, "recording failed")
    }

    /// The error message must survive the wire into BOTH fields displays
    /// read: `_domain` (the codebase's message-in-domain convention, what
    /// alerts and the multicam toast show) and `localizedDescription`.
    /// Message-in-domain errors must arrive as their message — never as
    /// NSError's synthesized "The operation couldn't be completed…" text or
    /// a placeholder domain.
    func testWireErrorIsReadableFromDomainAndDescription() {
        // The codebase convention: message in the domain, nothing else.
        let domainOnly = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back, currentLens: .wideAngle, currentZoom: 1,
            inReplyTo: .togglecamera,
            error: NSError(domain: "Couldn't switch camera", code: 0))
        let decodedDomainOnly: RemoteCmd.CameraCapabilitiesResp = roundTrip(domainOnly)
        XCTAssertEqual(decodedDomainOnly.error?._domain, "Couldn't switch camera")
        XCTAssertEqual(decodedDomainOnly.error?.localizedDescription, "Couldn't switch camera")

        // A system-style error with an explicit description keeps it.
        let described = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back, currentLens: .wideAngle, currentZoom: 1,
            inReplyTo: .togglecamera,
            error: NSError(domain: "AVFoundationErrorDomain", code: -11800,
                           userInfo: [NSLocalizedDescriptionKey: "recording failed"]))
        let decodedDescribed: RemoteCmd.CameraCapabilitiesResp = roundTrip(described)
        XCTAssertEqual(decodedDescribed.error?._domain, "recording failed")
        XCTAssertEqual(decodedDescribed.error?.localizedDescription, "recording failed")
    }

    // MARK: - 3. StopRecordingVideo

    func testStopRecordingVideo_roundTrip() {
        let original = RemoteCmd.StopRecordingVideo(sender: nil, sendMediaToPeer: true)
        let decoded: RemoteCmd.StopRecordingVideo = roundTrip(original)
        XCTAssertTrue(decoded.sendMediaToPeer)
    }

    func testStopRecordingVideo_false() {
        let original = RemoteCmd.StopRecordingVideo(sender: nil, sendMediaToPeer: false)
        let decoded: RemoteCmd.StopRecordingVideo = roundTrip(original)
        XCTAssertFalse(decoded.sendMediaToPeer)
    }

    // MARK: - 4. StopRecordingVideoAck

    func testStopRecordingVideoAck_roundTrip() {
        let original = RemoteCmd.StopRecordingVideoAck()
        let decoded: RemoteCmd.StopRecordingVideoAck = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - 5. StopRecordingVideoResp

    /// A successful terminal message is NOT the ack: the two ride distinct
    /// actions, so neither `success` nor a media payload is needed to tell
    /// them apart (the clip never travels in a message).
    func testStopRecordingVideoResp_successIsDistinctFromAck() {
        let decoded: RemoteCmd.StopRecordingVideoResp = roundTrip(RemoteCmd.StopRecordingVideoResp())
        XCTAssertNil(decoded.error)

        var buffer = ByteBuffer(bytes: [UInt8](toFlatBufferData(RemoteCmd.StopRecordingVideoResp())))
        let msg: RemoteShutter_P2PMessage? = try? getCheckedRoot(byteBuffer: &buffer)
        XCTAssertEqual(msg?.response?.action, .stoprecordingfinished)
        XCTAssertEqual(msg?.response?.success, true)
        XCTAssertFalse(msg?.response?.hasMediaData ?? true, "video never rides in the message")
    }

    func testStopRecordingVideoResp_withError() {
        let error = NSError(domain: "test", code: 99, userInfo: [NSLocalizedDescriptionKey: "stop recording failed"])
        let original = RemoteCmd.StopRecordingVideoResp(sender: nil, error: error)
        let decoded: RemoteCmd.StopRecordingVideoResp = roundTrip(original)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.localizedDescription, "stop recording failed")
    }

    // MARK: - 6. TakePic

    func testTakePic_roundTrip() {
        let original = RemoteCmd.TakePic(sender: nil, sendMediaToPeer: true)
        let decoded: RemoteCmd.TakePic = roundTrip(original)
        XCTAssertTrue(decoded.sendMediaToPeer)
    }

    func testTakePic_false() {
        let original = RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false)
        let decoded: RemoteCmd.TakePic = roundTrip(original)
        XCTAssertFalse(decoded.sendMediaToPeer)
    }

    // MARK: - 7. TakePicAck

    func testTakePicAck_roundTrip() {
        let original = RemoteCmd.TakePicAck(sender: nil)
        let decoded: RemoteCmd.TakePicAck = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - 8. TakePicResp

    func testTakePicResp_withPic() {
        let picData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header bytes
        let original = RemoteCmd.TakePicResp(sender: nil, pic: picData)
        let decoded: RemoteCmd.TakePicResp = roundTrip(original)
        XCTAssertEqual(decoded.pic, picData)
        XCTAssertNil(decoded.error)
    }

    func testTakePicResp_nilPicNilError() {
        let original = RemoteCmd.TakePicResp(sender: nil, pic: nil, error: nil)
        let decoded: RemoteCmd.TakePicResp = roundTrip(original)
        XCTAssertNil(decoded.pic)
        XCTAssertNil(decoded.error)
    }

    func testTakePicResp_withError() {
        let error = NSError(domain: "camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "take pic failed"])
        let original = RemoteCmd.TakePicResp(sender: nil, error: error)
        let decoded: RemoteCmd.TakePicResp = roundTrip(original)
        XCTAssertNil(decoded.pic)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.localizedDescription, "take pic failed")
    }

    // MARK: - 9. SendFrame

    func testSendFrame_roundTrip() {
        let frameData = Data(repeating: 0xFF, count: 128)
        let original = RemoteCmd.SendFrame(
            data: frameData,
            sender: nil,
            fps: 30,
            camPosition: .back,
            camOrientation: .landscapeRight
        )
        let decoded: RemoteCmd.SendFrame = roundTrip(original)
        XCTAssertEqual(decoded.data, frameData)
        XCTAssertEqual(decoded.fps, 30)
        XCTAssertEqual(decoded.camPosition, .back)
        XCTAssertEqual(decoded.camOrientation, .landscapeRight)
    }

    func testSendFrame_frontCamera() {
        let frameData = Data([1, 2, 3])
        let original = RemoteCmd.SendFrame(
            data: frameData,
            sender: nil,
            fps: 60,
            camPosition: .front,
            camOrientation: .portrait
        )
        let decoded: RemoteCmd.SendFrame = roundTrip(original)
        XCTAssertEqual(decoded.data, frameData)
        XCTAssertEqual(decoded.fps, 60)
        XCTAssertEqual(decoded.camPosition, .front)
        XCTAssertEqual(decoded.camOrientation, .portrait)
    }

    func testSendFrame_codecAndSequenceRoundTrip() {
        let original = RemoteCmd.SendFrame(
            data: Data([9, 9, 9]),
            sender: nil,
            fps: 30,
            camPosition: .back,
            camOrientation: .portrait,
            codec: .heic,
            sequenceNumber: 42_001
        )
        let decoded: RemoteCmd.SendFrame = roundTrip(original)
        XCTAssertEqual(decoded.codec, .heic)
        XCTAssertEqual(decoded.sequenceNumber, 42_001)
    }

    func testSendFrame_defaultsToJPEGCodec() {
        // Call sites that predate the codec field compile unchanged and must
        // stay on the JPEG wire value.
        let original = RemoteCmd.SendFrame(
            data: Data([1]),
            sender: nil,
            fps: 30,
            camPosition: .back,
            camOrientation: .portrait
        )
        let decoded: RemoteCmd.SendFrame = roundTrip(original)
        XCTAssertEqual(decoded.codec, .jpeg)
        XCTAssertEqual(decoded.sequenceNumber, 0)
    }

    /// A frame from an old app build has no codec/sequence fields at all.
    /// Decoding must treat it as JPEG, not drop it.
    func testSendFrame_legacyFrameWithoutCodecDecodesAsJPEG() throws {
        var fbb = FlatBufferBuilder()
        let imageOffset = fbb.createVector(bytes: Data([7, 7]))
        let frame = RemoteShutter_FrameData.createFrameData(
            &fbb,
            imageDataVectorOffset: imageOffset,
            fps: 24,
            cameraPosition: .front,
            orientation: 1
            // codec / sequenceNumber intentionally omitted (legacy layout)
        )
        let msg = RemoteShutter_P2PMessage.createP2PMessage(&fbb, type: .framedata, frameDataOffset: frame)
        fbb.finish(offset: msg, fileId: "RCAM")
        let decoded = try XCTUnwrap(RemoteCmd.fromFlatBuffer(fbb.data) as? RemoteCmd.SendFrame)
        XCTAssertEqual(decoded.codec, .jpeg)
        XCTAssertEqual(decoded.sequenceNumber, 0)
        XCTAssertEqual(decoded.data, Data([7, 7]))
        XCTAssertEqual(decoded.fps, 24)
    }

    // MARK: - 10. RequestFrame

    func testRequestFrame_roundTrip() {
        let original = RemoteCmd.RequestFrame(sender: nil)
        let decoded: RemoteCmd.RequestFrame = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - 11. SetZoom

    func testSetZoom_roundTrip() {
        let original = RemoteCmd.SetZoom(zoomFactor: 2.5)
        let decoded: RemoteCmd.SetZoom = roundTrip(original)
        XCTAssertEqual(decoded.zoomFactor, 2.5, accuracy: 0.001)
    }

    func testSetZoom_minZoom() {
        let original = RemoteCmd.SetZoom(zoomFactor: 1.0)
        let decoded: RemoteCmd.SetZoom = roundTrip(original)
        XCTAssertEqual(decoded.zoomFactor, 1.0, accuracy: 0.001)
    }

    // MARK: - 11b. FocusAtPoint

    func testFocusAtPoint_roundTrip() {
        let original = RemoteCmd.FocusAtPoint(x: 0.25, y: 0.75)
        let decoded: RemoteCmd.FocusAtPoint = roundTrip(original)
        XCTAssertEqual(decoded.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(decoded.y, 0.75, accuracy: 0.0001)
    }

    func testCameraCapabilities_supportsFocusPointRoundTrip() {
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            supportsFocusPoint: true, error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertTrue(decoded.supportsFocusPoint)
    }





    // MARK: - 13. CameraCapabilitiesResp

    func testCameraCapabilitiesResp_roundTrip() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle, .ultraWide, .telephoto],
            hasFlash: true,
            hasTorch: true,
            zoomCapabilities: [
                .wideAngle: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0),
                .ultraWide: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 2.0)
            ]
        )
        let frontCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle],
            hasFlash: false,
            hasTorch: false,
            zoomCapabilities: [.wideAngle: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 5.0)]
        )
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: frontCamera,
            backCamera: backCamera,
            currentCamera: .back,
            currentLens: .wideAngle,
            currentZoom: 2.5,
            error: nil
        )
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertNotNil(decoded.backCamera)
        XCTAssertEqual(decoded.backCamera?.availableLenses.count, 3)
        XCTAssertTrue(decoded.backCamera?.hasFlash ?? false)
        XCTAssertTrue(decoded.backCamera?.hasTorch ?? false)
        XCTAssertNotNil(decoded.frontCamera)
        XCTAssertEqual(decoded.frontCamera?.availableLenses.count, 1)
        XCTAssertFalse(decoded.frontCamera?.hasFlash ?? true)
        XCTAssertEqual(decoded.currentCamera, .back)
        XCTAssertEqual(decoded.currentLens, .wideAngle)
        XCTAssertEqual(decoded.currentZoom, 2.5, accuracy: 0.001)
        XCTAssertNil(decoded.error)
    }

    func testCameraCapabilitiesResp_nilCameras() {
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil,
            backCamera: nil,
            currentCamera: .front,
            currentLens: .ultraWide,
            currentZoom: 1.0,
            error: nil
        )
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertNil(decoded.frontCamera)
        XCTAssertNil(decoded.backCamera)
        XCTAssertEqual(decoded.currentCamera, .front)
        XCTAssertEqual(decoded.currentLens, .ultraWide)
    }

    // MARK: - 13a. Camera state report (the recording-truth channel)

    /// v10 contract: the phase is EXPLICIT on the wire; Recording carries the
    /// camera's elapsed tick (ms) — the camera drives the remote's timer.
    func testCameraStateReport_recordingRoundTrip() throws {
        let original = RemoteCmd.CameraStateReport(seq: 42, state: .recording(elapsedMillis: 61_500))
        let decoded: RemoteCmd.CameraStateReport = roundTrip(original)
        XCTAssertEqual(decoded.seq, 42)
        XCTAssertEqual(decoded.state, .recording(elapsedMillis: 61_500))
    }

    /// The other half of the contract: Idle is an explicit phase, never a
    /// sentinel timestamp.
    func testCameraStateReport_idleRoundTrip() {
        let original = RemoteCmd.CameraStateReport(seq: 7, state: .idle)
        let decoded: RemoteCmd.CameraStateReport = roundTrip(original)
        XCTAssertEqual(decoded.seq, 7)
        XCTAssertEqual(decoded.state, .idle)
    }

    // MARK: - 13b. Camera device selection

    func testSelectCameraDevice_roundTrip() {
        let original = RemoteCmd.SelectCameraDevice(uniqueID: "com.apple.avfoundation:USB-0x1234")
        let decoded: RemoteCmd.SelectCameraDevice = roundTrip(original)
        XCTAssertEqual(decoded.uniqueID, "com.apple.avfoundation:USB-0x1234")
    }

    func testSelectCameraDeviceReply_roundTripCarriesDeviceList() {
        let usbInfo = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle],
            hasFlash: false,
            hasTorch: false,
            zoomCapabilities: [.wideAngle: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 1.0)]
        )
        let devices = [
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "builtin-0", localizedName: "FaceTime HD Camera",
                positionRaw: AVCaptureDevice.Position.front.rawValue,
                isActive: false, info: nil),
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "usb-0", localizedName: "USB Camera",
                positionRaw: AVCaptureDevice.Position.unspecified.rawValue,
                isActive: true, info: usbInfo)
        ]
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            cameraDevices: devices, activeDeviceID: "usb-0", error: nil)
        capabilities.inReplyTo = .selectcameradevice

        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(capabilities)
        let decodedCaps: RemoteCmd.CameraCapabilitiesResp? = decoded
        XCTAssertEqual(decoded.inReplyTo, .selectcameradevice)
        XCTAssertNil(decoded.error)
        XCTAssertEqual(decodedCaps?.activeDeviceID, "usb-0")
        XCTAssertEqual(decodedCaps?.cameraDevices.count, 2)
        XCTAssertEqual(decodedCaps?.cameraDevices[0].uniqueID, "builtin-0")
        XCTAssertEqual(decodedCaps?.cameraDevices[0].localizedName, "FaceTime HD Camera")
        XCTAssertEqual(decodedCaps?.cameraDevices[0].position, .front)
        XCTAssertFalse(decodedCaps?.cameraDevices[0].isActive ?? true)
        // .unspecified survives the wire via has_unspecified_position.
        XCTAssertEqual(decodedCaps?.cameraDevices[1].position, .unspecified)
        XCTAssertTrue(decodedCaps?.cameraDevices[1].isActive ?? false)
        XCTAssertEqual(decodedCaps?.cameraDevices[1].info?.availableLenses, [.wideAngle])
    }

    func testCameraDeviceEntry_suspendedFlagRoundTrips() {
        let devices = [
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "builtin-0", localizedName: "MacBook Pro Camera",
                positionRaw: AVCaptureDevice.Position.unspecified.rawValue,
                isActive: false, isSuspended: true, info: nil),
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "usb-0", localizedName: "USB Camera",
                positionRaw: AVCaptureDevice.Position.unspecified.rawValue,
                isActive: true, isSuspended: false, info: nil)
        ]
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            cameraDevices: devices, activeDeviceID: "usb-0", error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(capabilities)
        XCTAssertEqual(decoded.cameraDevices[0].isSuspended, true,
                       "suspension must cross the wire so the monitor can gray the device out")
        XCTAssertEqual(decoded.cameraDevices[1].isSuspended, false)
    }


    func testCameraCapabilitiesResp_legacyShapeDecodesEmptyDeviceList() {
        // A peer that predates device selection encodes no camera_devices —
        // the decoded list must be empty (the monitor's gate stays closed).
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertTrue(decoded.cameraDevices.isEmpty)
        XCTAssertNil(decoded.activeDeviceID)
    }

    func testCameraCapabilitiesResp_deviceListRoundTrip() {
        let devices = [
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "back-0", localizedName: "Back Triple Camera",
                positionRaw: AVCaptureDevice.Position.back.rawValue,
                isActive: true, info: nil)
        ]
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            cameraDevices: devices, activeDeviceID: "back-0", error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertEqual(decoded.cameraDevices, devices.map {
            RemoteCmd.CameraDeviceEntry(
                uniqueID: $0.uniqueID, localizedName: $0.localizedName,
                positionRaw: $0.positionRaw, isActive: $0.isActive, info: nil)
        })
        XCTAssertEqual(decoded.activeDeviceID, "back-0")
    }

    // MARK: - 14. SwitchLens

    func testSwitchLens_roundTrip() {
        let original = RemoteCmd.SwitchLens(lensType: .telephoto)
        let decoded: RemoteCmd.SwitchLens = roundTrip(original)
        XCTAssertEqual(decoded.lensType, .telephoto)
    }

    func testSwitchLens_wideAngle() {
        let original = RemoteCmd.SwitchLens(lensType: .wideAngle)
        let decoded: RemoteCmd.SwitchLens = roundTrip(original)
        XCTAssertEqual(decoded.lensType, .wideAngle)
    }

    // MARK: - 15. SwitchLens




    // MARK: - 16. PeerBecameCamera

    func testPeerBecameCamera_roundTrip() {
        let original = RemoteCmd.PeerBecameCamera(bundleVersion: 66, shortVersion: "4.14.2", platform: "iPhone")
        let decoded: RemoteCmd.PeerBecameCamera = roundTrip(original)
        XCTAssertEqual(decoded.bundleVersion, 66)
        XCTAssertEqual(decoded.shortVersion, "4.14.2")
        XCTAssertEqual(decoded.platform, "iPhone")
    }

    // MARK: - 17. PeerBecameMonitor

    func testPeerBecameMonitor_roundTrip() {
        let original = RemoteCmd.PeerBecameMonitor(bundleVersion: 65, shortVersion: "4.14.1", platform: "iPad")
        let decoded: RemoteCmd.PeerBecameMonitor = roundTrip(original)
        XCTAssertEqual(decoded.bundleVersion, 65)
        XCTAssertEqual(decoded.shortVersion, "4.14.1")
        XCTAssertEqual(decoded.platform, "iPad")
    }

    // MARK: - Version handshake wire shape (cross-major)

    /// The role announcements carry the app version that `PeerAppCompatibility`
    /// compares, and that exchange happens BEFORE the gate can refuse anyone —
    /// so every major must decode every other major's announcement. These pin
    /// the exact bytes a build produces: the action numbers and the
    /// CommandParameters slots for bundle_version / short_version / platform.
    /// If this fails, a schema edit moved the handshake and older builds will
    /// pair silently with garbage instead of showing the update prompt.
    func testHandshakeActionNumbersNeverMove() {
        XCTAssertEqual(RemoteShutter_CommandAction.peerbecamecamera.rawValue, 13)
        XCTAssertEqual(RemoteShutter_CommandAction.peerbecamemonitor.rawValue, 14)
    }

    func testPeerBecameCamera_wireBytesArePinned() {
        let bytes = RemoteCmd.PeerBecameCamera(bundleVersion: 118, shortVersion: "11.0.0", platform: "iPhone").toFlatBuffer()
        XCTAssertEqual(bytes.map { String(format: "%02x", $0) }.joined(), goldenPeerBecameCameraHex)
    }

    func testPeerBecameMonitor_wireBytesArePinned() {
        let bytes = RemoteCmd.PeerBecameMonitor(bundleVersion: 118, shortVersion: "11.0.0", platform: "iPhone").toFlatBuffer()
        XCTAssertEqual(bytes.map { String(format: "%02x", $0) }.joined(), goldenPeerBecameMonitorHex)
    }

    /// The bytes an 11.0.0 build emits for these announcements. Captured once;
    /// never regenerate them from the current encoder to make a red test pass.
    private let goldenPeerBecameCameraHex = "100000005243414d0800080000000400080000000c00000008000c000b000400080000001c0000000000000d14001000000000000000000000000c0008000400140000000c0000001400000076000000060000006950686f6e6500000600000031312e302e300000"
    private let goldenPeerBecameMonitorHex = "100000005243414d0800080000000400080000000c00000008000c000b000400080000001c0000000000000e14001000000000000000000000000c0008000400140000000c0000001400000076000000060000006950686f6e6500000600000031312e302e300000"

    func testRequestKeyframe_roundTrip() {
        let original = RemoteCmd.RequestKeyframe(sender: nil)
        let decoded: RemoteCmd.RequestKeyframe = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - 18. ToggleFlash

    func testToggleFlash_roundTrip() {
        let original = RemoteCmd.ToggleFlash()
        let decoded: RemoteCmd.ToggleFlash = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - 19. ToggleFlash





    // MARK: - 20. ToggleTorch

    func testToggleTorch_roundTrip() {
        let original = RemoteCmd.ToggleTorch()
        let decoded: RemoteCmd.ToggleTorch = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - 21. ToggleTorch




    // MARK: - 24. ToggleCamera

    func testToggleCamera_roundTrip() {
        let original = RemoteCmd.ToggleCamera()
        let decoded: RemoteCmd.ToggleCamera = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - 25. ToggleCamera + the control reply

    func testToggleCameraReply_roundTrip() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle, .telephoto],
            hasFlash: true,
            hasTorch: true,
            zoomCapabilities: [.wideAngle: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0)]
        )
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil,
            backCamera: backCamera,
            currentCamera: .back,
            currentLens: .wideAngle,
            currentZoom: 1.0,
            error: nil
        )
        capabilities.inReplyTo = .togglecamera
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(capabilities)
        XCTAssertEqual(decoded.inReplyTo, .togglecamera)
        XCTAssertEqual(decoded.currentCamera, .back)
        XCTAssertEqual(decoded.currentLens, .wideAngle)
        XCTAssertEqual(decoded.backCamera?.availableLenses.count, 2)
        XCTAssertNil(decoded.error)
    }

    /// A control reply carries the camera's whole state: the command it
    /// answers, why it was refused, and torch / flash / aspect alongside the
    /// fields capabilities always had. Off / zero raw values must survive too.
    func testControlReply_roundTripsActionRefusalAndLiveState() {
        let refusal = NSError(domain: "Locked while recording", code: 0, userInfo: nil)
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .front, currentLens: .ultraWide, currentZoom: 0.5,
            previewMode: .standby, torchOn: true, flashMode: .auto, aspectRatio: .oneOne,
            inReplyTo: .toggleflash, error: refusal)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertEqual(decoded.inReplyTo, .toggleflash)
        XCTAssertEqual(decoded.error?._domain, "Locked while recording")
        XCTAssertTrue(decoded.torchOn)
        XCTAssertEqual(decoded.flashMode, .auto)
        XCTAssertEqual(decoded.aspectRatio, .oneOne)
        XCTAssertEqual(decoded.previewMode, .standby)
        XCTAssertEqual(decoded.currentLens, .ultraWide)

        let quiet = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            torchOn: false, flashMode: .off, aspectRatio: .sixteenNine, error: nil)
        let decodedQuiet: RemoteCmd.CameraCapabilitiesResp = roundTrip(quiet)
        XCTAssertEqual(decodedQuiet.inReplyTo, .requestcapabilities, "an unsolicited push")
        XCTAssertFalse(decodedQuiet.torchOn)
        XCTAssertEqual(decodedQuiet.flashMode, .off)
        XCTAssertEqual(decodedQuiet.aspectRatio, .sixteenNine)
        XCTAssertNil(decodedQuiet.error)
    }


    // MARK: - SetExposure + the exposure block of the state reply

    func testSetExposure_autoAndManualRoundTrip() {
        let auto: RemoteCmd.SetExposure = roundTrip(RemoteCmd.SetExposure(intent: .auto(bias: -1.5)))
        XCTAssertEqual(auto.intent, .auto(bias: -1.5))
        let manual: RemoteCmd.SetExposure = roundTrip(
            RemoteCmd.SetExposure(intent: .manual(durationSeconds: 1.0 / 250, iso: 400)))
        XCTAssertEqual(manual.intent, .manual(durationSeconds: 1.0 / 250, iso: 400))
        // 0 = "keep the camera's current value" must survive as 0.
        let keep: RemoteCmd.SetExposure = roundTrip(RemoteCmd.SetExposure(intent: .manual(durationSeconds: 0, iso: 800)))
        XCTAssertEqual(keep.intent, .manual(durationSeconds: 0, iso: 800))
    }

    func testControlReply_carriesTheExposureBlockOrNothing() {
        let block = ExposureState(
            mode: .manual, bias: 0.5, minBias: -8, maxBias: 8, targetOffset: -0.3, supportsManual: true,
            durationSeconds: 1.0 / 60, iso: 200, minDurationSeconds: 1.0 / 10_000, maxDurationSeconds: 1.0,
            minISO: 32, maxISO: 3200, maxFrameDurationSeconds: 1.0 / 30)
        let with = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back, currentLens: .wideAngle, currentZoom: 1,
            exposure: block, inReplyTo: .setexposure, error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(with)
        XCTAssertEqual(decoded.exposure, block)
        XCTAssertEqual(decoded.inReplyTo, .setexposure)

        let without = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back, currentLens: .wideAngle, currentZoom: 1, error: nil)
        let decodedWithout: RemoteCmd.CameraCapabilitiesResp = roundTrip(without)
        XCTAssertNil(decodedWithout.exposure, "absent block = no exposure control on this camera")
    }

    // MARK: - Cinematic commands + the Cinematic block of the state reply

    func testSetCinematic_roundTrip() {
        for intent in [CinematicIntent(enabled: true, aperture: 2.8, output: .baked),
                       CinematicIntent(enabled: false, aperture: 0, output: .editable)] {
            let decoded: RemoteCmd.SetCinematic = roundTrip(RemoteCmd.SetCinematic(intent: intent))
            XCTAssertEqual(decoded.intent, intent)
        }
    }

    func testSetCinematicFocus_everyKindRoundTrips() {
        let focuses: [CinematicFocus] = [
            .subject(id: 42, strength: .strong),
            .subject(id: 3, strength: .weak),
            .trackPoint(x: 0.25, y: 0.75, strength: .weak),
            .fixedPoint(x: 0.5, y: 0.1)
        ]
        for focus in focuses {
            let decoded: RemoteCmd.SetCinematicFocus = roundTrip(RemoteCmd.SetCinematicFocus(focus: focus))
            XCTAssertEqual(decoded.focus, focus)
        }
    }

    func testCinematicSubjects_roundTrip() {
        let report = CinematicSubjectsReport(
            subjects: [
                CinematicSubject(id: 7, groupID: 1, kind: .face,
                                 rect: CGRect(x: 0.25, y: 0.125, width: 0.25, height: 0.375),
                                 focus: .strong, isFixedFocus: false),
                CinematicSubject(id: 8, groupID: 1, kind: .humanBody,
                                 rect: CGRect(x: 0.125, y: 0.0625, width: 0.5, height: 0.875),
                                 focus: nil, isFixedFocus: false),
                CinematicSubject(id: 9, groupID: 2, kind: .dogHead,
                                 rect: CGRect(x: 0.5, y: 0.5, width: 0.125, height: 0.125),
                                 focus: .weak, isFixedFocus: true)
            ],
            notEnoughLight: true)
        let decoded: RemoteCmd.CinematicSubjects = roundTrip(RemoteCmd.CinematicSubjects(report: report))
        XCTAssertEqual(decoded.report, report)

        let empty: RemoteCmd.CinematicSubjects = roundTrip(
            RemoteCmd.CinematicSubjects(report: CinematicSubjectsReport(subjects: [], notEnoughLight: false)))
        XCTAssertEqual(empty.report.subjects, [])
        XCTAssertFalse(empty.report.notEnoughLight)
    }

    func testControlReply_carriesTheCinematicBlockOrNothing() {
        let block = CinematicState(
            enabled: true, output: .editable, aperture: 4, minAperture: 2, maxAperture: 16, defaultAperture: 2.8,
            qualities: [.hd1080p: [.fps24, .fps30], .uhd4k: [.fps30]])
        let with = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back, currentLens: .wideAngle, currentZoom: 2,
            cinematic: block, inReplyTo: .setcinematic, error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(with)
        XCTAssertEqual(decoded.cinematic, block)
        XCTAssertEqual(decoded.inReplyTo, .setcinematic)

        let without = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back, currentLens: .wideAngle, currentZoom: 1, error: nil)
        let decodedWithout: RemoteCmd.CameraCapabilitiesResp = roundTrip(without)
        XCTAssertNil(decodedWithout.cinematic, "absent block = no Cinematic on this camera")
    }

    /// Unknown enum values are malformed: dropped, never guessed into a default.
    func testCinematicCommandsWithUnknownEnumsAreDropped() {
        func command(_ action: RemoteShutter_CommandAction,
                     _ build: (inout FlatBufferBuilder) -> Offset) -> Data {
            var fbb = FlatBufferBuilder()
            let params = build(&fbb)
            let cmd = RemoteShutter_CameraCommand.createCameraCommand(&fbb, action: action, parametersOffset: params)
            let msg = RemoteShutter_P2PMessage.createP2PMessage(&fbb, type: .cameracommand, commandOffset: cmd)
            fbb.finish(offset: msg, fileId: "RCAM")
            return fbb.data
        }
        let unknownOutput = command(.setcinematic) {
            RemoteShutter_CommandParameters.createCommandParameters(&$0, cinematicEnabled: true)
        }
        XCTAssertNil(RemoteCmd.fromFlatBuffer(unknownOutput), "output Unknown: dropped")

        let unknownKind = command(.setcinematicfocus) {
            RemoteShutter_CommandParameters.createCommandParameters(&$0, cinematicFocusStrength: .strong)
        }
        XCTAssertNil(RemoteCmd.fromFlatBuffer(unknownKind), "focus kind Unknown: dropped")

        let trackWithoutStrength = command(.setcinematicfocus) {
            RemoteShutter_CommandParameters.createCommandParameters(
                &$0, cinematicFocusKind: .tracksubject, cinematicSubjectId: 7)
        }
        XCTAssertNil(RemoteCmd.fromFlatBuffer(trackWithoutStrength), "tracking without a strength: dropped")

        let unknownSubject = command(.cinematicsubjects) { fbb in
            let subject = RemoteShutter_CinematicSubject.createCinematicSubject(&fbb, id: 1, width: 0.5, height: 0.5)
            let vector = fbb.createVector(ofOffsets: [subject])
            return RemoteShutter_CommandParameters.createCommandParameters(&fbb, cinematicSubjectsVectorOffset: vector)
        }
        let report = (RemoteCmd.fromFlatBuffer(unknownSubject) as? RemoteCmd.CinematicSubjects)?.report
        XCTAssertEqual(report?.subjects, [], "a subject kind this build can't draw is skipped, the report kept")
    }

    // MARK: - 26. RequestCameraCapabilities

    func testRequestCameraCapabilities_roundTrip() {
        let original = RemoteCmd.RequestCameraCapabilities()
        let decoded: RemoteCmd.RequestCameraCapabilities = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - Gap coverage tests

    func testCameraCapabilitiesResp_zoomCapabilitiesValues() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle, .ultraWide, .telephoto],
            hasFlash: true,
            hasTorch: true,
            zoomCapabilities: [
                .wideAngle: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0),
                .ultraWide: RemoteCmd.ZoomRange(minZoom: 0.5, maxZoom: 2.0),
                .telephoto: RemoteCmd.ZoomRange(minZoom: 2.0, maxZoom: 15.0)
            ]
        )
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: backCamera,
            currentCamera: .back, currentLens: .telephoto,
            currentZoom: 5.0, error: nil
        )
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        let caps = decoded.backCamera!.getZoomCapabilities()
        XCTAssertEqual(caps[.wideAngle]?.minZoom, 1.0)
        XCTAssertEqual(caps[.wideAngle]?.maxZoom, 10.0)
        XCTAssertEqual(caps[.ultraWide]?.minZoom, 0.5)
        XCTAssertEqual(caps[.ultraWide]?.maxZoom, 2.0)
        XCTAssertEqual(caps[.telephoto]?.minZoom, 2.0)
        XCTAssertEqual(caps[.telephoto]?.maxZoom, 15.0)
    }


    func testStopRecordingVideoResp_successRoundTrip() {
        let original = RemoteCmd.StopRecordingVideoResp()
        let decoded: RemoteCmd.StopRecordingVideoResp = roundTrip(original)
        XCTAssertNil(decoded.error)
    }

    func testSwitchLens_dualCamera() {
        let original = RemoteCmd.SwitchLens(lensType: .dualCamera)
        let decoded: RemoteCmd.SwitchLens = roundTrip(original)
        XCTAssertEqual(decoded.lensType, .dualCamera, "dualCamera (rawValue 3) must survive round-trip")
    }

    func testSendFrame_landscapeLeft() {
        let frameData = Data([0xAA, 0xBB])
        let original = RemoteCmd.SendFrame(
            data: frameData, sender: nil, fps: 24,
            camPosition: .back, camOrientation: .landscapeLeft
        )
        let decoded: RemoteCmd.SendFrame = roundTrip(original)
        XCTAssertEqual(decoded.camOrientation, .landscapeLeft)
        XCTAssertEqual(decoded.data, frameData)
    }

    func testSendFrame_portraitUpsideDown() {
        let frameData = Data([0xCC, 0xDD])
        let original = RemoteCmd.SendFrame(
            data: frameData, sender: nil, fps: 15,
            camPosition: .front, camOrientation: .portraitUpsideDown
        )
        let decoded: RemoteCmd.SendFrame = roundTrip(original)
        XCTAssertEqual(decoded.camOrientation, .portraitUpsideDown)
        XCTAssertEqual(decoded.camPosition, .front)
    }

    func testToggleCameraReply_nestedZoomCapabilities() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle, .telephoto],
            hasFlash: true, hasTorch: true,
            zoomCapabilities: [
                .wideAngle: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0),
                .telephoto: RemoteCmd.ZoomRange(minZoom: 2.0, maxZoom: 20.0)
            ]
        )
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: backCamera,
            currentCamera: .back, currentLens: .wideAngle,
            currentZoom: 3.0, error: nil
        )
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(capabilities)
        let caps = decoded.backCamera!.getZoomCapabilities()
        XCTAssertEqual(caps[.wideAngle]?.minZoom, 1.0)
        XCTAssertEqual(caps[.wideAngle]?.maxZoom, 10.0)
        XCTAssertEqual(caps[.telephoto]?.minZoom, 2.0)
        XCTAssertEqual(caps[.telephoto]?.maxZoom, 20.0)
        XCTAssertEqual(Double(decoded.currentZoom), 3.0, accuracy: 0.001)
    }

    // MARK: - 26. SetVideoQuality

    func testSetVideoQuality_roundTrip() {
        let original = RemoteCmd.SetVideoQuality(resolution: .uhd4k, frameRate: .fps60)
        let decoded: RemoteCmd.SetVideoQuality = roundTrip(original)
        XCTAssertEqual(decoded.resolution, .uhd4k)
        XCTAssertEqual(decoded.frameRate, .fps60)
    }

    func testSetVideoQuality_hd1080p_24fps() {
        let original = RemoteCmd.SetVideoQuality(resolution: .hd1080p, frameRate: .fps24)
        let decoded: RemoteCmd.SetVideoQuality = roundTrip(original)
        XCTAssertEqual(decoded.resolution, .hd1080p)
        XCTAssertEqual(decoded.frameRate, .fps24)
    }

    // MARK: - 27. SetVideoQuality



    // MARK: - 28. SetPhotoQuality

    func testSetPhotoQuality_roundTrip() {
        let original = RemoteCmd.SetPhotoQuality(format: .heif, hdrMode: .on)
        let decoded: RemoteCmd.SetPhotoQuality = roundTrip(original)
        XCTAssertEqual(decoded.format, .heif)
        XCTAssertEqual(decoded.hdrMode, .on)
    }

    func testSetPhotoQuality_jpeg_hdrOff() {
        let original = RemoteCmd.SetPhotoQuality(format: .jpeg, hdrMode: .off)
        let decoded: RemoteCmd.SetPhotoQuality = roundTrip(original)
        XCTAssertEqual(decoded.format, .jpeg)
        XCTAssertEqual(decoded.hdrMode, .off)
    }

    // MARK: - 29. SetPhotoQuality



    // MARK: - 31. TimerCountdown

    func testTimerCountdown_positive() {
        let original = RemoteCmd.TimerCountdown(value: 5)
        let decoded: RemoteCmd.TimerCountdown = roundTrip(original)
        XCTAssertEqual(decoded.value, 5)
    }

    func testTimerCountdown_zero() {
        let original = RemoteCmd.TimerCountdown(value: 0)
        let decoded: RemoteCmd.TimerCountdown = roundTrip(original)
        XCTAssertEqual(decoded.value, 0)
    }

    func testTimerCountdown_cancelled() {
        let original = RemoteCmd.TimerCountdown(value: -1)
        let decoded: RemoteCmd.TimerCountdown = roundTrip(original)
        XCTAssertEqual(decoded.value, -1)
    }

    // MARK: - 30. CameraInfo with Quality Capabilities

    func testCameraInfo_withQualityCapabilities() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle],
            hasFlash: true,
            hasTorch: true,
            zoomCapabilities: [.wideAngle: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0)],
            supportedResolutions: [.hd1080p, .uhd4k],
            supportedFrameRates: [.fps24, .fps30, .fps60],
            resolutionFrameRates: [.uhd4k: [.fps24, .fps30]],
            supportsHEIF: true,
            supportsHDR: true
        )
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: backCamera,
            currentCamera: .back, currentLens: .wideAngle,
            currentZoom: 1.0, error: nil
        )
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        let info = decoded.backCamera!
        XCTAssertEqual(info.supportedResolutions, [.hd1080p, .uhd4k])
        XCTAssertEqual(info.supportedFrameRates, [.fps24, .fps30, .fps60])
        XCTAssertTrue(info.supportsHEIF)
        XCTAssertTrue(info.supportsHDR)
        let rfr = info.getResolutionFrameRates()
        XCTAssertEqual(rfr[.uhd4k], [.fps24, .fps30])
    }

    // MARK: - SetAspectRatio Round-Trip

    func testSetAspectRatio_fourThree_roundTrip() {
        let original = RemoteCmd.SetAspectRatio(aspectRatio: .fourThree)
        let decoded: RemoteCmd.SetAspectRatio = roundTrip(original)
        XCTAssertEqual(decoded.aspectRatio, .fourThree)
    }

    func testSetAspectRatio_sixteenNine_roundTrip() {
        let original = RemoteCmd.SetAspectRatio(aspectRatio: .sixteenNine)
        let decoded: RemoteCmd.SetAspectRatio = roundTrip(original)
        XCTAssertEqual(decoded.aspectRatio, .sixteenNine)
    }

    func testSetAspectRatio_oneOne_roundTrip() {
        let original = RemoteCmd.SetAspectRatio(aspectRatio: .oneOne)
        let decoded: RemoteCmd.SetAspectRatio = roundTrip(original)
        XCTAssertEqual(decoded.aspectRatio, .oneOne)
    }

    // MARK: - SetAspectRatio Round-Trip



    // MARK: - CameraInfo with Zoom Stops Round-Trip

    func testCameraInfo_withZoomStops_roundTrip() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle, .ultraWide, .telephoto],
            hasFlash: true,
            hasTorch: true,
            zoomCapabilities: [.wideAngle: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0)],
            zoomStops: [0.5, 1.0, 2.0, 5.0]
        )
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: backCamera,
            currentCamera: .back, currentLens: .wideAngle,
            currentZoom: 1.0, error: nil
        )
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertEqual(decoded.backCamera?.zoomStops, [0.5, 1.0, 2.0, 5.0])
    }

    func testCameraInfo_emptyZoomStops_defaultsToOne() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle],
            hasFlash: false,
            hasTorch: false,
            zoomCapabilities: [:]
            // zoomStops not provided, defaults to [1.0]
        )
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: backCamera,
            currentCamera: .back, currentLens: .wideAngle,
            currentZoom: 1.0, error: nil
        )
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertEqual(decoded.backCamera?.zoomStops, [1.0])
    }

    func testCameraInfo_zoomStopsPreservedWithOtherCapabilities() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle, .telephoto],
            hasFlash: true,
            hasTorch: true,
            zoomCapabilities: [
                .wideAngle: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0),
                .telephoto: RemoteCmd.ZoomRange(minZoom: 2.0, maxZoom: 20.0)
            ],
            supportedResolutions: [.hd1080p, .uhd4k],
            supportedFrameRates: [.fps30, .fps60],
            resolutionFrameRates: [:],
            supportsHEIF: true,
            supportsHDR: false,
            zoomStops: [1.0, 2.0, 5.0]
        )
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: backCamera,
            currentCamera: .back, currentLens: .wideAngle,
            currentZoom: 2.0, error: nil
        )
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        let info = decoded.backCamera!
        XCTAssertEqual(info.zoomStops, [1.0, 2.0, 5.0])
        XCTAssertEqual(info.supportedResolutions, [.hd1080p, .uhd4k])
        XCTAssertTrue(info.supportsHEIF)
        XCTAssertFalse(info.supportsHDR)
    }
}

// MARK: - Unknown actions

extension RemoteCmdSerializationTests {

    /// `CommandAction.Unknown = 0` is the whole point of the renumbering: a
    /// command from a future build decodes as nothing at all. It used to
    /// decode as TakePicture — the zero slot — so an action a peer didn't
    /// understand fired the shutter.
    func testUnknownActionDecodesToNothing() {
        var fbb = FlatBufferBuilder()
        // An action number no build assigns yet.
        let cmd = RemoteShutter_CameraCommand.createCameraCommand(
            &fbb, action: RemoteShutter_CommandAction(rawValue: 99) ?? .unknown)
        let msg = RemoteShutter_P2PMessage.createP2PMessage(
            &fbb, type: .cameracommand, commandOffset: cmd)
        fbb.finish(offset: msg, fileId: "RCAM")

        let decoded = RemoteCmd.fromFlatBuffer(fbb.sizedByteArray.withUnsafeBufferPointer { Data($0) })
        XCTAssertNil(decoded, "an action we do not know must be ignored, not guessed")
    }

    func testEndSessionRoundTrips() {
        let data = serializeToFlatBuffer(RemoteCmd.EndSession())
        XCTAssertNotNil(data)
        XCTAssertTrue(RemoteCmd.fromFlatBuffer(data!) is RemoteCmd.EndSession)
    }

    // MARK: - Camera preview mode

    func testSetCameraPreviewMode_roundTrip() {
        for mode: CameraPreviewMode in [.on, .standby] {
            let result = roundTrip(RemoteCmd.SetCameraPreviewMode(mode: mode))
            XCTAssertEqual(result.mode, mode)
        }
    }


    /// Capabilities carry both the support flag and the current mode so the
    /// monitor learns them from the first exchange.
    func testCapabilitiesCarryPreviewModeSupportAndMode() {
        let caps = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            supportsPreviewMode: true, previewMode: .standby, error: nil)
        let result = roundTrip(caps)
        XCTAssertTrue(result.supportsPreviewMode)
        XCTAssertEqual(result.previewMode, .standby)
    }

    /// A peer that predates the feature decodes as unsupported / preview-on.
    func testCapabilitiesDefaultPreviewModeIsOnAndUnsupported() {
        let caps = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            error: nil)
        let result = roundTrip(caps)
        XCTAssertFalse(result.supportsPreviewMode)
        XCTAssertEqual(result.previewMode, .on)
    }

    func testClockSyncPing_roundTrip() {
        let result = roundTrip(RemoteCmd.ClockSyncPing(t0Millis: 987_654_321_012))
        XCTAssertEqual(result.t0Millis, 987_654_321_012)
    }

    func testClockSyncPong_roundTrip() {
        let result = roundTrip(RemoteCmd.ClockSyncPong(
            echoT0Millis: 987_654_321_012, cameraClockMillis: 123_456_789_345))
        XCTAssertEqual(result.echoT0Millis, 987_654_321_012)
        XCTAssertEqual(result.cameraClockMillis, 123_456_789_345)
    }

    func testScheduledCapture_roundTrip() {
        let result = roundTrip(RemoteCmd.ScheduledCapture(
            fireAtCameraClockMillis: 1_754_800_000_123,
            anchorMillis: 1_754_800_000_000,
            captureId: "CAP-123",
            sessionId: "SESS-9",
            cameraIndex: 3))
        XCTAssertEqual(result.fireAtCameraClockMillis, 1_754_800_000_123)
        XCTAssertEqual(result.anchorMillis, 1_754_800_000_000)
        XCTAssertEqual(result.captureId, "CAP-123")
        XCTAssertEqual(result.sessionId, "SESS-9")
        XCTAssertEqual(result.cameraIndex, 3)
    }

    func testScheduledCaptureAck_roundTrip() {
        let ok = roundTrip(RemoteCmd.ScheduledCaptureAck(captureId: "CAP-42"))
        XCTAssertEqual(ok.captureId, "CAP-42")
        XCTAssertNil(ok.error)

        let nack = roundTrip(RemoteCmd.ScheduledCaptureAck(
            captureId: "CAP-43",
            error: NSError(domain: "too late", code: 0)))
        XCTAssertEqual(nack.captureId, "CAP-43")
        XCTAssertNotNil(nack.error)
    }

    func testScheduledStartRecording_roundTrip() {
        let result = roundTrip(RemoteCmd.ScheduledStartRecording(
            fireAtCameraClockMillis: 111, anchorMillis: 100,
            captureId: "REC-1", sessionId: "S", cameraIndex: 2))
        XCTAssertEqual(result.fireAtCameraClockMillis, 111)
        XCTAssertEqual(result.anchorMillis, 100)
        XCTAssertEqual(result.captureId, "REC-1")
        XCTAssertEqual(result.cameraIndex, 2)
    }

    func testScheduledStopRecording_roundTrip() {
        let result = roundTrip(RemoteCmd.ScheduledStopRecording(
            fireAtCameraClockMillis: 222, anchorMillis: 200,
            captureId: "REC-1", sessionId: "S", cameraIndex: 2))
        XCTAssertEqual(result.fireAtCameraClockMillis, 222)
        XCTAssertEqual(result.captureId, "REC-1")
    }

    // MARK: "Send Media to Remote" on the scheduled commands

    /// The director's setting rides both scheduled commands: on by default,
    /// and an explicit off survives the wire.
    func testScheduledCommands_carrySendMediaToPeer() {
        let capOn = roundTrip(RemoteCmd.ScheduledCapture(
            fireAtCameraClockMillis: 1, anchorMillis: 1, captureId: "C", sessionId: "S", cameraIndex: 1))
        XCTAssertTrue(capOn.sendMediaToPeer, "default: the director auto-collects")
        let capOff = roundTrip(RemoteCmd.ScheduledCapture(
            fireAtCameraClockMillis: 1, anchorMillis: 1, captureId: "C", sessionId: "S", cameraIndex: 1,
            sendMediaToPeer: false))
        XCTAssertFalse(capOff.sendMediaToPeer, "off: the still stays on the camera")

        let stopOn = roundTrip(RemoteCmd.ScheduledStopRecording(
            fireAtCameraClockMillis: 1, anchorMillis: 1, captureId: "R", sessionId: "S", cameraIndex: 1))
        XCTAssertTrue(stopOn.sendMediaToPeer)
        let stopOff = roundTrip(RemoteCmd.ScheduledStopRecording(
            fireAtCameraClockMillis: 1, anchorMillis: 1, captureId: "R", sessionId: "S", cameraIndex: 1,
            sendMediaToPeer: false))
        XCTAssertFalse(stopOff.sendMediaToPeer, "off: the clip stays on the camera")
    }

    /// The start/stop distinction (`isStop`) rides the response action, so the
    /// director routes each ack to the right aggregation.
    func testScheduledRecordingAck_roundTripPreservesIsStop() {
        let start = roundTrip(RemoteCmd.ScheduledRecordingAck(captureId: "R", isStop: false))
        XCTAssertFalse(start.isStop)
        XCTAssertEqual(start.captureId, "R")

        let stop = roundTrip(RemoteCmd.ScheduledRecordingAck(captureId: "R", isStop: true))
        XCTAssertTrue(stop.isStop)

        let nack = roundTrip(RemoteCmd.ScheduledRecordingAck(
            captureId: "R", isStop: false, error: NSError(domain: "x", code: 0)))
        XCTAssertNotNil(nack.error)
    }

    /// A microphone refusal crosses the wire as the enum, not as text, and
    /// the receiver words it in its own language.
    func testRecordingRefusal_roundTripsAsEnum() {
        let scheduled = roundTrip(RemoteCmd.ScheduledRecordingAck(
            captureId: "R", isStop: false, refusal: .microphonedenied))
        XCTAssertEqual(scheduled.refusal, .microphonedenied)
        XCTAssertFalse(scheduled.isAccepted)
        XCTAssertEqual(scheduled.failureMessage,
                       NSLocalizedString("microphone_off_on_camera", comment: ""))

        let plain = roundTrip(RemoteCmd.StartRecordingVideoAck(sender: nil, refusal: .microphonedenied))
        XCTAssertEqual(plain.refusal, .microphonedenied)
        XCTAssertFalse(plain.isAccepted)

        let accepted = roundTrip(RemoteCmd.ScheduledRecordingAck(captureId: "R", isStop: false))
        XCTAssertEqual(accepted.refusal, .unknown)
        XCTAssertTrue(accepted.isAccepted)
        XCTAssertNil(accepted.failureMessage)
    }

    func testSetStreamProfile_roundTrip() {
        let result = roundTrip(RemoteCmd.SetStreamProfile(
            maxLongEdge: 640, bitrateKbps: 500, fps: 20))
        XCTAssertEqual(result.maxLongEdge, 640)
        XCTAssertEqual(result.bitrateKbps, 500)
        XCTAssertEqual(result.fps, 20)
    }

    func testRequestVideoResend_roundTrip() {
        let result = roundTrip(RemoteCmd.RequestVideoResend(captureId: "R7"))
        XCTAssertEqual(result.captureId, "R7")
    }

    /// The multicam capability survives the wire, and a peer that predates it
    /// (absent field) decodes as not-multicam-capable.
    func testCapabilitiesCarryMulticamSupport() {
        let caps = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            supportsMulticam: true, error: nil)
        XCTAssertTrue(roundTrip(caps).supportsMulticam)

        let legacy = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            error: nil)
        XCTAssertFalse(roundTrip(legacy).supportsMulticam)
    }
}
