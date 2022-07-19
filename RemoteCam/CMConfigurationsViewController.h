

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Constants.h"

@interface CMConfigurationsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource> {

}
@property(strong, nonatomic) IBOutlet UITableViewCell *disableAdsAndEnableVideoRecording;
@property(strong, nonatomic) IBOutlet UITableViewCell *disableiAds;
@property(nonatomic, strong) IBOutlet UITableViewCell *restorePurchases;
@property(nonatomic, strong) IBOutlet UITableViewCell *acknowledgments;
@property(strong, nonatomic) IBOutlet UITableViewCell *versionCell;
@property(strong, nonatomic) IBOutlet UITableViewCell *blackFireApps;
@property(strong, nonatomic) IBOutlet UITableViewCell *theaterFramework;
@property(strong, nonatomic) IBOutlet UITableViewCell *contactSupport;
@property(strong, nonatomic) IBOutlet UITableViewCell *sourceCode;
@property(strong, nonatomic) IBOutlet UITableViewCell *toggleSendMediaToRemote;
@property(strong, nonatomic) IBOutlet UISwitch *toggleSendMediaToRemoteSwitch;

@property(retain, nonatomic) IBOutlet UITableView *tableView;
@property(nonatomic, retain) NSArray *tableViewCells;


- (void)restoreThePurchases;

+ (BOOL)sendMediaToRemote;

+ (void)sendMediaToRemote:(BOOL)flag;

+ (void)setFirstRunFlag:(BOOL)flag;

+ (BOOL)firstRun;


@end
