//
//  LLYFFMPEGPlayerViewController.m
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/13.
//  Copyright © 2018年 lly. All rights reserved.
//

#import "LLYFFMPEGPlayerViewController.h"
#import "LLYAudioPlayer.h"
#import "LLYVideoPlayer.h"

@interface LLYFFMPEGPlayerViewController ()<LLYAudioPlayerDataSourceDelegate>

@property (nonatomic, strong) LLYAudioPlayer * audioPlayer;
@property (nonatomic, strong) LLYVideoPlayer * videoPlayer;
@property (nonatomic, strong) NSDictionary * parameters;
@property (nonatomic, assign) CGRect contentFrame;
@property (nonatomic, assign,getter=isPlaying) BOOL playing;
@property (nonatomic, strong) EAGLSharegroup * shareGroup;

@end

@implementation LLYFFMPEGPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

+ (instancetype)viewControllerWithContentPath:(NSString *)path
                                 contentFrame:(CGRect)frame
                          playerStateDelegate:(id)playerStateDelegate
                                   parameters: (NSDictionary *)parameters
                                 usingHWCodec:(BOOL)usingHWCodec{
    return [[LLYFFMPEGPlayerViewController alloc]initWithContentPath:path contentFrame:frame playerStateDelegate:playerStateDelegate parameters:parameters usingHWCodec:usingHWCodec];
}

- (instancetype) initWithContentPath:(NSString *)path
                        contentFrame:(CGRect)frame
                 playerStateDelegate:(id) playerStateDelegate
                          parameters:(NSDictionary *)parameters
                        usingHWCodec:(BOOL)usingHWCodec{
    NSAssert(path.length > 0, @"empty path");
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _usingHWCodec = usingHWCodec;
        _contentFrame = frame;
        _parameters = parameters;
        _urlStr = path;
        _statusDelegate = playerStateDelegate;
        [self start];
    }
    return self;
}

- (void)start{
    _sync = [[LLYSync alloc]initWithPlayerStatusDelegate:self.statusDelegate];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (weakSelf) {
            NSError *error = nil;
            LLYOpenStatus openStatus = LLY_OPEN_FAILED;
            if ([weakSelf.parameters count] > 0) {
                openStatus  = [weakSelf.sync openFile:weakSelf.urlStr usingHWCodec:_usingHWCodec parameters:weakSelf.parameters error:&error];
            }
            else{
                openStatus = [weakSelf.sync openFile:weakSelf.urlStr usingHWCodec:_usingHWCodec error:&error];
            }
            
            if (openStatus == LLY_OPEN_SUCCESS) {
                
                //视频播放
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.view.backgroundColor = [UIColor clearColor];
                    [self.view insertSubview:self.videoPlayer atIndex:0];
                });
                //音频播放
                NSInteger audioChannels = [weakSelf.sync getAudioChannels];
                NSInteger audioSampleRate = [weakSelf.sync getAudioSampleRate];
                NSInteger bytesPerSample = 2;
                weakSelf.audioPlayer = [[LLYAudioPlayer alloc]initWithChannels:audioChannels sampleRate:audioSampleRate bytesPerSample:bytesPerSample dataSourceDelegate:weakSelf];
                [weakSelf.audioPlayer play];
                weakSelf.playing = YES;
                
                if (weakSelf.statusDelegate && [weakSelf.statusDelegate respondsToSelector:@selector(openSucceed)]) {
                    [weakSelf.statusDelegate openSucceed];
                }
            }
            else{
                if (weakSelf.statusDelegate && [weakSelf.statusDelegate respondsToSelector:@selector(connectFaild)]) {
                    [weakSelf.statusDelegate connectFaild];
                }
            }
        }
    });
}

- (void)play{
    if (self.isPlaying) {
        return;
    }
    
    if (self.audioPlayer) {
        [self.audioPlayer play];
    }
}

- (void)pause{
    if (!self.isPlaying)
        return;
    if(self.audioPlayer){
        [self.audioPlayer stop];
    }
}

- (void)stop{
    if(self.audioPlayer){
        [self.audioPlayer stop];
        self.audioPlayer = nil;
    }
    if(self.sync){
        if([self.sync isOpenInputSuccess]){
            [self.sync closeFile];
            self.sync = nil;
        } else {
            [self.sync interrupt];
        }
    }
}

- (void)restart{
    UIView* parentView = [self.view superview];
    [self.view removeFromSuperview];
    [self stop];
    [self start];
    [parentView addSubview:self.view];
}

- (BOOL)isPlaying{
    return self.isPlaying;
}

- (UIImage *)movieSnapshot{
    if (!self.videoPlayer) {
        return nil;
    }
    // See Technique Q&A QA1817: https://developer.apple.com/library/ios/qa/qa1817/_index.html
    UIGraphicsBeginImageContextWithOptions(self.videoPlayer.bounds.size, YES, 0);
    [self.videoPlayer drawViewHierarchyInRect:self.videoPlayer.bounds afterScreenUpdates:NO];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (LLYVideoPlayer *)videoPlayer;
{
    if (nil == _videoPlayer) {
        CGRect bounds = self.view.bounds;
        NSInteger textureWidth = [self.sync getVideoFrameWidth];
        NSInteger textureHeight = [self.sync getVideoFrameHeight];
        _videoPlayer = [[LLYVideoPlayer alloc] initWithFrame:bounds
                                            textureWidth:textureWidth
                                           textureHeight:textureHeight
                                              shareGroup:_shareGroup
                                                usingHWCodec:_usingHWCodec];
        _videoPlayer.contentMode = UIViewContentModeScaleAspectFill;
        _videoPlayer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    }
    return _videoPlayer;
}



#pragma mark - LLYAudioPlayerDataSourceDelegate

- (NSInteger)dataSource:(SInt16 *)sampleBuffer numFrames:(NSInteger)frameNum numChannels:(NSInteger)channels{
    
    if (self.sync && ![self.sync isPlayCompleted]) {
        [self.sync audioCallbackFillData:sampleBuffer numFrames:frameNum numChannels:channels];
        LLYVideoFrame *videoFrame = [self.sync getCorrectVideoFrame];
        if (videoFrame) {
            [self.videoPlayer presentVideoFrame:videoFrame];
        }
    }
    else{
        memset(sampleBuffer, 0, frameNum * channels * sizeof(SInt16));
    }
    return 1;
}

@end
