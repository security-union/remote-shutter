//
//  InAppPurchasesManager.h
//  Clapmera
//
//  Created by Dario Lencina on 5/4/12.
//  Copyright (c) 2012 BlackFireApps. All rights reserved.
//
/*
 * @description: The job of this guy is to make sure that our controllers are clean from purchases code, all the request to the AppStore should go through this
 guy.
 
 This guy talks to the Controllers through Notifications, those notifications are defined in the SharedControllers
 */

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
#import "PurchasesRestorer.h"
#import "Constants.h"

@class InAppPurchasesManager;

typedef void(^InAppPurchasesManagerHandler)(InAppPurchasesManager *purchasesManager, NSError *error);

@interface InAppPurchasesManager : NSObject <SKProductsRequestDelegate, SKPaymentTransactionObserver, PurchasesRestorerDelegate> {
    NSArray *products;
}
@property(nonatomic, strong) NSArray *products;
@property(nonatomic, copy) InAppPurchasesManagerHandler productRefreshHandler;
@property(nonatomic, copy) InAppPurchasesManagerHandler buyProductHandler;
@property(nonatomic, strong) PurchasesRestorer *purchasesRestorer;

+ (InAppPurchasesManager *)sharedManager;

- (void)userWantsToBuyFeature:(NSString *)identifier
                  withHandler:(InAppPurchasesManagerHandler)handler;

- (SKProduct *)productWithIdentifier:(NSString *)identifier;

#pragma mark - Centralized Feature Availability (Recommended API)
// These methods check both Pro bundle and individual purchases
// Use these instead of checking individual purchase methods directly

- (BOOL)hasAdRemovalFeature;
- (BOOL)hasVideoRecordingFeature;
- (BOOL)hasTorchFeature;
- (BOOL)hasProMode;

#pragma mark - Individual Purchase Status (Internal Use)
// These methods check specific purchases only
// Use centralized feature methods above instead

- (BOOL)didUserBuyRemoveiAdsFeature;

- (BOOL)didUserBuyProMode;

- (BOOL)didUserBuyEnableTorchFeature;

- (BOOL)didUserBuyEnableVideoOnlyFeature;

- (BOOL)didUserBuyProBundle;

- (void)setDidYserBuyProMode:(BOOL)feature;

- (void)setDidUserBuyEnableTorchFeature:(BOOL)feature;

- (void)setDidUserBuyEnableVideoOnlyFeature:(BOOL)feature;

- (void)reloadProductsWithHandler:(InAppPurchasesManagerHandler)handler;

- (NSNumberFormatter *)currencyFormatter;

- (void)restorePurchasesWithHandler:(InAppPurchasesManagerHandler)handler;

- (BOOL)isInProgress;

@end
