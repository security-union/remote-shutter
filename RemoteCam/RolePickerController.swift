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
    
    override public func receiveWithCtrl(ctrl: Weak<RolePickerController>) -> Receive {
        return {[unowned self] (msg: Message) in
            switch msg {
            
            case is RemoteCmd.PeerBecameMonitor:
                ^{
                    ctrl.value?.becomeCamera()
                }
            case is RemoteCmd.PeerBecameCamera:
                ^{
                    ctrl.value?.becomeMonitor()
                }
            default:
                self.receive(msg: msg)
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
    @IBOutlet var cameraButton: UIButton!
    @IBOutlet var remoteButton: UIButton!
    @IBOutlet var cameraView: UIView!
    @IBOutlet var remoteView: UIView!
    @IBOutlet var stackView: UIStackView!
    
    var rolePicker: ActorRef! = RemoteCamSystem.shared.actorOf(
        clz: RolePickerActor.self,
        name: "RolePickerActor"
    )

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
    
    override public func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        stackView.axis = (size.width > size.height) ? .horizontal : .vertical
    }
    
    func setupStyle() {
        self.navigationItem.prompt = connectedPrompt
        self.navigationItem.title = NSLocalizedString("Pick a role", comment: "")
        
        // Style buttons
        cameraButton.styleButton(backgroundColor: UIColor.systemBlue, borderColor: UIColor.clear, textColor: UIColor.white)
        remoteButton.styleButton(backgroundColor: UIColor.systemRed, borderColor: UIColor.clear, textColor: UIColor.white)
        if #available(iOS 13.0, *) {
            cameraView.backgroundColor = UIColor.tertiarySystemBackground
            remoteView.backgroundColor = UIColor.tertiarySystemBackground
        } else {
            cameraView.backgroundColor = UIColor.lightGray
            remoteView.backgroundColor = UIColor.lightGray
        }
        cameraView.layer.cornerRadius = 10;
        cameraView.layer.masksToBounds = true;
        remoteView.layer.cornerRadius = 10;
        remoteView.layer.masksToBounds = true;
    }

    public func showPhonePickerViewController() {
        self.performSegue(withIdentifier: Segues.presentPhonePicker, sender: self)
    }

    @IBAction func showSettings(sender: UIButton) {
        let ctrl = CMConfigurationsViewController()
        self.navigationController?.pushViewController(ctrl, animated: true)
    }

    @IBAction func becomeMonitor() {
        self.performSegue(withIdentifier: Segues.showRemote, sender: self)
    }

    @IBAction func becomeCamera() {
        self.performSegue(withIdentifier: Segues.showCamera, sender: self)
    }
    
    deinit {
        print("killing RolePickerController")
        rolePicker ! Actor.Harakiri(sender: nil)
    }
    
}
