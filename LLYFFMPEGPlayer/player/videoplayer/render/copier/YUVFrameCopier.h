//
//  YUVFrameCopier.h
//  video_player
//
//  Created by apple on 16/9/1.
//  Copyright © 2016年 xiaokai.zhan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BaseEffectFilter.h"
#import "LLYDecoder.h"

@interface YUVFrameCopier : BaseEffectFilter

- (void) renderWithTexId:(LLYVideoFrame*) videoFrame;

@end
