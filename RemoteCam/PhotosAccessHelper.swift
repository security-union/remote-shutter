import UIKit
import SwiftUI

extension UIViewController {
    
    func showPhotosAccessDeniedModal(for contentType: PhotosAccessDeniedView.ContentType) {
        let photosAccessView = PhotosAccessDeniedView(
            contentType: contentType,
            onOpenSettings: { [weak self] in
                self?.dismissPhotosAccessModal()
                PermissionManager.shared.openAppSettings()
            },
            onDismiss: { [weak self] in
                self?.dismissPhotosAccessModal()
            }
        )
        
        let hostingController = UIHostingController(rootView: photosAccessView)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        
        // Present from the top-most view controller
        if let topController = getTopMostViewController() {
            topController.present(hostingController, animated: true)
            
            // Store reference to dismiss later
            objc_setAssociatedObject(
                topController,
                &PhotosAccessAssociatedKeys.photosAccessController,
                hostingController,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
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

// MARK: - Global Function for Easy Access

func showPhotosAccessDeniedModal(for contentType: PhotosAccessDeniedView.ContentType) {
    // Get the top-most view controller and show the modal
    guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
          let rootViewController = window.rootViewController else {
        print("⚠️ Could not find root view controller to show photos access modal")
        return
    }
    
    var topController = rootViewController
    while let presentedController = topController.presentedViewController {
        topController = presentedController
    }
    
    topController.showPhotosAccessDeniedModal(for: contentType)
} 