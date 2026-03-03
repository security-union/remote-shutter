//
//  CameraAccess.swift
//  Actors
//
//  Created by Dario Lencina on 11/2/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import Photos
import AVFoundation

/**
Permissions verification extensions
*/

extension UIViewController {

    private struct AssociatedKeys {
        static var errorViewController = "errorViewController"
    }

    private func setErrorViewController(_ ctrl: UIViewController?) {
        objc_setAssociatedObject(self, &AssociatedKeys.errorViewController,
                ctrl,
                objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func getErrorViewController() -> UIViewController? {
        return objc_getAssociatedObject(self, &AssociatedKeys.errorViewController) as? UIViewController
    }

    @objc public func verifyCameraAndCameraRollAccess() {
        verifyCameraRollAccess()
        verifyCameraAccess()
        verifyNetworkAccess()
        // Microphone access is now requested only when recording video
    }

    public func verifyCameraAccess() {
        if AVCaptureDevice.authorizationStatus(for: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.video))) != AVAuthorizationStatus.authorized {
            AVCaptureDevice.requestAccess(for: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.video)), completionHandler: { (granted: Bool) -> Void in
                if !granted {
                    self.showNoAccessToCamera()
                }
            })
        }
    }

    public func verifyMicrophoneAccess() {
        if AVCaptureDevice.authorizationStatus(for: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.audio))) != AVAuthorizationStatus.authorized {
            AVCaptureDevice.requestAccess(for: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.audio)), completionHandler: { (granted: Bool) -> Void in
                if !granted {
                    self.showNoAccessToCamera()
                }
            })
        }
    }

    public func verifyCameraRollAccess() {
        if PHPhotoLibrary.authorizationStatus() != .authorized {
            PHPhotoLibrary.requestAuthorization {
                if $0 != .authorized {
                    ^{
                        self.showNoCameraRollAccess()
                    }
                }
            }
        }
    }

    public func verifyNetworkAccess() {
        // TODO: Implement after apple explains us how.
    }

    public func showNoAccessToCamera() {
        // Legacy method - now handled by new permission system in RolePickerController
        // This method is kept for compatibility but should not be used
        Log.warning("showNoAccessToCamera called - this should be handled by the new permission system")
    }

    public func addErrorView(view: UIView) {
        if let delegate = UIApplication.shared.delegate,
           let window = delegate.window {
            window!.addSubview(view)
            view.frame = (window?.bounds)!
        }
    }

    public func showNoCameraRollAccess() {
        // Legacy method - now handled by new permission system in RolePickerController
        // This method is kept for compatibility but should not be used
        Log.warning("showNoCameraRollAccess called - this should be handled by the new permission system")
    }

    private func showErrorNibWithName(_ fileName: String) {
        // Legacy method - now handled by new permission system
        Log.warning("showErrorNibWithName called with: \(fileName) - this should be handled by the new permission system")
    }

}

// Helper function inserted by Swift 4.2 migrator.
private func convertFromAVMediaType(_ input: AVMediaType) -> String {
    return input.rawValue
}
