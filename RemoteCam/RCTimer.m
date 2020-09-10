//
//  RCTimer.m
//  Remote
//
//  Created by Dario Lencina on 4/21/13.
//  Copyright (c) 2013 Dario Lencina. All rights reserved.
//

#import "RCTimer.h"

@interface RCTimer ()
    @property(nonatomic, strong) NSTimer * tickTimer;
    @property(nonatomic, copy) RCTimerTick tickHandler;
    @property(nonatomic, copy) RCTimerTick cancelHandler;
    @property(nonatomic, copy) RCTimerCompletion completionHandler;
    @property(nonatomic, assign) NSInteger duration;
@end

@implementation RCTimer

-(void)cancel{
    if(self.cancelHandler){
        self.cancelHandler(self);
    }
    if(self.tickTimer){
        [self.tickTimer invalidate];
        self.tickTimer=nil;
    }
}

-(NSInteger)timeRemaining{
    return self.duration;
}

-(void)startTimerWithDuration:(NSInteger)duration withTickHandler:(RCTimerTick)tick cancelHandler:(RCTimerTick)cancelHandler andCompletionHandler:(RCTimerCompletion)completionHandler{
    if(duration==0){
        completionHandler(self);
        return;
    }

    self.duration=duration;
    self.tickHandler=tick;
    self.completionHandler=completionHandler;
    self.cancelHandler=cancelHandler;
    self.tickTimer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(timerTick:) userInfo:nil repeats:NO];
}

-(void)timerTick:(NSTimer *)timer{
    self.duration--;
    if(self.duration>0){
        self.tickHandler(self);
        self.tickTimer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(timerTick:) userInfo:nil repeats:NO];
    }else{
        self.completionHandler(self);
    }
}

@end
