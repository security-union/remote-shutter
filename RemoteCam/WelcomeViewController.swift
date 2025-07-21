//
//  WelcomeViewController.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 11/30/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import UIKit
import StoreKit
import SwiftUI

let goToConnectViewControllerSegue = "goToConnectViewControllerSegue"

class WelcomeViewController: UIViewController {
    
    private var productsArray: [SKProduct] = []
    private var productIds: [String] = [disableAdsPID, enableVideoPID, enableTorchPID, enableVideoOnlyPID]
    
    // Instance property to track if this is the initial app launch
    private var isInitialAppLaunch: Bool = true

    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var disableAdsButton: UIButton!
    @IBOutlet weak var buyProButton: UIButton!
    @IBOutlet weak var enableTorchButton: UIButton!
    @IBOutlet weak var enableVideoOnlyButton: UIButton!
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
           sSelf.updateButtonTitlesAndPrices()
        }
        
        // Listen to purchase notifications to keep UI in sync
        setupPurchaseNotifications()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
        
        // Always refresh UI when returning to this screen (e.g., from settings)
        self.updateButtonTitlesAndPrices()
        self.hidePurchased()
        
        // Check if we should auto-skip to next screen on initial launch
        if isInitialAppLaunch {
            isInitialAppLaunch = false
            checkAndAutoSkipIfProUser()
        }
    }
    
    deinit {
        // Clean up notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Auto-Skip Logic
    
    private func checkAndAutoSkipIfProUser() {
        let manager = InAppPurchasesManager.shared()!
        let hasProMode = manager.hasProMode()
        
        // If user has Pro mode and this is the initial app launch, auto-skip to next screen
        if hasProMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.goToConnectViewController()
            }
        }
    }
    
    // MARK: - Purchase Notification Setup
    
    private func setupPurchaseNotifications() {
        let notificationCenter = NotificationCenter.default
        
        // Listen for all purchase-related notifications
        notificationCenter.addObserver(
            self,
            selector: #selector(purchaseStatusChanged),
            name: NSNotification.Name(rawValue: Constants.removeAds()),
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(purchaseStatusChanged),
            name: NSNotification.Name(rawValue: Constants.proModeAquired()),
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(purchaseStatusChanged),
            name: NSNotification.Name(rawValue: Constants.enableTorch()),
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(purchaseStatusChanged),
            name: NSNotification.Name(rawValue: Constants.enableVideoOnly()),
            object: nil
        )
    }
    
    @objc private func purchaseStatusChanged() {
        // Refresh UI on main thread when any purchase status changes
        DispatchQueue.main.async { [weak self] in
            self?.hidePurchased()
            self?.updateButtonTitlesAndPrices()
        }
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
    
    @IBAction func enableTorch() {
        purchaseProduct(productId: enableTorchPID) { (_) in
            self.hidePurchased()
        }
    }
    
    @IBAction func enableVideoOnly() {
        purchaseProduct(productId: enableVideoOnlyPID) { (_) in
            self.hidePurchased()
        }
    }
    
    @IBAction func restorePurchases() {
        PKIAPHandler.shared.restorePurchase { (alert, product, transaction) in
            self.hidePurchased()
            if alert == .restored {
                let controller = UIAlertController.init(title: NSLocalizedString("Purchases were successfully restored", comment: ""), message: NSLocalizedString("If you do not see your purchases, please ensure that the AppleId that this device is associated with, is correct.", comment: ""))
                controller.simpleOkAction()
                controller.show(true)
            }
        }
    }
    
    @IBAction func showHelp() {
        let helpView = RemoteShutterHelpView(onDismiss: { [weak self] in
            self?.dismiss(animated: true)
        })
        
        let hostingController = UIHostingController(rootView: helpView)
        hostingController.modalPresentationStyle = .pageSheet
        
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        
        present(hostingController, animated: true)
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
        // Styling with improved visual hierarchy
        
        // Review button - keep existing pink
        reviewAppButton.styleButton(
            backgroundColor: UIColor.systemPink,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        
        // Continue button - most prominent as primary action
        continueButton.styleButton(
            backgroundColor: UIColor.systemBlue,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        
        // Restore purchases - utility function, not a product
        restorePurchaseButton.styleButton(
            backgroundColor: UIColor.systemGray,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        
        // Individual purchase buttons - standard green, less prominent
        disableAdsButton.styleButton(
            backgroundColor: UIColor.systemGreen,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        
        // Pro button - premium purple to highlight best value
        buyProButton.styleButton(
            backgroundColor: UIColor.systemPurple,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        
        enableTorchButton.styleButton(
            backgroundColor: UIColor.systemGreen,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        
        enableVideoOnlyButton.styleButton(
            backgroundColor: UIColor.systemGreen,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        
        navigationController?.navigationBar.prefersLargeTitles = true
        self.navigationItem.title = "Welcome"
    }
    
    private func hidePurchased() {
        let manager = InAppPurchasesManager.shared()!;
        let hasProMode = manager.hasProMode()
        let hasAdRemoval = manager.hasAdRemovalFeature()
        let hasTorch = manager.hasTorchFeature()
        let hasVideo = manager.hasVideoRecordingFeature()
        
        // If user has Pro bundle (Product 06), hide all other purchase buttons
        if hasProMode {
            disableAdsButton.isHidden = true
            enableTorchButton.isHidden = true
            enableVideoOnlyButton.isHidden = true
            buyProButton.isHidden = true
            restorePurchaseButton.isHidden = true
            
            welcomeDescLabel.text = "Thanks for your support! We are working on new features for you!"
            showReviewButtonIfAppropriate()
            return
        }
        
        // Individual feature hiding
        if hasAdRemoval {
            disableAdsButton.isHidden = true
        }
        
        if hasTorch {
            enableTorchButton.isHidden = true
        }
        
        if hasVideo {
            enableVideoOnlyButton.isHidden = true
        }
        
        // Show thank you message and review button if user bought ANY feature
        if hasAdRemoval || hasTorch || hasVideo || hasProMode {
            welcomeDescLabel.text = "Thanks for your support! We are working on new features for you!"
            showReviewButtonIfAppropriate()
        } else {
            reviewAppButton.isHidden = true
        }
    }
    
    private func showReviewButtonIfAppropriate() {
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
    }
    
    private func updateButtonTitlesAndPrices() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            for product in self.productsArray {
                let price = self.formatPrice(product.price, locale: product.priceLocale)
                let title = "\(product.localizedTitle) \(price)"
                
                switch product.productIdentifier {
                case disableAdsPID:
                    self.disableAdsButton.setTitle(title, for: .normal)
                case enableVideoPID:
                    self.buyProButton.setTitle(title, for: .normal)
                case enableTorchPID:
                    self.enableTorchButton.setTitle(title, for: .normal)
                case enableVideoOnlyPID:
                    self.enableVideoOnlyButton.setTitle(title, for: .normal)
                default:
                    break
                }
            }
        }
    }
    
    private func formatPrice(_ price: NSDecimalNumber, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        return formatter.string(from: price) ?? "$0.00"
    }
}
