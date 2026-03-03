import UIKit
import SwiftUI

extension UIViewController {
    
    func showPhotosAccessDeniedModal(for contentType: PhotosAccessDeniedView.ContentType) {
        // Get the top-most view controller first
        guard let topController = getTopMostViewController() else {
            Log.warning("Could not find top view controller to show photos access modal")
            return
        }
        
        let photosAccessView = PhotosAccessDeniedView(
            contentType: contentType,
            onOpenSettings: {
                dismissPhotosAccessModalGlobally()
                PermissionManager.shared.openAppSettings()
            },
            onDismiss: {
                Log.debug("onDismiss callback called!")
                dismissPhotosAccessModalGlobally()
            }
        )
        
        let hostingController = UIHostingController(rootView: photosAccessView)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        
        // Prevent auto-dismissal
        hostingController.isModalInPresentation = true
        
        // Store reference BEFORE presenting to prevent race conditions
        objc_setAssociatedObject(
            topController,
            &PhotosAccessAssociatedKeys.photosAccessController,
            hostingController,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        
        topController.present(hostingController, animated: true) {
            Log.debug("Photos access modal presentation completed")
            _isPhotosAccessModalShowing = true
        }
    }
    
    private func dismissPhotosAccessModal() {
        if let topController = getTopMostViewController() {
            if let modalController = objc_getAssociatedObject(
                topController,
                &PhotosAccessAssociatedKeys.photosAccessController
            ) as? UIViewController {
                modalController.dismiss(animated: true)
                objc_setAssociatedObject(
                    topController,
                    &PhotosAccessAssociatedKeys.photosAccessController,
                    nil,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }
    
    private func getTopMostViewController() -> UIViewController? {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        
        var topController = window.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        
        return topController
    }
}

private struct PhotosAccessAssociatedKeys {
    static var photosAccessController = "photosAccessController"
}

// Global flag to track modal state
private var _isPhotosAccessModalShowing = false

// MARK: - Global Functions for Easy Access

func showPhotosAccessDeniedModal(for contentType: PhotosAccessDeniedView.ContentType) {
    // Ensure we're on the main queue and add a slight delay to avoid conflicts
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        // Check if there's already a photos access modal showing
        if isPhotosAccessModalCurrentlyShowing() {
            Log.debug("Photos access modal already showing, skipping duplicate")
            return
        }
        
        // Get the top-most view controller and show the modal
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = window.rootViewController else {
            Log.warning("Could not find root view controller to show photos access modal")
            return
        }
        
        var topController = rootViewController
        while let presentedController = topController.presentedViewController {
            topController = presentedController
        }
        
        Log.debug("Showing photos access modal for \(contentType)")
        topController.showPhotosAccessDeniedModal(for: contentType)
    }
}

func dismissPhotosAccessModalGlobally() {
    Log.debug("dismissPhotosAccessModalGlobally() called")
    DispatchQueue.main.async {
        Log.debug("On main queue - attempting to dismiss photos access modal")
        Log.debug("Global flag _isPhotosAccessModalShowing: \(_isPhotosAccessModalShowing)")
        
        // Find the top-most view controller and dismiss the modal
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = window.rootViewController else {
            Log.warning("Could not find root view controller to dismiss photos access modal")
            return
        }
        
        var topController = rootViewController
        var controllerDepth = 0
        var presentingController = rootViewController
        
        while let presentedController = topController.presentedViewController {
            presentingController = topController  // Keep track of the one that presented
            topController = presentedController
            controllerDepth += 1
        }
        Log.debug("Found top controller at depth: \(controllerDepth)")
        Log.debug("Top controller type: \(type(of: topController))")
        Log.debug("Presenting controller type: \(type(of: presentingController))")
        
        // Check if there's a presented modal to dismiss
        // Look for the associated object on the PRESENTING controller, not the presented one
        let associatedModal = objc_getAssociatedObject(
            presentingController,
            &PhotosAccessAssociatedKeys.photosAccessController
        )
        
        Log.debug("Looking for associated object on presenting controller...")
        
        if let modalController = associatedModal as? UIViewController {
            Log.debug("Found stored photos access modal: \(type(of: modalController))")
            Log.debug("Modal controller matches top controller: \(modalController === topController)")
            Log.debug("Dismissing stored photos access modal")
            modalController.dismiss(animated: true) {
                _isPhotosAccessModalShowing = false
                Log.debug("Photos access modal dismissed completely")
            }
            objc_setAssociatedObject(
                presentingController,
                &PhotosAccessAssociatedKeys.photosAccessController,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        } else {
            Log.error("No associated modal found on presenting controller")
            Log.debug("Associated object: \(String(describing: associatedModal))")
            // If no associated object, try to dismiss any presented view controller directly
            if controllerDepth > 0 {
                Log.debug("Trying to dismiss the top controller directly: \(type(of: topController))")
                // Since we know there's a presented controller, dismiss it
                presentingController.dismiss(animated: true) {
                    _isPhotosAccessModalShowing = false
                    Log.debug("Top controller dismissed directly")
                }
            } else {
                Log.debug("No modal found to dismiss - no presentation depth")
                _isPhotosAccessModalShowing = false
            }
        }
    }
}

func isPhotosAccessModalCurrentlyShowing() -> Bool {
    // Use global flag first
    if _isPhotosAccessModalShowing {
        return true
    }
    
    guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
          let rootViewController = window.rootViewController else {
        return false
    }
    
    var topController = rootViewController
    var presentingController = rootViewController
    
    while let presentedController = topController.presentedViewController {
        presentingController = topController
        topController = presentedController
    }
    
    // Check if there's a stored modal reference on the presenting controller
    if objc_getAssociatedObject(
        presentingController,
        &PhotosAccessAssociatedKeys.photosAccessController
    ) != nil {
        return true
    }
    
    return false
} 