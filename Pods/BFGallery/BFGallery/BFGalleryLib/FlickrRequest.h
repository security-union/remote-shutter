//
//  FlickrRequest.h
//  Graphic tweets
//
//  Created by Dario Lencina on 5/19/12.
//  Copyright (c) 2012 Dario Lencina. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FlickrImageParser.h"

@interface FlickrRequest : NSObject {
    NSURLConnection *theConnection;
}
@property (nonatomic) NSInteger page;
@property (nonatomic, strong)    NSString * searchCriteria;
@property (nonatomic, unsafe_unretained)   id <FlickrImageParserDelegate> delegate;
@property (nonatomic, strong)	NSMutableData * receivedData;
@property (nonatomic, strong)   NSOperationQueue *queue;
-(void)performFlickrRequestWithCriteria:(NSString *)criteria delegate:(id <FlickrImageParserDelegate>)delegate;
-(void)getNextPage;
-(void)getNextPageIfNeeded;
@end
