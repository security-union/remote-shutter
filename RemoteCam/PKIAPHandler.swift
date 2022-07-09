//
//  PKIAPHandler.swift
//
//  Created by Pramod Kumar on 13/07/2017.
//  Copyright © 2017 Pramod Kumar. All rights reserved.
//
//  https://medium.com/swiftcommmunity/implement-in-app-purchase-iap-in-ios-applications-swift-4d1649509599
//

import UIKit
import StoreKit

enum PKIAPHandlerAlertType {
    case setProductIds
    case disabled
    case restored
    case purchased
    
    var message: String{
        switch self {
        case .setProductIds: return "Product ids not set, call setProductIds method!"
        case .disabled: return "Purchases are disabled in your device!"
        case .restored: return "You\'ve successfully restored your purchase!"
        case .purchased: return "You\'ve successfully bought this product!"
        }
    }
}


class PKIAPHandler: NSObject {
    
    //MARK:- Shared Object
    //MARK:-
    static let shared = PKIAPHandler()
    private override init() {
        super.init()
    }
    
    //MARK:- Properties
    //MARK:- Private
    fileprivate var productIds = [String]()
    fileprivate var productID = ""
    fileprivate var productsRequest = SKProductsRequest()
    fileprivate var fetchProductCompletion: (([SKProduct])->Void)?
    
    fileprivate var productToPurchase: SKProduct?
    fileprivate var purchaseProductCompletion: ((PKIAPHandlerAlertType, SKProduct?, SKPaymentTransaction?)->Void)?
    
    //MARK:- Public
    var isLogEnabled: Bool = true
    
    //MARK:- Methods
    //MARK:- Public
    
    //Set Product Ids
    func setProductIds(ids: [String]) {
        self.productIds = ids
    }

    //MAKE PURCHASE OF A PRODUCT
    func canMakePurchases() -> Bool {  return SKPaymentQueue.canMakePayments()  }
    
    func purchase(product: SKProduct, completion: @escaping ((PKIAPHandlerAlertType, SKProduct?, SKPaymentTransaction?)->Void)) {
        
        self.purchaseProductCompletion = completion
        self.productToPurchase = product

        if self.canMakePurchases() {
            let payment = SKPayment(product: product)
            SKPaymentQueue.default().add(self)
            SKPaymentQueue.default().add(payment)
            
            log("PRODUCT TO PURCHASE: \(product.productIdentifier)")
            productID = product.productIdentifier
        }
        else {
            completion(PKIAPHandlerAlertType.disabled, nil, nil)
        }
    }
    
    // RESTORE PURCHASE
    func restorePurchase(_ completion: @escaping ((PKIAPHandlerAlertType, SKProduct?, SKPaymentTransaction?)->Void)) {
        self.purchaseProductCompletion = completion
        SKPaymentQueue.default().add(self)
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    
    // FETCH AVAILABLE IAP PRODUCTS
    func fetchAvailableProducts(completion: @escaping (([SKProduct])->Void)){
        
        self.fetchProductCompletion = completion
        // Put here your IAP Products ID's
        if self.productIds.isEmpty {
            log(PKIAPHandlerAlertType.setProductIds.message)
            fatalError(PKIAPHandlerAlertType.setProductIds.message)
        }
        else {
            productsRequest = SKProductsRequest(productIdentifiers: Set(self.productIds))
            productsRequest.delegate = self
            productsRequest.start()
        }
    }
    
    //MARK:- Private
    fileprivate func log <T> (_ object: T) {
        if isLogEnabled {
            NSLog("\(object)")
        }
    }
}

//MARK:- Product Request Delegate and Payment Transaction Methods
//MARK:-
extension PKIAPHandler: SKProductsRequestDelegate, SKPaymentTransactionObserver{
    
    // REQUEST IAP PRODUCTS
    func productsRequest (_ request:SKProductsRequest, didReceive response:SKProductsResponse) {
        
        if (response.products.count > 0) {
            if let completion = self.fetchProductCompletion {
                completion(response.products)
            }
        }
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        self.paymentQueue(queue, updatedTransactions: queue.transactions)
        if let completion = self.purchaseProductCompletion {
            completion(PKIAPHandlerAlertType.restored, nil, nil)
        }

    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        print("error \(error)")
    }
    
    // IAP PAYMENT QUEUE
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
                switch transaction.transactionState {
                case .purchased:
                    log("Product purchase done")
                    SKPaymentQueue.default().finishTransaction(transaction)
                    if (self.productID == disableAdsPID) {
                        UserDefaults.standard.set(true, forKey: didBuyRemoveiAdsFeature)
                    } else if (self.productID == enableVideoPID) {
                        UserDefaults.standard.set(true, forKey: didBuyRemoveAdsAndEnableVideo)
                    } else {
                        UserDefaults.standard.set(true, forKey: self.productID)
                    }
                    if let completion = self.purchaseProductCompletion {
                        completion(PKIAPHandlerAlertType.purchased, self.productToPurchase, transaction)
                    }
                    break
                    
                case .failed:
                    log("Product purchase failed")
                    SKPaymentQueue.default().finishTransaction(transaction)
                    break
                case .restored:
                    log("Product restored")
                    SKPaymentQueue.default().finishTransaction(transaction)
                    if (transaction.payment.productIdentifier == disableAdsPID) {
                        UserDefaults.standard.set(true, forKey: didBuyRemoveiAdsFeature)
                    } else if (transaction.payment.productIdentifier == enableVideoPID) {
                        UserDefaults.standard.set(true, forKey: didBuyRemoveAdsAndEnableVideo)
                    } else {
                        UserDefaults.standard.set(true, forKey: self.productID)
                    }
                    if let completion = self.purchaseProductCompletion {
                        completion(PKIAPHandlerAlertType.purchased, self.productToPurchase, transaction)
                    }
                    break
                    
                default: break
                }
        }
    }
}
