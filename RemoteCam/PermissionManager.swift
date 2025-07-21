import Foundation
import AVFoundation
import Photos
import UIKit

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var cameraStatus: AVAuthorizationStatus = .notDetermined
    @Published var photosStatus: PHAuthorizationStatus = .notDetermined
    @Published var microphoneStatus: AVAuthorizationStatus = .notDetermined
    
    private init() {
        updatePermissionStatuses()
    }
    
    // MARK: - Permission Status Checking
    
    func updatePermissionStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        photosStatus = PHPhotoLibrary.authorizationStatus()
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    var areCameraAndPhotosGranted: Bool {
        return cameraStatus == .authorized && (photosStatus == .authorized || photosStatus == .limited)
    }
    
    var areCameraAndPhotosDenied: Bool {
        return cameraStatus == .denied || photosStatus == .denied
    }
    
    var needsCameraAndPhotosPermission: Bool {
        return cameraStatus == .notDetermined || photosStatus == .notDetermined || areCameraAndPhotosDenied
    }
    
    var isMicrophoneGranted: Bool {
        return microphoneStatus == .authorized
    }
    
    var isMicrophoneDenied: Bool {
        return microphoneStatus == .denied
    }
    
    // MARK: - Permission Requesting
    
    func requestCameraAndPhotosPermissions(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var cameraGranted = false
        var photosGranted = false
        
        // Request camera permission
        group.enter()
        if cameraStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                cameraGranted = granted
                DispatchQueue.main.async {
                    self.cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                }
                group.leave()
            }
        } else {
            cameraGranted = (cameraStatus == .authorized)
            group.leave()
        }
        
        // Request photos permission
        group.enter()
        if photosStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization { status in
                photosGranted = (status == .authorized || status == .limited)
                DispatchQueue.main.async {
                    self.photosStatus = PHPhotoLibrary.authorizationStatus()
                }
                group.leave()
            }
        } else {
            photosGranted = (photosStatus == .authorized || photosStatus == .limited)
            group.leave()
        }
        
        group.notify(queue: .main) {
            let bothGranted = cameraGranted && photosGranted
            completion(bothGranted)
        }
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        if microphoneStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                    completion(granted)
                }
            }
        } else {
            completion(microphoneStatus == .authorized)
        }
    }
    
    // MARK: - Settings Navigation
    
    func openAppSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    // MARK: - Helper Methods
    
    func getCameraPermissionDescription() -> String {
        switch cameraStatus {
        case .notDetermined:
            return NSLocalizedString("camera_permission_not_determined", comment: "")
        case .denied:
            return NSLocalizedString("camera_permission_denied", comment: "")
        case .restricted:
            return NSLocalizedString("camera_permission_restricted", comment: "")
        case .authorized:
            return NSLocalizedString("camera_permission_authorized", comment: "")
        @unknown default:
            return NSLocalizedString("camera_permission_unknown", comment: "")
        }
    }
    
    func getPhotosPermissionDescription() -> String {
        switch photosStatus {
        case .notDetermined:
            return NSLocalizedString("photos_permission_not_determined", comment: "")
        case .denied:
            return NSLocalizedString("photos_permission_denied", comment: "")
        case .restricted:
            return NSLocalizedString("photos_permission_restricted", comment: "")
        case .authorized:
            return NSLocalizedString("photos_permission_authorized", comment: "")
        case .limited:
            return NSLocalizedString("photos_permission_limited", comment: "")
        @unknown default:
            return NSLocalizedString("photos_permission_unknown", comment: "")
        }
    }
} 