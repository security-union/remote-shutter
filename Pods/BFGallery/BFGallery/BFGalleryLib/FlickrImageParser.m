//
//  IBTParser.m
//  webServicesText
//
//  Created by Dario Lencina on 2/1/11.
//  Copyright 2011 Ironbit. All rights reserved.
//

#import "FlickrImageParser.h"
#import "SharedConstants.h"
#import "FlickrImage.h"
#import "BFLog.h"

@implementation FlickrImageParser

@synthesize delegate, searchCriteria, error;

- (id)initWithData:(NSData *)data  criteria:(NSString *) criteria delegate:(id <FlickrImageParserDelegate>)theDelegate{
	self= [super init];
	if(self){
		self.dataToParse= [[NSData alloc] initWithData:data];
		delegate= theDelegate;
        [self setSearchCriteria:criteria];
	}
	return self;
}

- (NSArray *)parseArray{
NSString * responseString = [[NSString alloc] initWithData:self.dataToParse encoding:NSUTF8StringEncoding];
	NSArray * URLArray=nil;
	NSArray * queryResult= [self resultsFromString:responseString];
	if(queryResult){
		NSMutableArray * mutableImagesArray= [NSMutableArray array];
		for(NSDictionary * photoDict in queryResult){
			NSString * fullSizeImageURL = [NSString stringWithFormat:mediumImagesURLFormat, 
										 photoDict[@"farm"], photoDict[@"server"], 
										 photoDict[@"id"], photoDict[@"secret"]];
            
            NSString * thumbnailURL= [NSString stringWithFormat:littleImagesURLFormat,
                                      photoDict[@"farm"], photoDict[@"server"],
                                      photoDict[@"id"], photoDict[@"secret"]];
            
            FlickrImage * flickrImage= [FlickrImage new];
            [flickrImage setThumbnailServerPath:[NSURL URLWithString:thumbnailURL]];
            [flickrImage setFullSizeImageServerPath:[NSURL URLWithString:fullSizeImageURL]];
            [flickrImage setSearchCriteria:self.searchCriteria];
            [flickrImage setTitle:photoDict[@"title"]];
			if(flickrImage){
				[mutableImagesArray addObject:flickrImage];
                if(delegate){
                    self.images= [NSArray arrayWithArray:mutableImagesArray];
                    [self.delegate performSelectorOnMainThread:@selector(parserDidDownloadImage:)withObject:self waitUntilDone:NO];
                }
            }
		}
		if([mutableImagesArray count]>0){
			URLArray= [NSArray arrayWithArray:mutableImagesArray];
		}
	}
	
	if(responseString)
		responseString=nil;
	return URLArray;
}

- (void)main{
	[self setImages:[self parseArray]];
	if (![self isCancelled])
    {
		if(self.images!=nil && ![self.images isMemberOfClass:[NSNull class]])
			[self.delegate performSelectorOnMainThread:@selector(didFinishParsing:) withObject:self waitUntilDone:FALSE];
		else {
			self.error= [NSError errorWithDomain:[NSString stringWithFormat:@"No matches for given criteria."]  code:401 userInfo:nil];
			[self.delegate performSelectorOnMainThread:@selector(parseErrorOccurred:)withObject:self waitUntilDone:FALSE];
		}
    }
}

-(NSArray *)resultsFromString:(NSString *)string{
	NSError *_error;
	SBJSON *json = [SBJSON new];
	
	NSDictionary *parsedJSON = [json objectWithString:string error:&_error];
	if(parsedJSON==nil){
		self.error= [NSError errorWithDomain:NSLocalizedStringFromTable(@"JSON mal formado", @"Localizable", @"JSON mal formado") code:401 userInfo:nil];
		[self.delegate performSelectorOnMainThread:@selector(parseErrorOccurred:)withObject:self waitUntilDone:FALSE];
		return nil;
	}
	NSDictionary *ResultSet = parsedJSON[@"photos"];
	if(ResultSet==nil){
		self.error= [NSError errorWithDomain:NSLocalizedStringFromTable(@"JSON mal formado ResultSet=nil",@"Localizable", @"JSON mal formado") code:401 userInfo:nil];
		[self.delegate performSelectorOnMainThread:@selector(parseErrorOccurred:)withObject:self waitUntilDone:FALSE];
		return nil;
	}
	BFLog(@"totalResultsReturned: %@", [ResultSet objectForKey:@"total"]);
	NSArray* Result = ResultSet[@"photo"];
	BFLog(@"did download resource %@", Result);
	return Result;
}


@end
