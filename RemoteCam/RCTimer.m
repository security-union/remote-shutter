//
//  RCTimer.m
//  Remote
//
//  Created by Dario Lencina on 4/21/13.
//  Copyright (c) 2013 Dario Lencina. All rights reserved.
//

#import "RCTimer.h"

@interface RCTimer ()
@property(nonatomic, copy) RCTimerTick tickHandler;
@property(nonatomic, copy) RCTimerCompletion completionHandler;
@property(nonatomic, assign) NSInteger duration;
@property(nonatomic, assign) BOOL isCanceled;
@end

@implementation RCTimer

- (void)cancel {
    _isCanceled = true;
    _completionHandler = nil;
    _tickHandler = nil;
}

- (NSInteger)timeRemaining {
    return self.duration;
}

- (void)startTimerWithDuration:(NSInteger)duration withTickHandler:(RCTimerTick)tick andCompletionHandler:(RCTimerCompletion)completionHandler {
    if (duration == 0) {
        completionHandler(self);
        return;
    }

    self.duration = duration;
    self.tickHandler = tick;
    self.completionHandler = completionHandler;
    self.isCanceled = false;
    [self scheduleTimer];
}

- (void)scheduleTimer {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && !strongSelf.isCanceled) {
            strongSelf.duration--;
            if (strongSelf.duration > 0) {
                strongSelf.tickHandler(strongSelf);
                [strongSelf scheduleTimer];
            } else {
                strongSelf.completionHandler(self);
                strongSelf.completionHandler = nil;
                strongSelf.tickHandler = nil;
            }
        }
    });
}

@end
