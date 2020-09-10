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

#import "FlickrRequest.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <UIKit/UIKit.h>
//#import "FBUserPictures.h"

static NSString * const kAddedAssetsToLibrary= @"AddedAssetsToLibrary";
static NSString * const kUserDeniedAccessToPics= @"kUserDeniedAccessToPics";
typedef void(^BFGAssetsManagerShareHandler)(BOOL enabled, NSError *error);
typedef enum{
    BFGAssetsManagerProviderPhotoLibrary=0,
    BFGAssetsManagerProviderFlickr,
    BFGAssetsManagerProviderFacebookAlbums,
    BFGAssetsManagerProviderFacebookPictures
}BFGAssetsManagerProvider;

//@interface BFGAssetsManager : NSObject <FlickrImageParserDelegate, FBUserPicturesParserDelegate>{
@interface BFGAssetsManager : NSObject <FlickrImageParserDelegate>{
    FlickrRequest * flickr;
    BFGAssetsManagerProvider _provider;
}
-(void)readImagesFromProvider:(BFGAssetsManagerProvider)provider withContext:(id)context;
-(void)getMoreImages;
+(BFGAssetsManager *)sharedInstance;
-(BOOL)handleOpenURL:(NSURL *)url;
-(BOOL)cameraRollAuthorizationStatus;
-(BOOL)shouldSharePicsToCameraRoll;
-(void)setShouldSharePicsToCameraRoll:(BOOL)shouldShare handler:(BFGAssetsManagerShareHandler)handler;
-(void)savePicToCameraRoll:(UIImage *)image completionBlock:(ALAssetsLibraryWriteImageCompletionBlock)block;
@property(strong)NSString * searchCriteria;
@property(atomic, strong) NSMutableArray * pics;
@end
