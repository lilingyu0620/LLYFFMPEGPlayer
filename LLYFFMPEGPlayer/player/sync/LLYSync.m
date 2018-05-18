//
//  LLYSync.m
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/9.
//  Copyright © 2018年 lly. All rights reserved.
//

#import "LLYSync.h"
#import <pthread/pthread.h>

#define LOCAL_MIN_BUFFERED_DURATION                     0.5
#define LOCAL_MAX_BUFFERED_DURATION                     1.0
#define NETWORK_MIN_BUFFERED_DURATION                   2.0
#define NETWORK_MAX_BUFFERED_DURATION                   4.0
#define LOCAL_AV_SYNC_MAX_TIME_DIFF                     0.05
#define FIRST_BUFFER_DURATION                           0.5

NSString * const kMIN_BUFFERED_DURATION = @"Min_Buffered_Duration";
NSString * const kMAX_BUFFERED_DURATION = @"Max_Buffered_Duration";

@interface LLYSync (){
    
    LLYDecoder *_decoder;
    
    //是否使用硬件解码
    BOOL _usingHWCodec;
    
    BOOL isDecoding;
    BOOL isInitializeDecodeThread;
    BOOL isDestoryed;
    
    //解码首屏数据的处理
    BOOL isFirstScreen;
    pthread_mutex_t decodeFirstBufferLock;
    pthread_cond_t decodeFirstBufferCondition;
    pthread_t decodeFirstBufferThread;
    BOOL isDecodingFirstBuffer;
    NSInteger _firstBufferDuration;

    
    pthread_mutex_t decoderLock;
    pthread_cond_t decoderCondition;
    pthread_t decoderThread;
    
    NSMutableArray *_videoFrames;
    NSMutableArray *_audioFrames;
    
    /** 分别是当外界需要音频数据和视频数据的时候, 全局变量缓存数据 **/
    NSData *_currentAudioFrame;
    NSUInteger _currentAudioFramePos;
    CGFloat _audioPosition;
    LLYVideoFrame* _currentVideoFrame;
    
    /** 控制何时该解码 **/
    BOOL _buffered;
    //解码的数据总时长
    CGFloat _bufferedDuration;
    
    //
    CGFloat _minBufferedDuration;
    CGFloat _maxBufferedDuration;
    
    //音视频同步时的最大时差
    CGFloat _syncMaxTimeDiff;
    
    BOOL _completion;

    NSTimeInterval _bufferedBeginTime;
    NSTimeInterval _bufferedTotalTime;
    
    int _decodeErrorState;
    NSTimeInterval _decodeErrorBeginTime;
    NSTimeInterval _decodeErrorTotalTime;
}


@end

@implementation LLYSync

#pragma mark - life cycle

- (instancetype)initWithPlayerStatusDelegate:(id<LLYPlayerStatusDelegate>)delegate{
    self = [super init];
    if (self) {
        self.delegate = delegate;
    }
    return self;
}

- (void)initPropertyWithPath:(NSString *)path Parameters:(NSDictionary *)parameters{
    
    //1、创建decoder实例
//    _decoder = [[LLYDecoder alloc]init];
    //2、初始化成员变量
    _currentVideoFrame = NULL;
    _currentAudioFramePos = 0;
    
    _bufferedBeginTime = 0;
    _bufferedTotalTime = 0;
    
    _decodeErrorBeginTime = 0;
    _decodeErrorTotalTime = 0;
    
    isFirstScreen = YES;
    
    _minBufferedDuration = [parameters[kMIN_BUFFERED_DURATION] floatValue];
    _maxBufferedDuration = [parameters[kMAX_BUFFERED_DURATION] floatValue];
    
    BOOL isNetwork = isNetworkPath(path);
    if (ABS(_minBufferedDuration - 0.f) < CGFLOAT_MIN) {
        if(isNetwork){
            _minBufferedDuration = NETWORK_MIN_BUFFERED_DURATION;
        } else{
            _minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
        }
    }
    
    if ((ABS(_maxBufferedDuration - 0.f) < CGFLOAT_MIN)) {
        if(isNetwork){
            _maxBufferedDuration = NETWORK_MAX_BUFFERED_DURATION;
        } else{
            _maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
        }
    }
    
    if (_minBufferedDuration > _maxBufferedDuration) {
        float temp = _minBufferedDuration;
        _minBufferedDuration = _maxBufferedDuration;
        _maxBufferedDuration = temp;
    }
    
    _syncMaxTimeDiff = LOCAL_AV_SYNC_MAX_TIME_DIFF;
    _firstBufferDuration = FIRST_BUFFER_DURATION;
}


#pragma mark - 文件打开与关闭

- (LLYOpenStatus)openFile:(NSString *)path parameters:(NSDictionary *)parameters error:(NSError **)pError{
    
    [self initPropertyWithPath:path Parameters:parameters];
    
    //3、打开流并且解析出来音视频流的Context
    BOOL openCode = [_decoder openFile:path parameter:parameters error:pError];
    if (!openCode || ![_decoder isSubscribed] || isDestoryed) {
        NSLog(@"VideoDecoder decode file fail...");
        [self closeDecoder];
        return [_decoder isSubscribed] ? LLY_OPEN_FAILED : LLY_CLIENT_CANCEL;
    }
    
    //4、回调客户端视频宽高以及duration
    NSUInteger videoWidth = [_decoder frameWidth];
    NSUInteger videoHeight = [_decoder frameHeight];
    if(videoWidth <= 0 || videoHeight <= 0){
        return [_decoder isSubscribed] ? LLY_OPEN_FAILED : LLY_CLIENT_CANCEL;
    }
  
    //5、开启解码线程与解码队列
    _audioFrames        = [NSMutableArray array];
    _videoFrames        = [NSMutableArray array];
    [self startDecoderThread];
    [self startDecodeFirstBufferThread];
    
    return LLY_OPEN_SUCCESS;
    
}
- (LLYOpenStatus)openFile:(NSString *)path error:(NSError **)pError{
    return 0;
}

- (LLYOpenStatus)openFile:(NSString *)path usingHWCodec:(BOOL)usingHWCodec parameters:(NSDictionary *)parameters error:(NSError **)pError{
    
    //1、创建decoder实例
    if(usingHWCodec){
        BOOL isIOS8OrUpper = ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0);
        if(!isIOS8OrUpper){
            usingHWCodec = false;
        }
    }
    _usingHWCodec = usingHWCodec;
    [self createDecoderInstance];
    
    return [self openFile:path parameters:parameters error:pError];
}

- (LLYOpenStatus)openFile:(NSString *)path usingHWCodec:(BOOL)usingHWCodec error:(NSError **)pError{
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[FPS_PROBE_SIZE_CONFIGURED] = @(true);
    parameters[PROBE_SIZE] = @(50 * 1024);
    NSMutableArray* durations = [NSMutableArray array];
    durations[0] = @(1250000);
    durations[0] = @(1750000);
    durations[0] = @(2000000);
    parameters[MAX_ANALYZE_DURATION_ARRAY] = durations;
    return [self openFile:path usingHWCodec:usingHWCodec parameters:parameters error:pError];
}

static BOOL isNetworkPath (NSString *path){
    NSRange r = [path rangeOfString:@":"];
    if (r.location == NSNotFound)
        return NO;
    NSString *scheme = [path substringToIndex:r.length];
    if ([scheme isEqualToString:@"file"])
        return NO;
    return YES;
}


- (void)closeFile{
    
    if (_decoder){
        [_decoder interrupt];
    }
    [self destroyDecodeFirstBufferThread];
    [self destroyDecoderThread];
    if([_decoder isOpenInputSuccess]){
        [self closeDecoder];
    }
    
    @synchronized(_videoFrames) {
        [_videoFrames removeAllObjects];
    }
    
    @synchronized(_audioFrames) {
        [_audioFrames removeAllObjects];
        _currentAudioFrame = nil;
    }
    NSLog(@"present diff video frame cnt is %d invalidGetCount is %d", count, invalidGetCount);
}

- (void)closeDecoder{
    if (_decoder) {
        [_decoder closeFile];
        if (self.delegate && [self.delegate respondsToSelector:@selector(buriedPointCallback:)]) {
            [self.delegate buriedPointCallback:[_decoder getBuriedPoint]];
        }
        _decoder = nil;
    }
}

#pragma mark - 解码相关

- (BOOL)addFrames:(NSArray *)frames duration:(CGFloat)duration{
    if (_decoder.validVideo) {
        @synchronized(_videoFrames){
            for (LLYFrame *frame in frames) {
                if (frame.frameType == LLYFrameType_Video || frame.frameType == LLYFrameType_HardVideo) {
                    [_videoFrames addObject:frame];
                    NSLog(@"_videoFrames 正在装数据.........");
                }
            }
            NSLog(@"videoFramesCount = %lu",(unsigned long)_videoFrames.count);
        }
    }
    
    if (_decoder.validAudio) {
        @synchronized(_audioFrames){
            for (LLYFrame *frame in frames) {
                if (frame.frameType == LLYFrameType_Audio) {
                    [_audioFrames addObject:frame];
                    _bufferedDuration += frame.duration;
                }
            }
        }
    }
    return _bufferedDuration < duration;
}

- (void) signalDecoderThread{
    if(NULL == _decoder || isDestoryed) {
        return;
    }
    if(!isDestoryed) {
        pthread_mutex_lock(&decoderLock);
        //        NSLog(@"Before signal First decode Buffer...");
        pthread_cond_signal(&decoderCondition);
        //        NSLog(@"After signal First decode Buffer...");
        pthread_mutex_unlock(&decoderLock);
    }
}

- (void)startDecoderThread{
    
    NSLog(@"AVSynchronizer::startDecoderThread ...");
    isDestoryed = NO;
    isDecoding = YES;
    
    pthread_mutex_init(&decoderLock, NULL);
    pthread_cond_init(&decoderCondition, NULL);
    isInitializeDecodeThread = YES;
    pthread_create(&decoderThread, NULL, runDecoderThread, (__bridge void *)self);
    
}

- (void)startDecodeFirstBufferThread{
    
    pthread_mutex_init(&decodeFirstBufferLock, NULL);
    pthread_cond_init(&decodeFirstBufferCondition, NULL);
    isDecodingFirstBuffer = true;
    
    pthread_create(&decodeFirstBufferThread, NULL, decodeFirstBufferRunLoop, (__bridge void*)self);
    
}

- (void) destroyDecodeFirstBufferThread {
    if (isDecodingFirstBuffer) {
        NSLog(@"Begin Wait Decode First Buffer...");
        double startWaitDecodeFirstBufferTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
        pthread_mutex_lock(&decodeFirstBufferLock);
        pthread_cond_wait(&decodeFirstBufferCondition, &decodeFirstBufferLock);
        pthread_mutex_unlock(&decodeFirstBufferLock);
        int wasteTimeMills = CFAbsoluteTimeGetCurrent() * 1000 - startWaitDecodeFirstBufferTimeMills;
        NSLog(@" Wait Decode First Buffer waste TimeMills is %d", wasteTimeMills);
    }
}

- (void) destroyDecoderThread {
    NSLog(@"AVSynchronizer::destroyDecoderThread ...");

    isDestoryed = true;
    isDecoding = false;
    if (!isInitializeDecodeThread) {
        return;
    }
    
    void* status;
    pthread_mutex_lock(&decoderLock);
    pthread_cond_signal(&decoderCondition);
    pthread_mutex_unlock(&decoderLock);
    pthread_join(decoderThread, &status);
    pthread_mutex_destroy(&decoderLock);
    pthread_cond_destroy(&decoderCondition);
}
- (void)decodeFirstBuffer{
    
    double startDecodeFirstBufferTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
    [self decodeFramesWithDuration:FIRST_BUFFER_DURATION];
    int wasteTimeMills = CFAbsoluteTimeGetCurrent() * 1000 - startDecodeFirstBufferTimeMills;
    NSLog(@"Decode First Buffer waste TimeMills is %d", wasteTimeMills);
    pthread_mutex_lock(&decodeFirstBufferLock);
    pthread_cond_signal(&decodeFirstBufferCondition);
    pthread_mutex_unlock(&decodeFirstBufferLock);
    isDecodingFirstBuffer = false;
    
}

- (void)decodeFramesWithDuration:(CGFloat) duration{
    
    BOOL good = YES;
    while (good) {
        good = NO;
        @autoreleasepool {
            if (_decoder && (_decoder.validVideo || _decoder.validAudio)) {
                int tmpDecodeVideoErrorState;
                NSArray *frames = [_decoder decode:0.0f errorState:&tmpDecodeVideoErrorState];
                if (frames.count) {
//                    NSLog(@"首屏解码成功啦！！！！！！！！！！！！");
                    good = [self addFrames:frames duration:duration];
                }
            }
        }
    }
}

- (void)decodeFrames{
    const CGFloat duration = 0.0f;
    BOOL good = YES;
    while (good) {
        good = NO;
        @autoreleasepool {
            if (_decoder && (_decoder.validVideo || _decoder.validAudio)) {
                NSArray *frames = [_decoder decode:duration errorState:&_decodeErrorState];
                if (frames.count) {
//                    NSLog(@"解码成功啦！！！！！！！！！！！！");
                    good = [self addFrames:frames duration:_maxBufferedDuration];
                }
            }
        }
    }
}

static void * runDecoderThread(void* ptr){
    LLYSync *sync = (__bridge LLYSync *)ptr;
    [sync run];
    return NULL;
}

static void * decodeFirstBufferRunLoop(void* ptr){
    LLYSync *sync = (__bridge LLYSync *)ptr;
    [sync decodeFirstBuffer];
    return NULL;
}

#pragma mark - 音视频数据

- (void)audioCallbackFillData:(SInt16 *)outData numFrames:(UInt32)numFrames numChannels:(UInt32)numChannels{
    
    [self checkPlayerStatus];
    
    //如果当前正在解码就返回空数据
//    if (_buffered) {
//        memset(outData, 0, numFrames * numChannels * sizeof(SInt16));
//        return;
//    }
    
    @autoreleasepool{
        while (numFrames > 0) {
            if (!_currentAudioFrame) {
                
                //从队列中取出音频数据
                @synchronized(_audioFrames){
                    NSUInteger count = _audioFrames.count;
                    if (count) {
                        LLYAudioFrame *frame = _audioFrames[0];
                        _bufferedDuration -= frame.duration;
                        
                        [_audioFrames removeObjectAtIndex:0];
                        _audioPosition = frame.position;
                        
                        _currentAudioFrame = frame.sampleData;
                        _currentAudioFramePos = 0;
                        
                    }
                }
            }
            
            if (_currentAudioFrame) {
                
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(SInt16);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
//                NSLog(@"音频正在输出zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz");
                
                //该帧数据已经用完的话需要置空当前帧
                if (bytesToCopy < bytesLeft)
                    _currentAudioFramePos += bytesToCopy;
                else
                    _currentAudioFrame = nil;
            }
            else{
                memset(outData, 0, numFrames * numChannels * sizeof(SInt16));
                break;
            }
        }
    }
}

static int count = 0;
static int invalidGetCount = 0;
float lastPosition = -1.0;

- (LLYVideoFrame *)getCorrectVideoFrame{
    LLYVideoFrame *videoFrame = nil;
    @synchronized(_videoFrames){
        while (_videoFrames.count > 0) {
            videoFrame = _videoFrames[0];
            const CGFloat delta = _audioPosition - videoFrame.position;
            NSLog(@"audioPosition = %f",_audioPosition);
            NSLog(@"videoPosition = %f",videoFrame.position);
            if (delta < (0 - _syncMaxTimeDiff)) {
//                NSLog(@"视频比音频快了好多,我们还是渲染上一帧");
                videoFrame = nil;
                break;
            }

            [_videoFrames removeObjectAtIndex:0];
            if (delta > _syncMaxTimeDiff) {
//                NSLog(@"视频比音频慢了好多,我们需要继续从queue拿到合适的帧 _audioPosition is %.3f frame.position %.3f", _audioPosition, videoFrame.position);
                videoFrame = nil;
                continue;
            }else{
                break;
            }
            break;
        }
    }
    
    if (videoFrame) {
        if (isFirstScreen) {
            [_decoder triggerFirstScreen];
            isFirstScreen = NO;
        }
        
        if (nil != _currentVideoFrame) {
            _currentVideoFrame = nil;
        }
        _currentVideoFrame = videoFrame;
        
        NSLog(@"视频文件正在输出vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv");
    }
    
    if (fabs(_currentVideoFrame.position - lastPosition) > 0.01f) {
        lastPosition = _currentVideoFrame.position;
        count++;
        return _currentVideoFrame;
    }
    else{
        invalidGetCount++;
        return nil;
    }
}
- (void)checkPlayerStatus{
    if (NULL == _decoder) {
        return;
    }
    
    if (_buffered && (_bufferedDuration > _minBufferedDuration)) {
        _buffered = NO;
        if (self.delegate && [self.delegate respondsToSelector:@selector(hideLoading)]) {
            [self.delegate hideLoading];
        }
    }
    
    if (1 == _decodeErrorState) {
        _decodeErrorState = 0;
        if (_minBufferedDuration > 0 && !_buffered) {
            _buffered = YES;
            _decodeErrorBeginTime = [[NSDate date]timeIntervalSince1970];
        }
        
        _decodeErrorTotalTime = [[NSDate date]timeIntervalSince1970] - _decodeErrorBeginTime;
        
        if (_decodeErrorTotalTime > TIMEOUT_DECODE_ERROR) {
            NSLog(@"decodeVideoErrorTotalTime = %f", _decodeErrorTotalTime);
            _decodeErrorTotalTime = 0;
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (self.delegate && [self.delegate respondsToSelector:@selector(restart)]) {
                    [self.delegate restart];
                }
            });
        }
        return;
    }
    
    
    const NSUInteger leftVideoFrames = _decoder.validVideo ? _videoFrames.count : 0;
    const NSUInteger leftAudioFrames = _decoder.validAudio ? _audioFrames.count : 0;
    if (leftAudioFrames == 0 || leftVideoFrames == 0) {
        [_decoder addStreamStatus:@"E"];
        if (_minBufferedDuration > 0 && !_buffered) {
            _buffered = YES;
            _decodeErrorBeginTime = [[NSDate date]timeIntervalSince1970];
        }
        if (self.delegate && [self.delegate respondsToSelector:@selector(showLoading)]) {
            [self.delegate showLoading];
        }
        
        if ([_decoder isEOF]) {
            if (self.delegate && [self.delegate respondsToSelector:@selector(onComplete)]) {
                _completion = YES;
                [self.delegate onComplete];
            }
        }
    }
    
    if (_buffered) {
        _decodeErrorTotalTime = [[NSDate date]timeIntervalSince1970] - _decodeErrorBeginTime;
        if (_decodeErrorTotalTime > TIMEOUT_DECODE_ERROR) {
            NSLog(@"decodeVideoErrorTotalTime = %f", _decodeErrorTotalTime);
            _decodeErrorTotalTime = 0;
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (self.delegate && [self.delegate respondsToSelector:@selector(restart)]) {
                    [self.delegate restart];
                }
            });
        }
    }
    if (!isDecodingFirstBuffer && (0 == leftVideoFrames || 0 == leftAudioFrames)) {
        //释放线程
        [self signalDecoderThread];
    }
    else if (_bufferedDuration >= _maxBufferedDuration){
        [_decoder addStreamStatus:@"F"];
    }
    
}


#pragma mark - 外部状态控制相关

- (void)run{
    while(isDecoding){
        pthread_mutex_lock(&decoderLock);
        //        NSLog(@"Before wait First decode Buffer...");
        pthread_cond_wait(&decoderCondition, &decoderLock);
        //        NSLog(@"After wait First decode Buffer...");
        pthread_mutex_unlock(&decoderLock);
        //            LOGI("after pthread_cond_wait");
        [self decodeFrames];
    }
}
- (BOOL)isOpenInputSuccess{
    
    BOOL bRet = NO;
    if (_decoder) {
        bRet = [_decoder isOpenInputSuccess];
    }
    return bRet;
    
}
- (void)interrupt{
    if (_decoder) {
        [_decoder interrupt];
    }
}
- (BOOL)isPlayCompleted{
    return _completion;
}
- (BOOL)isValid{
    if(_decoder && ![_decoder validVideo] && ![_decoder validAudio]){
        return NO;
    }
    return YES;
}

#pragma mark - 其他属性

- (void)createDecoderInstance{
    if(_usingHWCodec){
        _decoder = [[LLYHardDecoder alloc] init];
    } else {
        _decoder = [[LLYDecoder alloc] init];
    }
}


//使用硬件编码 (暂时没实现硬解)
- (BOOL)usingHWCodec{
    return _usingHWCodec;
}

//音频采样率
- (NSInteger)getAudioSampleRate{
    if (_decoder) {
        return [_decoder sampleRate];
    }
    return 0;
}
- (NSInteger)getAudioChannels{
    if (_decoder) {
        return [_decoder channels];
    }
    return 0;
}

- (CGFloat)getVideoFPS{
    if (_decoder) {
        return [_decoder getVideoFPS];
    }
    return 0.0f;
}
- (NSInteger)getVideoFrameHeight{
    if (_decoder) {
        return [_decoder frameHeight];
    }
    return 0;
}

- (NSInteger)getVideoFrameWidth{
    if (_decoder) {
        return [_decoder frameWidth];
    }
    return 0;
}

- (CGFloat)getDuration{
    if (_decoder) {
        return [_decoder getDuration];
    }
    return 0.0f;
}
@end
