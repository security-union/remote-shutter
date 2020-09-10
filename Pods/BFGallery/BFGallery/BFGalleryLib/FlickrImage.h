//
//  FlickrImage.h
//  Graphic tweets
//
//  Created by Dario Lencina on 10/3/12.
//  Copyright (c) 2012 Dario Lencina. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BFImage.h"

@interface FlickrImage : BFImage

@property(nonatomic, strong) UIImage * thumbnail;
@property(nonatomic, strong) UIImage * fullSizeImage;
@property(nonatomic, strong) NSURL * thumbnailServerPath;
@property(nonatomic, strong) NSURL * fullSizeImageServerPath;
@property(nonatomic, strong) NSString * searchCriteria;
@property(nonatomic, strong) NSString * title;

@end
