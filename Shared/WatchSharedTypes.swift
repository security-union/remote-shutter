//
//  WatchSharedTypes.swift
//  RemoteShutter
//
//  FlatBuffer-based serialization for Watch <-> iPhone communication via WCSession.
//  Uses generated types from FlatBufferSchemas.fbs: WatchCommand, WatchCameraState, WatchMessage.
//

import Foundation
import FlatBuffers

// MARK: - Watch -> iPhone Command Encoding

struct WatchCommandEncoder {

    static func encode(action: RemoteShutter_WatchCommandAction,
                       zoomFactor: Double = 0,
                       lensType: RemoteShutter_CameraLensType = .wideangle,
                       timerSeconds: Int32 = 0) -> Data {
        var fbb = FlatBufferBuilder()
        let cmd = RemoteShutter_WatchCommand.createWatchCommand(
            &fbb,
            action: action,
            zoomFactor: zoomFactor,
            lensType: lensType,
            timerSeconds: timerSeconds
        )
        let msg = RemoteShutter_WatchMessage.createWatchMessage(
            &fbb,
            type: .watchcommandmsg,
            commandOffset: cmd
        )
        fbb.finish(offset: msg)
        return fbb.data
    }

    static func decode(_ data: Data) -> (action: RemoteShutter_WatchCommandAction,
                                         zoomFactor: Double,
                                         lensType: RemoteShutter_CameraLensType,
                                         timerSeconds: Int32)? {
        let bytes = [UInt8](data)
        var buffer = ByteBuffer(bytes: bytes)
        guard let msg: RemoteShutter_WatchMessage = try? getCheckedRoot(byteBuffer: &buffer) else {
            return nil
        }
        guard msg.type == .watchcommandmsg, let cmd = msg.command else { return nil }
        return (cmd.action, cmd.zoomFactor, cmd.lensType, cmd.timerSeconds)
    }
}

// MARK: - iPhone -> Watch State Encoding

struct WatchStateEncoder {

    static func encode(
        isReady: Bool,
        currentZoomFactor: Double,
        minZoomFactor: Double,
        maxZoomFactor: Double,
        isRecording: Bool,
        currentMode: RemoteShutter_RecordingModeEnum,
        currentLensType: RemoteShutter_CameraLensType,
        availableLensTypes: [RemoteShutter_CameraLensType],
        isFlashEnabled: Bool,
        isTorchEnabled: Bool,
        zoomStops: [Double],
        wideAngleZoomFactor: Double,
        lastEvent: String? = nil
    ) -> Data {
        var fbb = FlatBufferBuilder()

        let lensVec = fbb.createVector(availableLensTypes.map { $0.rawValue })
        let stopsVec = fbb.createVector(zoomStops)
        let eventOffset: Offset = lastEvent.map { fbb.create(string: $0) } ?? Offset()

        let state = RemoteShutter_WatchCameraState.createWatchCameraState(
            &fbb,
            isReady: isReady,
            currentZoomFactor: currentZoomFactor,
            minZoomFactor: minZoomFactor,
            maxZoomFactor: maxZoomFactor,
            isRecording: isRecording,
            currentMode: currentMode,
            currentLensType: currentLensType,
            availableLensTypesVectorOffset: lensVec,
            isFlashEnabled: isFlashEnabled,
            isTorchEnabled: isTorchEnabled,
            zoomStopsVectorOffset: stopsVec,
            wideAngleZoomFactor: wideAngleZoomFactor,
            lastEventOffset: eventOffset
        )
        let msg = RemoteShutter_WatchMessage.createWatchMessage(
            &fbb,
            type: .watchstatemsg,
            stateOffset: state
        )
        fbb.finish(offset: msg)
        return fbb.data
    }

    struct DecodedState {
        let isReady: Bool
        let currentZoomFactor: Double
        let minZoomFactor: Double
        let maxZoomFactor: Double
        let isRecording: Bool
        let currentMode: RemoteShutter_RecordingModeEnum
        let currentLensType: RemoteShutter_CameraLensType
        let availableLensTypes: [RemoteShutter_CameraLensType]
        let isFlashEnabled: Bool
        let isTorchEnabled: Bool
        let zoomStops: [Double]
        let wideAngleZoomFactor: Double
        let lastEvent: String?
    }

    static func decode(_ data: Data) -> DecodedState? {
        let bytes = [UInt8](data)
        var buffer = ByteBuffer(bytes: bytes)
        guard let msg: RemoteShutter_WatchMessage = try? getCheckedRoot(byteBuffer: &buffer) else {
            return nil
        }
        guard msg.type == .watchstatemsg, let state = msg.state else { return nil }

        var lenses: [RemoteShutter_CameraLensType] = []
        for i in 0..<state.availableLensTypesCount {
            if let lens = state.availableLensTypes(at: i) {
                lenses.append(lens)
            }
        }

        var stops: [Double] = []
        for i in 0..<state.zoomStopsCount {
            stops.append(state.zoomStops(at: i))
        }

        return DecodedState(
            isReady: state.isReady,
            currentZoomFactor: state.currentZoomFactor,
            minZoomFactor: state.minZoomFactor,
            maxZoomFactor: state.maxZoomFactor,
            isRecording: state.isRecording,
            currentMode: state.currentMode,
            currentLensType: state.currentLensType,
            availableLensTypes: lenses,
            isFlashEnabled: state.isFlashEnabled,
            isTorchEnabled: state.isTorchEnabled,
            zoomStops: stops,
            wideAngleZoomFactor: state.wideAngleZoomFactor,
            lastEvent: state.lastEvent
        )
    }
}

// MARK: - Convenience mappings

extension RemoteShutter_CameraLensType {
    var displayName: String {
        switch self {
        case .wideangle: return "1x"
        case .ultrawide: return "0.5"
        case .telephoto: return "2x"
        case .dualcamera: return "Dual"
        }
    }
}

extension RemoteShutter_RecordingModeEnum {
    var isPhoto: Bool { self == .photo || self == .unknown }
    var isVideo: Bool { self == .video }
}
