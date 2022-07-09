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
    @IBOutlet weak var disableAdsButton: UIButton!
    @IBOutlet weak var enableVideoButton: UIButton!
    @IBOutlet weak var restorePurchaseButton: UIButton!
    @IBOutlet weak var reviewAppButton: UIButton!
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
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.portrait
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return UIInterfaceOrientation.portrait
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.setupStyle()
        self.hidePurchased()
    }
    
    @IBAction func disableAds() {
        purchaseProduct(productId: disableAdsPID)  { (_) in
            self.hidePurchased()
        }
    }
    
    @IBAction func goToConnectViewController() {
        self.performSegue(withIdentifier: goToConnectViewControllerSegue, sender: nil)
    }
    
    @IBAction func enableVideo() {
        purchaseProduct(productId: enableVideoPID) { (_) in
            self.hidePurchased()
        }
    }
    
    @IBAction func restorePurchases() {
        PKIAPHandler.shared.restorePurchase { (alert, product, transaction) in
            self.hidePurchased()
            let controller = UIAlertController.init(title: NSLocalizedString("Purchases were successfully restored", comment: ""), message: NSLocalizedString("If you do not see your purchases, please ensure that the AppleId that this device is associated with, is correct.", comment: ""))
            controller.simpleOkAction()
            controller.show(true)
        }
    }
    
    @IBAction func showHelp() {
        let alert = UIAlertController(title: NSLocalizedString("Remote Shutter lets you take pictures from a distance. Keep these few things in mind:\n\n1. Requires 2 apple devices.\n2. You must have Wi-Fi on, but don't need to be connected.", comment: ""), message: "")
        alert.simpleOkAction()
        alert.show(true)
    }

    @IBAction func reviewApp(_ sender: Any) {
        var count = UserDefaults.standard.integer(forKey: reviewCounterKey)
        count += 1
        UserDefaults.standard.set(count, forKey: reviewCounterKey)

        print("Review presented \(count) time(s)")

        let infoDictionaryKey = kCFBundleVersionKey as String
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String
            else { fatalError("Expected to find a bundle version in the info dictionary") }

        let lastVersionPromptedForReview = UserDefaults.standard.string(forKey: lastVersionPromptedForReviewKey)

        if count <= 4 && currentVersion != lastVersionPromptedForReview {
            let twoSecondsFromNow = DispatchTime.now() + 2.0
                DispatchQueue.main.asyncAfter(deadline: twoSecondsFromNow) { [navigationController] in
                    if navigationController?.topViewController is WelcomeViewController {
                        SKStoreReviewController.requestReview()
                        UserDefaults.standard.set(currentVersion, forKey: lastVersionPromptedForReviewKey)
                    }
                }
        }
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
        reviewAppButton.styleButton(
            backgroundColor: UIColor.systemPink,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
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
    }
    
    private func hidePurchased() {
        let disabledAds = UserDefaults.standard.bool(forKey: didBuyRemoveiAdsFeature)
        if (disabledAds) {
            disableAdsButton.isHidden = true
        }
        
        let enabledVideo = UserDefaults.standard.bool(forKey: didBuyRemoveAdsAndEnableVideo)
        if (enabledVideo) {
            enableVideoButton.isHidden = true
            disableAdsButton.isHidden = true
        }
        
        if (disabledAds && enabledVideo) {
            restorePurchaseButton.isHidden = true
            welcomeDescLabel.text = "Thanks for your support! We are working on new features for you!"
            
            // Only show the review button if the user has not reviewed this version yet
            // And they have reviewed 4 times or less.
            let count = UserDefaults.standard.integer(forKey: reviewCounterKey)
            let infoDictionaryKey = kCFBundleVersionKey as String
            guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String
                else { fatalError("Expected to find a bundle version in the info dictionary") }
            
            let lastVersionPromptedForReview = UserDefaults.standard.string(forKey: lastVersionPromptedForReviewKey)

            if count <= 4 && currentVersion != lastVersionPromptedForReview {
                reviewAppButton.isHidden = false
            } else {
                reviewAppButton.isHidden = true
            }
        } else {
            reviewAppButton.isHidden = true
        }
    }
}
