//
//  LLYVideoPlayer.h
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/17.
//  Copyright © 2018年 lly. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "BaseEffectFilter.h"
#import "LLYDecoder.h"

@interface LLYVideoPlayer : UIView

- (id) initWithFrame:(CGRect)frame textureWidth:(NSInteger)textureWidth textureHeight:(NSInteger)textureHeight usingHWCodec: (BOOL) usingHWCodec;
- (id) initWithFrame:(CGRect)frame textureWidth:(NSInteger)textureWidth textureHeight:(NSInteger)textureHeight shareGroup:(EAGLSharegroup *)shareGroup usingHWCodec: (BOOL) usingHWCodec;

- (void) presentVideoFrame:(LLYVideoFrame*) frame;

- (BaseEffectFilter*) createImageProcessFilterInstance;
- (BaseEffectFilter*) getImageProcessFilterInstance;

- (void) destroy;

@end
