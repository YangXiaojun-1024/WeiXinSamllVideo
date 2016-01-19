//
//  ViewController.m
//  微信小视频Demo
//
//  Created by apple on 16/1/19.
//  Copyright © 2016年 TopMH. All rights reserved.
//

#import "ViewController.h"
#import "IDVideoController.h"

@interface ViewController () <IDVideoControllerDelegate>

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor whiteColor];
}

- (IBAction)movieTakeButton:(id)sender {
    
    IDVideoController *videoVC = [[IDVideoController alloc] init];
    videoVC.delegate = self;
    [self.navigationController pushViewController:videoVC animated:YES];
}

#pragma mark --- IDVideoVCDelegate
- (void)IDVideoControllerDidFinishedTakeMovie:(NSURL *)mp4URL {
    
    NSLog(@"mp4URL == %@", mp4URL);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

@end
