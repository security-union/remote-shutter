//
//  UIImage+ImageProcessing.m
//  Actors
//
//  Created by Dario on 10/8/15.
//  Copyright © 2015 dario. All rights reserved.
//

#import "UIImage+ImageProcessing.h"
#import <AVFoundation/AVFoundation.h>

@implementation UIImage (ImageProcessing)

+ (UIImage *)imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer orientation:(UIImageOrientation) orientation
{
    CVImageBufferRef cvImage = CMSampleBufferGetImageBuffer(sampleBuffer);
    CGRect cropRect = AVMakeRectWithAspectRatioInsideRect(CGSizeMake(320, 320), CGRectMake(0,0, CVPixelBufferGetWidth(cvImage),CVPixelBufferGetHeight(cvImage)) );
    CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:cvImage];
    CIImage* croppedImage = [ciImage imageByCroppingToRect:cropRect];
    
    CIFilter *scaleFilter = [CIFilter filterWithName:@"CILanczosScaleTransform"];
    [scaleFilter setValue:croppedImage forKey:@"inputImage"];
    [scaleFilter setValue:[NSNumber numberWithFloat:0.25] forKey:@"inputScale"];
    [scaleFilter setValue:[NSNumber numberWithFloat:1.0] forKey:@"inputAspectRatio"];
    CIImage *finalImage = [scaleFilter valueForKey:@"outputImage"];
    UIImage* cgBackedImage = [UIImage cgImageBackedImageWithCIImage:finalImage orientation:orientation];
    
    return cgBackedImage;
}

+ (UIImage*) cgImageBackedImageWithCIImage:(CIImage*) ciImage orientation:(UIImageOrientation) orientation{
    
    CIContext *context = [CIContext contextWithOptions:nil ];
    CGImageRef ref = [context createCGImage:ciImage fromRect:ciImage.extent];
    UIImage* image = [UIImage imageWithCGImage:ref scale:[UIScreen mainScreen].scale orientation:orientation];
    CGImageRelease(ref);
    
    return image;
}

@end
