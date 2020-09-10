
#import <StoreKit/StoreKit.h>

static NSString * const didBuyRemoveiAdsFeature= @"didBuyRemoveiAdsFeature";
static NSString * const didBuyFlashAndFrontCamera= @"didBuyFlashAndFrontCamera";
static NSString * const DidRestoredPurchasesInDevice= @"DidRestoredPurchasesInDevice";
static NSString * const RemoveiAdsFeatureIdentifier= @"05";

@interface PurchasesRestorer : NSObject <SKPaymentTransactionObserver> {
    NSMutableArray * restoredLaws;
    NSInteger numberOfLawsToRestore;
	id __unsafe_unretained delegate;
	NSMutableArray * queriesArray;
    UIAlertView * progressAlert;
    UIProgressView * progressView;
}

-(void)showSyncError:(NSError *)error;
-(void)createProgressionAlertWithMessage:(NSString *)message withActivity:(BOOL)activity;

@property(nonatomic, strong)UIProgressView * progressView;
@property (strong) NSMutableArray * queriesArray;
@property (unsafe_unretained) id delegate;
@property(nonatomic, assign)    NSInteger numberOfLawsToRestore;
@property(nonatomic, strong) NSMutableArray * restoredLaws;

-(void)syncDBWithCompletedTransactionsQueue:(SKPaymentQueue *)queue;
-(void)showAlertToRestore;

@end

@protocol PurchasesRestorerDelegate <NSObject>
@required
    -(void)didEndedSync:(PurchasesRestorer *)restorer;
    -(void)errorHappened:(NSError *)error withRestorer:(PurchasesRestorer *)restorer ;
    -(void)setDidUserBuyRemoveiAdsFeatures:(BOOL)feature;
@end

