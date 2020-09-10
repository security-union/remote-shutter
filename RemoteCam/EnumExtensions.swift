//
//  EnumExtensions.swift
//  Actors
//
//  Created by Dario Lencina on 11/3/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import AVFoundation
import Theater

extension AVCaptureDevice.Position {
    public func toggle() -> Try<AVCaptureDevice.Position> {
        switch(self) {
        case .back:
            return Success(value: .front)
        case .front:
            return Success(value: .back)
        default:
            return Failure(error: NSError(domain: "Unable to find camera position", code: 0, userInfo: nil))
        }
    }
}

extension AVCaptureDevice.FlashMode {
    public func next() -> AVCaptureDevice.FlashMode {
        switch(self) {
        case .off:
            return .on
        case .on:
            return .auto
        case .auto:
            return .off
        }
    }
}
