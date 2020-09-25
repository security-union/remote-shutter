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
import Theater

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
        showErrorNibWithName("BFDeniedAccessToCameraView")
    }

    public func addErrorView(view: UIView) {
        if let delegate = UIApplication.shared.delegate,
           let window = delegate.window {
            window!.addSubview(view)
            view.frame = (window?.bounds)!
        }
    }

    public func showNoCameraRollAccess() {
        showErrorNibWithName("BFDeniedAccessToAssetsView")
    }
    
    private func showErrorNibWithName(_ fileName: String) {
        DispatchQueue.main.async {
            let errorViewController = ErrorViewController(nibName: fileName, bundle: Bundle.main)
            self.setErrorViewController(errorViewController)
            self.addErrorView(view: errorViewController.view)
        }
    }

}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVMediaType(_ input: AVMediaType) -> String {
    return input.rawValue
}
