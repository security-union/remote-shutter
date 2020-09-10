//
//  InAppPurchasesManager.m
//  Clapmera
//
//  Created by Dario Lencina on 5/4/12.
//  Copyright (c) 2012 BlackFireApps. All rights reserved.
//

#import "InAppPurchasesManager.h"

static InAppPurchasesManager * _manager= nil;

@implementation InAppPurchasesManager{
    SKProductsRequest * req;

}
@synthesize products;

+(InAppPurchasesManager *)sharedManager{
    if(_manager==nil){
        _manager= [[InAppPurchasesManager alloc] init];
    }
    return _manager;
};

-(BOOL)isInProgress {
    NSArray * transactions=[[SKPaymentQueue defaultQueue] transactions];
    BOOL isInProgress=transactions!=nil;
    if(isInProgress){
        isInProgress = [transactions count] > 0;
    }
    return isInProgress;
}

-(void)userWantsToBuyRemoveiAdsFeature:(InAppPurchasesManagerHandler)handler {
        self.buyIAdsHandler=handler;
    if(self.products){
        if([self.products count]<=0){
            return;
        }
        SKProduct * product= [self productWithIdentifier:RemoveiAdsFeatureIdentifier];
        SKPayment * payment= [SKPayment paymentWithProduct:product];
        SKPaymentQueue * queue= [SKPaymentQueue defaultQueue];
        [queue addPayment:payment];
        [queue addTransactionObserver:self];
    }else{
        if(self.productRefreshHandler){
            [self reloadProductsWithHandler:self.productRefreshHandler];
        }else{
            [self reloadProductsWithHandler:NULL];
        }
    }
};


-(SKProduct *)productWithIdentifier:(NSString *)identifier {
    if([self.products count]<=0) return nil;
    
    NSArray * filteredArray=[self.products filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SKProduct * evaluatedObject, NSDictionary *bindings) {
        return [evaluatedObject.productIdentifier isEqualToString:identifier];
    }]];
    return filteredArray[0];
}

-(BOOL)didUserBuyRemoveiAdsFeature {
    BOOL didBuyiAds=FALSE;
    NSUserDefaults * defaults= [NSUserDefaults standardUserDefaults];
    if([defaults objectForKey:didBuyRemoveiAdsFeature]){
        didBuyiAds= [defaults boolForKey:didBuyRemoveiAdsFeature];
    }
    return didBuyiAds;
};

-(void)setDidUserBuyRemoveiAdsFeatures:(BOOL)feature {
    if(feature){
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ShouldHideiAds" object:nil];
    }
    NSUserDefaults * defaults= [NSUserDefaults standardUserDefaults];
    [defaults setBool:feature forKey:didBuyRemoveiAdsFeature];
    [defaults synchronize];
}

-(void)reloadProductsWithHandler:(InAppPurchasesManagerHandler)handler {
    if(req){
        req.delegate = nil;
        req = nil;
    }
    self.productRefreshHandler = handler;
    NSSet * _products = [NSSet setWithObjects:RemoveiAdsFeatureIdentifier,nil];
    req= [[SKProductsRequest alloc] initWithProductIdentifiers:_products];
    [req setDelegate:self];
    [req start];
}

#pragma -
#pragma StoreKit Delegate

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response{
    if(response.products){
        self.products= response.products;
    }
    NSNumberFormatter *currencyStyle = [self currencyFormatter];
        	
    for(SKProduct * product in response.products){
        [currencyStyle setLocale:product.priceLocale];
       // BFLog(@"product %@ price %@ localizedPrice %@ %@", product.productIdentifier, product.price, [currencyStyle stringFromNumber:product.price], product.localizedTitle);
    }
    if(self.productRefreshHandler) self.productRefreshHandler(self, nil);
}

-(NSNumberFormatter *)currencyFormatter{
    NSNumberFormatter *currencyStyle = [[NSNumberFormatter alloc] init];
    [currencyStyle setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [currencyStyle setNumberStyle:NSNumberFormatterCurrencyStyle];
    return currencyStyle;
}

-(void)lacompraFallo:(NSError *)error{
    if(self.buyIAdsHandler)
        self.buyIAdsHandler(self, error);
}

-(void)request:(SKRequest *)request didFailWithError:(NSError *)error  {
    if(self.productRefreshHandler) self.productRefreshHandler(self, error);
}  

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions{

	for(SKPaymentTransaction * transaction in transactions){
        switch ([transaction transactionState]) {
            case SKPaymentTransactionStatePurchasing:

                break;
            case SKPaymentTransactionStateRestored:                
            case SKPaymentTransactionStatePurchased:{
                [queue finishTransaction:transaction];
                if([[[transaction payment] productIdentifier] isEqualToString:RemoveiAdsFeatureIdentifier]){
                    [self setDidUserBuyRemoveiAdsFeatures:TRUE];
                    if(self.buyIAdsHandler)
                        self.buyIAdsHandler(self, nil);
                }
                }
                break;
            case SKPaymentTransactionStateFailed:
                [queue finishTransaction:transaction];
                if([[[transaction payment] productIdentifier] isEqualToString:RemoveiAdsFeatureIdentifier]){
                    if(self.buyIAdsHandler)
                        self.buyIAdsHandler(self, transaction.error);
                }

                break;
                
            default:
                break;
        }           
	}
}

-(void)restorePurchasesWithHandler:(InAppPurchasesManagerHandler)handler {
    self.buyIAdsHandler=handler;
    PurchasesRestorer * _sync= [PurchasesRestorer new];
    self.purchasesRestorer= _sync;
    self.purchasesRestorer.delegate=self;
    [self.purchasesRestorer showAlertToRestore];
}

-(void)errorHappened:(NSError *)error withRestorer:(PurchasesRestorer *)restorer {
    self.buyIAdsHandler(self, error);
}

-(void)didEndedSync:(PurchasesRestorer *)restorer {
    [self setPurchasesRestorer:nil];
    self.buyIAdsHandler(self, nil);
}


@end
