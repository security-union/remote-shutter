//
//  FlickrRequest.m
//  Graphic tweets
//
//  Created by Dario Lencina on 5/19/12.
//  Copyright (c) 2012 Dario Lencina. All rights reserved.
//

#import "FlickrRequest.h"
#import "SharedConstants.h"
#import "BFLog.h"
#import <UIKit/UIKit.h>


@implementation FlickrRequest
@synthesize receivedData, queue, searchCriteria;

-(void)performFlickrRequestWithCriteria:(NSString *)criteria delegate:(id <FlickrImageParserDelegate>)del{
    [self setSearchCriteria:criteria];
    [self setDelegate:del];
    self.page=-1;
    self.queue = [[NSOperationQueue alloc] init];
    [self getNextPage];
}

-(void)getNextPageIfNeeded{
    if (self.queue && self.queue.operationCount>0) {
        BFLog(@"there's an operation in progress");
    }else if(self.queue && self.queue.operationCount==0){
        [self getNextPage];
        BFLog(@"downloading more stuff");
    }
}

-(NSString *)flickrKey{
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OBJECTIVE_FLICKR_API_KEY"];
}

-(void)getNextPage{
    self.page++;
    NSString * OBJECTIVE_FLICKR_API_KEY= [self flickrKey];
    NSString * flickrURLRequest=[NSString stringWithFormat:flickrSearchMethodString, OBJECTIVE_FLICKR_API_KEY, searchCriteria, self.page];
    
    NSString * encodedReq=[flickrURLRequest stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
	NSMutableURLRequest *req = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:encodedReq]
															cachePolicy:NSURLRequestReloadIgnoringCacheData
														timeoutInterval:20];
	[req setHTTPMethod:@"GET"];
	
    if(theConnection){
        [theConnection cancel];
        theConnection=nil;
    }
	theConnection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    
	if (theConnection) {
		NSMutableData *data = [[NSMutableData alloc] init];
		self.receivedData = data;
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    }
    else {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    }
}

#pragma mark -
#pragma mark NSURLConnection Callbacks

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	if ([response respondsToSelector:@selector(statusCode)])
    {
        int statusCode = [((NSHTTPURLResponse *)response) statusCode];
        if (statusCode >= 400)
        {
			[connection cancel];  // stop connecting; no more delegate messages
			NSError *statusError = [NSError errorWithDomain:@"fail"
													   code:statusCode
												   userInfo:nil];
			
			BFLog(@"Error with %d", statusCode);
			[self connection:connection didFailWithError:statusError];
        }
    }
	
	[receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	[receivedData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	UIAlertView * alert= [[UIAlertView alloc] initWithTitle:@"Flickr:" 
													message:[error localizedDescription]
												   delegate:self
										  cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
	self.receivedData = nil;
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	
	[connection cancel];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	NSData * data= self.receivedData;
    FlickrImageParser *parser = [[FlickrImageParser alloc] initWithData:data criteria:self.searchCriteria delegate:self.delegate];
    [queue addOperation:parser];
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}


@end
