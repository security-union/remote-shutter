//
//  LobbyViewController.swift
//  RemoteShutter
//
//  Created by Dario on 10/7/15.
//  Copyright © 2020 Security Union LLC. All rights reserved.
//

import UIKit
import Theater


/**
     Role picker allows the user to select whether the current device want's to be the camera or the monitor.
    
    It is important to mention that the session is the actor that coordinates this modes internally.
 
    One neat feature is that if two devices are connected and both are in the RolePickerController, when device1 selects a role, say Camera, RemoteCamSession will inform device2 about the choice, so that it becomes the Monitor.
*/

public class RemoteCamSystem: ActorSystem {
    static let shared = ActorSystem(name: "RemoteCam")
}

let connectedPrompt = NSLocalizedString("Pick a role: Camera or Remote", comment: "")

public class RolePickerActor: ViewCtrlActor<RolePickerController> {
    
    override public func receiveWithCtrl(ctrl: RolePickerController) -> Receive {
        return { (msg: Message) in
            switch msg {
            case is RemoteCmd.PeerBecameMonitor:
                ^{
                    ctrl.becomeCamera()
                }
            case is RemoteCmd.PeerBecameCamera:
                ^{
                    ctrl.becomeMonitor()
                }
            default:
            break
            }
        }
    }
}

public class RolePickerController: UIViewController {

    public struct States {
        let connect = "Connect"
        let disconnect = "Disconnect"
    }
    
    enum Segues {
        static let cameraRole = "cameraRole"
        static let remoteRole = "remoteRole"
        static let showCamera = "showCamera"
        static let showRemote = "showRemote"
        static let presentPhonePicker = "presentPhonePicker"
    }

    public let states = States()
    
    lazy var rolePicker: ActorRef = {
        RemoteCamSystem.shared.actorOf(
            clz: RolePickerActor.self,
            name: "RolePickerActor"
        )!
    }()
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        setupStyle()
        rolePicker ! SetViewCtrl(ctrl: self)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
        self.verifyCameraAndCameraRollAccess()
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed || self.isMovingFromParent {
            rolePicker ! Actor.Harakiri(sender: nil)
        }
    }
    
    func setupStyle() {
        self.navigationItem.prompt = connectedPrompt
        self.navigationItem.title = NSLocalizedString("Pick a role", comment: "")
    }

    public func showPhonePickerViewController() {
        self.performSegue(withIdentifier: Segues.presentPhonePicker, sender: self)
    }

    @IBAction func showSettings(sender: UIButton) {
        let ctrl = CMConfigurationsViewController()
        self.navigationController?.pushViewController(ctrl, animated: true)
    }

    @objc public func becomeMonitor() {
        self.performSegue(withIdentifier: Segues.showRemote, sender: self)
    }

    @objc public func becomeCamera() {
        self.performSegue(withIdentifier: Segues.showCamera, sender: self)
    }
    
    public override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case Segues.cameraRole:
            let destVC = segue.destination as! RolePickerOptionController
            // The view must be loaded before modifying UI properties
            destVC.loadViewIfNeeded()
            if #available(iOS 13.0, *) {
                destVC.view.styleEmbeddedView(backgroundColor: UIColor.secondarySystemBackground, borderColor: UIColor.clear, textColor: UIColor.white)
            } else {
                destVC.view.styleEmbeddedView(backgroundColor: UIColor.systemGray, borderColor: UIColor.clear, textColor: UIColor.white)
            }
            destVC.titleLabel.text = "Camera"
            destVC.descriptionLabel.text = "The device that captures the photo."
            destVC.tipLabel.text = "Tip: Choose the device with the best camera"
            destVC.colorfulButton.setTitle("Camera", for: .normal)
            destVC.colorfulButton.addTarget(self, action: #selector(becomeCamera), for: .touchUpInside)
            // TODO: ADD IMAGE AND FIX UI BUG IN STACK VIEW
            // destVC.image.src = "asdfasdfasdf"
        case Segues.remoteRole:
            let destVC = segue.destination as! RolePickerOptionController
            // The view must be loaded before modifying UI properties
            destVC.loadViewIfNeeded()
            if #available(iOS 13.0, *) {
                destVC.view.styleEmbeddedView(backgroundColor: UIColor.secondarySystemBackground, borderColor: UIColor.clear, textColor: UIColor.white)
            } else {
                destVC.view.styleEmbeddedView(backgroundColor: UIColor.systemGray, borderColor: UIColor.clear, textColor: UIColor.white)
            }
            destVC.titleLabel.text = "Remote"
            destVC.descriptionLabel.text = "The device that triggers the camera."
            destVC.tipLabel.text = "Tip: It typically works from up to 50 feet away"
            destVC.colorfulButton.setTitle("Remote", for: .normal)
            destVC.colorfulButton.styleButton(backgroundColor: UIColor.systemPink, borderColor: UIColor.clear, textColor: UIColor.white)
            destVC.colorfulButton.addTarget(self, action: #selector(becomeMonitor), for: .touchUpInside)
            // TODO: ADD IMAGE AND FIX UI BUG IN STACK VIEW
            // destVC.image.src = "asdfasdfasdf"
        default:
            print("Segue not recognized. Doing nothing.")
        }
    }
}
