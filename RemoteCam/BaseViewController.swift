//
//  DeviceViewController.swift
//  Actors
//
//  Created by Dario Lencina on 11/1/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import iAd
import Theater

/**
This UIViewController provides a preconfigured banner and some NSLayoutConstraints to show/hide the banner.
Users must subclass to integrate this into their projects
*/

public class iAdViewController : UIViewController, ADBannerViewDelegate {
    let iAdBanner : ADBannerView = ADBannerView()
    var iAdConstraints : [NSLayoutConstraint]?
    
    @IBOutlet weak var bannerView : UIView!
    @IBOutlet weak var bottomBannerConstraint : NSLayoutConstraint?
    @IBOutlet weak var bannerHeight : NSLayoutConstraint?
    
    private func setupiAdNetwork() {
        iAdBanner.delegate = self;
        iAdBanner.translatesAutoresizingMaskIntoConstraints = false
        self.bannerView.addSubview(iAdBanner)
        self.bannerView.addConstraints(self.iAdsLayoutConstrains())
        self.layoutBanners()
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
    
    func layoutBanners() {
        if iAdBanner.isBannerLoaded {
            self.shouldShowBanner()
        }else{
            self.shouldHideBanner()
        }
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
    
    @objc func ShouldHideiAds(notification : NSNotification) {
        ^{self.turnOffiAds()}
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
    
    
    public func bannerViewDidLoadAd(banner: ADBannerView!) {
        self.layoutBanners()
    }
    
    public func bannerView(_ banner: ADBannerView, didFailToReceiveAdWithError error: Error) {
        self.shouldHideBanner()
    }
    
    public func bannerViewActionShouldBegin(_ banner: ADBannerView, willLeaveApplication willLeave: Bool) -> Bool {
        return true
    }

    public func bannerViewActionDidFinish(_ banner: ADBannerView) {
        self.shouldHideBanner()
    }
    
}
