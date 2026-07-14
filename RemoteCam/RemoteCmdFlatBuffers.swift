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

/// Serializes any RemoteCmd message to FlatBuffers Data for sending over MultipeerConnectivity.
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
    case let m as RemoteCmd.SetZoom: return m.toFlatBuffer()
    case let m as RemoteCmd.SetZoomResp: return m.toFlatBuffer()
    case let m as RemoteCmd.CameraCapabilitiesResp: return m.toFlatBuffer()
    case let m as RemoteCmd.SwitchLens: return m.toFlatBuffer()
    case let m as RemoteCmd.SwitchLensResp: return m.toFlatBuffer()
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
    case let m as RemoteCmd.SetVideoQuality: return m.toFlatBuffer()
    case let m as RemoteCmd.SetVideoQualityResp: return m.toFlatBuffer()
    case let m as RemoteCmd.SetPhotoQuality: return m.toFlatBuffer()
    case let m as RemoteCmd.SetPhotoQualityResp: return m.toFlatBuffer()
    case let m as RemoteCmd.TimerCountdown: return m.toFlatBuffer()
    case let m as RemoteCmd.SyncMonitorSettings: return m.toFlatBuffer()
    case let m as RemoteCmd.SetAspectRatio: return m.toFlatBuffer()
    case let m as RemoteCmd.SetAspectRatioResp: return m.toFlatBuffer()
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
/// `CameraState` pair, including the appended camera-device list. Shared by
/// every response that carries capabilities (request/toggle/select).
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
        activeDeviceIdOffset: activeIDOffset)

    let stateOffset = RemoteShutter_CameraState.createCameraState(
        &fbb,
        currentCamera: toFBCamPos(c.currentCamera),
        currentLens: toFBLens(c.currentLens),
        zoomFactor: Double(c.currentZoom),
        videoResolution: toFBResolution(c.currentVideoResolution),
        videoFrameRate: toFBFrameRate(c.currentVideoFrameRate),
        photoFormat: toFBPhotoFormat(c.currentPhotoFormat),
        hdrMode: toFBHDRMode(c.currentHDRMode),
        activeDeviceIdOffset: activeIDOffset)

    return (capsOffset, stateOffset)
}

/// Builds a full capabilities-carrying response for the given action.
private func encodeCapabilitiesResponse(action: RemoteShutter_CommandAction,
                                        capabilities: RemoteCmd.CameraCapabilitiesResp?,
                                        error: Error?) -> Data {
    var fbb = FlatBufferBuilder()
    let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()
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
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()
        let startTime: UInt64 = recordingStartTime.map { UInt64($0.timeIntervalSince1970 * 1000) } ?? 0
        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .startrecording,
            success: error == nil,
            errorOffset: errorOffset,
            recordingStartTime: startTime
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
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()
        let mediaOffset = video.map { fbb.createVector(bytes: $0) } ?? Offset()
        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .stoprecording,
            success: error == nil && video != nil,
            errorOffset: errorOffset,
            mediaDataVectorOffset: mediaOffset
        )
        return buildResponse(&fbb, action: .stoprecording, response: resp)
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
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()
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

extension RemoteCmd.SetZoomResp {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()

        var stateOffset = Offset()
        if zoomFactor != nil || currentLens != nil {
            stateOffset = RemoteShutter_CameraState.createCameraState(
                &fbb,
                currentLens: currentLens.map { toFBLens($0) } ?? .wideangle,
                zoomFactor: zoomFactor.map { Double($0) } ?? 0.0
            )
        }

        var zoomRangeOffset = Offset()
        if let range = zoomRange {
            zoomRangeOffset = RemoteShutter_ZoomRange.createZoomRange(&fbb, minZoom: Double(range.minZoom), maxZoom: Double(range.maxZoom))
        }

        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .setzoom,
            success: error == nil,
            errorOffset: errorOffset,
            currentStateOffset: stateOffset,
            zoomRangeOffset: zoomRangeOffset
        )
        return buildResponse(&fbb, action: .setzoom, response: resp)
    }
}

extension RemoteCmd.CameraCapabilitiesResp {
    func toFlatBuffer() -> Data {
        encodeCapabilitiesResponse(action: .requestcapabilities, capabilities: self, error: error)
    }
}

extension RemoteCmd.SwitchLens {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(&fbb, lensType: toFBLens(lensType))
        return buildCommand(&fbb, action: .switchlens, parameters: params)
    }
}

extension RemoteCmd.SwitchLensResp {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()

        var stateOffset = Offset()
        if lensType != nil || currentZoom != nil {
            stateOffset = RemoteShutter_CameraState.createCameraState(
                &fbb,
                currentLens: lensType.map { toFBLens($0) } ?? .wideangle,
                zoomFactor: currentZoom.map { Double($0) } ?? 0.0
            )
        }

        var zoomRangeOffset = Offset()
        if let range = zoomRange {
            zoomRangeOffset = RemoteShutter_ZoomRange.createZoomRange(&fbb, minZoom: Double(range.minZoom), maxZoom: Double(range.maxZoom))
        }

        var lensesVector = Offset()
        if let lenses = availableLenses {
            lensesVector = fbb.createVector(lenses.map { toFBLens($0) })
        }

        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .switchlens,
            success: error == nil,
            errorOffset: errorOffset,
            currentStateOffset: stateOffset,
            availableLensesVectorOffset: lensesVector,
            zoomRangeOffset: zoomRangeOffset,
            currentZoom: currentZoom.map { Double($0) } ?? 0.0
        )
        return buildResponse(&fbb, action: .switchlens, response: resp)
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

extension RemoteCmd.ToggleFlash {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .toggleflash)
    }
}

extension RemoteCmd.ToggleFlashResp {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()

        var stateOffset = Offset()
        if let mode = flashMode {
            stateOffset = RemoteShutter_CameraState.createCameraState(&fbb, flashMode: toFBFlash(mode))
        }

        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .toggleflash,
            success: error == nil,
            errorOffset: errorOffset,
            currentStateOffset: stateOffset
        )
        return buildResponse(&fbb, action: .toggleflash, response: resp)
    }
}

extension RemoteCmd.ToggleTorch {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .toggletorch)
    }
}

extension RemoteCmd.ToggleTorchResp {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()

        var stateOffset = Offset()
        if let mode = torchMode {
            stateOffset = RemoteShutter_CameraState.createCameraState(&fbb, torchMode: toFBTorch(mode))
        }

        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .toggletorch,
            success: error == nil,
            errorOffset: errorOffset,
            currentStateOffset: stateOffset
        )
        return buildResponse(&fbb, action: .toggletorch, response: resp)
    }
}

extension RemoteCmd.SetTorch {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(&fbb, torchMode: toFBTorch(torchMode))
        return buildCommand(&fbb, action: .settorchmode, parameters: params)
    }
}

extension RemoteCmd.SetTorchResp {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()

        var stateOffset = Offset()
        if let mode = torchMode {
            stateOffset = RemoteShutter_CameraState.createCameraState(&fbb, torchMode: toFBTorch(mode))
        }

        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .settorchmode,
            success: error == nil,
            errorOffset: errorOffset,
            currentStateOffset: stateOffset
        )
        return buildResponse(&fbb, action: .settorchmode, response: resp)
    }
}

extension RemoteCmd.ToggleCamera {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .togglecamera)
    }
}

extension RemoteCmd.ToggleCameraResp {
    func toFlatBuffer() -> Data {
        // SelectCameraDeviceResp subclasses this type; the payload shape is
        // identical, only the wire action differs.
        let action: RemoteShutter_CommandAction =
            self is RemoteCmd.SelectCameraDeviceResp ? .selectcameradevice : .togglecamera
        return encodeCapabilitiesResponse(action: action, capabilities: cameraCapabilities, error: error)
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

// MARK: - Video/Photo Quality toFlatBuffer() extensions

extension RemoteCmd.SetVideoQuality {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb, videoResolution: toFBResolution(resolution), videoFrameRate: toFBFrameRate(frameRate))
        return buildCommand(&fbb, action: .setvideoquality, parameters: params)
    }
}

extension RemoteCmd.SetVideoQualityResp {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()

        var stateOffset = Offset()
        if let res = resolution, let fr = frameRate {
            stateOffset = RemoteShutter_CameraState.createCameraState(
                &fbb, videoResolution: toFBResolution(res), videoFrameRate: toFBFrameRate(fr))
        }

        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .setvideoquality,
            success: error == nil,
            errorOffset: errorOffset,
            currentStateOffset: stateOffset
        )
        return buildResponse(&fbb, action: .setvideoquality, response: resp)
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

extension RemoteCmd.SetPhotoQualityResp {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()

        var stateOffset = Offset()
        if let fmt = format, let hdr = hdrMode {
            stateOffset = RemoteShutter_CameraState.createCameraState(
                &fbb, photoFormat: toFBPhotoFormat(fmt), hdrMode: toFBHDRMode(hdr))
        }

        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .setphotoquality,
            success: error == nil,
            errorOffset: errorOffset,
            currentStateOffset: stateOffset
        )
        return buildResponse(&fbb, action: .setphotoquality, response: resp)
    }
}

// MARK: - RecordingMode enum conversions

private func toFBRecordingMode(_ m: RecordingMode) -> RemoteShutter_RecordingModeEnum {
    switch m {
    case .Photo: return .photo
    case .Video: return .video
    case .Shorts: return .shorts
    }
}

private func fromFBRecordingMode(_ m: RemoteShutter_RecordingModeEnum) -> RecordingMode {
    switch m {
    case .photo: return .Photo
    case .video: return .Video
    case .shorts: return .Shorts
    case .unknown: return .Photo
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

// MARK: - SetAspectRatio toFlatBuffer()

extension RemoteCmd.SetAspectRatio {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb, aspectRatio: toFBAspectRatio(aspectRatio))
        return buildCommand(&fbb, action: .setaspectratio, parameters: params)
    }
}

extension RemoteCmd.SetAspectRatioResp {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()

        var stateOffset = Offset()
        if let ratio = aspectRatio {
            stateOffset = RemoteShutter_CameraState.createCameraState(
                &fbb, aspectRatio: toFBAspectRatio(ratio))
        }

        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .setaspectratio,
            success: error == nil,
            errorOffset: errorOffset,
            currentStateOffset: stateOffset
        )
        return buildResponse(&fbb, action: .setaspectratio, response: resp)
    }
}

// MARK: - SyncMonitorSettings toFlatBuffer()

extension RemoteCmd.SyncMonitorSettings {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        let params = RemoteShutter_CommandParameters.createCommandParameters(
            &fbb,
            recordingMode: toFBRecordingMode(mode))
        return buildCommand(&fbb, action: .syncmonitorsettings, parameters: params)
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

        case .toggleflash:
            return ToggleFlash()

        case .toggletorch:
            return ToggleTorch()

        case .settorchmode:
            return SetTorch(torchMode: fromFBTorch(params?.torchMode ?? .off))

        case .setflashmode:
            return ToggleFlash() // No SetFlash command exists

        case .togglecamera:
            return ToggleCamera()

        case .requestcapabilities:
            return RequestCameraCapabilities()

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

        case .syncmonitorsettings:
            let mode = fromFBRecordingMode(params?.recordingMode ?? .photo)
            return SyncMonitorSettings(mode: mode)

        case .setaspectratio:
            let ratio = fromFBAspectRatio(params?.aspectRatio ?? .unknown)
            return SetAspectRatio(aspectRatio: ratio)

        case .selectcameradevice:
            return SelectCameraDevice(uniqueID: params?.deviceUniqueId ?? "")
        }
    }

    private static func decodeResponse(_ msg: RemoteShutter_P2PMessage) -> Message? {
        guard let resp = msg.response else { return nil }

        let errorStr = resp.error
        let nsError: Error? = errorStr.map { NSError(domain: "RemoteCmd", code: -1, userInfo: [NSLocalizedDescriptionKey: $0]) }

        switch resp.action {
        case .startrecording:
            let startTime: Date? = resp.recordingStartTime > 0 ? Date(timeIntervalSince1970: Double(resp.recordingStartTime) / 1000.0) : nil
            return StartRecordingVideoAck(sender: nil, recordingStartTime: startTime, error: nsError)

        case .stoprecording:
            // Ack: success=true, no media, no error
            if resp.success && !resp.hasMediaData && nsError == nil {
                return StopRecordingVideoAck()
            } else {
                let videoData: Data? = resp.mediaDataCount > 0 ? Data(resp.mediaData) : nil
                return StopRecordingVideoResp(sender: nil, pic: videoData, error: nsError)
            }

        case .takepicture:
            // Ack: success=true, no media, no error
            if resp.success && !resp.hasMediaData && nsError == nil {
                return TakePicAck(sender: nil)
            } else {
                let picData: Data? = resp.mediaDataCount > 0 ? Data(resp.mediaData) : nil
                return TakePicResp(sender: nil, pic: picData, error: nsError)
            }

        case .setzoom:
            let state = resp.currentState
            let zoomFactor: CGFloat? = state != nil ? CGFloat(state!.zoomFactor) : nil
            let currentLens: CameraLensType? = state != nil ? fromFBLens(state!.currentLens) : nil
            let zoomRange: ZoomRange? = resp.zoomRange.map { ZoomRange(minZoom: CGFloat($0.minZoom), maxZoom: CGFloat($0.maxZoom)) }
            return SetZoomResp(zoomFactor: zoomFactor, currentLens: currentLens, zoomRange: zoomRange, error: nsError)

        case .requestcapabilities:
            return decodeCameraCapabilitiesResp(resp, error: nsError)

        case .switchlens:
            let state = resp.currentState
            let lensType: CameraLensType? = state != nil ? fromFBLens(state!.currentLens) : nil
            let currentZoom: CGFloat? = state != nil ? CGFloat(state!.zoomFactor) : nil
            let zoomRange: ZoomRange? = resp.zoomRange.map { ZoomRange(minZoom: CGFloat($0.minZoom), maxZoom: CGFloat($0.maxZoom)) }

            var lenses: [CameraLensType]? = nil
            if resp.hasAvailableLenses {
                var arr: [CameraLensType] = []
                for i in 0..<resp.availableLensesCount {
                    if let l = resp.availableLenses(at: i) {
                        arr.append(fromFBLens(l))
                    }
                }
                lenses = arr
            }

            return SwitchLensResp(lensType: lensType, availableLenses: lenses, currentZoom: currentZoom, zoomRange: zoomRange, error: nsError)

        case .toggleflash:
            let flashMode: AVCaptureDevice.FlashMode? = resp.currentState.map { fromFBFlash($0.flashMode) }
            return ToggleFlashResp(flashMode: flashMode, error: nsError)

        case .toggletorch:
            let torchMode: AVCaptureDevice.TorchMode? = resp.currentState.map { fromFBTorch($0.torchMode) }
            return ToggleTorchResp(torchMode: torchMode, error: nsError)

        case .settorchmode:
            let torchMode: AVCaptureDevice.TorchMode? = resp.currentState.map { fromFBTorch($0.torchMode) }
            return SetTorchResp(torchMode: torchMode, error: nsError)

        case .togglecamera:
            if nsError != nil {
                return ToggleCameraResp(cameraCapabilities: nil, error: nsError)
            }
            let capabilities = decodeCameraCapabilitiesResp(resp, error: nil)
            return ToggleCameraResp(cameraCapabilities: capabilities, error: nil)

        case .selectcameradevice:
            if nsError != nil {
                return SelectCameraDeviceResp(cameraCapabilities: nil, error: nsError)
            }
            let capabilities = decodeCameraCapabilitiesResp(resp, error: nil)
            return SelectCameraDeviceResp(cameraCapabilities: capabilities, error: nil)

        case .setvideoquality:
            let state = resp.currentState
            let resolution: VideoResolution? = state.map { fromFBResolution($0.videoResolution) }
            let frameRate: VideoFrameRate? = state.map { fromFBFrameRate($0.videoFrameRate) }
            return SetVideoQualityResp(resolution: resolution, frameRate: frameRate, error: nsError)

        case .setphotoquality:
            let state = resp.currentState
            let format: PhotoFormat? = state.map { fromFBPhotoFormat($0.photoFormat) }
            let hdrMode: HDRMode? = state.map { fromFBHDRMode($0.hdrMode) }
            return SetPhotoQualityResp(format: format, hdrMode: hdrMode, error: nsError)

        case .setaspectratio:
            let state = resp.currentState
            let ratio: AspectRatio? = state.map { fromFBAspectRatio($0.aspectRatio) }
            return SetAspectRatioResp(aspectRatio: ratio, error: nsError)

        default:
            return nil
        }
    }

    private static func decodeCameraCapabilitiesResp(_ resp: RemoteShutter_CameraStateResponse, error: Error?) -> CameraCapabilitiesResp {
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
