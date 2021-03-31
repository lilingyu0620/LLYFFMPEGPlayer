//
//  ViewController.m
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/9.
//  Copyright © 2018年 lly. All rights reserved.
//

#import "ViewController.h"
#import "LLYPlayerViewController.h"
#import "CommonUtil.h"
#import "LLYDecoder.h"

NSString * const MIN_BUFFERED_DURATION = @"Min Buffered Duration";
NSString * const MAX_BUFFERED_DURATION = @"Max Buffered Duration";

@interface ViewController (){
    NSMutableDictionary *_requestHeader;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    _requestHeader = [NSMutableDictionary dictionary];
    _requestHeader[MIN_BUFFERED_DURATION] = @(1.0f);
    _requestHeader[MAX_BUFFERED_DURATION] = @(3.0f);
    _requestHeader[FPS_PROBE_SIZE_CONFIGURED] = @(true);
    _requestHeader[PROBE_SIZE] = @(50 * 1024);
    NSMutableArray* durations = [NSMutableArray array];
    durations[0] = @(1250000);
    durations[0] = @(1750000);
    durations[0] = @(2000000);
    _requestHeader[MAX_ANALYZE_DURATION_ARRAY] = durations;
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)startPlay:(id)sender {
    NSString *path = [CommonUtil bundlePath:@"hebe.MP4"];
    LLYPlayerViewController *vc = [LLYPlayerViewController viewControllerWithContentPath:path contentFrame:self.view.bounds parameters:_requestHeader usingHWCodec:NO];
    [self presentViewController:vc animated:YES completion:nil];
}


@end
