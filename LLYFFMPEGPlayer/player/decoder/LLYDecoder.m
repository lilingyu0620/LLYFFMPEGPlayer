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
    av_register_all();
    avformat_network_init();
    
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
    NSLog(@"Enter closeFile...");
    if (_buriedPoint.failOpenType == 1) {
        _buriedPoint.duration = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpenTime) / 1000.0f;
    }
    
    [self interrupt];
    
    [self closeAudioStream];
    [self closeVideoStream];
    
    _videoStreams = nil;
    _audioStreams = nil;
    
    if (_formatCtx) {
        _formatCtx->interrupt_callback.opaque = NULL;
        _formatCtx->interrupt_callback.callback = NULL;
        avformat_close_input(&_formatCtx);
        _formatCtx = NULL;
    }
    float decodeFrameAVGTimeMills = (double)decodeVideoFrameWasteTimeMills / (float)totalVideoFrameCount;
    NSLog(@"Decoder decoder totalVideoFramecount is %d decodeFrameAVGTimeMills is %.3f", totalVideoFrameCount, decodeFrameAVGTimeMills);
}
- (BOOL)isOpenInputSuccess{
    return _isOpenInputSuccess;
}

//打开视频流
- (BOOL)openVideoStream{
    _videoStreamIndex = -1;
    _videoStreams = collectionStreams(_formatCtx, AVMEDIA_TYPE_VIDEO);
    for (NSNumber *index in _videoStreams) {
        const NSUInteger streamIndex = [index integerValue];
        AVCodecContext *codecCtx = _formatCtx->streams[streamIndex]->codec;
        //获取该stream对应的解码器
        AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
        if (!codec) {
            NSLog(@"Find Video Decoder Failed codec_id %d AV_CODEC_ID_H264 is %d", codecCtx->codec_id, AV_CODEC_ID_H264);
            return NO;
        }
        
        int openCodecErrorCode = 0;
        if ((openCodecErrorCode = avcodec_open2(codecCtx, codec, NULL)) < 0) {
            NSLog(@"open Video Codec Failed openCodecErr is %s", av_err2str(openCodecErrorCode));
            return NO;
        }
        
        _videoFrame = av_frame_alloc();
        if (!_videoFrame) {
            NSLog(@"Alloc Video Frame Failed...");
            avcodec_close(codecCtx);
            return NO;
        }
        
        _videoStreamIndex = streamIndex;
        _videoCodecCtx = codecCtx;
        AVStream *st = _formatCtx->streams[streamIndex];
        avStreamFPSTimeBase(st, 0.04, &_fps, &_videoTimeBase);
    }
    return YES;
}
//关闭视频流
- (void)closeVideoStream{
    _videoStreamIndex = -1;
    
    [self closeScaler];
    
    if (_videoFrame) {
        av_free(_videoFrame);
        _videoFrame = NULL;
    }
    
    if (_videoCodecCtx) {
        avcodec_close(_videoCodecCtx);
        _videoCodecCtx = NULL;
    }
}

//打开音频流
- (BOOL)openAudioStream{
    _audioStreamIndex = -1;
    _audioStreams = collectionStreams(_formatCtx, AVMEDIA_TYPE_AUDIO);
    for (NSNumber *index in _audioStreams) {
        const NSUInteger streamIndex = [index integerValue];
        AVCodecContext *codecCtx = _formatCtx->streams[streamIndex]->codec;
        //获取该stream对应的解码器
        AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
        if(!codec){
            NSLog(@"Find Audio Decoder Failed codec_id %d CODEC_ID_AAC is %d", codecCtx->codec_id, AV_CODEC_ID_AAC);
            return NO;
        }
        
        int openCodecErrorCode = 0;
        if ((openCodecErrorCode = avcodec_open2(codecCtx, codec, NULL)) < 0) {
            NSLog(@"open Audio Codec Failed openCodecErr is %s", av_err2str(openCodecErrorCode));
            return NO;
        }
        
        //是否需要重采样
        SwrContext *swrContext = NULL;
        if (![self audioCodecIsSupported:codecCtx]) {
            
            NSLog(@"because of audio Codec Is Not Supported so we will init swresampler...");
            /**
             * 初始化resampler
             * @param s               Swr context, can be NULL
             * @param out_ch_layout   output channel layout (AV_CH_LAYOUT_*)
             * @param out_sample_fmt  output sample format (AV_SAMPLE_FMT_*).
             * @param out_sample_rate output sample rate (frequency in Hz)
             * @param in_ch_layout    input channel layout (AV_CH_LAYOUT_*)
             * @param in_sample_fmt   input sample format (AV_SAMPLE_FMT_*).
             * @param in_sample_rate  input sample rate (frequency in Hz)
             * @param log_offset      logging level offset
             * @param log_ctx         parent logging context, can be NULL
             */
            swrContext = swr_alloc_set_opts(NULL, av_get_default_channel_layout(codecCtx->channels), AV_SAMPLE_FMT_S16, codecCtx->sample_rate, av_get_default_channel_layout(codecCtx->channels), codecCtx->sample_fmt, codecCtx->sample_rate, 0, NULL);
            if (!swrContext || swr_init(swrContext)) {
                if (swrContext)
                    swr_free(&swrContext);
                avcodec_close(codecCtx);
                NSLog(@"init resampler failed...");
                return NO;
            }
            
            _audioFrame = av_frame_alloc();
            if (!_audioFrame) {
                NSLog(@"Alloc Audio Frame Failed...");
                if (swrContext)
                    swr_free(&swrContext);
                avcodec_close(codecCtx);
                return NO;
            }
            
            _audioStreamIndex = streamIndex;
            _audioCodecCtx = codecCtx;
            _swrContext = swrContext;
            
            AVStream *st = _formatCtx->streams[streamIndex];
            avStreamFPSTimeBase(st, 0.025, 0, &_audioTimeBase);
        }
    }
    return YES;
}

//关闭音频流
- (void)closeAudioStream{
    _audioStreamIndex = -1;
    
    if (_swrBuffer) {
        free(_swrBuffer);
        _swrBuffer = NULL;
        _swrBufferSize = 0;
    }
    
    if (_swrContext) {
        swr_free(&_swrContext);
        _swrContext = NULL;
    }
    
    if (_audioFrame) {
        av_free(_audioFrame);
        _audioFrame = NULL;
    }
    
    if (_audioCodecCtx) {
        avcodec_close(_audioCodecCtx);
        _audioCodecCtx = NULL;
    }
}

//获取流数据的索引
static NSArray *collectionStreams(AVFormatContext *formatCtx,enum AVMediaType codecType){
    NSMutableArray *ma = [NSMutableArray array];
    for (int i = 0; i < formatCtx->nb_streams; i++) {
        if (codecType == formatCtx->streams[i]->codec->codec_type) {
            [ma addObject:@(i)];
        }
    }
    return ma;
}

static void avStreamFPSTimeBase(AVStream *st, CGFloat defaultTimeBase, CGFloat *pFPS, CGFloat *pTimeBase){
    CGFloat fps, timebase;
    //timebase 同 CMTime() 标识时长
    if (st->time_base.den && st->time_base.num)
        timebase = av_q2d(st->time_base);
    else if(st->codec->time_base.den && st->codec->time_base.num)
        timebase = av_q2d(st->codec->time_base);
    else
        timebase = defaultTimeBase;
    
    if (st->codec->ticks_per_frame != 1) {
        NSLog(@"WARNING: st.codec.ticks_per_frame=%d", st->codec->ticks_per_frame);
        //timebase *= st->codec->ticks_per_frame;
    }
    
    if (st->avg_frame_rate.den && st->avg_frame_rate.num)
        fps = av_q2d(st->avg_frame_rate);
    else if (st->r_frame_rate.den && st->r_frame_rate.num)
        fps = av_q2d(st->r_frame_rate);
    else
        fps = 1.0 / timebase;
    
    if (pFPS)
        *pFPS = fps;
    if (pTimeBase)
        *pTimeBase = timebase;
}

- (BOOL)audioCodecIsSupported:(AVCodecContext *) audioCodecCtx;{
    if (audioCodecCtx->sample_fmt == AV_SAMPLE_FMT_S16) {
        return true;
    }
    return false;
}


- (BOOL) setupScaler
{
    [self closeScaler];
    _pictureValid = avpicture_alloc(&_picture,
                                    AV_PIX_FMT_YUV420P,
                                    _videoCodecCtx->width,
                                    _videoCodecCtx->height) == 0;
    if (!_pictureValid)
        return NO;
    _swsContext = sws_getCachedContext(_swsContext,
                                       _videoCodecCtx->width,
                                       _videoCodecCtx->height,
                                       _videoCodecCtx->pix_fmt,
                                       _videoCodecCtx->width,
                                       _videoCodecCtx->height,
                                       AV_PIX_FMT_YUV420P,
                                       SWS_FAST_BILINEAR,
                                       NULL, NULL, NULL);
    return _swsContext != NULL;
}

- (void) closeScaler{
    if (_swsContext) {
        sws_freeContext(_swsContext);
        _swsContext = NULL;
    }
    
    if (_pictureValid) {
        avpicture_free(&_picture);
        _pictureValid = NO;
    }
}


#pragma mark -  解码

- (NSArray *)decode:(CGFloat)minDuration errorState:(int *)errorState{
    
    if (_videoStreamIndex == -1 || _audioStreamIndex == -1) {
        return nil;
    }
    
    NSMutableArray *resultArray = [NSMutableArray array];
    AVPacket packet;
    CGFloat decodeDuration = 0;
    BOOL finished = NO;
    while (!finished) {
        //数据读取完了。。。
        if (av_read_frame(_formatCtx, &packet) < 0) {
            _isEOF = YES;
            break;
        }
        
        int pktSize = packet.size;
        int pktStreamIndex = packet.stream_index;
        if (pktStreamIndex == _videoStreamIndex) {
            //当前数据是视频
            double startDecodeTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
            LLYVideoFrame *videFrame = [self decodePacket:packet packetSize:pktSize errorState:errorState];
            int wasteTimeMills = CFAbsoluteTimeGetCurrent() * 1000 - startDecodeTimeMills;
            decodeVideoFrameWasteTimeMills +=  wasteTimeMills;
            if (videFrame) {
                
                NSLog(@"视频帧解码成功=============");
                
                totalVideoFrameCount++;
                [resultArray addObject:videFrame];
                decodeDuration += videFrame.duration;
                if (decodeDuration > minDuration) {
                    finished = YES;
                }
            }
        }
        else if (pktStreamIndex == _audioStreamIndex){
            //当前数据是音频
            while (pktSize > 0) {
                int gotFrame = 0;
                //len =  number of bytes consumed from the input *AVPacket
                int len = avcodec_decode_audio4(_audioCodecCtx, _audioFrame, &gotFrame, &packet);
                if (len < 0) {
                    NSLog(@"decode audio error, skip packet");
                    break;
                }
                
                if (gotFrame) {
                    LLYAudioFrame *frame = [self handleAudioFrame];
                    if (frame) {
                        [resultArray addObject:frame];
                        if (_videoStreamIndex == -1) {
                            _decodePosition = frame.position;
                            decodeDuration += frame.duration;
                            if (decodeDuration > minDuration) {
                                finished = YES;
                            }
                        }
                    }
                }
                
                if (len == 0) {
                    break;
                }
                
                pktSize -= len;
            }

        }
        else{
            NSLog(@"We Can Not Process Stream Except Audio And Video Stream...");
        }
        
        av_packet_unref(&packet);
    }
    
    _readLastestFrameTime = [[NSDate date] timeIntervalSince1970];
    
    return resultArray;
}

- (LLYVideoFrame *)decodePacket:(AVPacket)packet packetSize:(int)pktSize errorState:(int *)errorState{
    
    LLYVideoFrame *videoFrame = nil;
    
    while (pktSize > 0) {
        int gotFrmae = 0;
        int len = avcodec_decode_video2(_videoCodecCtx, _videoFrame, &gotFrmae, &packet);
        if (len < 0) {
            NSLog(@"decode video error, skip packet %s", av_err2str(len));
            *errorState = 1;
            break;
        }
        if (gotFrmae) {
            videoFrame = [self handleVideoFrame];
        }
        
        if(packet.flags == 1){
            //IDR Frame
            NSLog(@"IDR Frame %f", videoFrame.position);
        } else if (packet.flags == 0) {
            //NON-IDR Frame
            NSLog(@"===========NON-IDR Frame=========== %f", videoFrame.position);
        }
        if (0 == len)
            break;
        pktSize -= len;
    }
    
   
    return videoFrame;
}

- (LLYAudioFrame *)handleAudioFrame{
    
    if (!_audioFrame->data[0]) {
        return nil;
    }
    
    const NSUInteger numChannels = _audioCodecCtx->channels;
    NSInteger numFrames;
    
    void *audioData;
    
    if (_swrContext) {
        const NSUInteger ratio = 2;
        const int bufSize = av_samples_get_buffer_size(NULL, (int)numChannels ,(int)(_audioFrame->nb_samples * ratio), AV_SAMPLE_FMT_S16, 1);
        if (!_swrBuffer || _swrBufferSize < bufSize) {
            _swrBufferSize = bufSize;
            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
        }
        Byte *outbuf[2] = {_swrBuffer,0};
        numFrames = swr_convert(_swrContext, outbuf, (int)(_audioFrame->nb_samples * ratio), (const uint8_t **)_audioFrame->data, _audioFrame->nb_samples);
        if (numFrames < 0) {
            NSLog(@"fail resample audio");
            return nil;
        }
        audioData = _swrBuffer;
    }else{
        if (_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
            NSLog(@"Audio format is invalid");
            return nil;
        }
        audioData = _audioFrame->data[0];
        numFrames = _audioFrame->nb_samples;
    }
    
    //总帧数 = 一条信道的帧数*信道数
    const NSUInteger numElements = numFrames * numChannels;
    NSMutableData *pcmData = [NSMutableData dataWithLength:numElements * sizeof(SInt16)];
    memcpy(pcmData.mutableBytes, audioData, numElements * sizeof(SInt16));
    LLYAudioFrame *frame = [[LLYAudioFrame alloc]init];
    frame.position = av_frame_get_best_effort_timestamp(_audioFrame) * _audioTimeBase;
    frame.duration = av_frame_get_pkt_duration(_audioFrame) * _audioTimeBase;
    frame.sampleData = pcmData;
    frame.frameType = LLYFrameType_Audio;
    
    return frame;
}

- (LLYVideoFrame *)handleVideoFrame{
    
    if (!_videoFrame->data[0]) {
        return nil;
    }
    
    LLYVideoFrame *videoFrame = [[LLYVideoFrame alloc]init];
    //将yuv数据取出来
    if (_videoCodecCtx->pix_fmt == AV_PIX_FMT_YUV420P || _videoCodecCtx->pix_fmt == AV_PIX_FMT_YUVJ420P) {
        videoFrame.luma = copyFrameData(_videoFrame->data[0], _videoFrame->linesize[0], _videoCodecCtx->width, _videoCodecCtx->height);
        videoFrame.chromaB = copyFrameData(_videoFrame->data[1], _videoFrame->linesize[1], _videoCodecCtx->width/2, _videoCodecCtx->height/2);
        videoFrame.chromaR = copyFrameData(_videoFrame->data[2], _videoFrame->linesize[2], _videoCodecCtx->width/2, _videoCodecCtx->height/2);
    }else{
        //不是yuv格式先要将格式转为yuv的
        if (!_swsContext &&
            ![self setupScaler]) {
            NSLog(@"fail setup video scaler");
            return nil;
        }
        
        sws_scale(_swsContext,
                  (const uint8_t **)_videoFrame->data,
                  _videoFrame->linesize,
                  0,
                  _videoCodecCtx->height,
                  _picture.data,
                  _picture.linesize);
        videoFrame.luma = copyFrameData(_picture.data[0], _videoFrame->linesize[0], _videoCodecCtx->width, _videoCodecCtx->height);
        videoFrame.chromaB = copyFrameData(_picture.data[1], _videoFrame->linesize[1], _videoCodecCtx->width/2, _videoCodecCtx->height/2);
        videoFrame.chromaR = copyFrameData(_picture.data[2], _videoFrame->linesize[2], _videoCodecCtx->width/2, _videoCodecCtx->height/2);
    }
    videoFrame.width = _videoCodecCtx->width;
    videoFrame.height = _videoCodecCtx->height;
    videoFrame.lineSize = _videoFrame->linesize[0];
    videoFrame.frameType = LLYFrameType_Video;
    videoFrame.position = av_frame_get_best_effort_timestamp(_videoFrame) * _videoTimeBase;
    const int64_t frameDuration = av_frame_get_pkt_duration(_videoFrame);
    if (frameDuration) {
        videoFrame.duration = frameDuration * _videoTimeBase;
        videoFrame.duration += _videoFrame->repeat_pict * _videoTimeBase * 0.5;
    } else {
        // sometimes, ffmpeg unable to determine a frame duration
        // as example yuvj420p stream from web camera
        videoFrame.duration = 1.0 / _fps;
    }
    
    return videoFrame;
}

static NSData * copyFrameData(UInt8 *src, int linesize, int width, int height){
    width = MIN(linesize, width);
    NSMutableData *md = [NSMutableData dataWithLength: width * height];
    Byte *dst = md.mutableBytes;
    for (NSUInteger i = 0; i < height; ++i) {
        memcpy(dst, src, width);
        dst += width;
        src += linesize;
    }
    return md;
}

#pragma mark - 打断处理
//打断
- (void)interrupt{
    _subscribeTimeOutTimeInSecs = -1;
    _interrupted = YES;
    _isSubscribe = NO;
}
//打断状态
- (BOOL)detectInterrupted{
    //打断超时
    if ([[NSDate date] timeIntervalSince1970] - _readLastestFrameTime > _subscribeTimeOutTimeInSecs) {
        return YES;
    }
    return _interrupted;
}

static int interrupt_callback(void *ctx){
    if (!ctx) {
        return 0;
    }
    __unsafe_unretained LLYDecoder *decoder = (__bridge LLYDecoder *)ctx;
    const BOOL bRet = [decoder detectInterrupted];
    if (bRet) {
        NSLog(@"DEBUG: INTERRUPT_CALLBACK!");
    }
    return bRet;
}

#pragma mark - 埋点数据统计相关

- (void)triggerFirstScreen{
    //首屏显示成功
    if (_buriedPoint.failOpenType == 1) {
        _buriedPoint.firstScreenTimeMills = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpenTime) / 1000;
    }
}
- (void)addStreamStatus:(NSString *)status{
    if ([@"F" isEqualToString:status] && [[_buriedPoint.streamStatusArray lastObject] hasPrefix:@"F_"]) {
        return;
    }
    
    float timeInterval = ([[NSDate date] timeIntervalSince1970] * 1000 - _buriedPoint.beginOpenTime) / 1000;
    [_buriedPoint.streamStatusArray addObject:[NSString stringWithFormat:@"%@_%.3f",status,timeInterval]];
}
- (LLYBuriedPoint *)getBuriedPoint{
    return _buriedPoint;
}


#pragma mark - 其他属性

- (BOOL)isEOF{
    return _isEOF;
}

- (BOOL)isSubscribed{
    return _isSubscribe;
}

- (NSUInteger)frameWidth{
    return _videoCodecCtx ? _videoCodecCtx->width : 0;
}
- (NSUInteger)frameHeight{
    return _videoCodecCtx ? _videoCodecCtx->height : 0;
}

- (CGFloat)sampleRate{
    return _audioCodecCtx ? _audioCodecCtx->sample_rate : 0;
}

- (NSUInteger)channels{
    return _audioCodecCtx ? _audioCodecCtx->channels : 0;
}

- (BOOL)validVideo{
    return _videoStreamIndex != -1;
}

- (BOOL)validAudio{
    return _audioStreamIndex != -1;
}

- (CGFloat)getVideoFPS{
    return _fps;
}

- (CGFloat)getDuration{
    if (_formatCtx) {
        if (_formatCtx->duration == AV_NOPTS_VALUE) {
            return -1;
        }
        return _formatCtx->duration/AV_TIME_BASE;
    }
    return -1;
}

@end
