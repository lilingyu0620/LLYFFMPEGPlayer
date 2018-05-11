//
//  LLYDecoder.h
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/9.
//  Copyright © 2018年 lly. All rights reserved.
//
//  解码类
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CVImageBuffer.h>

#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/pixdesc.h"

//帧类型
typedef NS_ENUM(NSUInteger, LLYFrameType) {
    LLYFrameType_Audio = 0,
    LLYFrameType_Video,
};


//数据统计
@interface LLYBuriedPoint : NSObject

//开始试图去打开一个数据流的绝对时间
@property (nonatomic, assign) long long beginOpenTime;
//成功打开流花费时间
@property (nonatomic, assign) float successOpenTime;
//首屏时间
@property (nonatomic, assign) float firstScreenTimeMills;
//流打开失败花费时间
@property (nonatomic, assign) float failOpenTime;
//流打开失败类型
@property (nonatomic, assign) float failOpenType;
//打开流重试次数
@property (nonatomic, assign) int retryTimes;
//拉流时长
@property (nonatomic, assign) float duration;
//拉流状态
@property (nonatomic, strong) NSMutableArray *streamStatusArray;

@end

@interface LLYFrame : NSObject

@property (nonatomic, assign) LLYFrameType frameType;
@property (nonatomic, assign) CGFloat position;
@property (nonatomic, assign) CGFloat duration;

@end

@interface LLYAudioFrame : LLYFrame

@property (nonatomic, strong) NSData *sampleData;

@end


@interface LLYVideoFrame : LLYFrame

@property (nonatomic, assign) NSUInteger width;
@property (nonatomic, assign) NSUInteger height;
@property (nonatomic, assign) NSUInteger lineSize;
@property (nonatomic, strong) NSData *luma;
@property (nonatomic, strong) NSData *chromaB;
@property (nonatomic, strong) NSData *chromaR;
@property (nonatomic, strong) id imageBuffer;

@end


#ifndef SUBSCRIBE_VIDEO_DATA_TIME_OUT
#define SUBSCRIBE_VIDEO_DATA_TIME_OUT               20
#endif

#ifndef NET_WORK_STREAM_RETRY_TIME
#define NET_WORK_STREAM_RETRY_TIME                  3
#endif

#ifndef RTMP_TCURL_KEY
#define RTMP_TCURL_KEY                              @"RTMP_TCURL_KEY"
#endif

#ifndef FPS_PROBE_SIZE_CONFIGURED
#define FPS_PROBE_SIZE_CONFIGURED                   @"FPS_PROBE_SIZE_CONFIGURED"
#endif

#ifndef PROBE_SIZE
#define PROBE_SIZE                                  @"PROBE_SIZE"
#endif

#ifndef MAX_ANALYZE_DURATION_ARRAY
#define MAX_ANALYZE_DURATION_ARRAY                  @"MAX_ANALYZE_DURATION_ARRAY"
#endif

@interface LLYDecoder : NSObject{
    
    AVFormatContext *_formatCtx;
    
    BOOL _isOpenInputSuccess;
    
    LLYBuriedPoint *_buriedPoint;
    
    int totalVideoFrameCount;
    long long decodeVideoFrameWasteTimeMills;
    
    //保存解码前的音视频流的索引
    NSArray *_videoStreams;
    NSArray *_audioStreams;
    
    //当前打开的音视频流的索引
    NSInteger _videoStreamIndex;
    NSInteger _audioStreamIndex;
    
    //音视频相关解码信息
    AVCodecContext *_videoCodecCtx;
    AVCodecContext *_audioCodecCtx;
    
    CGFloat _videoTimeBase;
    CGFloat _audioTimeBase;
}

/**
 打开流文件

 @param path 地址可以是本地地址和网络地址
 @param parameter <#parameter description#>
 @param pError <#pError description#>
 @return <#return value description#>
 */
- (BOOL)openFile:(NSString *)path parameter:(NSDictionary *)parameter error:(NSError **)pError;
- (void)closeFile;
- (BOOL)isOpenInputSuccess;//文件打开是否成功

//打开视频流
- (BOOL)openVideoStream;
- (void)closeVideoStream;

//打开音频流
- (BOOL)openAudioStream;
- (void)closeAudioStream;

/**
 解码

 @param minDuration 解码时长
 @param errorState 错误状态
 @return 返回一个已解码的帧数组
 */
- (NSArray *)decode:(CGFloat)minDuration errorState:(int *)errorState;

/**
 解packet，在解码函数中调用

 @param packet <#packet description#>
 @param pktSize <#pktSize description#>
 @param errorState <#errorState description#>
 @return 返回一个已解码的帧
 */
- (LLYFrame *)decodePacket:(AVPacket *)packet packetSize:(int)pktSize errorState:(int *)errorState;

//打断
- (void)interrupt;
//打断状态
- (BOOL)detectInterrupted;

/*
 埋点数据统计相关
 */
- (void)triggerFirstScreen;//触发首屏显示
- (void)addStreamStatus:(NSString *)status;
- (LLYBuriedPoint *)getBuriedPoint;

//流的结尾，标识当前解码结束
- (BOOL)isEOF;

//当前解码是否可用，在打断时会被标识为不可用
- (BOOL)isSubscribed;

//视频流的宽高
- (NSUInteger)frameWidth;
- (NSUInteger)frameHeight;

//音频采样率 44.1kHZ?
- (CGFloat)sampleRate;

//音频声道数
- (NSUInteger)channels;

//视频流是否可用
- (BOOL)validVideo;

//音频流是否可用
- (BOOL)validAudio;

//视频帧率
- (CGFloat)getVideoFPS;

//总时长
- (CGFloat)getDuration;

@end
