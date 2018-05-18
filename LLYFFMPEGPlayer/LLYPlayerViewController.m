//
//  LLYPlayerViewController.m
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/13.
//  Copyright © 2018年 lly. All rights reserved.
//

#import "LLYPlayerViewController.h"
#import "LLYFFMPEGPlayerViewController.h"

@interface LLYPlayerViewController ()<LLYPlayerStatusDelegate>

@property (nonatomic, strong) LLYFFMPEGPlayerViewController * ffmpegPlayerController;

@end

@implementation LLYPlayerViewController

+ (id)viewControllerWithContentPath:(NSString *)path
                       contentFrame:(CGRect)frame
                         parameters:(NSDictionary *)parameters
                       usingHWCodec:(BOOL)usingHWCodec{
    return [[LLYPlayerViewController alloc]initWithContentPath:path contentFrame:frame parameters:parameters usingHWCodec:usingHWCodec];
}

- (id) initWithContentPath:(NSString *)path
              contentFrame:(CGRect)frame
                parameters:(NSDictionary *)parameters
              usingHWCodec:(BOOL)usingHWCodec{
    
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.ffmpegPlayerController = [LLYFFMPEGPlayerViewController viewControllerWithContentPath:path contentFrame:frame playerStateDelegate:self parameters:parameters usingHWCodec:usingHWCodec];
        [self addChildViewController:self.ffmpegPlayerController];
        [self.view addSubview:self.ffmpegPlayerController.view];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - LLYPlayerStatusDelegate
- (void) restart{
    //Loading 或者 毛玻璃效果在这里处理
    [self.ffmpegPlayerController restart];
}

- (void) hideLoading
{
    dispatch_async(dispatch_get_main_queue(), ^{
//        [[LoadingView shareLoadingView] close];
    });
}

- (void) showLoading
{
    dispatch_async(dispatch_get_main_queue(), ^{
//        [[LoadingView shareLoadingView] show];
    });
}

- (void) onCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
//        [[LoadingView shareLoadingView] close];
        UIAlertView *alterView = [[UIAlertView alloc] initWithTitle:@"提示信息" message:@"视频播放完毕了" delegate:self cancelButtonTitle:@"取消" otherButtonTitles: nil];
        [alterView show];
    });
    
}
- (void)connectFailed;{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertView *alterView = [[UIAlertView alloc] initWithTitle:@"提示信息" message:@"打开视频失败, 请检查文件或者远程连接是否存在！" delegate:self cancelButtonTitle:@"取消" otherButtonTitles: nil];
        [alterView show];
    });
}

- (void)buriedPointCallback:(LLYBuriedPoint *)buriedPoint{
    long long beginOpen = buriedPoint.beginOpenTime;
    float successOpen = buriedPoint.successOpenTime;
    float firstScreenTimeMills = buriedPoint.firstScreenTimeMills;
    float failOpen = buriedPoint.failOpenTime;
    float failOpenType = buriedPoint.failOpenType;
    int retryTimes = buriedPoint.retryTimes;
    float duration = buriedPoint.duration;
    NSMutableArray* bufferStatusRecords = buriedPoint.streamStatusArray;
    NSMutableString* buriedPointStatictics = [NSMutableString stringWithFormat:
                                              @"beginOpen : [%lld]", beginOpen];
    [buriedPointStatictics appendFormat:@"successOpen is [%.3f]", successOpen];
    [buriedPointStatictics appendFormat:@"firstScreenTimeMills is [%.3f]", firstScreenTimeMills];
    [buriedPointStatictics appendFormat:@"failOpen is [%.3f]", failOpen];
    [buriedPointStatictics appendFormat:@"failOpenType is [%.3f]", failOpenType];
    [buriedPointStatictics appendFormat:@"retryTimes is [%d]", retryTimes];
    [buriedPointStatictics appendFormat:@"duration is [%.3f]", duration];
    for (NSString* bufferStatus in bufferStatusRecords) {
        [buriedPointStatictics appendFormat:@"buffer status is [%@]", bufferStatus];
    }
    
    NSLog(@"buried point is %@", buriedPointStatictics);
}

@end
