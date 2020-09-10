//
//  RCTimer.h
//  Remote
//
//  Created by Dario Lencina on 4/21/13.
//  Copyright (c) 2013 Dario Lencina. All rights reserved.
//

#import <Foundation/Foundation.h>

@class RCTimer;
typedef void (^RCTimerTick)(RCTimer *timer);
typedef void (^RCTimerCompletion)(RCTimer *timer);

/**
Neat timer that uses blocks instead of the delegate pattern
*/

@interface RCTimer : NSObject

-(void)cancel;
-(void)startTimerWithDuration:(NSInteger)duration withTickHandler:(RCTimerTick)tick cancelHandler:(RCTimerTick)cancelHandler andCompletionHandler:(RCTimerCompletion)completionHandler;
-(NSInteger)timeRemaining;

@end
