//
//  BLEPeripheralConnection.swift
//  Actors
//
//  Created by Dario Lencina on 10/26/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import CoreBluetooth

/**
    BLECentral returns a BLEPeripheralConnection OnConnect, the idea is to simplify and provide a more organized
     way to interact with CBPeripherals
*/

public class BLEPeripheralConnection : Actor, WithListeners, CBPeripheralDelegate {
    
    /**
     
    Actors that care about this peripheral connection
    
     */
    
    public var listeners : [ActorRef] = [ActorRef]()
    
    func connected(peripheral : CBPeripheral) -> Receive {
        peripheral.delegate = self
        return { [unowned self] (msg : Actor.Message) in
        switch(msg) {
            
            case let m as DiscoverServices:
                peripheral.discoverServices(m.services)
            
            case is AddListener:
                self.addListener(sender: msg.sender)
            
            case is PeripheralDidUpdateName:
                self.broadcast(msg: msg)
            
            case is DidModifyServices:
                self.broadcast(msg: msg)
                
            case is DidReadRSSI:
                self.broadcast(msg: msg)
                
            case is DidDiscoverServices:
                self.broadcast(msg: msg)
                
            case is DidDiscoverIncludedServicesForService:
                self.broadcast(msg: msg)
                
            case is DidDiscoverCharacteristicsForService:
                self.broadcast(msg: msg)
                
            case is DidUpdateValueForCharacteristic:
                self.broadcast(msg: msg)
                
            case is DidWriteValueForCharacteristic:
                self.broadcast(msg: msg)
                
            case is DidUpdateNotificationStateForCharacteristic:
                self.broadcast(msg: msg)
                
            case is DidDiscoverDescriptorsForCharacteristic:
                self.broadcast(msg: msg)
                
            case is DidUpdateValueForDescriptor:
                self.broadcast(msg: msg)
                
            case is DidWriteValueForDescriptor:
                self.broadcast(msg: msg)
                
            default:
                print("ignored")
        }
        }
    }
    
    /**
    
    This is the message handler when there's no peripheral
     
     - parameter msg : incoming message
     
    */
    
    public override func receive(msg: Actor.Message) {
        switch(msg) {
            
            case let p as SetPeripheral:
                self.become(name: "connected", state: self.connected(peripheral: p.peripheral))
            
            default:
                super.receive(msg: msg)
        }
    }
    
    /**
    CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
    */
    
    public func peripheralDidUpdateName(_ peripheral: CBPeripheral){
        this ! PeripheralDidUpdateName(sender: this, peripheral: peripheral)
    }

    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */
    
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]){
        this ! DidModifyServices(sender: this, peripheral: peripheral, invalidatedServices: invalidatedServices)
    }
    
    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */
    
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?){
        this ! DidReadRSSI(sender: this, peripheral: peripheral, error: error, RSSI: RSSI)
    }
    
    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?){
        if let svcs = peripheral.services {
            if svcs.count > 0  {
                peripheral.services?.forEach {
                    print("didDiscoverServices \($0.uuid)")
                }
                
                peripheral.services?.forEach({ (service : CBService) in
                    peripheral.discoverCharacteristics(nil, for: service)
                })
                this ! DidDiscoverServices(sender: this, peripheral: peripheral, error: error)
            } else {
                this ! DidDiscoverNoServices(sender: this, peripheral: peripheral, error: error)
            }
        } else {
            this ! DidDiscoverNoServices(sender: this, peripheral: peripheral, error: error)
        }
    }
    
    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?){
        this ! DidDiscoverIncludedServicesForService(sender: this, peripheral: peripheral, service: service, error: error)
    }
    
    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?){
        this ! DidDiscoverCharacteristicsForService(sender: this, peripheral: peripheral, service: service, error: error)
    }
    
    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?){
        this ! DidUpdateValueForCharacteristic(sender: this, peripheral: peripheral, characteristic: characteristic, error: error)
    }
    
    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?){
        this ! DidWriteValueForCharacteristic(sender: this, peripheral: peripheral, characteristic: characteristic, error: error)
    }
    
    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?){
        this ! DidUpdateNotificationStateForCharacteristic(sender: this, peripheral: peripheral, characteristic: characteristic, error: error)
    }
    
    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?){
        this ! DidDiscoverDescriptorsForCharacteristic(sender: this, peripheral: peripheral, characteristic: characteristic, error: error)
    }
    
    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?){
        this ! DidUpdateValueForDescriptor(sender: this, peripheral: peripheral, descriptor: descriptor, error: error)
    }
    
    /**
     CBPeripheralDelegate forwarded message, this method is exposed through an Actor.Message subclass
     */
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?){
        this ! DidWriteValueForDescriptor(sender: this, peripheral: peripheral, descriptor: descriptor, error: error)
    }
    
    deinit {
        print("bye")
    }
    
}
