//
//  IBTParser.h
//  webServicesText
//
//  Created by Dario Lencina on 2/1/11.
//  Copyright 2011 Ironbit. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "JSON.h"


@class FlickrImageParser;

@protocol FlickrImageParserDelegate
- (void)didFinishParsing:(FlickrImageParser *)parser;
- (void)parserDidDownloadImage:(FlickrImageParser *)parser;
- (void)parseErrorOccurred:(FlickrImageParser *)parser;
@end

@interface FlickrImageParser : NSOperation {

}

@property(nonatomic, strong)    NSError * error;
@property(nonatomic, strong)    NSArray * images;
@property(nonatomic, strong)    NSString * searchCriteria;
@property(nonatomic, strong)    NSData * dataToParse;
@property(unsafe_unretained, atomic) id delegate;

- (id)initWithData:(NSData *)data criteria:(NSString *) criteria delegate:(id <FlickrImageParserDelegate>)theDelegate;
-(NSArray *)resultsFromString:(NSString *)string;
@end




