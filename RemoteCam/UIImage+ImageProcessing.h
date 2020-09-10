//
//  UIImage+ImageProcessing.h
//  Actors
//
//  Created by Dario on 10/8/15.
//  Copyright © 2015 dario. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>


@interface UIImage (ImageProcessing)
+ (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer orientation:(UIImageOrientation) orientation;
    + (UIImage*) cgImageBackedImageWithCIImage:(CIImage*) ciImage orientation:(UIImageOrientation) orientation;
@end
