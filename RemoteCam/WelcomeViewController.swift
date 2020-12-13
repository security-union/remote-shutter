//
//  WelcomeViewController.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 11/30/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import UIKit

let goToConnectViewControllerSegue = "goToConnectViewControllerSegue"

class WelcomeViewController: UIViewController {
    
    private var productsArray: [SKProduct] = []
    private var productIds: [String] = [disableAdsPID, enableVideoPID]
    
    
    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var restorePurchaseButton: UIButton!
    @IBOutlet weak var disableAdsButton: UIButton!
    @IBOutlet weak var enableVideoButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupStyle()
        
        // In-App Purchases
        PKIAPHandler.shared.setProductIds(ids: self.productIds)
        PKIAPHandler.shared.fetchAvailableProducts { [weak self](products)   in
           guard let sSelf = self else {return}
           sSelf.productsArray = products
        }
    }
    
    func setupStyle() {
        // Styling
        continueButton.styleButton(
            backgroundColor: UIColor.systemBlue,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        restorePurchaseButton.styleButton(
            backgroundColor: UIColor.systemYellow,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        disableAdsButton.styleButton(
            backgroundColor: UIColor.systemGreen,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        enableVideoButton.styleButton(
            backgroundColor: UIColor.systemGreen,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
    }
    
    @IBAction func showHelp() {
        let alert = UIAlertController(title: NSLocalizedString("help", comment: ""), message: "")
        alert.simpleOkAction()
        alert.show(true)
    }
    
    @IBAction func enableVideo() {
        purchaseProduct(productId: enableVideoPID)
    }
    
    @IBAction func disableAds() {
        purchaseProduct(productId: disableAdsPID)
    }
    
    @IBAction func restorePurchases() {
        PKIAPHandler.shared.restorePurchase()
    }
    
    @IBAction func goToConnectViewController() {
        self.performSegue(withIdentifier: goToConnectViewControllerSegue, sender: self)
    }
        
    private func purchaseProduct(productId: String) {
        for product in self.productsArray {
            if (product.productIdentifier == productId) {
                PKIAPHandler.shared.purchase(product: product) { (alert, product, transaction) in
                    if let _ = transaction, let _ = product {
                        debugPrint("Purchase successful!!!")
                   }
                   debugPrint(alert.message)
               }
            }
        }
    }
}
