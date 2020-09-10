//
//  LobbyViewController.swift
//  Actors
//
//  Created by Dario on 10/7/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import Theater

/**
     Role picker allows the user to select whether the current device want's to be the camera or the monitor.
    
    It is important to mention that the session is the actor that coordinates this modes internally.
 
    One neat feature is that if two devices are connected and both are in the RolePickerController, when device1 selects a role, say Camera, RemoteCamSession will inform device2 about the choice, so that it becomes the Monitor.
 
*/

public class RemoteCamSystem : ActorSystem {
    static let shared = ActorSystem(name: "RemoteCam")
}

public class RolePickerController : UIViewController {

    let showCameraSegue : String = "showCamera"
    
    let showRemoteSegue : String = "showRemote"
    
    let presentPhonePickerSegue : String = "presentPhonePicker"
    
    public struct States {
        let connect = "Connect"
        let disconnect = "Disconnect"
    }
    
    public let states =  States()
    
    @IBOutlet weak var remote: UIButton!
    @IBOutlet weak var camera: UIButton!
    
    
    lazy var remoteCamSession : ActorRef = RemoteCamSystem.shared.actorOf(clz: RemoteCamSession.self, name: "RemoteCam Session")
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: states.connect, style: .done, target: self, action: #selector(RolePickerController.toggleConnect(button:)))
        self.navigationItem.prompt = "Select camera or remote:"
        self.remoteCamSession ! SetViewCtrl(ctrl: self)
        self.remoteCamSession ! UICmd.StartScanning(sender : nil)
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
        self.verifyCameraAndCameraRollAccess()
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if(self.isBeingDismissed || self.isMovingFromParent){
            remoteCamSession ! Disconnect(sender:nil)
            remoteCamSession ! Actor.Harakiri(sender: nil)
        }
    }
    
    public func showPhonePickerViewController() {
        self.performSegue(withIdentifier: presentPhonePickerSegue, sender: self)
    }
    
    @IBAction public func becomeMonitor(button : UIButton) {
        becomeMonitor()
    }
    
    public func becomeMonitor() {
        self.performSegue(withIdentifier: showRemoteSegue, sender: self)
    }
    
    @IBAction public func becomeCamera(button : UIButton) {
        becomeCamera()
    }
    
    public func becomeCamera() {
        self.performSegue(withIdentifier: showCameraSegue, sender: self)
    }
        
    @objc public func toggleConnect(button : UIButton) {
        self.remoteCamSession ! UICmd.ToggleConnect(sender : nil)
    }
    
}
