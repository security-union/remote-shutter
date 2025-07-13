//
//  FlatBuffersMessages.swift
//  RemoteShutter
//
//  Actor.Message wrapper classes for FlatBuffers structures
//  Required because Theater actor system needs Message subclasses
//

import Foundation
import Theater

// MARK: - FlatBuffers Command Message

/// Actor.Message wrapper for FlatBuffers camera commands
public class FlatBuffersCameraCommand: Actor.Message {
    public let command: RemoteShutter_CameraCommand
    
    public init(command: RemoteShutter_CameraCommand) {
        self.command = command
        super.init()
    }
}

// MARK: - FlatBuffers Response Message

/// Actor.Message wrapper for FlatBuffers camera state responses
public class FlatBuffersCameraStateResponse: Actor.Message {
    public let response: RemoteShutter_CameraStateResponse
    
    public init(response: RemoteShutter_CameraStateResponse) {
        self.response = response
        super.init()
    }
}

// MARK: - FlatBuffers Frame Data Message

/// Actor.Message wrapper for FlatBuffers frame data
public class FlatBuffersFrameData: Actor.Message {
    public let frameData: RemoteShutter_FrameData
    
    public init(frameData: RemoteShutter_FrameData) {
        self.frameData = frameData
        super.init()
    }
}

// MARK: - FlatBuffers Media Data Message

/// Actor.Message wrapper for FlatBuffers media data
public class FlatBuffersMediaData: Actor.Message {
    public let mediaData: RemoteShutter_MediaData
    
    public init(mediaData: RemoteShutter_MediaData) {
        self.mediaData = mediaData
        super.init()
    }
}

// MARK: - FlatBuffers Heartbeat Message

/// Actor.Message wrapper for FlatBuffers heartbeat
public class FlatBuffersHeartbeat: Actor.Message {
    public let heartbeat: RemoteShutter_Heartbeat
    
    public init(heartbeat: RemoteShutter_Heartbeat) {
        self.heartbeat = heartbeat
        super.init()
    }
}

// MARK: - FlatBuffers Error Message

/// Actor.Message wrapper for FlatBuffers error messages
public class FlatBuffersErrorMessage: Actor.Message {
    public let errorMessage: RemoteShutter_ErrorMessage
    
    public init(errorMessage: RemoteShutter_ErrorMessage) {
        self.errorMessage = errorMessage
        super.init()
    }
} 
