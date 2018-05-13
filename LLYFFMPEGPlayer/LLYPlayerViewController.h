//
//  LLYPlayerViewController.h
//  LLYFFMPEGPlayer
//
//  Created by lly on 2018/5/13.
//  Copyright © 2018年 lly. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LLYPlayerViewController : UIViewController

+ (id)viewControllerWithContentPath:(NSString *)path
                       contentFrame:(CGRect)frame
                         parameters:(NSDictionary *)parameters;

@end
