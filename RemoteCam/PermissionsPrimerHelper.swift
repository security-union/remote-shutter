import UIKit
import SwiftUI
import AVFoundation
import Photos

class PermissionsPrimerHelper {
    
    /// Presents the permissions primer modal from a UIKit view controller
    /// - Parameters:
    ///   - presentingViewController: The UIKit view controller that will present the modal
    ///   - completion: Callback with camera, microphone, and photo library permission results
    static func presentPermissionsPrimer(
        from presentingViewController: UIViewController,
        completion: @escaping (Bool, Bool, Bool) -> Void
    ) {
        let permissionsPrimerView = PermissionsPrimerView { cameraGranted, microphoneGranted, photoLibraryGranted in
            completion(cameraGranted, microphoneGranted, photoLibraryGranted)
        }
        
        let hostingController = UIHostingController(rootView: permissionsPrimerView)
        hostingController.modalPresentationStyle = .fullScreen
        hostingController.modalTransitionStyle = .crossDissolve
        
        presentingViewController.present(hostingController, animated: true)
    }
    
    /// Checks if permissions primer should be shown (when permissions are not determined)
    /// - Returns: true if the modal should be shown, false otherwise
    static func shouldShowPermissionsPrimer() -> Bool {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let photoLibraryStatus = getPhotoLibraryAuthorizationStatus()
        
        // Show primer if any permission is not determined
        return cameraStatus == .notDetermined || microphoneStatus == .notDetermined || photoLibraryStatus == .notDetermined
    }
    
    /// Checks if camera permission is granted
    /// - Returns: true if camera permission is granted
    static func hasCameraPermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    /// Checks if microphone permission is granted
    /// - Returns: true if microphone permission is granted
    static func hasMicrophonePermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    /// Checks if photo library permission is granted
    /// - Returns: true if photo library permission is granted
    static func hasPhotoLibraryPermission() -> Bool {
        return getPhotoLibraryAuthorizationStatus() == .authorized
    }
    
    /// Gets the appropriate photo library authorization status based on iOS version
    /// - Returns: The current photo library authorization status
    private static func getPhotoLibraryAuthorizationStatus() -> PHAuthorizationStatus {
        if #available(iOS 14, *) {
            return PHPhotoLibrary.authorizationStatus(for: .addOnly)
        } else {
            return PHPhotoLibrary.authorizationStatus()
        }
    }
    
    /// Shows an alert when camera permission is denied and app can't function
    /// - Parameter presentingViewController: The view controller to present the alert from
    static func showCameraPermissionDeniedAlert(from presentingViewController: UIViewController) {
        let alert = UIAlertController(
            title: NSLocalizedString("Camera Access Required", comment: ""),
            message: NSLocalizedString("Remote Shutter needs camera access to function. Please enable it in Settings to continue.", comment: ""),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Open Settings", comment: ""), style: .default) { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        
        presentingViewController.present(alert, animated: true)
    }
    
    /// Shows an alert when photo library permission is denied and app can't save photos
    /// - Parameter presentingViewController: The view controller to present the alert from
    static func showPhotoLibraryPermissionDeniedAlert(from presentingViewController: UIViewController) {
        let alert = UIAlertController(
            title: NSLocalizedString("Photo Library Access Required", comment: ""),
            message: NSLocalizedString("Remote Shutter needs photo library access to save your photos and videos. Please enable it in Settings to continue.", comment: ""),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Open Settings", comment: ""), style: .default) { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        
        presentingViewController.present(alert, animated: true)
    }
    
    /// Shows an alert explaining that video recording without microphone will be silent
    /// - Parameter presentingViewController: The view controller to present the alert from
    static func showMicrophonePermissionExplanationAlert(from presentingViewController: UIViewController) {
        let alert = UIAlertController(
            title: NSLocalizedString("Silent Video Recording", comment: ""),
            message: NSLocalizedString("Video will be recorded without audio because microphone access was not granted. You can enable it in Settings to record with audio.", comment: ""),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Open Settings", comment: ""), style: .default) { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .cancel))
        
        presentingViewController.present(alert, animated: true)
    }
}

// MARK: - UIViewController Extension for easier access
extension UIViewController {
    
    /// Presents the permissions primer modal
    /// - Parameter completion: Callback with camera, microphone, and photo library permission results
    func presentPermissionsPrimer(completion: @escaping (Bool, Bool, Bool) -> Void) {
        PermissionsPrimerHelper.presentPermissionsPrimer(from: self, completion: completion)
    }
    
    /// Checks if permissions primer should be shown
    /// - Returns: true if the modal should be shown
    func shouldShowPermissionsPrimer() -> Bool {
        return PermissionsPrimerHelper.shouldShowPermissionsPrimer()
    }
} 