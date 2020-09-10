//
//  AcknowledgmentsViewController.m
//  GraphicTweets
//
//  Created by Dario Lencina on 2/1/13.
//  Copyright (c) 2013 Dario Lencina. All rights reserved.
//

#import "AcknowledgmentsViewController.h"

@interface AcknowledgmentsViewController ()

@end

@implementation AcknowledgmentsViewController

-(void)viewDidLoad{
    [super viewDidLoad];
    [self setupWebView];
}

-(void)setupWebView{
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor clearColor];
}

-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];    
    [self.webView loadRequest:[self acknowledgmentsLoadRequest]];
}

-(NSURLRequest *)acknowledgmentsLoadRequest{
    NSURLRequest * request=[NSURLRequest requestWithURL:self.URL];
    return request;
}

#pragma mark Autorotation

-(BOOL)shouldAutorotate
{
    return NO;
}

-(UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

@end
