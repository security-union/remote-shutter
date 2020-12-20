#import "CMConfigurationsViewController.h"
#import "InAppPurchasesManager.h"

#define kiAdsFeatureInstalled NSLocalizedString(@"Ads Removed",nil);
#define kiAdsRemovedANdVideoEnabledInstalled NSLocalizedString(@"Ads Removed and video enabled",nil);

#import "AcknowledgmentsViewController.h"

@interface CMConfigurationsViewController ()

@end

@implementation CMConfigurationsViewController

#pragma mark -
#pragma mark View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData:) name:@"AppDidBecomeActive" object:nil];
    [[[self navigationController] navigationBar] setPrefersLargeTitles: TRUE];
    [[[self navigationController] navigationBar] setHidden:FALSE];
    self.tableViewCells = @[@[self.disableAdsAndEnableVideoRecording, self.disableiAds, self.restorePurchases], @[self.contactSupport, self.blackFireApps, self.theaterFramework, self.acknowledgments, self.sourceCode, self.versionCell]];
    self.navigationItem.title = NSLocalizedString(@"Configuration", comment: "");
    
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:FALSE];
    [[self tableView] reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([self isBeingDismissed] || [self isMovingFromParentViewController])
        [self.navigationController setNavigationBarHidden:TRUE];
}

- (void)reloadData:(NSNotification *)notif {
    [self.tableView reloadData];
}

- (void)showAcknowledgments {
    AcknowledgmentsViewController *acknowledgments = [AcknowledgmentsViewController new];
    [acknowledgments setURL:[[NSBundle mainBundle] URLForResource:@"Acknowledgments.html" withExtension:nil]];
    [acknowledgments setTitle:NSLocalizedString(@"Acknowledgments", nil)];
    [self.navigationController pushViewController:acknowledgments animated:TRUE];
}

#pragma mark -
#pragma mark UITableView Stuff

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.tableViewCells[indexPath.section][indexPath.row];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return NSLocalizedString(@"Upgrades", nil);
        default:
            return NSLocalizedString(@"INFORMATION", nil);
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self.tableViewCells count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.tableViewCells[section] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = self.tableViewCells[indexPath.section][indexPath.row];
    return [cell frame].size.height;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:TRUE];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    InAppPurchasesManager *manager = [InAppPurchasesManager sharedManager];
    if ([cell isEqual:self.disableiAds]) {
        if ([manager didUserBuyRemoveiAdsFeature])
            return;
        if ([[[cell textLabel] text] isEqualToString:NSLocalizedString(@"Tap to refresh from AppStore.", nil)]) {
            [manager reloadProductsWithHandler:^(InAppPurchasesManager *purchasesManager, NSError *error) {
                if (!error) [self fillRestoreiAdsRow];
            }];
        } else {
            [manager userWantsToBuyFeature:RemoveiAdsFeatureIdentifier withHandler:^(InAppPurchasesManager *purchasesManager, NSError *error) {
                if (error) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"InApp Purchases:", nil) message:[error localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *_Nonnull action) {
                        [alert dismissViewControllerAnimated:TRUE completion:NULL];
                    }]];

                    [self presentViewController:alert animated:TRUE completion:NULL];
                } else {
                    [self fillRestoreiAdsRow];
                    [[NSNotificationCenter defaultCenter] postNotificationName:Constants.RemoveAds object:nil];
                }
            }];
        }
    } else if ([cell isEqual:self.disableAdsAndEnableVideoRecording]) {
        if ([manager didUserBuyRemoveiAdsFeatureAndEnableVideo])
            return;
        if ([[[cell textLabel] text] isEqualToString:NSLocalizedString(@"Tap to refresh from AppStore.", nil)]) {
            [manager reloadProductsWithHandler:^(InAppPurchasesManager *purchasesManager, NSError *error) {
                if (!error) [self fillRestoreRemoveAdsAndEnableVideoRow];
            }];
        } else {
            [manager userWantsToBuyFeature:RemoveAdsAndEnableVideoIdentifier withHandler:^(InAppPurchasesManager *purchasesManager, NSError *error) {
                if (error) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"InApp Purchases:", nil) message:[error localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *_Nonnull action) {
                        [alert dismissViewControllerAnimated:TRUE completion:NULL];
                    }]];

                    [self presentViewController:alert animated:TRUE completion:NULL];
                } else {
                    [self fillRestoreRemoveAdsAndEnableVideoRow];
                    [[NSNotificationCenter defaultCenter] postNotificationName:Constants.RemoveAdsAndEnableVideo object:nil];
                }
            }];
        }
    } else if ([cell isEqual:self.restorePurchases]) {
        [self restoreThePurchases];
    } else if ([cell isEqual:self.acknowledgments]) {
        [self showAcknowledgments];
    } else if ([cell isEqual:self.blackFireApps]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://securityunion.dev"] options:@{} completionHandler:nil];
    } else if ([cell isEqual:self.theaterFramework]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/security-union/Theater"] options:@{} completionHandler:nil];
    } else if ([cell isEqual:self.contactSupport]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"mailto:support@securityunion.dev"] options:@{} completionHandler:nil];
    } else if ([cell isEqual:self.sourceCode]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/security-union/remote-shutter"] options:@{} completionHandler:nil];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([cell isEqual:self.disableiAds]) {
        InAppPurchasesManager *manager = [InAppPurchasesManager sharedManager];
        NSArray *products = [manager products];
        if ([products count] > 0) {
            [self fillRestoreiAdsRow];
        } else {
            [manager reloadProductsWithHandler:^(InAppPurchasesManager *purchasesManager, NSError *error) {
                if (!error) {
                    [self fillRestoreiAdsRow];
                }
            }];
        }
    } else if ([cell isEqual:self.disableAdsAndEnableVideoRecording]) {
        InAppPurchasesManager *manager = [InAppPurchasesManager sharedManager];
        NSArray *products = [manager products];
        if ([products count] > 0) {
            [self fillRestoreRemoveAdsAndEnableVideoRow];
        } else {
            [manager reloadProductsWithHandler:^(InAppPurchasesManager *purchasesManager, NSError *error) {
                if (!error) {
                    [self fillRestoreRemoveAdsAndEnableVideoRow];
                }
            }];
        }
    } else if ([cell isEqual:self.versionCell]) {
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        NSString *bundle = [infoDictionary objectForKey:@"CFBundleVersion"];
        NSString *shortVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
        self.versionCell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@) ", shortVersion, bundle];
    }
}

- (void)fillRestoreiAdsRow {
    dispatch_async(dispatch_get_main_queue(), ^{
        InAppPurchasesManager *manager = [InAppPurchasesManager sharedManager];
        NSArray *products = [manager products];
        if ([manager didUserBuyRemoveiAdsFeature]) {
            self.disableiAds.textLabel.text = kiAdsFeatureInstalled;
            self.disableiAds.detailTextLabel.text = @"";
            [self.disableiAds setNeedsDisplay];
        } else if ([products count] > 0) {
            SKProduct *disableiAdsProduct = [manager productWithIdentifier:RemoveiAdsFeatureIdentifier];
            [[self.disableiAds textLabel] setText:[disableiAdsProduct localizedTitle]];
            NSString *localizedPrice = [[[InAppPurchasesManager sharedManager] currencyFormatter] stringFromNumber:disableiAdsProduct.price];
            [[self.disableiAds detailTextLabel] setText:localizedPrice];
            [self.disableiAds setNeedsLayout];
        }
    });
}
    
- (void)fillRestoreRemoveAdsAndEnableVideoRow {
    dispatch_async(dispatch_get_main_queue(), ^{
        InAppPurchasesManager *manager = [InAppPurchasesManager sharedManager];
        NSArray *products = [manager products];
        UITableViewCell * disableAdsAndEnableVideo = self.disableAdsAndEnableVideoRecording;
        if ([manager didUserBuyRemoveiAdsFeatureAndEnableVideo]) {
            disableAdsAndEnableVideo.textLabel.text = kiAdsRemovedANdVideoEnabledInstalled;
            disableAdsAndEnableVideo.detailTextLabel.text = @"";
        } else if ([products count] > 0) {
            SKProduct *disableAdsAndEnableVideoProduct = [manager productWithIdentifier:RemoveAdsAndEnableVideoIdentifier];
            if (disableAdsAndEnableVideoProduct == nil) {
                return;
            }
            [[disableAdsAndEnableVideo textLabel] setText:[disableAdsAndEnableVideoProduct localizedTitle]];
            NSString *localizedPrice = [[[InAppPurchasesManager sharedManager] currencyFormatter] stringFromNumber:disableAdsAndEnableVideoProduct.price];
            [[disableAdsAndEnableVideo detailTextLabel] setText:localizedPrice];
        }
        [disableAdsAndEnableVideo setNeedsDisplay];
    });
}

#pragma mark -
#pragma mark Local Storage.

+ (BOOL)firstRun {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    NSString *firstRunFlag = [NSString stringWithFormat:@"%@_firstRun", version];
    if ([userDefaults objectForKey:firstRunFlag]) {
        return [userDefaults boolForKey:firstRunFlag];
    }
    return TRUE;
}

+ (void)setFirstRunFlag:(BOOL)flag {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    NSString *firstRunFlag = [NSString stringWithFormat:@"%@_firstRun", version];
    [userDefaults setBool:flag forKey:firstRunFlag];
    [userDefaults synchronize];
}

- (void)restoreThePurchases {
    [[InAppPurchasesManager sharedManager] restorePurchasesWithHandler:^(InAppPurchasesManager *purchasesManager, NSError *error) {
        if (!error) {
            [self fillRestoreiAdsRow];
        }
    }];
}

@end
