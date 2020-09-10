#import "CMConfigurationsViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "InAppPurchasesManager.h"
#define kiAdsFeatureInstalled NSLocalizedString(@"iAds Removed.",nil);
#import "AcknowledgmentsViewController.h"

@interface CMConfigurationsViewController ()

@end

@implementation CMConfigurationsViewController

#pragma mark -
#pragma mark View Lifecycle

- (void)viewDidLoad{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData:)  name:@"AppDidBecomeActive" object:nil];
    [self setTitle:NSLocalizedString(@"Settings", nil)];
    [[[self navigationController] navigationBar] setHidden:FALSE];
    self.tableViewCells=@[@[ self.disableiAds, self.restorePurchases], @[self.acknowledgments, self.versionCell, self.blackFireApps, self.theaterFramework]];
}

-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:FALSE];
    [[self tableView] reloadData];
}

-(void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    if ([self isBeingDismissed] || [self isMovingFromParentViewController])
        [self.navigationController setNavigationBarHidden:TRUE];
}

- (void)viewDidUnload{
    [self setTableView:nil];
    [super viewDidUnload];
}

-(void)reloadData:(NSNotification *)notif{
    [self.tableView reloadData];
}

-(void)showAcknowledgments{
    AcknowledgmentsViewController * acknowledgments= [AcknowledgmentsViewController new];
    [acknowledgments setURL:[[NSBundle mainBundle] URLForResource:@"Acknowledgments.html" withExtension:nil]];
    [acknowledgments setTitle:NSLocalizedString(@"Acknowledgments", nil)];
    [self.navigationController pushViewController:acknowledgments animated:TRUE];
}

#pragma mark -
#pragma mark UITableView Stuff

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    return self.tableViewCells[indexPath.section][indexPath.row];
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{
    NSString * title=nil;
    if (section == 0){
            title= NSLocalizedString(@"Upgrades", nil);
    }else if(section == 1){
        title= nil;
    }
    return title;
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    return [self.tableViewCells count];
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return [self.tableViewCells[section] count];
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    UITableViewCell * cell = self.tableViewCells[indexPath.section][indexPath.row];
    return  [cell frame].size.height;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [tableView deselectRowAtIndexPath:indexPath animated:TRUE];
    UITableViewCell * cell= [tableView cellForRowAtIndexPath:indexPath];
    InAppPurchasesManager * manager= [InAppPurchasesManager sharedManager];
    if ([cell isEqual:self.disableiAds]){
        if([manager didUserBuyRemoveiAdsFeature])
            return;
        if([[[cell textLabel] text] isEqualToString:NSLocalizedString(@"Tap to refresh from AppStore.", nil)]){
            [manager reloadProductsWithHandler:^(InAppPurchasesManager *purchasesManager, NSError *error) {
                if(!error) [self fillRestoreiAdsRow];
            }];
        }else{
            [manager userWantsToBuyRemoveiAdsFeature:^(InAppPurchasesManager *purchasesManager, NSError *error) {
                if(error){
                    UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"InApp Purchases:",nil) message:[error localizedDescription] preferredStyle: UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [alert dismissViewControllerAnimated:TRUE completion:NULL];
                    }]];
                    
                    [self presentViewController:alert animated:TRUE completion:NULL];
                }else{
                    [self fillRestoreiAdsRow];
                    [[NSNotificationCenter defaultCenter] postNotificationName:ShouldHideiAds object:nil];
                }
            }];
        }
    }else if([cell isEqual:self.restorePurchases]){
        [self restoreThePurchases];
    } else if ([cell isEqual:self.acknowledgments]) {
        [self showAcknowledgments];
    } else if ([cell isEqual:self.blackFireApps]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://darioalessandro.com"]];
    } else if ([cell isEqual:self.theaterFramework]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://www.theaterframework.com"]];
    }
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{
    if([cell isEqual:self.disableiAds]){
        InAppPurchasesManager * manager= [InAppPurchasesManager sharedManager];
        NSArray * products= [manager products];
        if(indexPath.row==0){
            if([products count]>0){
                [self fillRestoreiAdsRow];
            }else{
                [manager reloadProductsWithHandler:^(InAppPurchasesManager *purchasesManager, NSError *error) {
                    if (!error) {
                        [self fillRestoreiAdsRow];
                    }
                }];
            }
        }
    }else if([cell isEqual:self.versionCell]){
        NSDictionary * infoDictionary= [[NSBundle mainBundle] infoDictionary];
        NSString * bundle=[infoDictionary objectForKey:@"CFBundleVersion"];
        NSString * shortVersion=[infoDictionary objectForKey:@"CFBundleShortVersionString"];        
        self.versionCell.detailTextLabel.text=[NSString stringWithFormat:@"%@ (%@) ", shortVersion,  bundle];
    }
}

-(void)fillRestoreiAdsRow{
    InAppPurchasesManager * manager= [InAppPurchasesManager sharedManager];
    NSArray * products= [manager products];
    if([manager didUserBuyRemoveiAdsFeature]) {
        self.disableiAds.textLabel.text=kiAdsFeatureInstalled;
        self.disableiAds.detailTextLabel.text=@"";
        [self.disableiAds setNeedsDisplay];
    }else if([products count]>0){
        SKProduct * disableiAdsProduct=[manager productWithIdentifier:RemoveiAdsFeatureIdentifier];
        [[self.disableiAds textLabel] setText:[disableiAdsProduct localizedTitle]];
        NSString * localizedPrice=[[[InAppPurchasesManager sharedManager] currencyFormatter] stringFromNumber:disableiAdsProduct.price];
        [[self.disableiAds detailTextLabel] setText:localizedPrice];
        [self.disableiAds setNeedsLayout];
    }
}

#pragma mark -
#pragma mark Local Storage.

+(BOOL)firstRun{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString * version= [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    NSString * firstRunFlag= [NSString stringWithFormat:@"%@_firstRun", version];
    if([userDefaults objectForKey:firstRunFlag]){    
        return [userDefaults boolForKey:firstRunFlag];
    }
    return TRUE;
}

+(void)setFirstRunFlag:(BOOL)flag{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString * version= [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    NSString * firstRunFlag= [NSString stringWithFormat:@"%@_firstRun", version];
    [userDefaults setBool:flag forKey:firstRunFlag];
    [userDefaults synchronize];
}

-(void)restoreThePurchases{
    [[InAppPurchasesManager sharedManager] restorePurchasesWithHandler:^(InAppPurchasesManager *purchasesManager, NSError *error) {
            if (!error) {
                [self fillRestoreiAdsRow];
            }
    }];
}
    
- (void)dealloc{

}

@end
