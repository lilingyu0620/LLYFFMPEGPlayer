//
//  LLYSync.h
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/9.
//  Copyright © 2018年 lly. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LLYDecoder.h"
#import "LLYHardDecoder.h"

#define TIMEOUT_DECODE_ERROR            20
#define TIMEOUT_BUFFER                  10

extern NSString * const kMIN_BUFFERED_DURATION;
extern NSString * const kMAX_BUFFERED_DURATION;

typedef enum : NSUInteger {
    LLY_OPEN_SUCCESS = 0,
    LLY_OPEN_FAILED,
    LLY_CLIENT_CANCEL,
} LLYOpenStatus;

@protocol LLYPlayerStatusDelegate <NSObject>

- (void)openSucceed;
- (void)connectFaild;
- (void)hideLoading;
- (void)showLoading;
- (void)onComplete;
- (void)buriedPointCallback:(LLYBuriedPoint *)buriedPoint;
- (void)restart;

@end

@interface LLYSync : NSObject

@property (nonatomic, weak) id<LLYPlayerStatusDelegate> delegate;
- (instancetype)initWithPlayerStatusDelegate:(id<LLYPlayerStatusDelegate>)delegate;

- (LLYOpenStatus)openFile:(NSString *)path usingHWCodec:(BOOL)usingHWCodec error:(NSError **)pError;
- (LLYOpenStatus)openFile:(NSString *)path usingHWCodec:(BOOL)usingHWCodec parameters:(NSDictionary *)parameters error:(NSError **)pError;

//- (LLYOpenStatus)openFile:(NSString *)path parameters:(NSDictionary *)parameters error:(NSError **)pError;
//- (LLYOpenStatus)openFile:(NSString *)path error:(NSError **)pError;
- (void)closeFile;

- (void)audioCallbackFillData:(SInt16 *)outData numFrames:(UInt32)numFrames numChannels:(UInt32)numChannels;
- (LLYVideoFrame *)getCorrectVideoFrame;

- (void)run;
- (BOOL)isOpenInputSuccess;
- (void)interrupt;
- (BOOL)isPlayCompleted;
- (BOOL)isValid;


//使用硬件编码
- (BOOL)usingHWCodec;

//音频采样率
- (NSInteger)getAudioSampleRate;
- (NSInteger)getAudioChannels;

- (CGFloat)getVideoFPS;
- (NSInteger)getVideoFrameHeight;
- (NSInteger)getVideoFrameWidth;

- (CGFloat)getDuration;
@end
