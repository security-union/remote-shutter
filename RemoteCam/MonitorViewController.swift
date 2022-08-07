//
//  RemoteViewController.swift
//  Actors
//
//  Created by Dario on 10/7/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import Theater
import AVFoundation

let timerDefault = "timerDefault"

func setFlashMode(ctrl: Weak<MonitorViewController>, flashMode: AVCaptureDevice.FlashMode?) {
    if let f = flashMode {
        switch f {
        case .off:
            ctrl.value?.flashStatus.text = "Off"
        case .on:
            ctrl.value?.flashStatus.text = "On"
        case .auto:
            ctrl.value?.flashStatus.text = "Auto"
        default:
            ctrl.value?.flashStatus.text = "None"
        }
    } else {
        ctrl.value?.flashStatus.text = "None"
    }
}

/**
Monitor actor has a reference to the session actor and to the monitorViewController, it acts as the connection between the model and the controller from an MVC perspective.
*/

public class MonitorActor: ViewCtrlActor<MonitorViewController> {

    public required init(context: ActorSystem, ref: ActorRef) {
        super.init(context: context, ref: ref)
        mailbox = OperationQueue()
        let session: ActorRef? = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")
        session! ! UICmd.BecomeMonitor(ref, mode: .Photo)
    }

    override public func receiveWithCtrl(ctrl: Weak<MonitorViewController>) -> Receive {

        return { [unowned self](msg: Message) in
            switch msg {
                
            case is UICmd.RenderPhotoMode:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.configurePhotoMode()
                }

            case is UICmd.RenderVideoMode:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.configureVideoMode()
                }

            case is UICmd.RenderVideoModeRecording:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.configureVideoModeRecording()
                }

            case is UICmd.BecomeMonitorFailed:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.navigationController?.popViewController(animated: true)
                }

            case let cam as UICmd.ToggleCameraResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl {
                        setFlashMode(ctrl: ctrl, flashMode: cam.flashMode)
                    }
                }

            case let flash as RemoteCmd.ToggleFlashResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl {
                        setFlashMode(ctrl: ctrl, flashMode: flash.flashMode)
                    }
                }

            case let f as RemoteCmd.OnFrame:
                if let cgImage = UIImage(data: f.data) {
                    OperationQueue.main.addOperation {[weak ctrl] in
                        if let ctrl = ctrl {
                            ctrl.value?.imageView.image = cgImage
                        }
                    }
                }
            default:
                self.receive(msg: msg)
            }
        }
    }
}

/**
UI for the monitor.
*/

public class MonitorViewController: iAdViewController, UIImagePickerControllerDelegate & UINavigationControllerDelegate {

    let session = getRemoteCamSession()!

    let monitor = RemoteCamSystem.shared.actorOf(clz: MonitorActor.self, name: "MonitorActor")!

    let timer: RCTimer = RCTimer()

    let soundManager: CPSoundManager = CPSoundManager()

    private let sliderColor1 = UIColor(red: 0.150, green: 0.670, blue: 0.80, alpha: 1)
    private let sliderColor2 = UIColor(red: 0.060, green: 0.100, blue: 0.160, alpha: 1)

    @IBOutlet weak var flashStatus: UILabel!

    @IBOutlet weak var imageView: UIImageView!

    @IBOutlet weak var takePicture: UIButton!

    @IBOutlet weak var sliderContainer: UIView!

    @IBOutlet weak var timerSlider: UISlider!

    @IBOutlet weak var timerLabel: UILabel!

    @IBOutlet weak var galleryButton: UIButton!

    @IBOutlet weak var backButton: UIButton!

    @IBOutlet weak var flashButton: UIButton!

    @IBOutlet weak var settingsButton: UIButton!
    
    @IBOutlet weak var endVideoButton: UIButton!
    
    @IBOutlet weak var cancelVideoButton: UIButton!

    @IBOutlet weak var toggleCamera: UIButton!

    @IBOutlet weak var segmentedControl: UISegmentedControl!

    @IBOutlet weak var recordingView: UIImageView!

    var buttonPrompt: String = ""

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        monitor ! SetViewCtrl(ctrl: self)
        self.configureTimerUI()
        self.segmentedControl.addTarget(self,
                                        action: #selector(self.onSegmentedControlChanged(event:)),
                                        for: .valueChanged)
        self.takePicture.imageView?.contentMode = .scaleAspectFit
        self.flashButton.imageView?.contentMode = .scaleAspectFit
        self.imageView.contentMode = .scaleAspectFit
        recordingView.image = UIImage.gifImageWithName("recording")
        configurePhotoMode()
    }

    deinit {
        print("stop monitor")
        self.timer.cancel()
        self.soundManager.stopPlayer()
        session ! UICmd.UnbecomeMonitor(sender: nil)
        monitor ! Actor.Harakiri(sender: nil)
    }

    let buttonPromptPhotoMode = NSLocalizedString("Taking picture", comment: "")
    let buttonPromptVideoMode = NSLocalizedString("Starting video", comment: "")
    let buttonPromptRecordingMode = NSLocalizedString("Stopping video", comment: "")
    var timerSliderValue: Int {
        set {
            UserDefaults.standard.set(newValue, forKey: timerDefault)
            UserDefaults.standard.synchronize()
        }
        
        get {
            UserDefaults.standard.integer(forKey: timerDefault)
        }
    }

    func configurePhotoMode() {
        takePicture.setImage(UIImage.init(named: "camera.png"), for: .normal)
        galleryButton.isEnabled = true
        backButton.isEnabled = true
        flashButton.isEnabled = true
        flashButton.isHidden = false
        flashStatus.isHidden = false
        timerSlider.isEnabled = true
        settingsButton.isEnabled = true
        segmentedControl.isEnabled = true
        recordingView.isHidden = true
        toggleCamera.isEnabled = true
        toggleCamera.isHidden = false
        buttonPrompt = buttonPromptPhotoMode
        endVideoButton.isHidden = true
        cancelVideoButton.isHidden = true
    }

    func configureVideoMode() {
        takePicture.setImage(UIImage.init(named: "record-button.png"), for: .normal)
        galleryButton.isEnabled = true
        backButton.isEnabled = true
        flashButton.isEnabled = false
        flashButton.isHidden = true
        flashStatus.isHidden = true
        timerSlider.isEnabled = true
        settingsButton.isEnabled = true
        segmentedControl.isEnabled = true
        recordingView.isHidden = true
        toggleCamera.isEnabled = true
        toggleCamera.isHidden = false
        buttonPrompt = buttonPromptVideoMode
        endVideoButton.isHidden = true
        cancelVideoButton.isHidden = true
    }

    func configureVideoModeRecording() {
        takePicture.setImage(UIImage.init(named: "stop-button.png"), for: .normal)
        galleryButton.isEnabled = false
        backButton.isEnabled = false
        flashButton.isEnabled = false
        flashButton.isHidden = true
        flashStatus.isHidden = true
        timerSlider.isEnabled = false
        settingsButton.isEnabled = false
        segmentedControl.isEnabled = false
        recordingView.isHidden = false
        toggleCamera.isEnabled = false
        toggleCamera.isHidden = true
        buttonPrompt = buttonPromptRecordingMode
    }

    @IBAction func toggleCamera(sender: UIButton) {
        session ! UICmd.ToggleCamera()
    }

    @IBAction func onSliderChange(sender: UISlider) {
        timerSliderValue = Int(round(sender.value))
        self.timerLabel.text = "\(timerSliderValue)"
    }

    @IBAction func toggleFlash(sender: UIButton) {
        session ! UICmd.ToggleFlash()
    }

    @IBAction func showSettings(sender: UIButton) {
        let ctrl = CMConfigurationsViewController()
        self.navigationController?.pushViewController(ctrl, animated: true)
    }

    @IBAction func showGallery(sender: UIButton) {
        let pickerController = UIImagePickerController()
        pickerController.delegate = self
        pickerController.allowsEditing = true
        pickerController.videoMaximumDuration = 60 * 60
        pickerController.mediaTypes = ["public.image", "public.movie"]
        pickerController.sourceType = .savedPhotosAlbum
        #if targetEnvironment(macCatalyst)
        pickerController.modalPresentationStyle = UIModalPresentationStyle.pageSheet
        #else
        pickerController.modalPresentationStyle = UIModalPresentationStyle.popover
        pickerController.popoverPresentationController?.sourceView = sender
        #endif
        self.present(pickerController, animated: true)
    }

    @IBAction func goBack(sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }

    /**
     Take picture contains the logic to kick off the Timer for the picture.
    */

    @IBAction func onTrigger(sender: UIBarButtonItem) {
        let sendMediaToRemote = CMConfigurationsViewController.sendMediaToRemote();
        if buttonPrompt == buttonPromptRecordingMode {
            self.session ! UICmd.AddVideoClip(sender: nil, sendMediaToRemote: sendMediaToRemote)
            return
        }

        func timerAlertTitle(seconds: Int) -> String {
            "\(buttonPrompt) in \(seconds) seconds"
        }

        let alert = UIAlertController(title: timerAlertTitle(seconds: timerSliderValue),
                message: nil,
                preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self](_) in
            alert.dismiss(animated: true, completion: nil)
            self?.timer.cancel()
        })

        self.soundManager.playBeepSound(CPSoundManagerAudioTypeSlow)

        self.present(alert, animated: true) { [weak self] in
            self?.timer.start(withDuration: Int(round(self?.timerSlider.value ?? 0)), withTickHandler: { [weak self](t) in
                alert.title = timerAlertTitle(seconds: t!.timeRemaining())
                switch t!.timeRemaining() {
                case let l where l > 3:
                    self?.soundManager.playBeepSound(CPSoundManagerAudioTypeSlow)
                case 3:
                    self?.soundManager.playBeepSound(CPSoundManagerAudioTypeFast)
                default:
                    break
                }
            },
            andCompletionHandler: { [weak self] (_) in
                alert.dismiss(animated: true, completion: nil)
                self?.session.tell(msg:UICmd.TakePicture(sender: nil, sendMediaToRemote: sendMediaToRemote))
            })
        }
    }

    @IBAction func endVideo(sender: UIBarButtonItem) {
        let sendMediaToRemote = CMConfigurationsViewController.sendMediaToRemote();
        if buttonPrompt == buttonPromptRecordingMode {
            self.session ! UICmd.EndVideoClip(sender: nil, sendMediaToRemote: sendMediaToRemote)
            return
        }
    }
    
    @IBAction func deleteVideo(sender: UIBarButtonItem) {
        let alert = UIAlertController(title: NSLocalizedString("Discard the last clip?", comment: ""),
                message: nil,
                preferredStyle: .alert)

        alert.addAction(UIAlertAction(title:  NSLocalizedString("Keep", comment: ""), style: .cancel) { (_) in
            alert.dismiss(animated: true, completion: nil)
            
        })
        
        alert.addAction(UIAlertAction(title:  NSLocalizedString("Discard", comment: ""), style: .cancel) { [weak self](_) in
            // TODO: send discard clip command to camera
            alert.dismiss(animated: true, completion: nil)
            if let s = self {
                s.session ! UICmd.DeleteLastVideoClip(sender: nil)
            }
        })

        self.present(alert, animated: true) { [weak self] in
            
        }
    }
    
    
    private func configureTimerUI() {
        self.timerSlider.value = Float(timerSliderValue)
        self.timerLabel.text = "\(timerSliderValue)"
        self.sliderContainer.layer.cornerRadius = 30.0
        self.sliderContainer.clipsToBounds = true
        self.timerSlider.layer.anchorPoint = CGPoint.init(x: 1.0, y: 1.0)
        self.timerSlider.transform = CGAffineTransform(rotationAngle: CGFloat(-Double.pi / 2))
        self.timerSlider.minimumTrackTintColor = sliderColor1
        self.timerSlider.maximumTrackTintColor = sliderColor2
        self.timerSlider.thumbTintColor = sliderColor1
    }

    @objc func onSegmentedControlChanged(event: UIEvent) {
        if InAppPurchasesManager.shared().didUserBuyRemoveiAdsFeatureAndEnableVideo() {
            var mode = RecordingMode.Photo
            switch segmentedControl.selectedSegmentIndex {
            case 0:
                mode = RecordingMode.Photo
            default:
                mode = RecordingMode.Video
            }
            session ! UICmd.BecomeMonitor(nil, mode: mode)
        } else {
            showSettings(sender: settingsButton)
            segmentedControl.selectedSegmentIndex = 0
        }
    }

    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let image = info[.originalImage] {
            let activityViewController = UIActivityViewController(activityItems: [image], applicationActivities: [])
            picker.dismiss(animated: true) {
                #if targetEnvironment(macCatalyst)
                activityViewController.modalPresentationStyle = UIModalPresentationStyle.pageSheet
                #else
                activityViewController.modalPresentationStyle = UIModalPresentationStyle.popover
                activityViewController.popoverPresentationController?.sourceView = self.galleryButton
                #endif
                self.present(activityViewController, animated: true)
            }
        }
    }
}
