//
//  ShortsViewController.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2025.
//  Copyright © 2025 Security Union. All rights reserved.
//

import UIKit
import Theater
import AVFoundation
import Photos
import SwiftUI
import Combine

/**
 * SwiftUI-based camera controller for shorts recording.
 * Hosts ShortsView and integrates with existing camera infrastructure.
 */
public class ShortsViewController: UIViewController {
    
    // MARK: - Properties
    private var shortsSession: ShortsSession?
    private var hostingController: UIHostingController<ShortsView>?
    
    // Camera infrastructure (reuse from CameraViewController)
    var captureSession: AVCaptureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "shorts video output queue", attributes: [], target: nil)
    private let photoOutput = AVCapturePhotoOutput()
    var videoDeviceInput: AVCaptureDeviceInput!
    var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    // Recording state
    var isRecording: Bool = false
    var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput!
    private let writingQueue = DispatchQueue(label: "shorts recording queue", attributes: [], target: nil)
    
    // Actor integration
    var session: ActorRef = getRemoteCamSession()!
    
    // MARK: - Lifecycle
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        // Note: ShortsViewController doesn't use BecomeCamera - it's a specialized controller
        // session ! UICmd.BecomeCamera(sender: nil, ctrl: self)
        print("📱 DEBUG: ShortsViewController loaded")
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = true
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            session ! UICmd.UnbecomeCamera(sender: nil)
        }
    }
    
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        captureVideoPreviewLayer?.frame = view.frame
    }
    
    // MARK: - SwiftUI Integration
    
    func setupShortsUI(with shortsSession: ShortsSession) {
        self.shortsSession = shortsSession
        
        // Remove existing subviews
        view.subviews.forEach { $0.removeFromSuperview() }
        
        // Create SwiftUI view
        let shortsView = ShortsView(
            session: shortsSession,
            onBackTapped: { [weak self] in
                self?.handleBackTapped()
            },
            onStartRecording: { [weak self] in
                self?.handleStartRecording()
            },
            onStopRecording: { [weak self] in
                self?.handleStopRecording()
            }
        )
        
        // Host SwiftUI view
        let hosting = UIHostingController(rootView: shortsView)
        hosting.view.backgroundColor = UIColor.clear // Let camera preview show through
        
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        
        // Setup constraints
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        self.hostingController = hosting
        
        // Ensure camera preview layer is behind SwiftUI view
        if let previewLayer = captureVideoPreviewLayer {
            view.layer.insertSublayer(previewLayer, at: 0)
        }
    }
    
    // MARK: - Camera Setup
    
    private func setupCamera() {
        guard PermissionManager.shared.cameraStatus == .authorized else {
            print("📱 ERROR: No camera permission for shorts")
            return
        }
        
        captureSession.sessionPreset = .high
        
        // Setup video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("📱 ERROR: Could not create video device input for shorts")
            return
        }
        
        if captureSession.canAddInput(videoDeviceInput) {
            captureSession.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
        }
        
        // Setup video output
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        }
        
        // Setup preview layer
        captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        captureVideoPreviewLayer?.videoGravity = .resizeAspectFill
        captureVideoPreviewLayer?.frame = view.frame
        
        // Start session
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    // MARK: - Public Interface (Called by Actor messages)
    
    public func startShortsMode(config: ShortsConfig) {
        DispatchQueue.main.async { [weak self] in
            let session = ShortsSession(config: config)
            self?.setupShortsUI(with: session)
            print("📱 DEBUG: Started shorts mode with \(config.maxDuration)s duration")
            
            // Notify actor system that ShortsViewController is ready to take over
            self?.notifyActorSystemReady()
        }
    }
    
    private func notifyActorSystemReady() {
        print("📱 DEBUG: ShortsViewController notifying actor system it's ready")
        
        // Send a message to the actor system to transition to cameraShortsMode
        session ! UICmd.ShortsControllerReady(controller: self, sender: nil)
    }
    
    public func startRecordingClip(maxDuration: TimeInterval) {
        guard let session = shortsSession, session.canAddClip else {
            print("📱 ERROR: Cannot start recording - session full or invalid")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.shortsSession?.state = .recording
            self?.beginRecording(maxDuration: maxDuration)
        }
    }
    
    public func stopRecordingClip() {
        guard isRecording else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.endRecording()
        }
    }
    
    // MARK: - Recording Implementation
    
    private func beginRecording(maxDuration: TimeInterval) {
        guard !isRecording else { return }
        
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let clipFileName = "shorts_clip_\(UUID().uuidString).mov"
        let outputURL = URL(fileURLWithPath: documentsPath).appendingPathComponent(clipFileName)
        
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6000000
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            
            if assetWriter!.canAdd(videoInput) {
                assetWriter!.add(videoInput)
            }
            
            assetWriter!.startWriting()
            assetWriter!.startSession(atSourceTime: CMTime.zero)
            
            isRecording = true
            print("📱 DEBUG: Started recording shorts clip to \(outputURL)")
            
            // Auto-stop after max duration
            DispatchQueue.main.asyncAfter(deadline: .now() + maxDuration) { [weak self] in
                if self?.isRecording == true {
                    self?.stopRecordingClip()
                }
            }
            
        } catch {
            print("📱 ERROR: Failed to start recording: \(error)")
        }
    }
    
    private func endRecording() {
        guard isRecording, let writer = assetWriter else { return }
        
        isRecording = false
        shortsSession?.state = .processing
        
        videoInput.markAsFinished()
        
        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                if writer.status == .completed {
                    self?.handleClipCompleted(outputURL: writer.outputURL)
                } else {
                    print("📱 ERROR: Recording failed with status: \(writer.status)")
                    self?.shortsSession?.state = .idle // Reset to idle on error
                    print("📱 ERROR: Recording failed with status: \(writer.status)")
                }
            }
        }
    }
    
    private func handleClipCompleted(outputURL: URL) {
        guard let session = shortsSession else { return }
        
        // Create clip model
        let clipDuration = getVideoDuration(url: outputURL)
        let fileSize = getFileSize(url: outputURL)
        let clip = ShortsClip(
            id: UUID(),
            duration: clipDuration,
            videoURL: outputURL,
            thumbnailImage: nil, // Could generate thumbnail here
            recordedAt: Date(),
            order: session.clips.count,
            fileSize: fileSize
        )
        
        // Add to session
        do {
            try session.addClip(clip)
            print("📱 DEBUG: Clip added successfully")
        } catch {
            print("📱 ERROR: Failed to add clip: \(error)")
            return
        }
        session.state = .idle
        
        // Send to remote via actor
        let clipData = UICmd.ShortsClipRecorded(
            clipURL: outputURL,
            duration: clipDuration,
            thumbnailImage: nil,
            sender: nil
        )
        self.session ! clipData
        
        print("📱 DEBUG: Completed shorts clip: \(clipDuration)s")
    }
    
    // MARK: - Button Handlers
    
    private func handleBackTapped() {
        print("📱 DEBUG: Shorts back button tapped")
        exitShortsMode()
    }
    
    public func exitShortsMode() {
        print("📱 DEBUG: ShortsViewController exiting shorts mode")
        
        // Notify actor system we're exiting
        session ! UICmd.ShortsControllerExiting(sender: nil)
        
        // Pop back to CameraViewController
        navigationController?.popViewController(animated: true)
    }
    
    private func handleStartRecording() {
        // This would be called by remote, not directly by UI
        print("📱 DEBUG: Start recording requested from UI")
    }
    
    private func handleStopRecording() {
        // This would be called by remote, not directly by UI
        print("📱 DEBUG: Stop recording requested from UI")
    }
    
    // MARK: - Utilities
    
    private func getVideoDuration(url: URL) -> TimeInterval {
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }
    
    private func getFileSize(url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            print("📱 ERROR: Failed to get file size: \(error)")
            return 0
        }
    }
    
    public override var shouldAutorotate: Bool {
        return false
    }
    
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ShortsViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard isRecording,
              let writer = assetWriter,
              writer.status == .writing,
              videoInput.isReadyForMoreMediaData else {
            return
        }
        
        videoInput.append(sampleBuffer)
    }
} 