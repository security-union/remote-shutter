/*
 *  BFLog.h
 *  Fuck
 *
 *  Created by Dario Lencina on 6/23/10.
 *  Copyright 2010 __MyCompanyName__. All rights reserved.
 *
 */

#ifdef DEBUGLOGMODE
#define BFLog(s, ...) NSLog(@"%@**************************", [self class]); NSLog(s, ##__VA_ARGS__)
#else
#define BFLog(s, ...)
#endif
