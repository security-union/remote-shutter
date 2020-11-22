//
//  BLEPeripheral.swift
//  Actors
//
//  Created by Dario on 10/26/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import CoreBluetooth

/**
    Actor wrapper of CBPeripheralManager
*/

public final class BLEPeripheral : Actor, CBPeripheralManagerDelegate, WithListeners {
    
    /**
     All actors interested on changes in BLEPeripheral
    */
    
    public var listeners : [ActorRef] = []
    
    /**
     Services configured
    */
     
    public var svcs : [CBService] = []
    
    /**
     Centrals subscriptions to CBCharacteristics DB
    */
    
    var subscriptions : Subscriptions = Subscriptions()
    
    /**
     Human readable states
     */
    
    public struct States {
        public let idle = "idle"
        public let connected = "connected"
        public let advertising = "advertising"
        public let startingAdvertisement = "startingAdvertisement"
    }
    
    /**
    Human readable states
     */
    
    public let states : States = States()
    
    /**
     CBPeripheral manager is the one that interacts with BLE hardware
     */
    
    private var peripheral : CBPeripheralManager
    
    /**
     This is the constructor used by the ActorSystem to instantiate BLEPeripheral, do not call it directly, use the ActorSystem actor of method.
     */
    
    required public init(context: ActorSystem, ref: ActorRef) {
        self.peripheral = CBPeripheralManager() //Stupid swift
        super.init(context: context, ref: ref)
        self.peripheral = CBPeripheralManager(delegate: self, queue: self.mailbox.underlyingQueue)
        self.peripheral.removeAllServices()

    }
    
    override public func preStart() -> Void {
        super.preStart()
        become(name: states.idle, state: self.idle)
    }
    
    /**
    This is the fallback message handler in case that the message is not handled on the other states
    */
    
    public override func receive(msg : Actor.Message) -> Void {
        switch(msg) {
            case is PeripheralManagerDidUpdateState:
                self.broadcast(msg: msg)
            
            case let m as SetServices:
                self.peripheral.removeAllServices()
                self.svcs = []
                m.svcs.forEach{self.peripheral.add($0)}
            
            
            case let m as RemoveServices:
                //TODO: have to check if this works
                m.svcs.forEach{self.peripheral.remove($0)}
//                self.svcs = self.svcs.filter({return !m.svcs.contains($0)})
            
            case is RemoveAllServices:
                self.peripheral.removeAllServices()
                self.svcs = []
            
        default:
            super.receive(msg: msg)
        }
    }
    
    /**
     Idle is the initial state
     */
    
    public lazy var idle : Receive = {[unowned self] (msg : Actor.Message) in
        switch (msg) {
            
            case is DidStartAdvertising:
                self.become(name: self.states.advertising, state: self.advertising)
                self.broadcast(msg: msg)
            
            case let m as StartAdvertising:
                self.peripheral.startAdvertising(m.advertisementData)
                self.become(name: self.states.startingAdvertisement, state: self.startingAdvertisement(advertisementData: m.advertisementData, svcs: m.svcs))
                self.addListener(sender: m.sender)
            
            case is FailedToStartAdvertising:
                self.broadcast(msg: msg)
            
            default :
                self.receive(msg: msg)
            }
    }
    
    public func startingAdvertisement(advertisementData : [String : AnyObject]?, svcs:[CBMutableService]) -> Receive {
            return {[unowned self] (msg : Actor.Message) in
        switch (msg) {
            case let s as PeripheralManagerDidUpdateState:
                switch(s.state) {
                case .poweredOn:
                        self.peripheral.startAdvertising(advertisementData)
                    
                    default:
                        print("waiting")
                }
                self.broadcast(msg: s)
            
            case is StartAdvertising:
                print("already starting")
            
            case is DidStartAdvertising:
                self.become(name: self.states.advertising, state: self.advertising)
                svcs.forEach {self.peripheral.add($0)}
                self.broadcast(msg: msg)
            
            case is FailedToStartAdvertising:
                self.popToState(name: self.states.idle)
                self.broadcast(msg: msg)
            
            case is StopAdvertising:
                self.peripheral.stopAdvertising()
                self.this ! RemoveAllServices(sender:nil)
                self.popToState(name: self.states.idle)
                self.broadcast(msg: DidStopAdvertising(sender: self.this))
            
            default :
                self.receive(msg: msg)
        }
    }
    }
    

    /**
    Message receiver for the advertising state
    */
    
    public lazy var advertising : Receive = {[unowned self](msg : Actor.Message) in
        switch (msg) {
            
            case let m as StartAdvertising:
                Thread.sleep(forTimeInterval: 1)
                self.peripheral.stopAdvertising()
                self.peripheral.startAdvertising(m.advertisementData)
                self.addListener(sender: m.sender)
            
            case is DidStartAdvertising,
                 is DidReceiveWriteRequests,
                 is DidReceiveReadRequest:
                self.broadcast(msg: msg)
            
            case let m as RespondToRequest:
                self.peripheral.respond(to: m.request, withResult : m.result)
            
            case let m as UpdateCharacteristicValue:
                self.peripheral.updateValue(m.value, for:m.char, onSubscribedCentrals: m.centrals)
            
            case is StopAdvertising:
                self.peripheral.stopAdvertising()
                self.svcs = []
                self.this ! RemoveAllServices(sender:nil)
                self.popToState(name: self.states.idle)
                self.broadcast(msg: DidStopAdvertising(sender: self.this))
            
            case let m as CentralDidSubscribeToCharacteristic:
                if var subs = self.subscriptions[m.central] {
                    subs.append(m.characteristic)
                } else {
                    self.subscriptions[m.central] = [m.characteristic]
                }
                self.broadcast(msg: msg)
                self.broadcast(msg: SubscriptionsChanged(sender: self.this, subscriptions: self.subscriptions))
                
            case let m as CentralDidUnsubscribeFromCharacteristic:
                if var subs = self.subscriptions[m.central],
                    let i = subs.firstIndex(of:m.characteristic) {
                        subs.remove(at:i)
                        if subs.count == 0 {
                            self.subscriptions.removeValue(forKey: m.central)
                        }
                }
                self.broadcast(msg: msg)
                self.broadcast(msg: SubscriptionsChanged(sender: self.this, subscriptions: self.subscriptions))
            
            case let m as DidAddService:
                self.broadcast(msg: msg)
            
            default :
                self.receive(msg: msg)
        }
    }
    
    /**
     CBPeripheralManagerDelegate methods, BLEPeripheral hides this methods so that messages can interact with BLE devices using actors
     */
    
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        this ! PeripheralManagerDidUpdateState(sender : this, state : CBManagerState.init(rawValue: peripheral.state.rawValue)!)
    }
    
    /**
     CBPeripheralManagerDelegate methods, BLEPeripheral hides this methods so that messages can interact with BLE devices using actors
     */
    
    public func peripheralManager(peripheral: CBPeripheralManager, central: CBCentral, didSubscribeToCharacteristic characteristic: CBCharacteristic) {
        this ! CentralDidSubscribeToCharacteristic(sender: this, central: central, characteristic: characteristic)
    }
    
    /**
     CBPeripheralManagerDelegate methods, BLEPeripheral hides this methods so that messages can interact with BLE devices using actors
     */
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
            this ! CentralDidUnsubscribeFromCharacteristic(sender: this, central: central, characteristic: characteristic)
    }
    
    /**
     CBPeripheralManagerDelegate methods, BLEPeripheral hides this methods so that messages can interact with BLE devices using actors
     */
    
    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            this ! FailedToStartAdvertising(sender: this, error: error)
        } else {
            this ! DidStartAdvertising(sender: this, svcs: self.svcs)
        }
    }
    
    /**
     CBPeripheralManagerDelegate methods, BLEPeripheral hides this methods so that messages can interact with BLE devices using actors
     */
    
    public func peripheralManager(peripheral: CBPeripheralManager, didReceiveReadRequest request: CBATTRequest) {
        this ! DidReceiveReadRequest(sender: this, request: request)
    }
    
    /**
     CBPeripheralManagerDelegate methods, BLEPeripheral hides this methods so that messages can interact with BLE devices using actors
     */
    
    public func peripheralManager(peripheral: CBPeripheralManager, didReceiveWriteRequests requests: [CBATTRequest]) {
        this ! DidReceiveWriteRequests(sender: this, requests: requests)
    }
    
    /**
     CBPeripheralManagerDelegate methods, BLEPeripheral hides this methods so that messages can interact with BLE devices using actors
     */
    
    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        //TODO: What is this for?
    }
    
    /**
     CBPeripheralManagerDelegate methods, BLEPeripheral hides this methods so that messages can interact with BLE devices using actors
     */
    
    public func peripheralManager(peripheral: CBPeripheralManager, willRestoreState dict: [String : AnyObject]) {
        //TODO: what is this for?
    }
    
    public func peripheralManager(peripheral: CBPeripheralManager, didAddService service: CBService, error: Error?) {
        self.svcs.append(service)
        this ! DidAddService(svc:service, sender:this)
    }
    
    deinit {
        self.peripheral.stopAdvertising()
    }
    
}
