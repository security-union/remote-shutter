/*Copyright (C) <2012> <Dario Alessandro Lencina Talarico>
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import <UIKit/UIKit.h>
#import <AssetsLibrary/AssetsLibrary.h>
#define kMustDismissGalleryDetails @"MustDismissGalleryDetails"

@class BFGFullSizeViewController;

@protocol BFGFullSizeViewControllerDelegate <NSObject>
-(NSInteger)numberOfViewsInMenuDetailViewController:(BFGFullSizeViewController *)menuDetailViewController;
-(void)didKilledDetailViewController:(BFGFullSizeViewController *)menu;

@optional
-(ALAsset *)menuDetailViewController:(BFGFullSizeViewController *)menuDetailViewController assetAtIndex:(NSInteger)index;
-(UIImage *)menuDetailViewController:(BFGFullSizeViewController *)menuDetailViewController imageAtIndex:(NSInteger)index;

@end

@interface BFGFullSizeViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate> {
    id <BFGFullSizeViewControllerDelegate> __weak delegate;
    UITableView *galleryTableView;
    NSIndexPath * initialRowToShow;
    NSOperationQueue * queue;
}

@property (strong, nonatomic) IBOutlet UIImageView *imageView;
@property (nonatomic, strong) NSIndexPath * initialRowToShow;
@property (nonatomic, strong) IBOutlet UITableView *galleryTableView;
@property (nonatomic, weak) id <BFGFullSizeViewControllerDelegate> delegate;
@property (nonatomic, weak) UIView * originView;

-(void)showFromCoordinatesInView:(UIView *)baseView;
- (void)postDismissCleanup;

@end


