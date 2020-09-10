//
//  CPSoundManager.h
//  Clapmera
//
//  Created by Dario Lencina on 5/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <AVFoundation/AVFoundation.h>
#include <AudioToolbox/AudioToolbox.h>

typedef enum CPSoundManagerAudioType {
    CPSoundManagerAudioTypeSlow=0,
    CPSoundManagerAudioTypeFast
    } CPSoundManagerAudioType;

@interface CPSoundManager : NSObject{
    //TODO: Understand why the plain C implementation of this doesn't work, but this is good enough for the current devices.
    AVAudioPlayer * player;
}


- (void) stopPlayer;

- (void) playBeepSound: (CPSoundManagerAudioType) audioId;

- (void) vibrate: (id) sender;

@end