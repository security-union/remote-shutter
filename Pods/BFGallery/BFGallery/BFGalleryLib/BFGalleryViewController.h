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
#import "BFGFullSizeViewController.h"
#import "BFGFullSizeCell.h"
#import "BFGAssetsManager.h"
//#import "FBAlbum.h"

@interface BFGalleryViewController : UIViewController <BFGFullSizeViewControllerDelegate, UIScrollViewDelegate, UISearchBarDelegate>{
    NSArray * productsArray;
    BOOL isShowingFullSizeGallery;
    NSIndexPath * lastSelectedRow;
}
    -(void)showGalleryDetailWithIndex:(NSInteger)index fromView:(UIView *)originView;
    -(id)initWithMediaProvider:(BFGAssetsManagerProvider)mediaProvider;
    -(id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil mediaProvider:(BFGAssetsManagerProvider)mediaProvider;
    -(void)showFullSizeGalleryWithImageSelected:(UIImageView *)imageView;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *loadingPicsIndicator;
@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) IBOutlet UISearchBar * bar;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *tableActivityIndicator;
@property (strong, nonatomic) IBOutlet UIView *noAccessToCamView;
@property (strong, nonatomic) NSIndexPath * lastSelectedRow;
//@property (strong, nonatomic) FBAlbum * facebookAlbum;
@property (nonatomic, assign) BOOL isShowingFullSizeGallery;
@property (weak, nonatomic) id delegate;
@property (atomic, strong) NSArray * productsArray;
@property (nonatomic,  strong) NSString * searchCriteria;
@property (nonatomic) BFGAssetsManagerProvider mediaProvider;

@end
