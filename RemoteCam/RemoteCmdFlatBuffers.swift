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

// MARK: - FlatBuffer serialization for MultipeerService

/// Serializes any RemoteCmd message to FlatBuffers Data for sending over MultipeerConnectivity.
/// Used by MultipeerService.send() as the single encode entry point.
func serializeToFlatBuffer(_ msg: Actor.Message) -> Data? {
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
    case let m as RemoteCmd.ToggleCameraResp: return m.toFlatBuffer()
    case let m as RemoteCmd.RequestCameraCapabilities: return m.toFlatBuffer()
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

    return RemoteShutter_CameraInfo.createCameraInfo(
        &fbb,
        availableLensesVectorOffset: lensesVector,
        hasFlash: info.hasFlash,
        hasTorch: info.hasTorch,
        zoomCapabilitiesVectorOffset: zoomCapsVector
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

    return RemoteCmd.CameraInfo(
        availableLenses: lenses,
        hasFlash: fb.hasFlash,
        hasTorch: fb.hasTorch,
        zoomCapabilities: zoomCaps
    )
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
            orientation: Int32(camOrientation.rawValue)
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
        var fbb = FlatBufferBuilder()
        let errorOffset = (self.error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()

        let frontOffset = frontCamera.map { encodeCameraInfo($0, &fbb) } ?? Offset()
        let backOffset = backCamera.map { encodeCameraInfo($0, &fbb) } ?? Offset()
        let capsOffset = RemoteShutter_CameraCapabilities.createCameraCapabilities(&fbb, frontCameraOffset: frontOffset, backCameraOffset: backOffset)

        let stateOffset = RemoteShutter_CameraState.createCameraState(
            &fbb,
            currentCamera: toFBCamPos(currentCamera),
            currentLens: toFBLens(currentLens),
            zoomFactor: Double(currentZoom)
        )

        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .requestcapabilities,
            success: error == nil,
            errorOffset: errorOffset,
            currentStateOffset: stateOffset,
            capabilitiesOffset: capsOffset
        )
        return buildResponse(&fbb, action: .requestcapabilities, response: resp)
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
        var fbb = FlatBufferBuilder()
        let errorOffset = (error as NSError?).map { fbb.create(string: $0.localizedDescription) } ?? Offset()

        var capsOffset = Offset()
        var stateOffset = Offset()
        if let c = cameraCapabilities {
            let frontOffset = c.frontCamera.map { encodeCameraInfo($0, &fbb) } ?? Offset()
            let backOffset = c.backCamera.map { encodeCameraInfo($0, &fbb) } ?? Offset()
            capsOffset = RemoteShutter_CameraCapabilities.createCameraCapabilities(&fbb, frontCameraOffset: frontOffset, backCameraOffset: backOffset)
            stateOffset = RemoteShutter_CameraState.createCameraState(
                &fbb,
                currentCamera: toFBCamPos(c.currentCamera),
                currentLens: toFBLens(c.currentLens),
                zoomFactor: Double(c.currentZoom)
            )
        }

        let resp = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &fbb,
            action: .togglecamera,
            success: error == nil,
            errorOffset: errorOffset,
            currentStateOffset: stateOffset,
            capabilitiesOffset: capsOffset
        )
        return buildResponse(&fbb, action: .togglecamera, response: resp)
    }
}

extension RemoteCmd.RequestCameraCapabilities {
    func toFlatBuffer() -> Data {
        var fbb = FlatBufferBuilder()
        return buildCommand(&fbb, action: .requestcapabilities)
    }
}

// MARK: - fromFlatBuffer() factory

extension RemoteCmd {
    /// Parses raw Data into a P2PMessage. Returns nil if the data is malformed.
    static func parseMessage(_ data: Data) -> RemoteShutter_P2PMessage? {
        let bytes = [UInt8](data)
        var buffer = ByteBuffer(bytes: bytes)
        return try? getCheckedRoot(byteBuffer: &buffer)
    }

    /// Decodes an already-parsed P2PMessage into an Actor.Message.
    /// Returns nil for heartbeats or unknown types.
    static func decode(from msg: RemoteShutter_P2PMessage) -> Actor.Message? {
        switch msg.type {
        case .cameracommand:
            return decodeCommand(msg)
        case .camerastateresponse:
            return decodeResponse(msg)
        case .framedata:
            return decodeFrame(msg)
        case .heartbeat:
            return nil
        }
    }

    /// Convenience: parses raw Data and decodes in one step.
    static func fromFlatBuffer(_ data: Data) -> Actor.Message? {
        guard let msg = parseMessage(data) else { return nil }
        return decode(from: msg)
    }

    private static func decodeCommand(_ msg: RemoteShutter_P2PMessage) -> Actor.Message? {
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
        }
    }

    private static func decodeResponse(_ msg: RemoteShutter_P2PMessage) -> Actor.Message? {
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

        default:
            return nil
        }
    }

    private static func decodeCameraCapabilitiesResp(_ resp: RemoteShutter_CameraStateResponse, error: Error?) -> CameraCapabilitiesResp {
        let state = resp.currentState
        let caps = resp.capabilities

        let frontCamera: CameraInfo? = caps?.frontCamera.map { decodeCameraInfo($0) }
        let backCamera: CameraInfo? = caps?.backCamera.map { decodeCameraInfo($0) }

        return CameraCapabilitiesResp(
            frontCamera: frontCamera,
            backCamera: backCamera,
            currentCamera: state.map { fromFBCamPos($0.currentCamera) } ?? .back,
            currentLens: state.map { fromFBLens($0.currentLens) } ?? .wideAngle,
            currentZoom: state.map { CGFloat($0.zoomFactor) } ?? 1.0,
            error: error
        )
    }

    private static func decodeFrame(_ msg: RemoteShutter_P2PMessage) -> Actor.Message? {
        guard let frame = msg.frameData else { return nil }
        let imageData = Data(frame.imageData)
        let position = fromFBCamPos(frame.cameraPosition)
        let orientation = UIInterfaceOrientation(rawValue: Int(frame.orientation)) ?? .portrait

        return SendFrame(
            data: imageData,
            sender: nil,
            fps: Int(frame.fps),
            camPosition: position,
            camOrientation: orientation
        )
    }
}
