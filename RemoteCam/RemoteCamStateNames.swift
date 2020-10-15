//
//  States.swift
//  RemoteShutter
//
//  Created by Dario on 10/9/15.
//  Copyright © 2020 Security Union LLC. All rights reserved.
//

import Foundation

struct RemoteCamStates {
    let scanning = "scanning"
    let idle = "idle"
    let connected = "connected"
    let camera = "camera"
    let monitor = "monitor"
    let cameraTakingPic = "cameraTakingPic"
    let cameraRecordingVideo = "cameraRecordingVideo"
    let monitorTakingPicture = "monitorTakingPicture"
    let monitorTogglingFlash = "monitorTogglingFlash"
    let monitorTogglingCamera = "monitorTogglingCamera"
    let monitorRecordingVideo = "monitorRecordingVideo"
    let monitorPhotoMode = "monitorPhotoMode"
    let monitorVideoMode = "monitorVideoMode"
    let monitorWaitingForVideo = "monitorWaitingForVideo"
    let cameraTransmittingVideo = "cameraTransmittingVideo"
}
