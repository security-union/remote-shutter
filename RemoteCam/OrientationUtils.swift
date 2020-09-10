//
//  OrientationUtils.swift
//  Actors
//
//  Created by Dario Lencina on 11/1/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import AVFoundation

public class OrientationUtils {
    
    class public func transform(o : UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch(o) {
            
        case .landscapeLeft:
            return .landscapeLeft
            
        case .landscapeRight:
            return .landscapeRight
            
        case .portraitUpsideDown:
            return .portraitUpsideDown
            
        default:
            return .portrait;
        }
    }
    
    class public func transformToUIKit(o : AVCaptureVideoOrientation) ->  UIInterfaceOrientation{
        switch(o) {
            
        case .landscapeLeft:
            return .landscapeLeft
            
        case .landscapeRight:
            return .landscapeRight
            
        case .portraitUpsideDown:
            return .portraitUpsideDown
            
        default:
            return .portrait;
        }
    }
    
    class public func transformToUIImage(o : AVCaptureVideoOrientation) ->  UIImage.Orientation {
        switch(o) {
            
        case .landscapeLeft:
            return .left
            
        case .landscapeRight:
            return .right
            
        case .portraitUpsideDown:
            return .down
            
        default:
            return .up;
        }
    }
    
    class public func transformOrientationToImage(o : UIInterfaceOrientation) -> UIImage.Orientation {
        switch(o) {
            
        case .landscapeLeft:
            return .left
            
        case .landscapeRight:
            return .right
            
        case .portraitUpsideDown:
            return .down
            
        default:
            return .up
        }
    }
}
