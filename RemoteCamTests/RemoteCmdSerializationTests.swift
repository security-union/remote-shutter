//
//  RemoteCmdSerializationTests.swift
//  RemoteShutterTests
//
//  Round-trip NSCoding serialization tests for every RemoteCmd subclass.
//  Uses the exact same encode/decode path as production (MultipeerService).
//

import XCTest
import AVFoundation

@testable import RemoteShutter

final class RemoteCmdSerializationTests: XCTestCase {

    // MARK: - Helper

    /// Encodes and decodes using the exact production path from MultipeerService.
    private func roundTrip<T>(_ original: T) -> T {
        // Encode (MultipeerService.send line 64)
        let data: Data
        do {
            data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: false)
        } catch {
            XCTFail("Failed to archive: \(error)")
            fatalError()
        }

        // Decode (MultipeerService.session(_:didReceive:fromPeer:) lines 100-104)
        let unarchiver: NSKeyedUnarchiver
        do {
            unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        } catch {
            XCTFail("Failed to create unarchiver: \(error)")
            fatalError()
        }
        unarchiver.requiresSecureCoding = false
        let obj = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()

        guard let result = obj as? T else {
            XCTFail("Decoded object is \(type(of: obj as Any)), expected \(T.self)")
            fatalError()
        }
        return result
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
        XCTAssertEqual((decoded.error as NSError?)?.code, 42)
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
        let error = NSError(domain: "test", code: 99)
        let original = RemoteCmd.StopRecordingVideoResp(sender: nil, error: error)
        let decoded: RemoteCmd.StopRecordingVideoResp = roundTrip(original)
        XCTAssertNil(decoded.video)
        XCTAssertEqual((decoded.error as NSError?)?.code, 99)
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
        let error = NSError(domain: "camera", code: 1)
        let original = RemoteCmd.TakePicResp(sender: nil, error: error)
        let decoded: RemoteCmd.TakePicResp = roundTrip(original)
        XCTAssertNil(decoded.pic)
        XCTAssertEqual((decoded.error as NSError?)?.code, 1)
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

    // MARK: - 12. SetZoomResp

    func testSetZoomResp_roundTrip() {
        let range = RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0)
        let original = RemoteCmd.SetZoomResp(
            zoomFactor: 3.0,
            currentLens: .telephoto,
            zoomRange: range,
            error: nil
        )
        let decoded: RemoteCmd.SetZoomResp = roundTrip(original)
        XCTAssertEqual(decoded.zoomFactor!, 3.0, accuracy: 0.001)
        XCTAssertEqual(decoded.currentLens, .telephoto)
        XCTAssertEqual(decoded.zoomRange?.minZoom, 1.0)
        XCTAssertEqual(decoded.zoomRange?.maxZoom, 10.0)
        XCTAssertNil(decoded.error)
    }

    /// Known bug: wideAngle has rawValue 0, but `init?(coder:)` treats 0 as nil.
    func testSetZoomResp_wideAngleLens_BUG() {
        let original = RemoteCmd.SetZoomResp(
            zoomFactor: 1.0,
            currentLens: .wideAngle,
            zoomRange: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 5.0),
            error: nil
        )
        let decoded: RemoteCmd.SetZoomResp = roundTrip(original)
        // BUG: wideAngle (rawValue 0) is decoded as nil because of `lensRaw > 0` check
        // This test documents the bug. When fixed, change to XCTAssertEqual.
        XCTAssertNil(decoded.currentLens, "Known bug: wideAngle (rawValue 0) lost during decode")
    }

    func testSetZoomResp_withError() {
        let error = NSError(domain: "zoom", code: 5)
        let original = RemoteCmd.SetZoomResp(zoomFactor: nil, currentLens: nil, zoomRange: nil, error: error)
        let decoded: RemoteCmd.SetZoomResp = roundTrip(original)
        XCTAssertNil(decoded.zoomFactor)
        XCTAssertNil(decoded.currentLens)
        XCTAssertNil(decoded.zoomRange)
        XCTAssertEqual((decoded.error as NSError?)?.code, 5)
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

    // MARK: - 15. SwitchLensResp

    func testSwitchLensResp_roundTrip() {
        let range = RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 8.0)
        let original = RemoteCmd.SwitchLensResp(
            lensType: .ultraWide,
            availableLenses: [.wideAngle, .ultraWide, .telephoto],
            currentZoom: 1.5,
            zoomRange: range,
            error: nil
        )
        let decoded: RemoteCmd.SwitchLensResp = roundTrip(original)
        XCTAssertEqual(decoded.lensType, .ultraWide)
        XCTAssertEqual(decoded.availableLenses?.count, 3)
        XCTAssertEqual(decoded.currentZoom!, 1.5, accuracy: 0.001)
        XCTAssertEqual(decoded.zoomRange?.minZoom, 1.0)
        XCTAssertEqual(decoded.zoomRange?.maxZoom, 8.0)
        XCTAssertNil(decoded.error)
    }

    func testSwitchLensResp_wideAngle() {
        let original = RemoteCmd.SwitchLensResp(
            lensType: .wideAngle,
            availableLenses: [.wideAngle],
            currentZoom: 1.0,
            zoomRange: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 5.0),
            error: nil
        )
        let decoded: RemoteCmd.SwitchLensResp = roundTrip(original)
        XCTAssertEqual(decoded.lensType, .wideAngle, "wideAngle (rawValue 0) should survive round-trip")
        XCTAssertEqual(decoded.currentZoom!, 1.0, accuracy: 0.001)
    }

    func testSwitchLensResp_withError() {
        let error = NSError(domain: "lens", code: 3)
        let original = RemoteCmd.SwitchLensResp(
            lensType: nil,
            availableLenses: nil,
            currentZoom: nil,
            zoomRange: nil,
            error: error
        )
        let decoded: RemoteCmd.SwitchLensResp = roundTrip(original)
        XCTAssertNil(decoded.lensType)
        XCTAssertNil(decoded.availableLenses)
        XCTAssertNil(decoded.currentZoom)
        XCTAssertNil(decoded.zoomRange)
        XCTAssertEqual((decoded.error as NSError?)?.code, 3)
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
        let error = NSError(domain: "flash", code: 7)
        let original = RemoteCmd.ToggleFlashResp(flashMode: nil, error: error)
        let decoded: RemoteCmd.ToggleFlashResp = roundTrip(original)
        XCTAssertNil(decoded.flashMode)
        XCTAssertEqual((decoded.error as NSError?)?.code, 7)
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
        let error = NSError(domain: "torch", code: 8)
        let original = RemoteCmd.ToggleTorchResp(torchMode: nil, error: error)
        let decoded: RemoteCmd.ToggleTorchResp = roundTrip(original)
        XCTAssertNil(decoded.torchMode)
        XCTAssertEqual((decoded.error as NSError?)?.code, 8)
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
        let error = NSError(domain: "torch", code: 9)
        let original = RemoteCmd.SetTorchResp(torchMode: nil, error: error)
        let decoded: RemoteCmd.SetTorchResp = roundTrip(original)
        XCTAssertNil(decoded.torchMode)
        XCTAssertEqual((decoded.error as NSError?)?.code, 9)
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
        let original = RemoteCmd.ToggleCameraResp(cameraCapabilities: capabilities, error: nil)
        let decoded: RemoteCmd.ToggleCameraResp = roundTrip(original)
        XCTAssertNotNil(decoded.cameraCapabilities)
        XCTAssertEqual(decoded.cameraCapabilities?.currentCamera, .back)
        XCTAssertEqual(decoded.cameraCapabilities?.currentLens, .wideAngle)
        XCTAssertEqual(decoded.cameraCapabilities?.backCamera?.availableLenses.count, 2)
        XCTAssertNil(decoded.error)
    }

    func testToggleCameraResp_withError() {
        let error = NSError(domain: "camera", code: 11)
        let original = RemoteCmd.ToggleCameraResp(cameraCapabilities: nil, error: error)
        let decoded: RemoteCmd.ToggleCameraResp = roundTrip(original)
        XCTAssertNil(decoded.cameraCapabilities)
        XCTAssertEqual((decoded.error as NSError?)?.code, 11)
    }

    // MARK: - 26. RequestCameraCapabilities

    func testRequestCameraCapabilities_roundTrip() {
        let original = RemoteCmd.RequestCameraCapabilities()
        let decoded: RemoteCmd.RequestCameraCapabilities = roundTrip(original)
        XCTAssertNotNil(decoded)
    }
}
