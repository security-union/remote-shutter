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


#import "BFGFullSizeViewController.h"
#import <QuartzCore/QuartzCore.h>
#define kTransitionDuration 0.5
#import "FlickrImage.h"
//#import "FBImage.h"
#import "BFLog.h"

@implementation BFGFullSizeViewController{
    UIImage * initialImage;
    BOOL isFirstImage;
}
@synthesize imageView;
@synthesize galleryTableView, delegate, initialRowToShow;


-(id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self= [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mustDismissGalleryDetails:) name:kMustDismissGalleryDetails object:nil];
    queue= [NSOperationQueue new];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - dismissCallback

-(void)mustDismissGalleryDetails:(NSNotification *)notification
{
    [self dismissDetailView:nil];
}

-(void)dismissDetailView:(UITapGestureRecognizer *)tapRecognizer
{
    if(delegate){
        [delegate didKilledDetailViewController:self];
    }
    [self dismissAndDispose];

}

-(void)showFromCoordinatesInView:(UIView *)baseView
{
    id asset= [delegate menuDetailViewController:self assetAtIndex:self.initialRowToShow.row];
    
    if([asset isMemberOfClass:[FlickrImage class]]){
        FlickrImage * img= asset;
        if(![img fullSizeImage]){
            initialImage=[img thumbnail];
            [img loadFullSizeImageWithQueue:queue setResultInImageView:self.imageView];
        }else{
            initialImage=[img fullSizeImage];
        }
    /*}else if([asset isMemberOfClass:[FBImage class]]){
        FBImage * img= asset;
        if(![img fullSizeImage]){
            initialImage=[img thumbnail];
            [img loadFullSizeImageWithQueue:queue setResultInImageView:self.imageView];
        }else{
            initialImage=[img fullSizeImage];
        }*/
    }else{
        initialImage= [UIImage imageWithCGImage:[[asset defaultRepresentation] fullScreenImage]];
    }
    [self.imageView setImage:initialImage];
    CGSize originalSize= baseView.frame.size;
    CGSize tableViewSize= self.imageView.frame.size;
    CGFloat scale= originalSize.width/tableViewSize.width;
    self.imageView.center= [self.view convertPoint:baseView.center fromView:baseView.superview];

    [self.imageView.layer setAnchorPoint:CGPointMake(0.5, 0.5)];
	self.imageView.transform = CGAffineTransformMakeScale( scale, scale);
    self.imageView.alpha=0.01;
    [self presentFullScreenImageFromView:baseView];
}

-(void)presentFullScreenImageFromView:(UIView *)baseView
{
    BFLog(@"frame %@", NSStringFromCGRect(self.view.frame));
    self.originView=baseView;
   self.originView.alpha=0.01;
    [UIView animateWithDuration:kTransitionDuration/1.5 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.imageView.transform = CGAffineTransformMakeScale( 1.0, 1.0);
        self.imageView.alpha=1;
        self.imageView.center= CGPointMake(self.view.frame.size.width/2, self.view.frame.size.height/2);
    }completion:^(BOOL finished){
        [UIView animateWithDuration:kTransitionDuration/3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.imageView.transform = CGAffineTransformMakeScale( 0.95, 0.95);
        }completion:^(BOOL finished){
            [UIView animateWithDuration:kTransitionDuration/2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                self.imageView.transform = CGAffineTransformMakeScale( 1.0, 1.0);
            }completion:^(BOOL finished){
                BFLog(@"frame %@", NSStringFromCGRect(self.view.frame));
            }];
        }];
    }];
}

- (CGFloat)angleForCurrentOrientation
{
	UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
	if (orientation == UIInterfaceOrientationLandscapeLeft) {
        return M_PI;
    } else 	if (orientation == UIInterfaceOrientationLandscapeRight) {
        return 0;
	} else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
		return M_PI_2;
	}
    return -M_PI_2;
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    isFirstImage=TRUE;
    UITapGestureRecognizer * gestureRecognizer= [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissDetailView:)];
    [self.view addGestureRecognizer:gestureRecognizer];
    [self.view setBackgroundColor:[UIColor colorWithWhite:0.0f alpha:0.8]];
    [self configureScrollView];
}

-(void)configureScrollView
{
    UIScrollView * scroll= (UIScrollView *)self.view;
    [scroll setMinimumZoomScale:1];
    [scroll setMaximumZoomScale:10];
    scroll.delegate=self;
}

- (void)viewDidUnload
{
    [self setGalleryTableView:nil];
    [self setImageView:nil];
    [super viewDidUnload];
}


#pragma mark -
#pragma mark Actions

-(void)dismissAndDispose
{
 
    [UIView animateWithDuration:kTransitionDuration animations:^{
        self.originView.alpha=1;
        self.view.alpha = 0;
    }completion:^(BOOL finished){
        [self postDismissCleanup];
    }];
}

- (void)postDismissCleanup
{
	[self.view removeFromSuperview];
}

#pragma mark -
#pragma mark UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView{
    return self.imageView;
}



@end
