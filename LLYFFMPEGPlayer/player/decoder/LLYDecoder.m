//
//  LLYDecoder.m
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/9.
//  Copyright © 2018年 lly. All rights reserved.
//

#import "LLYDecoder.h"

@implementation LLYFrame

@end

@implementation LLYAudioFrame

@end

@implementation LLYVideoFrame

@end

@implementation LLYBuriedPoint

@end


@interface LLYDecoder (){
    
    AVFrame *_videoFrame;
    AVFrame *_audioFrame;
    
    CGFloat _fps;

    //解码到流的哪个位置了。。。
    CGFloat _decodePosition;
    
    BOOL _isSubscribe;
    BOOL _isEOF;

    //重采样相关，判断当前音频流格式是否支持，不支持的话需要重采样
    SwrContext *_swrContext;
    void *_swrBuffer;
    NSUInteger _swrBufferSize;
    
    //像素转换相关
    AVPicture _picture;
    BOOL _pictureValid;
    struct SwsContext *_swsContext;

    //打断超时时长
    int _subscribeTimeOutTimeInSecs;
    
    //当前读取最后一帧时的的绝对时间
    int _readLastestFrameTime;
    
    BOOL _interrupted;
    
    int _connectionRetry;
}

@end


@implementation LLYDecoder

@end
