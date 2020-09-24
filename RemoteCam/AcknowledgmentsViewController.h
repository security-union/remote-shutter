//
//  AcknowledgmentsViewController.h
//  GraphicTweets
//
//  Created by Dario Lencina on 2/1/13.
//  Copyright (c) 2013 Dario Lencina. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface AcknowledgmentsViewController : UIViewController

@property(weak, nonatomic) IBOutlet WKWebView *webView;
@property(strong, nonatomic) NSURL *URL;
@end
