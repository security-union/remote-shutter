//
//  RemoteCmdFlatBuffers.swift
//  RemoteShutter
//
//  FlatBuffers encode/decode extensions for RemoteCmd types.
//  Replaces NSCoding serialization at the MultipeerService boundary.
//

import Foundation
import FlatBuffers
import AVFoundation
import UIKit


// MARK: - FlatBuffer serialization for MultipeerService

/// Serializes any RemoteCmd message to FlatBuffers Data for sending to the remote peer.
/// Used by MultipeerService.send() as the single encode entry point.
func serializeToFlatBuffer(_ msg: Message) -> Data? {
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
    case let m as RemoteCmd.SetCameraPreviewMode: return m.toFlatBuffer()
    case let m as RemoteCmd.EndSession: return m.toFlatBuffer()
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
    default: return nil
    }
}

// MARK: - Encode helpers

private func buildCommand(_ fbb: inout FlatBufferBuilder, action: RemoteShutter_CommandAction, parameters: Offset = Offset()) -> Data {
    let cmd = RemoteShutter_CameraCommand.createCameraCommand(&fbb, action: action, parametersOffset: parameters)
    let msg = RemoteShutter_P2PMessage.createP2PMessage(&fbb, type: .cameracommand, commandOffset: cmd)
    fbb.finish(offset: msg, fileId: "RCAM")
    return fbb.data
}

private func buildResponse(_ fbb: inout FlatBufferBuilder, action: RemoteShutter_CommandAction, response: Offset) -> Data {
    let msg = RemoteShutter_P2PMessage.createP2PMessage(&fbb, type: .camerastateresponse, responseOffset: response)
    fbb.finish(offset: msg, fileId: "RCAM")
    return fbb.data
}

private func buildFrame(_ fbb: inout FlatBufferBuilder, frame: Offset) -> Data {
    let msg = RemoteShutter_P2PMessage.createP2PMessage(&fbb, type: .framedata, frameDataOffset: frame)
    fbb.finish(offset: msg, fileId: "RCAM")
    return fbb.data
}

// MARK: - Enum conversions

private func toFBLens(_ lens: CameraLensType) -> RemoteShutter_CameraLensType {
    switch lens {
    case .wideAngle: return .wideangle
    case .ultraWide: return .ultrawide
    case .telephoto: return .telephoto
    case .dualCamera: return .dualcamera
    }
}

private func fromFBLens(_ lens: RemoteShutter_CameraLensType) -> CameraLensType {
    switch lens {
    case .wideangle: return .wideAngle
    case .ultrawide: return .ultraWide
    case .telephoto: return .telephoto
    case .dualcamera: return .dualCamera
    }
}

private func toFBCamPos(_ pos: AVCaptureDevice.Position) -> RemoteShutter_CameraPosition {
    switch pos {
    case .front: return .front
    default: return .back
    }
}

private func fromFBCamPos(_ pos: RemoteShutter_CameraPosition) -> AVCaptureDevice.Position {
    switch pos {
    case .front: return .front
    case .back: return .back
    }
}

// Internal (not private): the Watch preview transport (WatchSessionManager)
// maps its codec tag through the same single conversion.
func toFBStreamCodec(_ codec: RemoteCmd.StreamCodec) -> RemoteShutter_StreamCodec {
    switch codec {
    case .jpeg: return .jpeg
    case .hevc: return .hevc
    case .heic: return .heic
    case .vp9: return .vp9
    }
}

func fromFBStreamCodec(_ codec: RemoteShutter_StreamCodec) -> RemoteCmd.StreamCodec {
    switch codec {
    case .jpeg: return .jpeg
    case .hevc: return .hevc
    case .heic: return .heic
    case .vp9: return .vp9
    case .unknown: return .jpeg   // legacy sender: field absent => JPEG payload
    }
}

private func toFBTorch(_ mode: AVCaptureDevice.TorchMode) -> RemoteShutter_TorchMode {
    switch mode {
    case .off: return .off
    case .on: return .on
    case .auto: return .auto
    @unknown default: return .off
    }
}

private func fromFBTorch(_ mode: RemoteShutter_TorchMode) -> AVCaptureDevice.TorchMode {
    switch mode {
    case .off: return .off
    case .on: return .on
    case .auto: return .auto
    }
}

private func toFBFlash(_ mode: AVCaptureDevice.FlashMode) -> RemoteShutter_FlashMode {
    switch mode {
    case .off: return .off
    case .on: return .on
    case .auto: return .auto
    @unknown default: return .off
    }
}

private func fromFBFlash(_ mode: RemoteShutter_FlashMode) -> AVCaptureDevice.FlashMode {
    switch mode {
    case .off: return .off
    case .on: return .on
    case .auto: return .auto
    }
}

// MARK: - Quality enum conversions

private func toFBResolution(_ r: VideoResolution) -> RemoteShutter_VideoResolution {
    switch r {
    case .unknown: return .unknown
    case .hd1080p: return .hd1080p
    case .uhd4k: return .uhd4k
    }
}

private func fromFBResolution(_ r: RemoteShutter_VideoResolution) -> VideoResolution {
    switch r {
    case .unknown: return .unknown
    case .hd1080p: return .hd1080p
    case .uhd4k: return .uhd4k
    }
}

private func toFBFrameRate(_ f: VideoFrameRate) -> RemoteShutter_VideoFrameRate {
    switch f {
    case .unknown: return .unknown
    case .fps24: return .fps24
    case .fps30: return .fps30
    case .fps60: return .fps60
    }
}

private func fromFBFrameRate(_ f: RemoteShutter_VideoFrameRate) -> VideoFrameRate {
    switch f {
    case .unknown: return .unknown
    case .fps24: return .fps24
    case .fps30: return .fps30
    case .fps60: return .fps60
    }
}

private func toFBPhotoFormat(_ f: PhotoFormat) -> RemoteShutter_PhotoFormat {
    switch f {
    case .unknown: return .unknown
    case .jpeg: return .jpeg
    case .heif: return .heif
    }
}

private func fromFBPhotoFormat(_ f: RemoteShutter_PhotoFormat) -> PhotoFormat {
    switch f {
    case .unknown: return .unknown
    case .jpeg: return .jpeg
    case .heif: return .heif
    }
}

private func toFBHDRMode(_ m: HDRMode) -> RemoteShutter_HDRMode {
    switch m {
    case .unknown: return .unknown
    case .off: return .off
    case .on: return .on
    }
}

private func fromFBHDRMode(_ m: RemoteShutter_HDRMode) -> HDRMode {
    switch m {
    case .unknown: return .unknown
    case .off: return .off
    case .on: return .on
    }
}

// MARK: - CameraInfo encode helper

private func encodeCameraInfo(_ info: RemoteCmd.CameraInfo, _ fbb: inout FlatBufferBuilder) -> Offset {
    let lenses = info.availableLenses.map { toFBLens($0) }
    let lensesVector = fbb.createVector(lenses)

    let caps = info.getZoomCapabilities()
    var zoomCapOffsets: [Offset] = []
    for (lens, range) in caps {
        let rangeOffset = RemoteShutter_ZoomRange.createZoomRange(&fbb, minZoom: Double(range.minZoom), maxZoom: Double(range.maxZoom))
        let capOffset = RemoteShutter_ZoomCapability.createZoomCapability(&fbb, lensType: toFBLens(lens), zoomRangeOffset: rangeOffset)
        zoomCapOffsets.append(capOffset)
    }
    let zoomCapsVector = fbb.createVector(ofOffsets: zoomCapOffsets)

    // Video quality capabilities
    var videoQualityOffset = Offset()
    if !info.supportedResolutions.isEmpty {
        let resVector = fbb.createVector(info.supportedResolutions.map { toFBResolution($0) })
        let allFrameRates = info.supportedFrameRates.map { toFBFrameRate($0) }
        let frVector = fbb.createVector(allFrameRates)

        let resFrameRates = info.getResolutionFrameRates()
        var rfrOffsets: [Offset] = []
        for (resolution, rates) in resFrameRates {
            let ratesVec = fbb.createVector(rates.map { toFBFrameRate($0) })
            let rfrOffset = RemoteShutter_ResolutionFrameRates.createResolutionFrameRates(
                &fbb, resolution: toFBResolution(resolution),
                supportedFrameRatesVectorOffset: ratesVec)
            rfrOffsets.append(rfrOffset)
        }
        let rfrVector = fbb.createVector(ofOffsets: rfrOffsets)

        videoQualityOffset = RemoteShutter_VideoQualityCapabilities.createVideoQualityCapabilities(
            &fbb,
            supportedResolutionsVectorOffset: resVector,
            supportedFrameRatesVectorOffset: frVector,
            resolutionFrameRatesVectorOffset: rfrVector)
    }

    // Photo quality capabilities
    let photoQualityOffset = RemoteShutter_PhotoQualityCapabilities.createPhotoQualityCapabilities(
        &fbb, supportsHeif: info.supportsHEIF, supportsHdr: info.supportsHDR)

    // Zoom stops
    let zoomStopsVector = fbb.createVector(info.zoomStops.map { Double($0) })

    return RemoteShutter_CameraInfo.createCameraInfo(
        &fbb,
        availableLensesVectorOffset: lensesVector,
        hasFlash: info.hasFlash,
        hasTorch: info.hasTorch,
        zoomCapabilitiesVectorOffset: zoomCapsVector,
        videoQualityOffset: videoQualityOffset,
        photoQualityOffset: photoQualityOffset,
        zoomStopsVectorOffset: zoomStopsVector,
        wideAngleZoomFactor: Double(info.wideAngleZoomFactor)
    )
}

// MARK: - CameraInfo decode helper

private func decodeCameraInfo(_ fb: RemoteShutter_CameraInfo) -> RemoteCmd.CameraInfo {
    var lenses: [CameraLensType] = []
    for i in 0..<fb.availableLensesCount {
        if let l = fb.availableLenses(at: i) {
            lenses.append(fromFBLens(l))
        }
    }

    var zoomCaps: [CameraLensType: RemoteCmd.ZoomRange] = [:]
    for i in 0..<fb.zoomCapabilitiesCount {
        if let cap = fb.zoomCapabilities(at: i), let range = cap.zoomRange {
            zoomCaps[fromFBLens(cap.lensType)] = RemoteCmd.ZoomRange(
                minZoom: CGFloat(range.minZoom),
                maxZoom: CGFloat(range.maxZoom)
            )
        }
    }

    // Decode video quality capabilities
    var supportedResolutions: [VideoResolution] = []
    var supportedFrameRates: [VideoFrameRate] = []
    var resolutionFrameRates: [VideoResolution: [VideoFrameRate]] = [:]
    if let vq = fb.videoQuality {
        for i in 0..<vq.supportedResolutionsCount {
            if let r = vq.supportedResolutions(at: i) {
                supportedResolutions.append(fromFBResolution(r))
            }
        }
        for i in 0..<vq.supportedFrameRatesCount {
            if let f = vq.supportedFrameRates(at: i) {
                supportedFrameRates.append(fromFBFrameRate(f))
            }
        }
        for i in 0..<vq.resolutionFrameRatesCount {
            if let rfr = vq.resolutionFrameRates(at: i) {
                let resolution = fromFBResolution(rfr.resolution)
                var rates: [VideoFrameRate] = []
                for j in 0..<rfr.supportedFrameRatesCount {
                    if let f = rfr.supportedFrameRates(at: j) {
                        rates.append(fromFBFrameRate(f))
                    }
                }
                resolutionFrameRates[resolution] = rates
            }
        }
    }

    // Decode photo quality capabilities
    let supportsHEIF = fb.photoQuality?.supportsHeif ?? false
    let supportsHDR = fb.photoQuality?.supportsHdr ?? false

    // Decode zoom stops
    var zoomStops: [CGFloat] = []
    for i in 0..<fb.zoomStopsCount {
        zoomStops.append(CGFloat(fb.zoomStops(at: i)))
    }
    if zoomStops.isEmpty {
        zoomStops = [1.0] // Default for backward compat
    }

    let wideAngleZoomFactor = fb.wideAngleZoomFactor > 0 ? CGFloat(fb.wideAngleZoomFactor) : 1.0

    return RemoteCmd.CameraInfo(
        availableLenses: lenses,
        hasFlash: fb.hasFlash,
        hasTorch: fb.hasTorch,
        zoomCapabilities: zoomCaps,
        supportedResolutions: supportedResolutions,
        supportedFrameRates: supportedFrameRates,
        resolutionFrameRates: resolutionFrameRates,
        supportsHEIF: supportsHEIF,
        supportsHDR: supportsHDR,
        zoomStops: zoomStops,
        wideAngleZoomFactor: wideAngleZoomFactor
    )
}

// MARK: - Capabilities envelope encode helpers

/// Encodes a `CameraCapabilitiesResp` into the wire `CameraCapabilities` +
/// `CameraState` pair — what the camera has, and what it is doing.
private func encodeCapabilitiesEnvelope(
    _ c: RemoteCmd.CameraCapabilitiesResp,
    _ fbb: inout FlatBufferBuilder
) -> (caps: Offset, state: Offset) {
    let frontOffset = c.frontCamera.map { encodeCameraInfo($0, &fbb) } ?? Offset()
    let backOffset = c.backCamera.map { encodeCameraInfo($0, &fbb) } ?? Offset()

    var devicesVector = Offset()
    if !c.cameraDevices.isEmpty {
        let deviceOffsets = c.cameraDevices.map { entry -> Offset in
            let idOffset = fbb.create(string: entry.uniqueID)
            let nameOffset = fbb.create(string: entry.localizedName)
            let infoOffset = entry.info.map { encodeCameraInfo($0, &fbb) } ?? Offset()
            return RemoteShutter_CameraDeviceInfo.createCameraDeviceInfo(
                &fbb,
                uniqueIdOffset: idOffset,
                localizedNameOffset: nameOffset,
                position: toFBCamPos(entry.position),
                hasUnspecifiedPosition: entry.position == .unspecified,
                isActive: entry.isActive,
                infoOffset: infoOffset,
                isSuspended: entry.isSuspended)
        }
        devicesVector = fbb.createVector(ofOffsets: deviceOffsets)
    }
    let activeIDOffset = c.activeDeviceID.map { fbb.create(string: $0) } ?? Offset()

    let capsOffset = RemoteShutter_CameraCapabilities.createCameraCapabilities(
        &fbb,
        frontCameraOffset: frontOffset,
        backCameraOffset: backOffset,
        cameraDevicesVectorOffset: devicesVector,
        activeDeviceIdOffset: activeIDOffset,
        supportsFocusPoint: c.supportsFocusPoint,
        supportsPreviewMode: c.supportsPreviewMode,
        supportsMulticam: c.supportsMulticam)

    let stateOffset = RemoteShutter_CameraState.createCameraState(
        &fbb,
        currentCamera: toFBCamPos(c.currentCamera),
        currentLens: toFBLens(c.currentLens),
        zoomFactor: Double(c.currentZoom),
        torchMode: c.torchOn ? .on : .off,
        flashMode: toFBFlash(c.flashMode),
        videoResolution: toFBResolution(c.currentVideoResolution),
        videoFrameRate: toFBFrameRate(c.currentVideoFrameRate),
        photoFormat: toFBPhotoFormat(c.currentPhotoFormat),
        hdrMode: toFBHDRMode(c.currentHDRMode),
        aspectRatio: toFBAspectRatio(c.aspectRatio),
        activeDeviceIdOffset: activeIDOffset,
        previewMode: toFBPreviewMode(c.previewMode))

    return (capsOffset, stateOffset)
}

/// Builds a full capabilities-carrying response for the given action.
private func encodeCapabilitiesResponse(action: RemoteShutter_CommandAction,
                                        capabilities: RemoteCmd.CameraCapabilitiesResp?,
                                        error: Error?) -> Data {
    var fbb = FlatBufferBuilder()
    let errorOffset = (error as NSError?).map { fbb.create(string: RemoteCmd.wireErrorMessage($0)) } ?? Offset()
    var capsOffset = Offset()
    var stateOffset = Offset()
    if let c = capabilities {
        (capsOffset, stateOffset) = encodeCapabilitiesEnvelope(c, &fbb)
    }
    let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
        &fbb,
        action: action,
        success: error == nil,
        errorOffset: errorOffset,
        currentStateOffset: stateOffset,
        capabilitiesOffset: capsOffset
    )
    return buildResponse(&fbb, action: action, response: resp)
}

// MARK: - toFlatBuffer() extensions

extension RemoteCmd.StartRecordingVideo {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .startrecording)
    }
}

extension RemoteCmd.StartRecordingVideoAck {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: RemoteCmd.wireErrorMessage($0)) } ?? Offset()
        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .startrecording,
            success: error == nil,
            errorOffset: errorOffset
        )
        return buildResponse(&fbb, action: .startrecording, response: resp)
    }
}

extension RemoteCmd.StopRecordingVideo {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(&fbb, sendToRemote: sendMediaToPeer)
        return buildCommand(&fbb, action: .stoprecording, parameters: params)
    }
}

extension RemoteCmd.StopRecordingVideoAck {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .stoprecording,
            success: true
        )
        return buildResponse(&fbb, action: .stoprecording, response: resp)
    }
}

extension RemoteCmd.StopRecordingVideoResp {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: RemoteCmd.wireErrorMessage($0)) } ?? Offset()
        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .stoprecordingfinished,
            success: error == nil,
            errorOffset: errorOffset
        )
        return buildResponse(&fbb, action: .stoprecordingfinished, response: resp)
    }
}

extension RemoteCmd.TakePic {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(&fbb, sendToRemote: sendMediaToPeer)
        return buildCommand(&fbb, action: .takepicture, parameters: params)
    }
}

extension RemoteCmd.TakePicAck {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(&fbb, action: .takepicture, success: true)
        return buildResponse(&fbb, action: .takepicture, response: resp)
    }
}

extension RemoteCmd.TakePicResp {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: RemoteCmd.wireErrorMessage($0)) } ?? Offset()
        let mediaOffset = pic.map { fbb.createVector(bytes: $0) } ?? Offset()
        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .takepicture,
            success: error == nil && pic != nil,
            errorOffset: errorOffset,
            mediaDataVectorOffset: mediaOffset
        )
        return buildResponse(&fbb, action: .takepicture, response: resp)
    }
}

extension RemoteCmd.SendFrame {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let imageOffset = fbb.createVector(bytes: data)
        let frame = RemoteShutter_FrameData.createFrameData(
            &fbb,
            imageDataVectorOffset: imageOffset,
            fps: Int32(fps),
            cameraPosition: toFBCamPos(camPosition),
            orientation: Int32(camOrientation.rawValue),
            codec: toFBStreamCodec(codec),
            sequenceNumber: sequenceNumber
        )
        return buildFrame(&fbb, frame: frame)
    }
}

extension RemoteCmd.RequestFrame {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .requestframe)
    }
}

extension RemoteCmd.SetZoom {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(&fbb, zoomFactor: Double(zoomFactor))
        return buildCommand(&fbb, action: .setzoom, parameters: params)
    }
}

extension RemoteCmd.FocusAtPoint {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(&fbb, focusPointX: x, focusPointY: y)
        return buildCommand(&fbb, action: .focusatpoint, parameters: params)
    }
}

extension RemoteCmd.EndSession {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .endsession, parameters: Offset())
    }
}

extension RemoteCmd.SetCameraPreviewMode {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb, cameraPreviewMode: toFBPreviewMode(mode))
        return buildCommand(&fbb, action: .setcamerapreviewmode, parameters: params)
    }
}

extension RemoteCmd.CameraCapabilitiesResp {
    func toFlatBuffer() -> Data {
        encodeCapabilitiesResponse(action: inReplyTo, capabilities: self, error: error)
    }
}

extension RemoteCmd.SwitchLens {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(&fbb, lensType: toFBLens(lensType))
        return buildCommand(&fbb, action: .switchlens, parameters: params)
    }
}

extension RemoteCmd.PeerBecameCamera {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let shortVersionOffset = fbb.create(string: shortVersion)
        let platformOffset = fbb.create(string: platform)
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb,
            bundleVersion: Int32(bundleVersion),
            shortVersionOffset: shortVersionOffset,
            platformOffset: platformOffset
        )
        return buildCommand(&fbb, action: .peerbecamecamera, parameters: params)
    }
}

extension RemoteCmd.PeerBecameMonitor {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let shortVersionOffset = fbb.create(string: shortVersion)
        let platformOffset = fbb.create(string: platform)
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb,
            bundleVersion: Int32(bundleVersion),
            shortVersionOffset: shortVersionOffset,
            platformOffset: platformOffset
        )
        return buildCommand(&fbb, action: .peerbecamemonitor, parameters: params)
    }
}

extension RemoteCmd.RequestKeyframe {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .requestkeyframe)
    }
}

extension RemoteCmd.ClockSyncPing {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb, clockSyncT0Ms: t0Millis)
        return buildCommand(&fbb, action: .clocksyncping, parameters: params)
    }
}

extension RemoteCmd.ClockSyncPong {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .clocksyncping,
            success: true,
            clockSyncEchoT0Ms: echoT0Millis,
            clockSyncCameraClockMs: cameraClockMillis)
        return buildResponse(&fbb, action: .clocksyncping, response: resp)
    }
}

extension RemoteCmd.ScheduledCapture {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let captureIdOffset = fbb.create(string: captureId)
        let sessionIdOffset = fbb.create(string: sessionId)
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb,
            sendToRemote: sendMediaToPeer,
            captureFireAtCameraClockMs: fireAtCameraClockMillis,
            captureAnchorMs: anchorMillis,
            captureIdOffset: captureIdOffset,
            captureSessionIdOffset: sessionIdOffset,
            captureCameraIndex: Int32(cameraIndex))
        return buildCommand(&fbb, action: .scheduledcapture, parameters: params)
    }
}

extension RemoteCmd.ScheduledCaptureAck {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let echoOffset = fbb.create(string: captureId)
        let errorOffset = (error as NSError?).map { fbb.create(string: RemoteCmd.wireErrorMessage($0)) } ?? Offset()
        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .scheduledcapture,
            success: error == nil,
            errorOffset: errorOffset,
            captureIdEchoOffset: echoOffset)
        return buildResponse(&fbb, action: .scheduledcapture, response: resp)
    }
}

extension RemoteCmd.ScheduledStartRecording {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let captureIdOffset = fbb.create(string: captureId)
        let sessionIdOffset = fbb.create(string: sessionId)
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb,
            captureFireAtCameraClockMs: fireAtCameraClockMillis,
            captureAnchorMs: anchorMillis,
            captureIdOffset: captureIdOffset,
            captureSessionIdOffset: sessionIdOffset,
            captureCameraIndex: Int32(cameraIndex))
        return buildCommand(&fbb, action: .scheduledstartrecording, parameters: params)
    }
}

extension RemoteCmd.ScheduledStopRecording {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let captureIdOffset = fbb.create(string: captureId)
        let sessionIdOffset = fbb.create(string: sessionId)
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb,
            sendToRemote: sendMediaToPeer,
            captureFireAtCameraClockMs: fireAtCameraClockMillis,
            captureAnchorMs: anchorMillis,
            captureIdOffset: captureIdOffset,
            captureSessionIdOffset: sessionIdOffset,
            captureCameraIndex: Int32(cameraIndex))
        return buildCommand(&fbb, action: .scheduledstoprecording, parameters: params)
    }
}

extension RemoteCmd.RequestVideoResend {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let idOffset = fbb.create(string: captureId)
        let params = RemoteShutter_CommandParameters.createCommandParameters(&fbb, captureIdOffset: idOffset)
        return buildCommand(&fbb, action: .requestvideoresend, parameters: params)
    }
}

extension RemoteCmd.SetStreamProfile {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb,
            streamMaxLongEdge: Int32(maxLongEdge),
            streamBitrateKbps: Int32(bitrateKbps),
            streamFps: Int32(fps))
        return buildCommand(&fbb, action: .setstreamprofile, parameters: params)
    }
}

extension RemoteCmd.ScheduledRecordingAck {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let echoOffset = fbb.create(string: captureId)
        let errorOffset = (error as NSError?).map { fbb.create(string: RemoteCmd.wireErrorMessage($0)) } ?? Offset()
        let action: RemoteShutter_CommandAction = isStop ? .scheduledstoprecording : .scheduledstartrecording
        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: action,
            success: error == nil,
            errorOffset: errorOffset,
            captureIdEchoOffset: echoOffset)
        return buildResponse(&fbb, action: action, response: resp)
    }
}

extension RemoteCmd.ToggleFlash {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .toggleflash)
    }
}

extension RemoteCmd.ToggleTorch {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .toggletorch)
    }
}

extension RemoteCmd.ToggleCamera {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .togglecamera)
    }
}

extension RemoteCmd.SelectCameraDevice {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let idOffset = fbb.create(string: uniqueID)
        let params = RemoteShutter_CommandParameters.createCommandParameters(&fbb, deviceUniqueIdOffset: idOffset)
        return buildCommand(&fbb, action: .selectcameradevice, parameters: params)
    }
}

extension RemoteCmd.RequestCameraCapabilities {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .requestcapabilities)
    }
}

extension RemoteCmd.CameraStateReport {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let phase: RemoteShutter_RecordingPhase
        let elapsedMs: UInt64
        switch state {
        case .idle:
            phase = .idle
            elapsedMs = 0
        case .recording(let elapsed):
            phase = .recording
            elapsedMs = elapsed
        }
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb,
            stateReportSeq: seq,
            stateRecordingPhase: phase,
            stateRecordingElapsedMs: elapsedMs)
        return buildCommand(&fbb, action: .camerastatereport, parameters: params)
    }
}

// MARK: - Video/Photo Quality toFlatBuffer() extensions

extension RemoteCmd.SetVideoQuality {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb, videoResolution: toFBResolution(resolution), videoFrameRate: toFBFrameRate(frameRate))
        return buildCommand(&fbb, action: .setvideoquality, parameters: params)
    }
}

extension RemoteCmd.SetPhotoQuality {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb, photoFormat: toFBPhotoFormat(format), hdrMode: toFBHDRMode(hdrMode))
        return buildCommand(&fbb, action: .setphotoquality, parameters: params)
    }
}

// MARK: - AspectRatio enum conversions

private func toFBAspectRatio(_ r: AspectRatio) -> RemoteShutter_AspectRatioEnum {
    switch r {
    case .unknown: return .unknown
    case .fourThree: return .fourthree
    case .sixteenNine: return .sixteennine
    case .oneOne: return .oneone
    }
}

private func fromFBAspectRatio(_ r: RemoteShutter_AspectRatioEnum) -> AspectRatio {
    switch r {
    case .unknown: return .unknown
    case .fourthree: return .fourThree
    case .sixteennine: return .sixteenNine
    case .oneone: return .oneOne
    }
}

// MARK: - CameraPreviewMode enum conversions

func toFBPreviewMode(_ mode: CameraPreviewMode) -> RemoteShutter_CameraPreviewModeEnum {
    switch mode {
    case .on: return .on
    case .standby: return .standby
    }
}

/// Absent/Unknown => legacy peer or no signal; treat as On (the default).
func fromFBPreviewMode(_ mode: RemoteShutter_CameraPreviewModeEnum) -> CameraPreviewMode {
    switch mode {
    case .standby: return .standby
    case .on, .unknown: return .on
    }
}

// MARK: - SetAspectRatio toFlatBuffer()

extension RemoteCmd.SetAspectRatio {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb, aspectRatio: toFBAspectRatio(aspectRatio))
        return buildCommand(&fbb, action: .setaspectratio, parameters: params)
    }
}

// MARK: - TimerCountdown toFlatBuffer()

extension RemoteCmd.TimerCountdown {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(&fbb, countdownValue: Int32(value))
        return buildCommand(&fbb, action: .timercountdown, parameters: params)
    }
}

// MARK: - fromFlatBuffer() factory

extension RemoteCmd {
    static func fromFlatBuffer(_ data: Data) -> Message? {
        let bytes = [UInt8](data)
        var buffer = ByteBuffer(bytes: bytes)
        guard let msg: RemoteShutter_P2PMessage = try? getCheckedRoot(byteBuffer: &buffer) else {
            return nil
        }

        switch msg.type {
        case .cameracommand:
            return decodeCommand(msg)
        case .camerastateresponse:
            return decodeResponse(msg)
        case .framedata:
            return decodeFrame(msg)
        }
    }

    private static func decodeCommand(_ msg: RemoteShutter_P2PMessage) -> Message? {
        guard let cmd = msg.command else { return nil }
        let params = cmd.parameters

        switch cmd.action {
        case .unknown:
            // An action this build does not know: ignore-and-log. Before the
            // enum was renumbered this slot was TakePicture, so an unknown
            // command fired the shutter.
            logWarning("RemoteCmd: ignoring unknown command action")
            return nil

        case .settorchmode, .setflashmode, .syncmonitorsettings, .requestcamerastatereport:
            // Retired actions. Their numbers stay in the enum so the version
            // handshake's numbers never move (see FlatBufferSchemas.fbs); a
            // peer old enough to send one is refused by the version gate.
            logWarning("RemoteCmd: ignoring deprecated command action \(cmd.action)")
            return nil

        case .startrecording:
            return StartRecordingVideo(sender: nil)

        case .stoprecording:
            return StopRecordingVideo(sender: nil, sendMediaToPeer: params?.sendToRemote ?? false)

        case .takepicture:
            return TakePic(sender: nil, sendMediaToPeer: params?.sendToRemote ?? false)

        case .requestframe:
            return RequestFrame(sender: nil)

        case .setzoom:
            return SetZoom(zoomFactor: CGFloat(params?.zoomFactor ?? 1.0))

        case .switchlens:
            return SwitchLens(lensType: fromFBLens(params?.lensType ?? .wideangle))

        case .peerbecamecamera:
            return PeerBecameCamera(
                bundleVersion: Int(params?.bundleVersion ?? 0),
                shortVersion: params?.shortVersion ?? "0",
                platform: params?.platform ?? "0"
            )

        case .peerbecamemonitor:
            return PeerBecameMonitor(
                bundleVersion: Int(params?.bundleVersion ?? 0),
                shortVersion: params?.shortVersion ?? "0",
                platform: params?.platform ?? "0"
            )

        case .requestkeyframe:
            return RequestKeyframe(sender: nil)

        case .clocksyncping:
            return ClockSyncPing(t0Millis: params?.clockSyncT0Ms ?? 0)

        case .scheduledcapture:
            return ScheduledCapture(
                fireAtCameraClockMillis: params?.captureFireAtCameraClockMs ?? 0,
                anchorMillis: params?.captureAnchorMs ?? 0,
                captureId: params?.captureId ?? "",
                sessionId: params?.captureSessionId ?? "",
                cameraIndex: Int(params?.captureCameraIndex ?? 0),
                sendMediaToPeer: params?.sendToRemote ?? false)

        case .scheduledstartrecording:
            return ScheduledStartRecording(
                fireAtCameraClockMillis: params?.captureFireAtCameraClockMs ?? 0,
                anchorMillis: params?.captureAnchorMs ?? 0,
                captureId: params?.captureId ?? "",
                sessionId: params?.captureSessionId ?? "",
                cameraIndex: Int(params?.captureCameraIndex ?? 0))

        case .scheduledstoprecording:
            return ScheduledStopRecording(
                fireAtCameraClockMillis: params?.captureFireAtCameraClockMs ?? 0,
                anchorMillis: params?.captureAnchorMs ?? 0,
                captureId: params?.captureId ?? "",
                sessionId: params?.captureSessionId ?? "",
                cameraIndex: Int(params?.captureCameraIndex ?? 0),
                sendMediaToPeer: params?.sendToRemote ?? false)

        case .setstreamprofile:
            return SetStreamProfile(
                maxLongEdge: Int(params?.streamMaxLongEdge ?? 0),
                bitrateKbps: Int(params?.streamBitrateKbps ?? 0),
                fps: Int(params?.streamFps ?? 0))

        case .requestvideoresend:
            return RequestVideoResend(captureId: params?.captureId ?? "")

        case .toggleflash:
            return ToggleFlash()

        case .toggletorch:
            return ToggleTorch()

        case .togglecamera:
            return ToggleCamera()

        case .requestcapabilities:
            return RequestCameraCapabilities()

        case .camerastatereport:
            // The phase is explicit; an Unknown phase is malformed and
            // DROPPED, never guessed at.
            let state: CameraStateReport.RecordingState
            switch params?.stateRecordingPhase {
            case .idle:
                state = .idle
            case .recording:
                state = .recording(elapsedMillis: params?.stateRecordingElapsedMs ?? 0)
            default:
                return nil
            }
            return CameraStateReport(seq: params?.stateReportSeq ?? 0, state: state)

        case .stoprecordingfinished:
            // `CommandAction` is ONE enum shared by commands and responses, and
            // this switch must be exhaustive. StopRecordingFinished only ever
            // travels as a response (see `decodeResponse`); a peer sending it
            // as a command is malformed, so it is ignored like `.unknown`.
            logWarning("RemoteCmd: StopRecordingFinished is not a command")
            return nil

        case .setvideoquality:
            let resolution = fromFBResolution(params?.videoResolution ?? .hd1080p)
            let frameRate = fromFBFrameRate(params?.videoFrameRate ?? .fps30)
            return SetVideoQuality(resolution: resolution, frameRate: frameRate)

        case .setphotoquality:
            let format = fromFBPhotoFormat(params?.photoFormat ?? .jpeg)
            let hdrMode = fromFBHDRMode(params?.hdrMode ?? .off)
            return SetPhotoQuality(format: format, hdrMode: hdrMode)

        case .timercountdown:
            return TimerCountdown(value: Int(params?.countdownValue ?? 0))

        case .setaspectratio:
            let ratio = fromFBAspectRatio(params?.aspectRatio ?? .unknown)
            return SetAspectRatio(aspectRatio: ratio)

        case .selectcameradevice:
            return SelectCameraDevice(uniqueID: params?.deviceUniqueId ?? "")

        case .focusatpoint:
            return FocusAtPoint(x: params?.focusPointX ?? 0.5, y: params?.focusPointY ?? 0.5)

        case .setcamerapreviewmode:
            return SetCameraPreviewMode(mode: fromFBPreviewMode(params?.cameraPreviewMode ?? .unknown))

        case .endsession:
            return EndSession()
        }
    }

    /// The human-readable message an error contributes to the wire. Errors in
    /// this codebase carry their message in the NSError domain (what every
    /// monitor display shows); a bridged system error carries it in an
    /// explicit localized description. Never the synthesized "The operation
    /// couldn't be completed…" boilerplate a bare-domain NSError produces.
    static func wireErrorMessage(_ error: NSError) -> String {
        (error.userInfo[NSLocalizedDescriptionKey] as? String) ?? error.domain
    }

    private static func decodeResponse(_ msg: RemoteShutter_P2PMessage) -> Message? {
        guard let resp = msg.response else { return nil }

        // The message rides in BOTH the domain (the convention every monitor
        // display reads via `error._domain`) and the localized description.
        let errorStr = resp.error
        let nsError: Error? = errorStr.map {
            NSError(domain: $0, code: -1, userInfo: [NSLocalizedDescriptionKey: $0])
        }

        switch resp.action {
        case .clocksyncping:
            return ClockSyncPong(echoT0Millis: resp.clockSyncEchoT0Ms,
                                 cameraClockMillis: resp.clockSyncCameraClockMs)

        case .scheduledcapture:
            return ScheduledCaptureAck(captureId: resp.captureIdEcho ?? "", error: nsError)

        case .scheduledstartrecording:
            return ScheduledRecordingAck(captureId: resp.captureIdEcho ?? "", isStop: false, error: nsError)

        case .scheduledstoprecording:
            return ScheduledRecordingAck(captureId: resp.captureIdEcho ?? "", isStop: true, error: nsError)

        case .startrecording:
            return StartRecordingVideoAck(sender: nil, error: nsError)

        // The stop protocol's two replies ride two DISTINCT actions:
        //   .stoprecording         → StopRecordingVideoAck  ("stop received")
        //   .stoprecordingfinished → StopRecordingVideoResp ("take over" + error?)
        // Before this split both rode `.stoprecording`, told apart by sniffing
        // `success` and `media_data` — and a successful "stopped, nothing to
        // send" had to be encoded as success=false to land in the right
        // branch. The clip never travels in either message: it streams as a
        // resource transfer, so neither reply reads or writes `media_data`.
        case .stoprecording:
            return StopRecordingVideoAck()

        case .stoprecordingfinished:
            return StopRecordingVideoResp(error: nsError)

        case .takepicture:
            // Ack: success=true, no media, no error
            if resp.success && !resp.hasMediaData && nsError == nil {
                return TakePicAck(sender: nil)
            } else {
                let picData: Data? = resp.mediaDataCount > 0 ? Data(resp.mediaData) : nil
                return TakePicResp(sender: nil, pic: picData, error: nsError)
            }

        case .requestcapabilities, .setzoom, .switchlens, .toggleflash, .toggletorch,
             .togglecamera, .selectcameradevice, .setvideoquality, .setphotoquality,
             .setaspectratio, .setcamerapreviewmode:
            // Every control command is answered by the camera's full state
            // under the command's own action (Docs/control-plane.md).
            return decodeCameraCapabilitiesResp(resp, inReplyTo: resp.action, error: nsError)

        default:
            return nil
        }
    }

    private static func decodeCameraCapabilitiesResp(_ resp: RemoteShutter_CameraStateResponse,
                                                     inReplyTo: RemoteShutter_CommandAction,
                                                     error: Error?) -> CameraCapabilitiesResp {
        let state = resp.currentState
        let caps = resp.capabilities

        let frontCamera: CameraInfo? = caps?.frontCamera.map { decodeCameraInfo($0) }
        let backCamera: CameraInfo? = caps?.backCamera.map { decodeCameraInfo($0) }

        // Appended fields: absent on legacy peers, which leaves the device
        // list empty — the signal that SelectCameraDevice must not be sent.
        var cameraDevices: [CameraDeviceEntry] = []
        if let caps {
            for i in 0..<caps.cameraDevicesCount {
                guard let d = caps.cameraDevices(at: i) else { continue }
                let position: AVCaptureDevice.Position =
                    d.hasUnspecifiedPosition ? .unspecified : fromFBCamPos(d.position)
                cameraDevices.append(CameraDeviceEntry(
                    uniqueID: d.uniqueId ?? "",
                    localizedName: d.localizedName ?? "",
                    positionRaw: position.rawValue,
                    isActive: d.isActive,
                    isSuspended: d.isSuspended,
                    info: d.info.map { decodeCameraInfo($0) }))
            }
        }
        let activeDeviceID = caps?.activeDeviceId ?? state?.activeDeviceId

        return CameraCapabilitiesResp(
            frontCamera: frontCamera,
            backCamera: backCamera,
            currentCamera: state.map { fromFBCamPos($0.currentCamera) } ?? .back,
            currentLens: state.map { fromFBLens($0.currentLens) } ?? .wideAngle,
            currentZoom: state.map { CGFloat($0.zoomFactor) } ?? 1.0,
            currentVideoResolution: state.map { fromFBResolution($0.videoResolution) } ?? .hd1080p,
            currentVideoFrameRate: state.map { fromFBFrameRate($0.videoFrameRate) } ?? .fps30,
            currentPhotoFormat: state.map { fromFBPhotoFormat($0.photoFormat) } ?? .jpeg,
            currentHDRMode: state.map { fromFBHDRMode($0.hdrMode) } ?? .off,
            cameraDevices: cameraDevices,
            activeDeviceID: activeDeviceID,
            supportsFocusPoint: caps?.supportsFocusPoint ?? false,
            supportsPreviewMode: caps?.supportsPreviewMode ?? false,
            supportsMulticam: caps?.supportsMulticam ?? false,
            previewMode: state.map { fromFBPreviewMode($0.previewMode) } ?? .on,
            torchOn: state?.torchMode == .on,
            flashMode: state.map { fromFBFlash($0.flashMode) } ?? .off,
            aspectRatio: state.map { fromFBAspectRatio($0.aspectRatio) } ?? .sixteenNine,
            inReplyTo: inReplyTo,
            error: error
        )
    }

    private static func decodeFrame(_ msg: RemoteShutter_P2PMessage) -> Message? {
        guard let frame = msg.frameData else { return nil }
        let imageData = Data(frame.imageData)
        let position = fromFBCamPos(frame.cameraPosition)
        let orientation = UIInterfaceOrientation(rawValue: Int(frame.orientation)) ?? .portrait

        return SendFrame(
            data: imageData,
            sender: nil,
            fps: Int(frame.fps),
            camPosition: position,
            camOrientation: orientation,
            codec: fromFBStreamCodec(frame.codec),
            sequenceNumber: frame.sequenceNumber
        )
    }
}
