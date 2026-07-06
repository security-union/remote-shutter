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
