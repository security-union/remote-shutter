
#import "PurchasesRestorer.h"

@implementation PurchasesRestorer
@synthesize restoredLaws, numberOfLawsToRestore;
@synthesize delegate, queriesArray, progressView;

#pragma -
#pragma Constructor

- (id)init{
	self= [super init];
	if(self){
        
		self.queriesArray= [NSMutableArray array];
	}
	return self;
}


#pragma mark - UIAlertViewDelegate


-(void)showSyncError:(NSError *)error{
    NSString * message= [NSString stringWithFormat:NSLocalizedString(@"%@, ¿Desea intentar nuevamente?",nil), [error localizedDescription]];
    UIAlertView * alert= [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"AppName", nil) message:message delegate:self cancelButtonTitle:NSLocalizedString(@"Si", nil) otherButtonTitles:@"No", nil];
    [progressAlert dismissWithClickedButtonIndex:0 animated:TRUE];
    [alert setDelegate:self];
    [alert show];
}

- (void) createProgressionAlertWithMessage:(NSString *)message withActivity:(BOOL)activity
{
    progressAlert = [[UIAlertView alloc] initWithTitle: message
                                               message: NSLocalizedString(@"Espere...", nil)
                                              delegate: nil
                                     cancelButtonTitle: nil
                                     otherButtonTitles: nil];
    
    
    // Create the progress bar and add it to the alert
    if (activity) {
        UIActivityIndicatorView *  activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        activityView.frame = CGRectMake(139.0f-18.0f, 80.0f, activityView.frame.size.width, activityView.frame.size.height);
        [progressAlert addSubview:activityView];
        [activityView startAnimating];
    } else {
        UIProgressView * _progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(30.0f, 80.0f, 225.0f, 90.0f)];
        [progressAlert addSubview:_progressView];
        [_progressView setProgressViewStyle: UIProgressViewStyleBar];
        self.progressView=_progressView;
    }
    [progressAlert show];
}

-(void)errorHappened:(NSError *)error withRestorer:(PurchasesRestorer *)restorer{
    //BFLog(@"error %@", error);
    [progressAlert dismissWithClickedButtonIndex:1 animated:TRUE];
}

-(void)syncDBWithCompletedTransactionsQueue:(SKPaymentQueue *)queue{
    //BFLog(@"queue %@", queue.transactions);
    [queue removeTransactionObserver:self];
    progressAlert.delegate=nil;
    [delegate didEndedSync:self];
    
}


-(void)showAlertToRestore{
    NSString * message= [NSString stringWithFormat:NSLocalizedString(@"¿Desea sincronizar su %@ con los productos previamente comprados en la AppStore (gratuitamente)?",nil), [[UIDevice currentDevice] model]];
    UIAlertView * alert= [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"AppName", nil) message:message delegate:self cancelButtonTitle:NSLocalizedString(@"Si", nil) otherButtonTitles:@"No", nil];
    [alert setDelegate:self];
    [alert show];
}

-(void)processTransactions:(NSArray *)transactions{
    if(transactions==nil || [transactions count]<=0)
        return;
    
    //BFLog(@"number of transactions %lu", (unsigned long)[transactions count]);
    for(SKPaymentTransaction * transaction in transactions){
        switch ([transaction transactionState]) {
            case SKPaymentTransactionStateRestored:
                //BFLog(@"SKPaymentTransactionStateRestored");
                //BFLog(@"producto %@", transaction.payment.productIdentifier);
                [self.delegate setDidUserBuyRemoveiAdsFeatures:TRUE];
                break;
                
            default:
                break;
        }
    }
    
    [progressAlert dismissWithClickedButtonIndex:1 animated:TRUE];
}

-(void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue{
    [progressView setProgress:0.5];
    NSUserDefaults * userDefs= [NSUserDefaults standardUserDefaults];
    [userDefs setBool:TRUE forKey:DidRestoredPurchasesInDevice];
    [userDefs synchronize];
    [queue removeTransactionObserver:self];
    
    NSArray * transactions= queue.transactions;
    [self processTransactions:transactions];
    [self syncDBWithCompletedTransactionsQueue:queue];
}

-(void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error{
    [self showSyncError:error];
}

-(void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions{
    [progressView setProgress:0.5];
    NSUserDefaults * userDefs= [NSUserDefaults standardUserDefaults];
    [userDefs setBool:TRUE forKey:DidRestoredPurchasesInDevice];
    [userDefs synchronize];
    [queue removeTransactionObserver:self];
    [self processTransactions:transactions];
}

#pragma mark - UIAlertViewDelegate

-(void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex{
    if (buttonIndex==0) {
        SKPaymentQueue * queue= [SKPaymentQueue defaultQueue];
        [queue restoreCompletedTransactions];
        [queue addTransactionObserver:self];
        [self createProgressionAlertWithMessage:NSLocalizedString(@"Reestableciendo compras", nil) withActivity:TRUE];
    }else{
        SKPaymentQueue * queue= [SKPaymentQueue defaultQueue];
        [queue removeTransactionObserver:self];
        [delegate didEndedSync:self];
    }
}


@end
