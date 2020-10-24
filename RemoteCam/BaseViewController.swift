//
//  DeviceViewController.swift
//  Actors
//
//  Created by Dario Lencina on 11/1/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import GoogleMobileAds
import Theater
import UserMessagingPlatform

public func showError(_ error: String) {
    ^{
        let alert = UIAlertController(
            title: NSLocalizedString("Error", comment: ""),
            message: error
        )
        alert.simpleOkAction()
        alert.show(true)
    }
}

/**
This UIViewController provides a preconfigured banner and some NSLayoutConstraints to show/hide the banner.
Users must subclass to integrate this into their projects
*/

public class iAdViewController: UIViewController, GADBannerViewDelegate {
    let AdBanner: GADBannerView = GADBannerView()
    var AdConstraints: [NSLayoutConstraint]?

    @IBOutlet weak var bannerView: UIView!
    @IBOutlet weak var bottomBannerConstraint: NSLayoutConstraint?
    @IBOutlet weak var bannerHeight: NSLayoutConstraint?

    private func setupAdNetwork() {
        let parameters = UMPRequestParameters()
        // Set tag for under age of consent. Here NO means users are not under age.
        parameters.tagForUnderAgeOfConsent = false

        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(
                with: parameters,
                completionHandler: { [self] error in
                    if error == nil {
                        if UMPConsentInformation.sharedInstance.formStatus == UMPFormStatus.available {
                            loadForm()
                        } else {
                            startShowingAds()
                        }
                    }
                })
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        self.shouldHideBanner()
    
        if !InAppPurchasesManager.shared().didUserBuyRemoveiAdsFeature() && !InAppPurchasesManager.shared().didUserBuyRemoveiAdsFeatureAndEnableVideo() {
            self.setupAdNetwork()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(iAdViewController.ShouldHideAds(notification:)), name: NSNotification.Name(rawValue: Constants.removeAds()), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(iAdViewController.ShouldHideAds(notification:)), name: NSNotification.Name(rawValue: Constants.removeAdsAndEnableVideo()), object: nil)
    }

    func shouldHideBanner() {
        UIView.animate(withDuration: 0.3) { () -> Void in
            self.bottomBannerConstraint!.constant = 40
            self.view.layoutSubviews()
        }
    }

    func shouldShowBanner() {
        UIView.animate(withDuration: 0.3) { () -> Void in
            let value = 40 - self.AdBanner.frame.size.height
            self.bottomBannerConstraint!.constant = value
            self.view.layoutSubviews()
        }
    }

    @objc func ShouldHideAds(notification: NSNotification) {
        DispatchQueue.main.async {
            self.turnOffAds()
        }
    }

    func turnOffAds() {
        self.bannerView.removeConstraints(self.iAdsLayoutConstrains())
        self.shouldHideBanner()
        self.AdBanner.removeFromSuperview()
        self.AdBanner.delegate = nil
    }

    func iAdsLayoutConstrains() -> [NSLayoutConstraint] {
        if AdConstraints != nil {
            return AdConstraints!
        }

        let leading = NSLayoutConstraint(item: AdBanner, attribute: .leading, relatedBy: .equal, toItem: self.bannerView, attribute: .leading, multiplier: 1, constant: 0)

        let top = NSLayoutConstraint(item: AdBanner, attribute: .top, relatedBy: .equal, toItem: self.bannerView, attribute: .top, multiplier: 1, constant: 0)

        let width = NSLayoutConstraint(item: AdBanner, attribute: .width, relatedBy: .equal, toItem: self.bannerView, attribute: .width, multiplier: 1, constant: 0)

        self.AdConstraints = [top, width, leading]
        return self.AdConstraints!
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    /// Tells the delegate that an ad request successfully received an ad. The delegate may want to add
    /// the banner view to the view hierarchy if it hasn't been added yet.
    public func adViewDidReceiveAd(_ bannerView: GADBannerView) {
        self.shouldShowBanner()
    }

    /// Tells the delegate that an ad request failed. The failure is normally due to network
    /// connectivity or ad availablility (i.e., no fill).
    public func adView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: GADRequestError) {
        self.shouldHideBanner()
    }

    public func adViewWillPresentScreen(_ bannerView: GADBannerView) {

    }

    public func adViewDidDismissScreen(_ bannerView: GADBannerView) {
        self.shouldHideBanner()
    }

    func loadForm() {
        UMPConsentForm.load(
                completionHandler: { form, loadError in
                    if loadError != nil {
                    } else {
                        form?.present(
                                from: self,
                                completionHandler: { [self] dismissError in
                                    if UMPConsentInformation.sharedInstance.consentStatus == UMPConsentStatus.obtained {
                                        self.startShowingAds()
                                    }
                                })
                    }
                })
    }

    func startShowingAds() {
        self.AdBanner.adUnitID = "ca-app-pub-4832821923197585/2168670673"
        self.AdBanner.rootViewController = self
        self.AdBanner.delegate = self
        self.AdBanner.adSize = GADAdSize(size: self.bannerView.frame.size, flags: 0)
        self.AdBanner.frame = CGRect(x: 0, y: 0, width: bannerView.frame.width, height: bannerView.frame.height)
        self.bannerView.addSubview(self.AdBanner)
        self.bannerView.addConstraints(self.iAdsLayoutConstrains())
        self.shouldHideBanner()
        self.AdBanner.isAutoloadEnabled = true
    }
}
