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
        case let m as RemoteCmd.FocusAtPoint: return m.toFlatBuffer()
        case let m as RemoteCmd.SetExposure: return m.toFlatBuffer()
        case let m as RemoteCmd.ControlStateChanged: return m.toFlatBuffer()
        case let m as RemoteCmd.SetCinematic: return m.toFlatBuffer()
        case let m as RemoteCmd.SetCameraPreviewMode: return m.toFlatBuffer()
        case let m as RemoteCmd.CameraPreviewModeResp: return m.toFlatBuffer()
        case let m as RemoteCmd.CameraCapabilitiesResp: return m.toFlatBuffer()
        case let m as RemoteCmd.SwitchLens: return m.toFlatBuffer()
        case let m as RemoteCmd.PeerBecameCamera: return m.toFlatBuffer()
        case let m as RemoteCmd.PeerBecameMonitor: return m.toFlatBuffer()
        case let m as RemoteCmd.ToggleFlash: return m.toFlatBuffer()
        case let m as RemoteCmd.ToggleFlashResp: return m.toFlatBuffer()
        case let m as RemoteCmd.ToggleTorch: return m.toFlatBuffer()
        case let m as RemoteCmd.ToggleTorchResp: return m.toFlatBuffer()
        case let m as RemoteCmd.SetTorch: return m.toFlatBuffer()
        case let m as RemoteCmd.SetTorchResp: return m.toFlatBuffer()
        case let m as RemoteCmd.ToggleCamera: return m.toFlatBuffer()
        case let m as RemoteCmd.ToggleCameraResp: return m.toFlatBuffer() // also SelectCameraDeviceResp (subclass)
        case let m as RemoteCmd.SelectCameraDevice: return m.toFlatBuffer()
        case let m as RemoteCmd.RequestCameraCapabilities: return m.toFlatBuffer()
        case let m as RemoteCmd.CameraStateReport: return m.toFlatBuffer()
        case let m as RemoteCmd.RequestCameraStateReport: return m.toFlatBuffer()
        case let m as RemoteCmd.SetVideoQuality: return m.toFlatBuffer()
        case let m as RemoteCmd.SetVideoQualityResp: return m.toFlatBuffer()
        case let m as RemoteCmd.SetPhotoQuality: return m.toFlatBuffer()
        case let m as RemoteCmd.SetPhotoQualityResp: return m.toFlatBuffer()
        case let m as RemoteCmd.TimerCountdown: return m.toFlatBuffer()
        case let m as RemoteCmd.SyncMonitorSettings: return m.toFlatBuffer()
        case let m as RemoteCmd.SetAspectRatio: return m.toFlatBuffer()
        case let m as RemoteCmd.SetAspectRatioResp: return m.toFlatBuffer()
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
        let date = Date(timeIntervalSince1970: 1700000000)
        let original = RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: date)
        let decoded: RemoteCmd.StartRecordingVideoAck = roundTrip(original)
        XCTAssertEqual(decoded.recordingStartTime?.timeIntervalSince1970, date.timeIntervalSince1970)
        XCTAssertNil(decoded.error)
    }

    func testStartRecordingVideoAck_withError() {
        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "recording failed"])
        let original = RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil, error: error)
        let decoded: RemoteCmd.StartRecordingVideoAck = roundTrip(original)
        XCTAssertNil(decoded.recordingStartTime)
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
        let domainOnly = RemoteCmd.ToggleCameraResp(
            cameraCapabilities: nil,
            error: NSError(domain: "Couldn't switch camera", code: 0))
        let decodedDomainOnly: RemoteCmd.ToggleCameraResp = roundTrip(domainOnly)
        XCTAssertEqual(decodedDomainOnly.error?._domain, "Couldn't switch camera")
        XCTAssertEqual(decodedDomainOnly.error?.localizedDescription, "Couldn't switch camera")

        // A system-style error with an explicit description keeps it.
        let described = RemoteCmd.ToggleCameraResp(
            cameraCapabilities: nil,
            error: NSError(domain: "AVFoundationErrorDomain", code: -11800,
                           userInfo: [NSLocalizedDescriptionKey: "recording failed"]))
        let decodedDescribed: RemoteCmd.ToggleCameraResp = roundTrip(described)
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

    func testStopRecordingVideoResp_withVideo() {
        let videoData = Data(repeating: 0xAB, count: 256)
        let original = RemoteCmd.StopRecordingVideoResp(sender: nil, video: videoData)
        let decoded: RemoteCmd.StopRecordingVideoResp = roundTrip(original)
        XCTAssertEqual(decoded.video, videoData)
        XCTAssertNil(decoded.error)
    }

    func testStopRecordingVideoResp_withError() {
        let error = NSError(domain: "test", code: 99, userInfo: [NSLocalizedDescriptionKey: "stop recording failed"])
        let original = RemoteCmd.StopRecordingVideoResp(sender: nil, error: error)
        let decoded: RemoteCmd.StopRecordingVideoResp = roundTrip(original)
        XCTAssertNil(decoded.video)
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
        // Focus-point support now rides the control snapshot the caps carry.
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back,
            control: ControlState(seq: 1, supportsFocusPoint: true), error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertEqual(decoded.control?.supportsFocusPoint, true)
    }

    // MARK: - 11c. SetExposure

    private let sampleExposure = ExposureState(
        mode: .manual, durationSeconds: 1.0 / 250, iso: 400,
        minDurationSeconds: 1.0 / 10_000, maxDurationSeconds: 1.0, minISO: 32, maxISO: 3200)

    func testSetExposure_manualRoundTrip() {
        let original = RemoteCmd.SetExposure(intent: .manual(durationSeconds: 1.0 / 250, iso: 400))
        let decoded: RemoteCmd.SetExposure = roundTrip(original)
        XCTAssertEqual(decoded.intent, .manual(durationSeconds: 1.0 / 250, iso: 400))
    }

    func testSetExposure_autoRoundTrip() {
        let decoded: RemoteCmd.SetExposure = roundTrip(RemoteCmd.SetExposure(intent: .auto))
        XCTAssertEqual(decoded.intent, .auto)
    }

    func testCameraCapabilities_manualExposureRoundTrip() {
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back,
            control: ControlState(seq: 1, exposure: sampleExposure), error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertEqual(decoded.control?.supportsManualExposure, true)
        XCTAssertEqual(decoded.control?.exposure, sampleExposure)
    }

    /// A peer that predates exposure control leaves the fields absent: the
    /// monitor must read "no support, no truth", never a fabricated Auto.
    func testCameraCapabilities_noExposureWhenControlOmitsIt() {
        // A device without manual exposure carries a control snapshot whose
        // `exposure` is absent — capability is presence, never a boolean.
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back,
            control: ControlState(seq: 1), error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertEqual(decoded.control?.supportsManualExposure, false)
        XCTAssertNil(decoded.control?.exposure)
    }

    // MARK: - 11d. SetCinematic

    private let sampleCinematic = CinematicState(
        enabled: true, simulatedAperture: 2.8,
        minSimulatedAperture: 1.4, maxSimulatedAperture: 16,
        defaultSimulatedAperture: 2.0, apertureLocked: true, notEnoughLight: true)

    func testSetCinematic_roundTrip() {
        let on: RemoteCmd.SetCinematic = roundTrip(RemoteCmd.SetCinematic(intent: .on(aperture: 2.8)))
        XCTAssertEqual(on.intent, .on(aperture: 2.8))
        // aperture nil = "keep current"; 0 on the wire must decode back to nil.
        let keep: RemoteCmd.SetCinematic = roundTrip(RemoteCmd.SetCinematic(intent: .on(aperture: nil)))
        XCTAssertEqual(keep.intent, .on(aperture: nil))
        let off: RemoteCmd.SetCinematic = roundTrip(RemoteCmd.SetCinematic(intent: .off))
        XCTAssertEqual(off.intent, .off)
    }

    func testCameraCapabilities_cinematicRoundTrip() {
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back,
            control: ControlState(seq: 1, cinematic: sampleCinematic), error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertEqual(decoded.control?.supportsCinematicVideo, true)
        XCTAssertEqual(decoded.control?.cinematic, sampleCinematic)
        // Absent when the control snapshot omits it.
        let none: RemoteCmd.CameraCapabilitiesResp = roundTrip(RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back,
            control: ControlState(seq: 1), error: nil))
        XCTAssertEqual(none.control?.supportsCinematicVideo, false)
        XCTAssertNil(none.control?.cinematic)
    }

    // MARK: - 12. ControlStateChanged (the control-plane truth channel)

    private let fullControl = ControlState(
        seq: 12,
        mode: .Video,
        activeDeviceID: "back-triple",
        currentLens: .telephoto,
        availableLenses: [.wideAngle, .ultraWide, .telephoto],
        zoomFactor: 3.0, minZoom: 1.0, maxZoom: 10.0,
        zoomStops: [1.0, 2.0, 6.0], wideAngleZoomFactor: 2.0,
        supportsFocusPoint: true,
        exposure: ExposureState(mode: .manual, durationSeconds: 1.0 / 250, iso: 400,
                                minDurationSeconds: 1.0 / 10_000, maxDurationSeconds: 1.0,
                                minISO: 32, maxISO: 3200),
        cinematic: CinematicState(enabled: true, simulatedAperture: 2.8,
                                  minSimulatedAperture: 1.4, maxSimulatedAperture: 16,
                                  defaultSimulatedAperture: 2.0, apertureLocked: true,
                                  notEnoughLight: true))

    func testControlStateChanged_fullSnapshotRoundTrip() {
        let decoded: RemoteCmd.ControlStateChanged = roundTrip(RemoteCmd.ControlStateChanged(state: fullControl))
        XCTAssertEqual(decoded.state, fullControl)
        // A clean apply carries no refusal.
        XCTAssertNil(decoded.refusal)
        XCTAssertNil(decoded.refusalDetail)
    }

    func testControlStateChanged_omittedCapabilitiesStayNil() {
        // wideAngle rawValue 0 and an exposure/cinematic-free device must
        // survive: capability is presence, so the fields decode back to nil.
        let bare = ControlState(seq: 3, currentLens: .wideAngle,
                                zoomFactor: 1.0, minZoom: 1.0, maxZoom: 5.0,
                                zoomStops: [1.0], wideAngleZoomFactor: 1.0)
        let decoded: RemoteCmd.ControlStateChanged = roundTrip(RemoteCmd.ControlStateChanged(state: bare))
        XCTAssertEqual(decoded.state.currentLens, .wideAngle)
        XCTAssertNil(decoded.state.exposure)
        XCTAssertNil(decoded.state.cinematic)
        XCTAssertFalse(decoded.state.supportsManualExposure)
    }

    func testControlStateChanged_eachRefusalReasonRoundTrips() {
        for reason in [ControlRefusalReason.photoMode, .recording, .unsupported, .sessionRefused] {
            let decoded: RemoteCmd.ControlStateChanged = roundTrip(
                RemoteCmd.ControlStateChanged(state: fullControl, refusal: reason,
                                              refusalDetail: "Back Camera; 1920x1080"))
            XCTAssertEqual(decoded.refusal, reason, "refusal \(reason) must survive the wire")
            XCTAssertEqual(decoded.refusalDetail, "Back Camera; 1920x1080")
            // The snapshot is carried even on refusal — it is the truth to show.
            XCTAssertEqual(decoded.state, fullControl)
        }
    }

    // MARK: - 13. CameraCapabilitiesResp

    func testCameraCapabilitiesResp_roundTrip() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle, .ultraWide, .telephoto],
            hasFlash: true,
            hasTorch: true
        )
        let frontCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle],
            hasFlash: false,
            hasTorch: false
        )
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: frontCamera,
            backCamera: backCamera,
            currentCamera: .back,
            control: ControlState(seq: 1, currentLens: .wideAngle, zoomFactor: 2.5),
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
        XCTAssertEqual(decoded.control?.currentLens, .wideAngle)
        XCTAssertEqual(decoded.control?.zoomFactor ?? 0, 2.5, accuracy: 0.001)
        XCTAssertNil(decoded.error)
    }

    func testCameraCapabilitiesResp_nilCameras() {
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil,
            backCamera: nil,
            currentCamera: .front,
            control: ControlState(seq: 1, currentLens: .ultraWide),
            error: nil
        )
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertNil(decoded.frontCamera)
        XCTAssertNil(decoded.backCamera)
        XCTAssertEqual(decoded.currentCamera, .front)
        XCTAssertEqual(decoded.control?.currentLens, .ultraWide)
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

    func testRequestCameraStateReport_roundTrip() {
        let _: RemoteCmd.RequestCameraStateReport = roundTrip(RemoteCmd.RequestCameraStateReport())
    }

    // MARK: - 13b. Camera device selection

    func testSelectCameraDevice_roundTrip() {
        let original = RemoteCmd.SelectCameraDevice(uniqueID: "com.apple.avfoundation:USB-0x1234")
        let decoded: RemoteCmd.SelectCameraDevice = roundTrip(original)
        XCTAssertEqual(decoded.uniqueID, "com.apple.avfoundation:USB-0x1234")
    }

    func testSelectCameraDeviceResp_roundTripCarriesDeviceList() {
        let usbInfo = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle],
            hasFlash: false,
            hasTorch: false
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
            currentCamera: .back, cameraDevices: devices,
            control: ControlState(seq: 1, activeDeviceID: "usb-0"), error: nil)
        let original = RemoteCmd.SelectCameraDeviceResp(cameraCapabilities: capabilities, error: nil)

        let decoded: RemoteCmd.SelectCameraDeviceResp = roundTrip(original)
        let decodedCaps = decoded.cameraCapabilities
        XCTAssertNil(decoded.error)
        XCTAssertEqual(decodedCaps?.control?.activeDeviceID, "usb-0")
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
            currentCamera: .back, cameraDevices: devices, error: nil)
        let original = RemoteCmd.SelectCameraDeviceResp(cameraCapabilities: capabilities, error: nil)

        let decoded: RemoteCmd.SelectCameraDeviceResp = roundTrip(original)
        XCTAssertEqual(decoded.cameraCapabilities?.cameraDevices[0].isSuspended, true,
                       "suspension must cross the wire so the monitor can gray the device out")
        XCTAssertEqual(decoded.cameraCapabilities?.cameraDevices[1].isSuspended, false)
    }

    func testSelectCameraDeviceResp_withError() {
        let err = NSError(domain: "busy", code: 7, userInfo: [NSLocalizedDescriptionKey: "busy"])
        let original = RemoteCmd.SelectCameraDeviceResp(cameraCapabilities: nil, error: err)
        let decoded: RemoteCmd.SelectCameraDeviceResp = roundTrip(original)
        XCTAssertNotNil(decoded.error)
        XCTAssertNil(decoded.cameraCapabilities)
    }

    func testCameraCapabilitiesResp_legacyShapeDecodesEmptyDeviceList() {
        // A peer that predates device selection encodes no camera_devices —
        // the decoded list must be empty (the monitor's gate stays closed).
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertTrue(decoded.cameraDevices.isEmpty)
        XCTAssertNil(decoded.control?.activeDeviceID)
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
            currentCamera: .back, cameraDevices: devices,
            control: ControlState(seq: 1, activeDeviceID: "back-0"), error: nil)
        let decoded: RemoteCmd.CameraCapabilitiesResp = roundTrip(original)
        XCTAssertEqual(decoded.cameraDevices, devices.map {
            RemoteCmd.CameraDeviceEntry(
                uniqueID: $0.uniqueID, localizedName: $0.localizedName,
                positionRaw: $0.positionRaw, isActive: $0.isActive, info: nil)
        })
        XCTAssertEqual(decoded.control?.activeDeviceID, "back-0")
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

    // MARK: - 19. ToggleFlashResp

    func testToggleFlashResp_on() {
        let original = RemoteCmd.ToggleFlashResp(flashMode: .on, error: nil)
        let decoded: RemoteCmd.ToggleFlashResp = roundTrip(original)
        XCTAssertEqual(decoded.flashMode, .on)
        XCTAssertNil(decoded.error)
    }

    func testToggleFlashResp_off_rawValueZero() {
        let original = RemoteCmd.ToggleFlashResp(flashMode: .off, error: nil)
        let decoded: RemoteCmd.ToggleFlashResp = roundTrip(original)
        XCTAssertEqual(decoded.flashMode, .off, "FlashMode.off (rawValue 0) should survive round-trip")
    }

    func testToggleFlashResp_auto() {
        let original = RemoteCmd.ToggleFlashResp(flashMode: .auto, error: nil)
        let decoded: RemoteCmd.ToggleFlashResp = roundTrip(original)
        XCTAssertEqual(decoded.flashMode, .auto)
    }

    func testToggleFlashResp_withError() {
        let error = NSError(domain: "flash", code: 7, userInfo: [NSLocalizedDescriptionKey: "flash toggle failed"])
        let original = RemoteCmd.ToggleFlashResp(flashMode: nil, error: error)
        let decoded: RemoteCmd.ToggleFlashResp = roundTrip(original)
        XCTAssertNil(decoded.flashMode)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.localizedDescription, "flash toggle failed")
    }

    // MARK: - 20. ToggleTorch

    func testToggleTorch_roundTrip() {
        let original = RemoteCmd.ToggleTorch()
        let decoded: RemoteCmd.ToggleTorch = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - 21. ToggleTorchResp

    func testToggleTorchResp_on() {
        let original = RemoteCmd.ToggleTorchResp(torchMode: .on, error: nil)
        let decoded: RemoteCmd.ToggleTorchResp = roundTrip(original)
        XCTAssertEqual(decoded.torchMode, .on)
        XCTAssertNil(decoded.error)
    }

    func testToggleTorchResp_off() {
        let original = RemoteCmd.ToggleTorchResp(torchMode: .off, error: nil)
        let decoded: RemoteCmd.ToggleTorchResp = roundTrip(original)
        XCTAssertEqual(decoded.torchMode, .off)
    }

    func testToggleTorchResp_withError() {
        let error = NSError(domain: "torch", code: 8, userInfo: [NSLocalizedDescriptionKey: "torch toggle failed"])
        let original = RemoteCmd.ToggleTorchResp(torchMode: nil, error: error)
        let decoded: RemoteCmd.ToggleTorchResp = roundTrip(original)
        XCTAssertNil(decoded.torchMode)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.localizedDescription, "torch toggle failed")
    }

    // MARK: - 22. SetTorch

    func testSetTorch_on() {
        let original = RemoteCmd.SetTorch(torchMode: .on)
        let decoded: RemoteCmd.SetTorch = roundTrip(original)
        XCTAssertEqual(decoded.torchMode, .on)
    }

    func testSetTorch_off() {
        let original = RemoteCmd.SetTorch(torchMode: .off)
        let decoded: RemoteCmd.SetTorch = roundTrip(original)
        XCTAssertEqual(decoded.torchMode, .off)
    }

    // MARK: - 23. SetTorchResp

    func testSetTorchResp_on() {
        let original = RemoteCmd.SetTorchResp(torchMode: .on, error: nil)
        let decoded: RemoteCmd.SetTorchResp = roundTrip(original)
        XCTAssertEqual(decoded.torchMode, .on)
        XCTAssertNil(decoded.error)
    }

    func testSetTorchResp_withError() {
        let error = NSError(domain: "torch", code: 9, userInfo: [NSLocalizedDescriptionKey: "set torch failed"])
        let original = RemoteCmd.SetTorchResp(torchMode: nil, error: error)
        let decoded: RemoteCmd.SetTorchResp = roundTrip(original)
        XCTAssertNil(decoded.torchMode)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.localizedDescription, "set torch failed")
    }

    // MARK: - 24. ToggleCamera

    func testToggleCamera_roundTrip() {
        let original = RemoteCmd.ToggleCamera()
        let decoded: RemoteCmd.ToggleCamera = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - 25. ToggleCameraResp

    func testToggleCameraResp_roundTrip() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle, .telephoto],
            hasFlash: true,
            hasTorch: true
        )
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil,
            backCamera: backCamera,
            currentCamera: .back,
            error: nil
        )
        let original = RemoteCmd.ToggleCameraResp(cameraCapabilities: capabilities, error: nil)
        let decoded: RemoteCmd.ToggleCameraResp = roundTrip(original)
        XCTAssertNotNil(decoded.cameraCapabilities)
        XCTAssertEqual(decoded.cameraCapabilities?.currentCamera, .back)
        XCTAssertEqual(decoded.cameraCapabilities?.backCamera?.availableLenses.count, 2)
        XCTAssertNil(decoded.error)
    }

    func testToggleCameraResp_withError() {
        let error = NSError(domain: "camera", code: 11, userInfo: [NSLocalizedDescriptionKey: "camera toggle failed"])
        let original = RemoteCmd.ToggleCameraResp(cameraCapabilities: nil, error: error)
        let decoded: RemoteCmd.ToggleCameraResp = roundTrip(original)
        XCTAssertNil(decoded.cameraCapabilities)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.localizedDescription, "camera toggle failed")
    }

    // MARK: - 26. RequestCameraCapabilities

    func testRequestCameraCapabilities_roundTrip() {
        let original = RemoteCmd.RequestCameraCapabilities()
        let decoded: RemoteCmd.RequestCameraCapabilities = roundTrip(original)
        XCTAssertNotNil(decoded)
    }

    // MARK: - Gap coverage tests

    func testToggleTorchResp_auto() {
        let original = RemoteCmd.ToggleTorchResp(torchMode: .auto, error: nil)
        let decoded: RemoteCmd.ToggleTorchResp = roundTrip(original)
        XCTAssertEqual(decoded.torchMode, .auto, "TorchMode.auto (rawValue 2) must survive round-trip")
    }

    func testSetTorchResp_off_rawValueZero() {
        let original = RemoteCmd.SetTorchResp(torchMode: .off, error: nil)
        let decoded: RemoteCmd.SetTorchResp = roundTrip(original)
        XCTAssertEqual(decoded.torchMode, .off, "TorchMode.off (rawValue 0) must survive round-trip")
    }

    func testStopRecordingVideoResp_nilVideoNilError() {
        let original = RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil)
        let decoded: RemoteCmd.StopRecordingVideoResp = roundTrip(original)
        XCTAssertNil(decoded.video)
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

    /// The capabilities envelope carries the control seed intact — the zoom
    /// truth a fresh monitor boots from rides inside the toggle response.
    func testToggleCameraResp_nestedControlSeed() {
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil,
            backCamera: RemoteCmd.CameraInfo(availableLenses: [.wideAngle, .telephoto],
                                             hasFlash: true, hasTorch: true),
            currentCamera: .back,
            control: ControlState(seq: 7, activeDeviceID: "back-1",
                                  zoomFactor: 3.0, minZoom: 1.0, maxZoom: 10.0,
                                  zoomStops: [1.0, 2.0], wideAngleZoomFactor: 2.0),
            error: nil
        )
        let original = RemoteCmd.ToggleCameraResp(cameraCapabilities: capabilities, error: nil)
        let decoded: RemoteCmd.ToggleCameraResp = roundTrip(original)
        let control = decoded.cameraCapabilities?.control
        XCTAssertEqual(control?.seq, 7)
        XCTAssertEqual(control?.activeDeviceID, "back-1")
        XCTAssertEqual(Double(control?.zoomFactor ?? 0), 3.0, accuracy: 0.001)
        XCTAssertEqual(Double(control?.maxZoom ?? 0), 10.0, accuracy: 0.001)
        XCTAssertEqual(control?.zoomStops, [1.0, 2.0])
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

    // MARK: - 27. SetVideoQualityResp

    func testSetVideoQualityResp_success() {
        let original = RemoteCmd.SetVideoQualityResp(resolution: .uhd4k, frameRate: .fps30, error: nil)
        let decoded: RemoteCmd.SetVideoQualityResp = roundTrip(original)
        XCTAssertEqual(decoded.resolution, .uhd4k)
        XCTAssertEqual(decoded.frameRate, .fps30)
        XCTAssertNil(decoded.error)
    }

    func testSetVideoQualityResp_withError() {
        let error = NSError(domain: "quality", code: -1, userInfo: [NSLocalizedDescriptionKey: "4K not supported"])
        let original = RemoteCmd.SetVideoQualityResp(resolution: nil, frameRate: nil, error: error)
        let decoded: RemoteCmd.SetVideoQualityResp = roundTrip(original)
        XCTAssertNil(decoded.resolution)
        XCTAssertNil(decoded.frameRate)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.localizedDescription, "4K not supported")
    }

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

    // MARK: - 29. SetPhotoQualityResp

    func testSetPhotoQualityResp_success() {
        let original = RemoteCmd.SetPhotoQualityResp(format: .heif, hdrMode: .on, error: nil)
        let decoded: RemoteCmd.SetPhotoQualityResp = roundTrip(original)
        XCTAssertEqual(decoded.format, .heif)
        XCTAssertEqual(decoded.hdrMode, .on)
        XCTAssertNil(decoded.error)
    }

    func testSetPhotoQualityResp_withError() {
        let error = NSError(domain: "quality", code: -1, userInfo: [NSLocalizedDescriptionKey: "HEIF not supported"])
        let original = RemoteCmd.SetPhotoQualityResp(format: nil, hdrMode: nil, error: error)
        let decoded: RemoteCmd.SetPhotoQualityResp = roundTrip(original)
        XCTAssertNil(decoded.format)
        XCTAssertNil(decoded.hdrMode)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.localizedDescription, "HEIF not supported")
    }

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

    // MARK: - 32. SyncMonitorSettings

    func testSyncMonitorSettings_photoMode() {
        let original = RemoteCmd.SyncMonitorSettings(mode: .Photo)
        let decoded: RemoteCmd.SyncMonitorSettings = roundTrip(original)
        XCTAssertEqual(decoded.mode, .Photo)
    }

    func testSyncMonitorSettings_videoMode() {
        let original = RemoteCmd.SyncMonitorSettings(mode: .Video)
        let decoded: RemoteCmd.SyncMonitorSettings = roundTrip(original)
        XCTAssertEqual(decoded.mode, .Video)
    }

    func testSyncMonitorSettings_shortsMode() {
        let original = RemoteCmd.SyncMonitorSettings(mode: .Shorts)
        let decoded: RemoteCmd.SyncMonitorSettings = roundTrip(original)
        XCTAssertEqual(decoded.mode, .Shorts)
    }

    // MARK: - 30. CameraInfo with Quality Capabilities

    func testCameraInfo_withQualityCapabilities() {
        let backCamera = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle],
            hasFlash: true,
            hasTorch: true,
            supportedResolutions: [.hd1080p, .uhd4k],
            supportedFrameRates: [.fps24, .fps30, .fps60],
            resolutionFrameRates: [.uhd4k: [.fps24, .fps30]],
            supportsHEIF: true,
            supportsHDR: true
        )
        let original = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: backCamera,
            currentCamera: .back, error: nil
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

    // MARK: - SetAspectRatioResp Round-Trip

    func testSetAspectRatioResp_success_roundTrip() {
        let original = RemoteCmd.SetAspectRatioResp(aspectRatio: .fourThree, error: nil)
        let decoded: RemoteCmd.SetAspectRatioResp = roundTrip(original)
        XCTAssertEqual(decoded.aspectRatio, .fourThree)
        XCTAssertNil(decoded.error)
    }

    func testSetAspectRatioResp_withError_roundTrip() {
        let error = NSError(domain: "ratio", code: -1, userInfo: [NSLocalizedDescriptionKey: "not supported"])
        let original = RemoteCmd.SetAspectRatioResp(aspectRatio: nil, error: error)
        let decoded: RemoteCmd.SetAspectRatioResp = roundTrip(original)
        XCTAssertNil(decoded.aspectRatio)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.localizedDescription, "not supported")
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

    func testCameraPreviewModeResp_roundTrip() {
        for mode: CameraPreviewMode in [.on, .standby] {
            let result = roundTrip(RemoteCmd.CameraPreviewModeResp(mode: mode))
            XCTAssertEqual(result.mode, mode)
        }
    }

    /// Capabilities carry both the support flag and the current mode so the
    /// monitor learns them from the first exchange.
    func testCapabilitiesCarryPreviewModeSupportAndMode() {
        let caps = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, supportsPreviewMode: true, previewMode: .standby, error: nil)
        let result = roundTrip(caps)
        XCTAssertTrue(result.supportsPreviewMode)
        XCTAssertEqual(result.previewMode, .standby)
    }

    /// A peer that predates the feature decodes as unsupported / preview-on.
    func testCapabilitiesDefaultPreviewModeIsOnAndUnsupported() {
        let caps = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, error: nil)
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
            currentCamera: .back, supportsMulticam: true, error: nil)
        XCTAssertTrue(roundTrip(caps).supportsMulticam)

        let legacy = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, error: nil)
        XCTAssertFalse(roundTrip(legacy).supportsMulticam)
    }
}
