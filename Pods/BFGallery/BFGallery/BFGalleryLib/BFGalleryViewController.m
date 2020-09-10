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

#import "BFGalleryViewController.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import "FlickrImage.h"
//#import "FBImage.h"
//#import "FBAlbum.h"

@interface BFGalleryViewController ()
    -(BFGFullSizeCell *)getCell;
    -(void)showLastPic:(id)caller;
@end

@implementation BFGalleryViewController
@synthesize loadingPicsIndicator;
@synthesize tableView, lastSelectedRow;
@synthesize productsArray, isShowingFullSizeGallery;

-(id)initWithMediaProvider:(BFGAssetsManagerProvider)mediaProvider{
    self= [super init];
    if(self){
        self.mediaProvider=mediaProvider;
    }
    return self;
}

-(id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil mediaProvider:(BFGAssetsManagerProvider)mediaProvider{
    self= [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        if(!productsArray){
            isShowingFullSizeGallery=FALSE;
            self.mediaProvider=mediaProvider;
        }
    }
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        if(!productsArray){
            isShowingFullSizeGallery=FALSE;
            self.mediaProvider=BFGAssetsManagerProviderPhotoLibrary;
        }
    }
    return self;
}

#pragma mark - View lifecycle

- (void)viewDidLoad{
    [super viewDidLoad];
    [[self tableView] setHidden:NO];
    [[self tableView] setCanCancelContentTouches:YES];    
}

- (void)viewDidUnload{
    [self setTableView:nil];
    [self setLoadingPicsIndicator:nil];
    [self setTableActivityIndicator:nil];
    [self setNoAccessToCamView:nil];
    [super viewDidUnload];
}

-(void)viewWillDisappear:(BOOL)animated{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    [self addAllNotifications];
    [self configureUI];
    [self startLoadingContent];
}

-(void)configureUI{
    if(self.mediaProvider==BFGAssetsManagerProviderPhotoLibrary || self.mediaProvider==BFGAssetsManagerProviderFacebookPictures || self.mediaProvider==BFGAssetsManagerProviderFacebookAlbums){
        [self.tableView setContentInset:UIEdgeInsetsMake(-40, 0, 0, 0)];
        [self.bar setHidden:TRUE];
        [self.tableActivityIndicator setHidden:TRUE];
    }else if(self.mediaProvider==BFGAssetsManagerProviderFlickr){
        self.bar.text= self.searchCriteria;
    }
}

-(void)addAllNotifications{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didAddedAssets:) name:kAddedAssetsToLibrary object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDeniedAccessToAssets:) name:kUserDeniedAccessToPics object:nil];
}

-(void)startLoadingContent{
    id context=nil;
    if(self.mediaProvider==BFGAssetsManagerProviderFacebookPictures || self.mediaProvider==BFGAssetsManagerProviderFacebookAlbums){
        [loadingPicsIndicator startAnimating];
        [loadingPicsIndicator setHidden:NO];
        //context=[self.facebookAlbum albumInfo];
    }
    [[BFGAssetsManager sharedInstance] setSearchCriteria:self.searchCriteria];
    [[BFGAssetsManager sharedInstance] readImagesFromProvider:self.mediaProvider withContext:context];
}

-(void)showLastPic:(id)caller{
    if(![[self productsArray] count]>0)
        return;
    
}

-(void)userDeniedAccessToAssets:(NSNotification *)notif{
    [self showDeniedAccessToAssetsView];
}

-(void)showDeniedAccessToAssetsView{
    if(self.noAccessToCamView==nil){
        NSString * nibName=@"BFDeniedAccessToAssetsView";

        self.noAccessToCamView= [[NSBundle bundleForClass:[BFGalleryViewController class]] loadNibNamed:nibName owner:nil options:nil][0];
    }
    [self.loadingPicsIndicator stopAnimating];
    [self.noAccessToCamView setFrame:self.view.window.bounds];
    [self.view.window addSubview:self.noAccessToCamView];
}

-(void)dismissDeniedAccessToAssetsView{
    if(self.noAccessToCamView){
        [self.noAccessToCamView removeFromSuperview];
        self.noAccessToCamView=nil;
    }
}

-(void)didAddedAssets:(NSNotification *)notif{
    [self dismissDeniedAccessToAssetsView];
    id array= [notif object];
    self.productsArray=array;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.tableView reloadData];
        [self.loadingPicsIndicator stopAnimating];
    }];
}

-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation{
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource & scrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView{
    if(self.mediaProvider==BFGAssetsManagerProviderFlickr){
        if(scrollView.contentOffset.y + scrollView.frame.size.height>=scrollView.contentSize.height){
            [[BFGAssetsManager sharedInstance] getMoreImages];
        }
    }
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    if(self.mediaProvider==BFGAssetsManagerProviderFacebookAlbums){
        return [self.productsArray count]-1;
    }
    NSInteger numberOfImages= [[[self getCell] imageViews] count];
    float modulo= [self.productsArray count]%numberOfImages;
    float numberOfCells= [self.productsArray count]/numberOfImages;
    NSInteger rounded= (NSInteger)numberOfCells;
    NSInteger corrected= (modulo!=0)?rounded+1:rounded;
    return corrected;
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    if(self.mediaProvider==BFGAssetsManagerProviderFacebookAlbums){
        return 50;
    }
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {        
        return 79;
    }
    return 146;
}

-(BFGFullSizeCell *)getCell{
    NSString * fileName= @"BFGFullSizeCell";
        
    if(UIInterfaceOrientationIsLandscape([[UIApplication sharedApplication] statusBarOrientation])){
        fileName= [NSString stringWithFormat:@"%@_landscape", fileName];
    }
    
    BFGFullSizeCell * cell= (BFGFullSizeCell *)[self.tableView dequeueReusableCellWithIdentifier:@"ff"];
    if(cell==nil){
        cell= [[NSBundle bundleForClass:[BFGalleryViewController class] ] loadNibNamed:fileName owner:nil options:nil][0];
        [cell setSelectedBackgroundView:[[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)]];
        [cell setBackgroundView:[[UIView alloc] init]];
        [[cell backgroundView] setBackgroundColor:[UIColor blackColor]];
    }
    return cell;
}
                                                                                        
-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    if(self.mediaProvider==BFGAssetsManagerProviderFacebookAlbums){
       /* UITableViewCell * cell= [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"id"];
        FBAlbum * album=self.productsArray[indexPath.row];
        [cell.textLabel setText:[[album albumInfo] objectForKey:@"name"]];
        [[cell textLabel] setTextColor:[UIColor whiteColor]];
        [cell.imageView setImage:[album thumbnail]];
        return cell;*/
    }
    
    BFGFullSizeCell * cell= [self getCell];
    int numberOfImageViewsInCell= [[cell imageViews] count];
    int index0= indexPath.row * numberOfImageViewsInCell;

    NSInteger count= self.productsArray.count;
    
    for(int j=0;j<numberOfImageViewsInCell;j++){
        if(count>index0+j){
            ALAsset * image=nil;
            UIImage * thumbnail=nil;
            
            if(self.mediaProvider==BFGAssetsManagerProviderPhotoLibrary){
                image= (self.productsArray)[index0+j];
                thumbnail= [UIImage imageWithCGImage:[image thumbnail]];
            }else if(self.mediaProvider==BFGAssetsManagerProviderFlickr){
                FlickrImage * image=(self.productsArray)[index0+j];
                thumbnail= [image thumbnail];
            }else if(self.mediaProvider==BFGAssetsManagerProviderFacebookPictures){
               // FBImage * image=(self.productsArray)[index0+j];
               // thumbnail= [image thumbnail];
            }
            
            UITapGestureRecognizer * tap= [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didSelectImage:)];
            [tap setNumberOfTapsRequired:1];
            [[cell imageViews][j] addGestureRecognizer:tap];
            [[cell imageViews][j] setImage:thumbnail];
            [[cell imageViews][j] setTag:index0+j];
            [[cell imageViews][j] setUserInteractionEnabled:TRUE];
        }else{
            [[cell imageViews][j] setHidden:TRUE];
        }

    }
    return cell;
}

-(CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    CGFloat height=0;
    if(self.mediaProvider==BFGAssetsManagerProviderFlickr){
        height=44;
    }
    return height;
}

-(CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section{
        return 0;
}

-(UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section{
    UIView * view= [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    [view setBackgroundColor:[UIColor clearColor]];
    return view;
}

-(void)pinchSelectedImage:(UIPinchGestureRecognizer *)pinch{
    UIView * PinchedView= [pinch view];
    if([pinch state]==UIGestureRecognizerStateBegan){
        [[PinchedView superview] bringSubviewToFront:[pinch view]];
    }else if([pinch state]==UIGestureRecognizerStateEnded || [pinch state]==UIGestureRecognizerStateFailed){
        if([pinch scale]>1.5){
            [self showFullSizeGalleryWithImageSelected:(UIImageView *)[pinch view]];
        }
        [[pinch view] setTransform:CGAffineTransformMakeScale(1, 1)];
    }else if([pinch state]== UIGestureRecognizerStateChanged){
        [PinchedView setTransform:CGAffineTransformMakeScale(pinch.scale, pinch.scale)]; 
        if([pinch scale]>1.5){
            [self showFullSizeGalleryWithImageSelected:(UIImageView *)[pinch view]];
        }
    }
}

-(void)showGalleryDetailWithIndex:(NSInteger)index fromView:(UIView *)originView{
    
    NSString * fileName= nil;
    fileName= @"BFGFullSizeViewController";

        
    BFGFullSizeViewController * controller= [[BFGFullSizeViewController alloc] initWithNibName:fileName bundle:[NSBundle bundleForClass:[BFGFullSizeViewController class]]];
    [self addChildViewController:controller];
    self.lastSelectedRow= [NSIndexPath indexPathForRow:index inSection:0];
    [self.view addSubview:controller.view];
    CGRect rect= CGRectZero;
    if(self.navigationController==nil){
        rect= self.tableView.frame;
    }else{
        rect=self.view.frame;
    }
    rect.origin.y=0;
    controller.view.frame= rect;

    [controller setDelegate:self];
    [controller setInitialRowToShow:[NSIndexPath indexPathForRow:index inSection:0]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller showFromCoordinatesInView:originView];
    });
}

-(void)showFullSizeGalleryWithImageSelected:(UIImageView *)imageView{
    if(isShowingFullSizeGallery==TRUE)
        return;
    
    if([self.bar isFirstResponder]){
        [self.bar resignFirstResponder];
    }
    isShowingFullSizeGallery=TRUE;
    NSInteger index= [imageView tag];
    [self showGalleryDetailWithIndex:index fromView:imageView];
}

-(void)didSelectImage:(UITapGestureRecognizer *)tap{
    [self showFullSizeGalleryWithImageSelected:(UIImageView *)[tap view]];
}

#pragma mark - UITableViewDelegate

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [self.tableView deselectRowAtIndexPath:indexPath animated:TRUE];
    if (self.mediaProvider==BFGAssetsManagerProviderFacebookAlbums) {
        BFGalleryViewController * galleryViewController=[[BFGalleryViewController alloc] initWithMediaProvider:BFGAssetsManagerProviderFacebookPictures];
        //galleryViewController.facebookAlbum=self.productsArray[indexPath.row];
        [[BFGAssetsManager sharedInstance] setPics:nil];
        [self.navigationController pushViewController:galleryViewController animated:TRUE];
    }
}

#pragma mark - SRMenuDetailViewControllerDelegate

-(NSDictionary *)menuDetailViewController:(BFGFullSizeViewController *)menuDetailViewController assetAtIndex:(NSInteger)index{
    return productsArray[index];
}

-(NSInteger)numberOfViewsInMenuDetailViewController:(BFGFullSizeViewController *)menuDetailViewController{
    return [self.productsArray count];
}

-(void)didKilledDetailViewController:(BFGFullSizeViewController *)menu{
    isShowingFullSizeGallery=FALSE;
}

-(UIImage *)menuDetailViewController:(BFGFullSizeViewController *)menuDetailViewController imageAtIndex:(NSInteger)index{
    return nil;
}

#pragma mark -
#pragma mark UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar{
    [searchBar resignFirstResponder];
    [[BFGAssetsManager sharedInstance] setSearchCriteria:[searchBar text]];
    [[BFGAssetsManager sharedInstance] readImagesFromProvider:BFGAssetsManagerProviderFlickr withContext:nil];
}

-(void)searchBarCancelButtonClicked:(UISearchBar *)searchBar{
    [searchBar resignFirstResponder];
}


@end
