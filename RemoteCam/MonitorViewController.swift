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

/**
Monitor actor has a reference to the session actor and to the monitorViewController, it acts as the connection between the model and the controller from an MVC perspective.
*/

public class MonitorActor: ViewCtrlActor<MonitorViewController> {

    public required init(context: ActorSystem, ref: ActorRef) {
        super.init(context: context, ref: ref)
        let session: Optional<ActorRef> = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")
        session! ! UICmd.BecomeMonitor(sender: ref)
    }

    override public func receiveWithCtrl(ctrl: MonitorViewController) -> Receive {
        return { [unowned self](msg: Message) in
            switch (msg) {

            case is UICmd.BecomeMonitorFailed:
                ^{
                    ctrl.navigationController?.popViewController(animated: true)
                }

            case let cam as UICmd.ToggleCameraResp:
                self.setFlashMode(ctrl: ctrl, flashMode: cam.flashMode)

            case let flash as RemoteCmd.ToggleFlashResp:
                self.setFlashMode(ctrl: ctrl, flashMode: flash.flashMode)

            case is UICmd.UnbecomeMonitor:
                let session: Optional<ActorRef> = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")
                session! ! msg

            case let f as RemoteCmd.OnFrame:
                if let img = UIImage(data: f.data) {
                    let orientation = imageTransform(UIDevice.current.orientation, cameraOrientation: f.camOrientation, camPosition: f.camPosition)
                    ^{
                        ctrl.imageView.image = UIImage(cgImage: img.cgImage!, scale: 1, orientation: orientation)
                    }
                }

            default:
                self.receive(msg: msg)
            }
        }
    }

    func imageTransform(_ deviceOrientation: UIDeviceOrientation,
                        cameraOrientation: UIInterfaceOrientation,
                        camPosition: AVCaptureDevice.Position) -> UIImage.Orientation {
        switch (cameraOrientation, camPosition) {
        case (UIInterfaceOrientation.landscapeRight, AVCaptureDevice.Position.back):
            return .up
        case (UIInterfaceOrientation.portrait, AVCaptureDevice.Position.back):
            return .right
        case (UIInterfaceOrientation.landscapeLeft, AVCaptureDevice.Position.back):
            return .down
        case (UIInterfaceOrientation.portraitUpsideDown, AVCaptureDevice.Position.back):
            return .left

        case (UIInterfaceOrientation.landscapeRight, AVCaptureDevice.Position.front):
            return .down
        case (UIInterfaceOrientation.portrait, AVCaptureDevice.Position.front):
            return .right
        case (UIInterfaceOrientation.landscapeLeft, AVCaptureDevice.Position.front):
            return .up
        case (UIInterfaceOrientation.portraitUpsideDown, AVCaptureDevice.Position.front):
            return .left
        default:
            return .up
        }
    }

    func setFlashMode(ctrl: MonitorViewController, flashMode: AVCaptureDevice.FlashMode?) {
        if let f = flashMode {
            switch (f) {
            case .off:
                ^{
                    ctrl.flashStatus.text = "Off"
                }
            case .on:
                ^{
                    ctrl.flashStatus.text = "On"
                }
            case .auto:
                ^{
                    ctrl.flashStatus.text = "Auto"
                }
            }
        } else {
            ^{
                ctrl.flashStatus.text = "None"
            }
        }
    }

}

/**
UI for the monitor.
*/

public class MonitorViewController: iAdViewController {

    let session = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")!

    let monitor = RemoteCamSystem.shared.actorOf(clz: MonitorActor.self, name: "MonitorActor")

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
        goToPhotos()
    }

    @IBAction func goBack(sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }

    /**
     Take picture contains the logic to kick off the Timer for the picture.
    */

    @IBAction func onTakePicture(sender: UIBarButtonItem) {

        func timerAlertTitle(seconds: Int) -> String {
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

        self.present(alert, animated: true) { [unowned self] in
            self.timer.start(withDuration: Int(round(self.timerSlider.value)), withTickHandler: { [unowned self](t) in
                ^^{
                    alert.title = timerAlertTitle(seconds: t!.timeRemaining())
                }
                switch (t!.timeRemaining()) {
                case let l where l > 3:
                    self.soundManager.playBeepSound(CPSoundManagerAudioTypeSlow)
                case 3:
                    self.soundManager.playBeepSound(CPSoundManagerAudioTypeFast)
                default:
                    break
                }
            }, cancelHandler: { (t) in
                ^^{
                    alert.dismiss(animated: true, completion: nil)
                }
            }, andCompletionHandler: { [unowned self] (t) in
                ^^{
                    alert.dismiss(animated: true, completion: nil)
                }
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
        self.sliderContainer.clipsToBounds = true
        self.timerSlider.layer.anchorPoint = CGPoint.init(x: 1.0, y: 1.0)
        self.timerSlider.transform = CGAffineTransform(rotationAngle: CGFloat(-Double.pi / 2))
        self.timerSlider.minimumTrackTintColor = sliderColor1
        self.timerSlider.maximumTrackTintColor = sliderColor2
        self.timerSlider.thumbTintColor = sliderColor1
    }

    deinit {
        self.timer.cancel()
        self.soundManager.stopPlayer()
    }
}

extension CGImage {

    func rotated(by angle: CGFloat) -> CGImage? {
        let angleInRadians = angle * .pi / 180

        let imgRect = CGRect(x: 0, y: 0, width: width, height: height)
        let transform = CGAffineTransform.identity.rotated(by: angleInRadians)
        let rotatedRect = imgRect.applying(transform)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let bmContext = CGContext(
                data: nil,
                width: Int(rotatedRect.size.width),
                height: Int(rotatedRect.size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
                else {
            return nil
        }

        bmContext.setAllowsAntialiasing(true)
        bmContext.setShouldAntialias(true)
        bmContext.interpolationQuality = .high
        bmContext.translateBy(x: rotatedRect.size.width * 0.5, y: rotatedRect.size.height * 0.5)
        bmContext.rotate(by: angleInRadians)
        let drawRect = CGRect(
                origin: CGPoint(x: -imgRect.size.width * 0.5, y: -imgRect.size.height * 0.5),
                size: imgRect.size)
        bmContext.draw(self, in: drawRect)

        guard let rotatedImage = bmContext.makeImage() else {
            return nil
        }

        return rotatedImage
    }

}
