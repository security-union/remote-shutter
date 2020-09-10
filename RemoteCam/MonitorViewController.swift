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
import BFGallery

/**
Monitor actor has a reference to the session actor and to the monitorViewController, it acts as the connection between the model and the controller from an MVC perspective.
*/

public class MonitorActor : ViewCtrlActor<MonitorViewController> {
    
    public required init(context: ActorSystem, ref: ActorRef) {
        super.init(context: context, ref: ref)
        let session : Optional<ActorRef> = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")
        session! ! UICmd.BecomeMonitor(sender: ref)
    }
    
    override public func receiveWithCtrl(ctrl: MonitorViewController) -> Receive {
        return {[unowned self](msg : Message) in
            switch(msg) {
                
            case is UICmd.BecomeMonitorFailed:
                ^{ctrl.navigationController?.popViewController(animated: true)}
                
            case let cam as UICmd.ToggleCameraResp:
                self.setFlashMode(ctrl: ctrl, flashMode:  cam.flashMode)
                
            case let flash as RemoteCmd.ToggleFlashResp:
                self.setFlashMode(ctrl: ctrl, flashMode:  flash.flashMode)
                
            case is UICmd.UnbecomeMonitor:
                let session : Optional<ActorRef> = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")
                session! ! msg
                
            case let f as RemoteCmd.OnFrame:
                if let img = UIImage(data: f.data) {
                    var t : CGAffineTransform?
                    switch(img.imageOrientation) {
                    case .left, .right:
                        let multiplier = (f.camPosition == .back) ? Double(-1) : Double(1)
                        t = CGAffineTransform(rotationAngle: CGFloat(multiplier * Double.pi))
                    case .up:
                            t = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
                        default:
                            print("none")
                    }
                    if let transform = t {
                        ^{ctrl.imageView.transform = transform}
                    }
                    ^{ctrl.imageView.image = img}
                }
                
            default:
                self.receive(msg: msg)
            }
        }
    }
    
    func setFlashMode(ctrl : MonitorViewController, flashMode : AVCaptureDevice.FlashMode?) {
        if let f = flashMode {
            switch(f) {
            case .off:
                ^{ctrl.flashStatus.text = "Off"}
            case .on:
                ^{ctrl.flashStatus.text = "On"}
            case .auto:
                ^{ctrl.flashStatus.text = "Auto"}
            }
        } else {
            ^{ctrl.flashStatus.text = "None"}
        }
    }
    
}

/**
UI for the monitor.
*/

public class MonitorViewController : iAdViewController {
    
    let session = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")!
    
    let monitor = RemoteCamSystem.shared.actorOf(clz: MonitorActor.self, name: "MonitorActor")
    
    let timer : RCTimer = RCTimer()
    
    let soundManager : CPSoundManager = CPSoundManager()
    
    private let sliderColor1 = UIColor(red: 0.150, green: 0.670, blue: 0.80, alpha: 1)
    private let sliderColor2 = UIColor(red: 0.060, green: 0.100, blue: 0.160, alpha: 1)
    
    @IBOutlet weak var flashStatus: UILabel!
    
    @IBOutlet weak var imageView: UIImageView!
    
    @IBOutlet weak var takePicture: UIButton!
    
    @IBOutlet weak var sliderContainer : UIView!
    
    @IBOutlet weak var timerSlider : UISlider!
    
    @IBOutlet weak var timerLabel: UILabel!
    
    @IBAction func toggleCamera(sender: UIButton) {
        session ! UICmd.ToggleCamera()
    }
    
    @IBAction func onSliderChange(sender: UISlider) {
        self.timerLabel.text = "\(Int(sender.value))"
    }
    @IBAction func toggleFlash(sender: UIButton) {
        session ! UICmd.ToggleFlash()
    }
    
    @IBAction func showSettings(sender: UIButton) {
        let ctrl = CMConfigurationsViewController()
        self.navigationController?.pushViewController(ctrl, animated: true)
    }
    
    @IBAction func showGallery(sender: UIButton) {
        if let ctrl = GalleryViewController(nibName: "BFGalleryViewController", bundle: Bundle(for:BFGalleryViewController.self),  mediaProvider:BFGAssetsManagerProviderPhotoLibrary) {
            self.navigationController?.pushViewController(ctrl, animated: true)
        }
    }
    
    @IBAction func goBack(sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
    /**
     Take picture contains the logic to kick off the Timer for the picture.
    */
    
    @IBAction func onTakePicture(sender: UIBarButtonItem) {
        
        func timerAlertTitle(seconds : Int) -> String {
            return "Taking picture in \(seconds) seconds"
        }
        
        let alert = UIAlertController(title: timerAlertTitle(seconds: Int(round(self.timerSlider.value))),
            message: nil,
            preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { (a) in
            alert.dismiss(animated: true, completion: nil)
            self.timer.cancel()
        })
        
        self.soundManager.playBeepSound(CPSoundManagerAudioTypeSlow)
        
        self.present(alert, animated: true) {[unowned self] in
            self.timer.start(withDuration: Int(round(self.timerSlider.value)), withTickHandler: {[unowned self](t) in
                ^^{ alert.title = timerAlertTitle(seconds: t!.timeRemaining())}
                switch(t!.timeRemaining()) {
                    case let l where l > 3:
                        self.soundManager.playBeepSound(CPSoundManagerAudioTypeSlow)
                    case 3:
                        self.soundManager.playBeepSound(CPSoundManagerAudioTypeFast)
                    default:
                        break
                }
                }, cancelHandler: {(t) in
                    ^^{alert.dismiss(animated: true, completion: nil)}
                }, andCompletionHandler: {[unowned self] (t) in
                    ^^{alert.dismiss(animated: true, completion: nil)}
                    self.session ! UICmd.TakePicture(sender: nil)
                })
        }
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        monitor ! SetViewCtrl(ctrl: self)
        self.configureTimerUI()
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed || self.isMovingFromParent {
            monitor ! UICmd.UnbecomeMonitor(sender: nil)
            monitor ! Actor.Harakiri(sender: nil)
        }
    }
    
    private func configureTimerUI() {
        self.sliderContainer.layer.cornerRadius = 30.0
        self.sliderContainer.clipsToBounds=true
        self.timerSlider.layer.anchorPoint = CGPoint.init(x: 1.0, y: 1.0)
        self.timerSlider.transform = CGAffineTransform(rotationAngle: CGFloat(-Double.pi))
        self.timerSlider.minimumTrackTintColor = sliderColor1
        self.timerSlider.maximumTrackTintColor = sliderColor2
        self.timerSlider.thumbTintColor = sliderColor1
    }
    
    deinit {
        self.timer.cancel()
        self.soundManager.stopPlayer()
    }
}
