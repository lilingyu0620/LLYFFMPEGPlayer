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
    
    //当前读取最后一帧时的当前时间
    int _readLastestFrameTime;
    
    //打断标识
    BOOL _interrupted;
    
    //重连次数
    int _connectionRetry;
}

@end

#pragma mark - func define

//static int interrupt_callback(void *ctx);

@implementation LLYDecoder

#pragma mark - 流的打开关闭

- (BOOL)openFile:(NSString *)path parameter:(NSDictionary *)parameter error:(NSError **)pError{
    
    BOOL bRet = YES;
    if (nil == path) {
        return NO;
    }
    
    _connectionRetry = 0;
    totalVideoFrameCount = 0;
    _subscribeTimeOutTimeInSecs = SUBSCRIBE_VIDEO_DATA_TIME_OUT;
    _interrupted = NO;
    _isOpenInputSuccess = NO;
    _isSubscribe = YES;
    
    _buriedPoint = [[LLYBuriedPoint alloc]init];
    _buriedPoint.streamStatusArray = [NSMutableArray array];
    _buriedPoint.beginOpenTime = [[NSDate date] timeIntervalSince1970] * 1000;
    
    _readLastestFrameTime = [[NSDate date] timeIntervalSince1970] * 1000;//秒
    
    //初始化ffmpeg
    avformat_network_init();
    av_register_all();
    
    int openInputErrorCode = [self openInput:path paramater:parameter];
    if (openInputErrorCode > 0) {
        _buriedPoint.successOpenTime = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpenTime) / 1000.0f;
        _buriedPoint.failOpenTime = 0;
        _buriedPoint.failOpenType = 1;
        
        BOOL openVideoStatus = [self openVideoStream];
        BOOL openAudioStatus = [self openAudioStream];
        //打开音频流或者视频流失败
        if (!openVideoStatus || !openAudioStatus) {
            [self closeFile];
            bRet = NO;
        }
    }
    else{
        _buriedPoint.failOpenTime = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpenTime) / 1000.0f;
        _buriedPoint.successOpenTime = 0;
        _buriedPoint.failOpenType = openInputErrorCode;
    }
    //重连次数
    _buriedPoint.retryTimes = _connectionRetry;
    
    if (bRet) {
        //在网络的播放器中有可能会拉到长宽都为0 并且pix_fmt是None的流 这个时候我们需要重连
        NSInteger videoWidth = [self frameWidth];
        NSInteger videoHeight = [self frameHeight];
        int retryTimes = 5;
        
        while(((videoWidth <= 0 || videoHeight <= 0) && retryTimes > 0)){
            NSLog(@"because of videoWidth and videoHeight is Zero We will Retry...");
            usleep(500 * 1000);
            _connectionRetry = 0;
            bRet = [self openFile:path parameter:parameter error:pError];
            if(!bRet){
                continue;
            }
            retryTimes--;
            videoWidth = [self frameWidth];
            videoHeight = [self frameHeight];
        }
    }
    
    _isOpenInputSuccess = bRet;
    
    return bRet;
}

- (int)openInput:(NSString *)path paramater:(NSDictionary *)parameters{
    
    //初始化AVFormatContext
    AVFormatContext *formatCtx = avformat_alloc_context();
    AVIOInterruptCB int_cb = {interrupt_callback,(__bridge void *)self};
    formatCtx->interrupt_callback = int_cb;
    
    int openInputErrorCode = 0;
    if ((openInputErrorCode = [self openInputWithFormatCtx:&formatCtx path:path parameter:parameters]) != 0) {
        NSLog(@"Video decoder open input file failed... videoSourceURI is %@ openInputErr is %s", path, av_err2str(openInputErrorCode));
        if (formatCtx) {
            avformat_free_context(formatCtx);
        }
        return openInputErrorCode;
    }
    
    [self initAnalyzeDurationAndProbeSize:formatCtx parameter:parameters];
    
    int findStreamErrorCode = 0;
    double startFindStreamTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
    if ((findStreamErrorCode = avformat_find_stream_info(formatCtx, NULL)) < 0) {
        avformat_close_input(&formatCtx);
        avformat_free_context(formatCtx);
        NSLog(@"Video decoder find stream info failed... find stream ErrCode is %s", av_err2str(findStreamErrorCode));
    }
    
    int wasteTimeMills = CFAbsoluteTimeGetCurrent() * 1000 - startFindStreamTimeMills;
    NSLog(@"Find Stream Info waste TimeMills is %d", wasteTimeMills);

    if (formatCtx->streams[0]->codec->codec_id == AV_CODEC_ID_NONE) {
        avformat_close_input(&formatCtx);
        avformat_free_context(formatCtx);
        NSLog(@"Video decoder First Stream Codec ID Is UnKnown...");
        if ([self isNeedRetry]) {
            return [self openInput:path paramater:parameters];
        }
        else{
            return -1;
        }
    }
    
    _formatCtx = formatCtx;
    return 1;
}

- (int)openInputWithFormatCtx:(AVFormatContext **)formatCtx path:(NSString *)path parameter:(NSDictionary *)parameters{
    const char *inputURL = [path cStringUsingEncoding:NSUTF8StringEncoding];
    AVDictionary *options = NULL;
    //TCURL应该与流的CDN相关 如果原始的req中有tcUrl，就使用原始的
    NSString *rtmpTCURLStr = parameters[RTMP_TCURL_KEY];
    if (rtmpTCURLStr.length > 0) {
        const char *rtmpTcURL = [rtmpTCURLStr cStringUsingEncoding:NSUTF8StringEncoding];
        av_dict_set(&options, "rtmp_tcurl", rtmpTcURL, 0);
    }
    return avformat_open_input(formatCtx, inputURL, NULL, &options);
}

//个人理解是开始读取数据的延时和缓存空间（默认5M）
- (void)initAnalyzeDurationAndProbeSize:(AVFormatContext *)formatCtx parameter:(NSDictionary *)parameters{
    float probeSize = [parameters[PROBE_SIZE] floatValue];
    formatCtx->probesize = probeSize ?: 50 * 1024;
    NSArray *durations = parameters[MAX_ANALYZE_DURATION_ARRAY];
    if (durations && durations.count > _connectionRetry) {
        formatCtx->max_analyze_duration = [durations[_connectionRetry] floatValue];
    }
    else{
        //pow(x,y) x的y次方
        float multiplier = 0.5 + (double)pow(2.0, (double)_connectionRetry) * 0.25;
        formatCtx->max_analyze_duration = multiplier;
    }
    
    //帧率
    BOOL fpsProbeSizeConfiged = [parameters[FPS_PROBE_SIZE_CONFIGURED] floatValue];
    if (fpsProbeSizeConfiged) {
        formatCtx->fps_probe_size = 3;
    }
}

- (BOOL)isNeedRetry{
    _connectionRetry++;
    return _connectionRetry <= NET_WORK_STREAM_RETRY_TIME;
}
- (void)closeFile{
    
}
- (BOOL)isOpenInputSuccess{
    
}

//打开视频流
- (BOOL)openVideoStream{}
//关闭视频流
- (void)closeVideoStream{}

//打开音频流
- (BOOL)openAudioStream{}
//关闭音频流
- (void)closeAudioStream{}

#pragma mark -  解码

- (NSArray *)decode:(CGFloat)minDuration errorState:(int *)errorState{}

- (LLYFrame *)decodePacket:(AVPacket *)packet packetSize:(int)pktSize errorState:(int *)errorState{}

#pragma mark - 打断处理
//打断
- (void)interrupt{}
//打断状态
- (BOOL)detectInterrupted{}

static int interrupt_callback(void *ctx){
    
}

#pragma mark - 埋点数据统计相关

- (void)triggerFirstScreen{}
- (void)addStreamStatus:(NSString *)status{}
- (LLYBuriedPoint *)getBuriedPoint{}


#pragma mark - 其他属性

- (BOOL)isEOF{}

- (BOOL)isSubscribed{}

- (NSUInteger)frameWidth{}
- (NSUInteger)frameHeight{}

- (CGFloat)sampleRate{}

- (NSUInteger)channels{}

- (BOOL)validVideo{}

- (BOOL)validAudio{}

- (CGFloat)getVideoFPS{}

- (CGFloat)getDuration{}

@end
