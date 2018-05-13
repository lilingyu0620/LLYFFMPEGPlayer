//
//  LLYFFMPEGPlayerViewController.m
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/13.
//  Copyright © 2018年 lly. All rights reserved.
//

#import "LLYFFMPEGPlayerViewController.h"

@interface LLYFFMPEGPlayerViewController ()<LLYAudioPlayerDataSourceDelegate>

@property (nonatomic, strong) LLYAudioPlayer * audioPlayer;
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
                                   parameters: (NSDictionary *)parameters{
    return [[LLYFFMPEGPlayerViewController alloc]initWithContentPath:path contentFrame:frame playerStateDelegate:playerStateDelegate parameters:parameters];
}

- (instancetype) initWithContentPath:(NSString *)path
                        contentFrame:(CGRect)frame
                 playerStateDelegate:(id) playerStateDelegate
                          parameters:(NSDictionary *)parameters{
    NSAssert(path.length > 0, @"empty path");
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
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
                openStatus = [weakSelf.sync openFile:weakSelf.urlStr parameters:weakSelf.parameters error:&error];
            }
            else{
                openStatus = [weakSelf.sync openFile:weakSelf.urlStr error:&error];
            }
            
            if (openStatus == LLY_OPEN_SUCCESS) {
                
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
    return nil;
}

#pragma mark - LLYAudioPlayerDataSourceDelegate

- (NSInteger)dataSource:(SInt16 *)sampleBuffer numFrames:(NSInteger)frameNum numChannels:(NSInteger)channels{
    
    if (self.sync && ![self.sync isPlayCompleted]) {
        [self.sync audioCallbackFillData:sampleBuffer numFrames:frameNum numChannels:channels];
    }
    else{
        memset(sampleBuffer, 0, frameNum * channels * sizeof(SInt16));
    }
    return 1;
}

@end
