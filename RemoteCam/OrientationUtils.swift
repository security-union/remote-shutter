//
//  OrientationUtils.swift
//  Actors
//
//  Created by Dario Lencina on 11/1/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

public class OrientationUtils {

    /// Whether this platform rotates capture/preview connections to match the
    /// interface orientation. iOS sensors are portrait-native and need the
    /// rotation for buffers to leave the connection upright; Mac cameras are
    /// landscape-native and already upright, so Catalyst never applies
    /// interface-derived rotation. Single definition of the policy — every
    /// connection-orientation write reads this.
    public static var appliesInterfaceRotation: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return true
        #endif
    }

    class public func transform(o: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch o {
        case .landscapeLeft:
            return .landscapeLeft

        case .landscapeRight:
            return .landscapeRight

        case .portraitUpsideDown:
            return .portraitUpsideDown

        default:
            return .portrait
        }
    }

}
