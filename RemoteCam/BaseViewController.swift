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

/**
This UIViewController provides a preconfigured banner and some NSLayoutConstraints to show/hide the banner.
Users must subclass to integrate this into their projects
*/

public class iAdViewController: UIViewController, GADBannerViewDelegate {
    let iAdBanner: GADBannerView = GADBannerView()
    var iAdConstraints: [NSLayoutConstraint]?

    @IBOutlet weak var bannerView: UIView!
    @IBOutlet weak var bottomBannerConstraint: NSLayoutConstraint?
    @IBOutlet weak var bannerHeight: NSLayoutConstraint?

    private func setupiAdNetwork() {
        iAdBanner.adUnitID = "ca-app-pub-4832821923197585/2168670673"
        iAdBanner.rootViewController = self
        iAdBanner.delegate = self
        iAdBanner.adSize = GADAdSize(size: bannerView.frame.size, flags: 0)
        iAdBanner.frame = CGRect(x: 0, y: 0, width: bannerView.frame.width, height: bannerView.frame.height)
        self.bannerView.addSubview(iAdBanner)
        self.bannerView.addConstraints(self.iAdsLayoutConstrains())
        self.shouldHideBanner()
        iAdBanner.isAutoloadEnabled = true
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        if !InAppPurchasesManager.shared().didUserBuyRemoveiAdsFeature() {
            self.setupiAdNetwork()
        } else {
            self.shouldHideBanner()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(iAdViewController.ShouldHideiAds(notification:)), name: NSNotification.Name(rawValue: "ShouldHideiAds"), object: nil)
    }

    func shouldHideBanner() {
        UIView.animate(withDuration: 0.3) { () -> Void in
            self.bottomBannerConstraint!.constant = 40
            self.view.layoutSubviews()
        }
    }

    func shouldShowBanner() {
        UIView.animate(withDuration: 0.3) { () -> Void in
            let value = 40 - self.iAdBanner.frame.size.height
            self.bottomBannerConstraint!.constant = value
            self.view.layoutSubviews()
        }
    }

    @objc func ShouldHideiAds(notification: NSNotification) {
        ^{
            self.turnOffiAds()
        }
    }

    func turnOffiAds() {
        self.bannerView.removeConstraints(self.iAdsLayoutConstrains())
        self.shouldHideBanner()
        self.iAdBanner.removeFromSuperview()
        self.iAdBanner.delegate = nil
    }

    func iAdsLayoutConstrains() -> [NSLayoutConstraint] {
        if iAdConstraints != nil {
            return iAdConstraints!
        }

        let leading = NSLayoutConstraint(item: iAdBanner, attribute: .leading, relatedBy: .equal, toItem: self.bannerView, attribute: .leading, multiplier: 1, constant: 0)

        let top = NSLayoutConstraint(item: iAdBanner, attribute: .top, relatedBy: .equal, toItem: self.bannerView, attribute: .top, multiplier: 1, constant: 0)

        let width = NSLayoutConstraint(item: iAdBanner, attribute: .width, relatedBy: .equal, toItem: self.bannerView, attribute: .width, multiplier: 1, constant: 0)

        self.iAdConstraints = [top, width, leading]
        return self.iAdConstraints!
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

}
