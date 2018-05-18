//
//  LLYFFMPEGPlayerViewController.h
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/13.
//  Copyright © 2018年 lly. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "LLYSync.h"


@interface LLYFFMPEGPlayerViewController : UIViewController

@property (nonatomic, strong) LLYSync * sync;
@property (nonatomic, copy) NSString * urlStr;
@property (nonatomic, weak) id<LLYPlayerStatusDelegate> statusDelegate;
@property(nonatomic, assign) BOOL usingHWCodec;

+ (instancetype)viewControllerWithContentPath:(NSString *)path
                                 contentFrame:(CGRect)frame
                          playerStateDelegate:(id)playerStateDelegate
                                   parameters:(NSDictionary *)parameters
                                 usingHWCodec:(BOOL)usingHWCodec;

- (void)play;

- (void)pause;

- (void)stop;

- (void) restart;

- (BOOL) isPlaying;

- (UIImage *)movieSnapshot;

//- (VideoOutput*) createVideoOutputInstance;
//- (VideoOutput*) getVideoOutputInstance;

@end

