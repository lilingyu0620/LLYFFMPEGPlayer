### 使用FFMPEG解码之--音频解码

这几天一直在写使用ffmpeg完成一个视频播放器的demo,因为对音频这一块比较熟悉，所以先从音频解码开始下手，也熟悉一下ffmpeg的使用流程。音频解码这块已经完成了，所以这里先简单总结一下整个音频解码的流程。这里只说大概流程，具体实现细节参考下面的demo就可以。

#### 1.注册ffmpeg

```
av_register_all()

```

#### 2.初始化AVFormatContext

```
    AVFormatContext *formatCtx = avformat_alloc_context();

```

#### 3.可以注册一个打断回调

```
AVIOInterruptCB int_cb = {interrupt_callback,(__bridge void *)self};
    formatCtx->interrupt_callback = int_cb;

```

其中 interrupt_callback 是一个函数指针 

```
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

//打断状态
- (BOOL)detectInterrupted{
    //打断超时
    if ([[NSDate date] timeIntervalSince1970] - _readLastestFrameTime > _subscribeTimeOutTimeInSecs) {
        return YES;
    }
    return _interrupted;
}

```

即使返回一个是否被打断的状态。

#### 4.打开流地址

```
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

```

返回一个是否打开成功的状态。0表示成功


#### 5.设置解析参数probesize & max_analyze_duration

```
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

```

#### 6.获取音视频信息

```
int findStreamErrorCode = 0;
double startFindStreamTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
if ((findStreamErrorCode = avformat_find_stream_info(formatCtx, NULL)) < 0) {
    avformat_close_input(&formatCtx);
    avformat_free_context(formatCtx);
    NSLog(@"Video decoder find stream info failed... find stream ErrCode is %s", av_err2str(findStreamErrorCode));
}

```
获取的信息都在formatCtx这个参数里存着，后面很多地方要用。

#### 7.获取流数据的索引数组

通过流的类型获取流的索引，有时候可能音频或者视频都有好几路流数据

```
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

```

#### 8.通过流的索引，获取每一路流的AVCodecContext & AVCodec

```    

AVCodecContext *codecCtx = _formatCtx->streams[streamIndex]->codec;
//获取该stream对应的解码器
AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
if(!codec){
    NSLog(@"Find Audio Decoder Failed codec_id %d CODEC_ID_AAC is %d", codecCtx->codec_id, AV_CODEC_ID_AAC);
    return NO;
}

```

#### 9.打开解码器

```
int openCodecErrorCode = 0;
if ((openCodecErrorCode = avcodec_open2(codecCtx, codec, NULL)) < 0) {
    NSLog(@"open Audio Codec Failed openCodecErr is %s", av_err2str(openCodecErrorCode));
    return NO;
}
    
```

#### 10.如果不支持当前流的采样格式，需要做一下重新采样

```
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
}


- (BOOL)audioCodecIsSupported:(AVCodecContext *) audioCodecCtx;{
    if (audioCodecCtx->sample_fmt == AV_SAMPLE_FMT_S16) {
        return true;
    }
    return false;
}

```
#### 11.初始化一个AVFrame

```
_audioFrame = av_frame_alloc();
if (!_audioFrame) {
    NSLog(@"Alloc Audio Frame Failed...");
    if (swrContext)
        swr_free(&swrContext);
    avcodec_close(codecCtx);
    return NO;
}

```

#### 12.获取AVPacket

```

AVPacket packet;
if (av_read_frame(_formatCtx, &packet) < 0) {
        _isEOF = YES;
        break;
}

```

#### 13.获取AVFrame

```

int gotFrame = 0;
//len =  number of bytes consumed from the input *AVPacket
int len = avcodec_decode_audio4(_audioCodecCtx, _audioFrame, &gotFrame, &packet);
if (len < 0) {
    NSLog(@"decode audio error, skip packet");
    break;
}

```

#### 14.将AVFrame转为自定义的LLYAudioFrame

```
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

```
这里判断一下如果是重采样的，需要做一个转换。

主要流程大概就是上面这些了。当然还有一些细节的东西，这里没有一一列出来，可以从demo中寻找答案。

[LLYFFMPEGPlayer](https://github.com/lilingyu0620/LLYFFMPEGPlayer.git)