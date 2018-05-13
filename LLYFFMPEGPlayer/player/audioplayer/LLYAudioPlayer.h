//
//  LLYAudioPlayer.h
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/9.
//  Copyright © 2018年 lly. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol LLYAudioPlayerDataSourceDelegate <NSObject>

- (NSInteger)dataSource:(SInt16 *)sampleBuffer numFrames:(NSInteger)frameNum numChannels:(NSInteger)channels;

@end

@interface LLYAudioPlayer : NSObject

@property (nonatomic, assign) Float64 sampleRate;
@property (nonatomic, assign) Float64 channels;

- (instancetype)initWithChannels:(NSInteger)channels sampleRate:(NSInteger)sampleRate bytesPerSample:(NSInteger)bytePerSample dataSourceDelegate:(id<LLYAudioPlayerDataSourceDelegate>)delegate;

- (BOOL)play;
- (void)stop;

@end
