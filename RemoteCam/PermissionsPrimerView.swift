import SwiftUI
import AVFoundation
import Photos

struct PermissionsPrimerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    @State private var microphonePermissionStatus: AVAuthorizationStatus = .notDetermined
    @State private var photoLibraryPermissionStatus: PHAuthorizationStatus = .notDetermined
    @State private var isProcessingPermissions = false
    
    let onPermissionsCompleted: (Bool, Bool, Bool) -> Void // (cameraGranted, microphoneGranted, photoLibraryGranted)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Let's set up Remote Shutter")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("We need a few permissions to give you the best experience")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Permissions List
                VStack(spacing: 20) {
                    // Camera Permission (Required)
                    PermissionRow(
                        icon: "camera.fill",
                        title: "Camera Access",
                        subtitle: "Required - Take photos and control your camera remotely",
                        isRequired: true,
                        status: cameraPermissionStatus == .authorized
                    )
                    
                    // Photo Library Permission (Required)
                    PermissionRow(
                        icon: "photo.on.rectangle",
                        title: "Photo Library Access",
                        subtitle: "Required - Save your photos and videos to your device",
                        isRequired: true,
                        status: photoLibraryPermissionStatus == .authorized
                    )
                    
                    // Microphone Permission (Optional)
                    PermissionRow(
                        icon: "mic.fill",
                        title: "Microphone Access",
                        subtitle: "Optional - Record video with audio",
                        isRequired: false,
                        status: microphonePermissionStatus == .authorized
                    )
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: requestPermissions) {
                        HStack {
                            if isProcessingPermissions {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isProcessingPermissions ? "Setting up..." : "Continue")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isProcessingPermissions)
                    
                    Button(action: skipOptionalPermissions) {
                        Text("Skip Microphone (Silent Videos)")
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                    .disabled(isProcessingPermissions)
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
            .navigationBarHidden(true)
        }
        .onAppear {
            updatePermissionStatuses()
        }
    }
    
    private func requestPermissions() {
        isProcessingPermissions = true
        
        // Request camera permission first
        AVCaptureDevice.requestAccess(for: .video) { [self] cameraGranted in
            DispatchQueue.main.async {
                self.cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
                
                if cameraGranted {
                    // Request photo library permission (write-only)
                    requestPhotoLibraryPermission { photoLibraryGranted in
                        if photoLibraryGranted {
                            // Request microphone permission
                            AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                                DispatchQueue.main.async {
                                    self.microphonePermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                                    self.isProcessingPermissions = false
                                    self.onPermissionsCompleted(cameraGranted, micGranted, photoLibraryGranted)
                                    self.dismiss()
                                }
                            }
                        } else {
                            self.isProcessingPermissions = false
                            self.showPhotoLibraryPermissionDeniedAlert()
                        }
                    }
                } else {
                    self.isProcessingPermissions = false
                    self.showCameraPermissionDeniedAlert()
                }
            }
        }
    }
    
    private func skipOptionalPermissions() {
        isProcessingPermissions = true
        
        // Request camera permission first
        AVCaptureDevice.requestAccess(for: .video) { [self] cameraGranted in
            DispatchQueue.main.async {
                self.cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
                
                if cameraGranted {
                    // Request photo library permission (still required)
                    requestPhotoLibraryPermission { photoLibraryGranted in
                        self.isProcessingPermissions = false
                        
                        if photoLibraryGranted {
                            self.onPermissionsCompleted(true, false, photoLibraryGranted)
                            self.dismiss()
                        } else {
                            self.showPhotoLibraryPermissionDeniedAlert()
                        }
                    }
                } else {
                    self.isProcessingPermissions = false
                    self.showCameraPermissionDeniedAlert()
                }
            }
        }
    }
    
    private func requestPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14, *) {
            // iOS 14+ supports write-only access
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async {
                    self.photoLibraryPermissionStatus = status
                    completion(status == .authorized)
                }
            }
        } else {
            // iOS 13 and earlier - request full access
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.photoLibraryPermissionStatus = status
                    completion(status == .authorized)
                }
            }
        }
    }
    
    private func updatePermissionStatuses() {
        cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphonePermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        if #available(iOS 14, *) {
            photoLibraryPermissionStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        } else {
            photoLibraryPermissionStatus = PHPhotoLibrary.authorizationStatus()
        }
    }
    
    private func showCameraPermissionDeniedAlert() {
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
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            self.dismiss()
        })
        
        presentAlert(alert)
    }
    
    private func showPhotoLibraryPermissionDeniedAlert() {
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
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            self.dismiss()
        })
        
        presentAlert(alert)
    }
    
    private func presentAlert(_ alert: UIAlertController) {
        // Present from the root view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isRequired: Bool
    let status: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .frame(width: 30)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if isRequired {
                        Text("Required")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    } else {
                        Text("Optional")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicator
            if status {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 8)
    }
}

struct PermissionsPrimerView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionsPrimerView { cameraGranted, micGranted, photoLibraryGranted in
            print("Camera: \(cameraGranted), Microphone: \(micGranted), Photo Library: \(photoLibraryGranted)")
        }
    }
} 