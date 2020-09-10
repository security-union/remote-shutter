

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#define ShouldHideiAds @"ShouldHideiAds"

@interface CMConfigurationsViewController : UIViewController<UITableViewDelegate, UITableViewDataSource>{
       
}
@property (strong, nonatomic) IBOutlet UITableViewCell *disableiAds;
@property (nonatomic, strong) IBOutlet UITableViewCell *restorePurchases;
@property (nonatomic, strong) IBOutlet UITableViewCell *acknowledgments;
@property (strong, nonatomic) IBOutlet UITableViewCell *versionCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *blackFireApps;
@property (strong, nonatomic) IBOutlet UITableViewCell *theaterFramework;

@property (retain, nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic, retain) NSArray * tableViewCells;


-(void)restoreThePurchases;

+(void)setFirstRunFlag:(BOOL)flag;

+(BOOL)firstRun;


@end