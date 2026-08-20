//
//  States.swift
//  RemoteShutter
//
//  Created by Dario on 10/9/15.
//  Copyright © 2020 Security Union LLC. All rights reserved.
//

import Foundation

enum RemoteCamState: String {
    case scanning
    case reconnecting
    case idle
    case connected
    case camera
    case monitor
    case cameraTakingPic
    case cameraRecordingVideo
    case cameraTransmittingVideo
    case monitorTakingPicture
    case monitorTogglingFlash
    case monitorTogglingCamera
    case monitorStartingVideo
    case monitorRecordingVideo
    case monitorPhotoMode
    case monitorVideoMode
    case monitorWaitingForVideo
    case monitorSwitchingLens
    case watchRemoteCamera
    case watchRemoteCameraTakingPic
    case watchRemoteCameraStartingVideo
    case watchRemoteCameraRecordingVideo
}
