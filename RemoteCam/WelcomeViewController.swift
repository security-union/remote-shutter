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
    @IBOutlet weak var welcomeDescLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // In-App Purchases
        PKIAPHandler.shared.setProductIds(ids: self.productIds)
        PKIAPHandler.shared.fetchAvailableProducts { [weak self](products)   in
           guard let sSelf = self else {return}
           sSelf.productsArray = products
        }
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.setupStyle()
        self.hidePurchased()
    }
    
    @IBAction func disableAds() {
        purchaseProduct(productId: disableAdsPID)  { (result) -> () in
            self.disableAdsButton.isHidden = result
        }
    }
    
    @IBAction func goToConnectViewController() {
        self.performSegue(withIdentifier: goToConnectViewControllerSegue, sender: self)
    }
    
    @IBAction func enableVideo() {
        purchaseProduct(productId: enableVideoPID) { (result) -> () in
            self.enableVideoButton.isHidden = result
        }
    }
    
    @IBAction func restorePurchases() {
        PKIAPHandler.shared.restorePurchase()
    }
    
    @IBAction func showHelp() {
        let alert = UIAlertController(title: NSLocalizedString("help", comment: ""), message: "")
        alert.simpleOkAction()
        alert.show(true)
    }
        
    private func purchaseProduct(productId: String, handler: @escaping (Bool) -> ()) {
        for product in self.productsArray {
            if (product.productIdentifier == productId) {
                PKIAPHandler.shared.purchase(product: product) { (alert, product, transaction) in
                    if let _ = transaction, let _ = product {
                        handler(true)
                    } else {
                        debugPrint(alert.message)
                        handler(false)
                    }
               }
            }
        }
    }
    
    private func setupStyle() {
        // Styling
        continueButton.styleButton(
            backgroundColor: UIColor.systemBlue,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        restorePurchaseButton.styleButton(
            backgroundColor: UIColor.systemOrange,
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
        navigationController?.navigationBar.prefersLargeTitles = true
        self.navigationItem.title = "Welcome"
        self.navigationItem.rightBarButtonItem = nil
    }
    
    private func hidePurchased() {
        let disabledAds = UserDefaults.standard.bool(forKey: disableAdsPID)
        if (disabledAds) {
            disableAdsButton.isHidden = true
        }
        
        let enabledVideo = UserDefaults.standard.bool(forKey: enableVideoPID)
        if (enabledVideo) {
            enableVideoButton.isHidden = true
        }
        
        if (disabledAds && enabledVideo) {
            restorePurchaseButton.isHidden = true
            welcomeDescLabel.text = "Thanks for your support! We are working on new features for you!"
        }
    }
}
