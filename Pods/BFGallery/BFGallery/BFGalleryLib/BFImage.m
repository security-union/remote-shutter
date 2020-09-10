//
//  BFImage.m
//  BFGallery
//
//  Created by Dario Lencina on 10/14/12.
//  Copyright (c) 2012 Dario Lencina. All rights reserved.
//

#import "BFImage.h"

@implementation BFImage

-(void)loadFullSizeImageWithQueue:(NSOperationQueue *)queue setResultInImageView:(UIImageView *)imageView{
    NSURLRequest * req= [NSURLRequest requestWithURL:self.fullSizeImageServerPath];
    [NSURLConnection sendAsynchronousRequest:req queue:queue completionHandler: ^(NSURLResponse * response, NSData * data, NSError * error){
        if(!error){
            self.fullSizeImage= [UIImage imageWithData:data];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if(imageView){
                    imageView.image=self.fullSizeImage;
                }
            }];
        }
    }];
}


@end
