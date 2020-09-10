//
//  CPSoundManager.m
//  Clapmera
//
//  Created by Dario Lencina on 5/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "CPSoundManager.h"

@implementation CPSoundManager


static NSURL * beepURL = nil;
static NSURL * fastBeepURL = nil;


- (id) init {    
    self=[super init];    
    
    // Create the URL for the source audio file. The URLForResource:withExtension: method is new in iOS 4.0.    
    return self;
}

-(NSURL *)beep:(CPSoundManagerAudioType)beepType{
    if (beepType == CPSoundManagerAudioTypeFast) {
        if(!fastBeepURL){
            fastBeepURL= [[NSBundle mainBundle] URLForResource:@"fastBeep" withExtension:@"aif"];
        }
        
        return fastBeepURL;
    } else {
        if(!beepURL){
            beepURL = [[NSBundle mainBundle] URLForResource:@"beep" withExtension:@"m4a"];
        }
        
        return beepURL;
    }
}

- (void) playBeepSound: (CPSoundManagerAudioType) audioId {    
    [self stopPlayer];

    player = [[AVAudioPlayer alloc] initWithContentsOfURL:[self beep:audioId] error:nil];
    
    [player play];
}

- (void)stopPlayer
{
    if(player){
        [player stop];
        player = nil;
    }
}

- (void) vibrate: (id) sender {
    
//    AudioServicesPlaySystemSound (kSystemSoundID_Vibrate);
//    I think a vibration would be anoying becase if you put the iPhone just laying on its side, maybe it could fall with the movement
    NSLog(@"not implemented!!!");
}

- (void) dealloc {
    if(player){
        player = nil;
    }
    
    if (fastBeepURL) {
        fastBeepURL = nil;
    }
    
    if (beepURL) {
        beepURL = nil;
    }
    
}

@end