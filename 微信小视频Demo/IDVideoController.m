//
//  ViewController.m
//  AVFoundationCamera
//
//  Created by Kenshin Cui on 14/04/05.
//  Copyright (c) 2014年 cmjstudio. All rights reserved.
//  视频录制

#import "IDVideoController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <MediaAccessibility/MediaAccessibility.h>
#import <MediaPlayer/MediaPlayer.h>

#ifdef iDeviceWidth 

#else 
#define iDeviceWidth [UIScreen mainScreen].bounds.size.width
#define iDeviceHeight [UIScreen mainScreen].bounds.size.height
#endif


#define TABBARHEIGHT 100  // 底部条高度
#define HEADERHEIGHT 40   // 头部条高度
#define STATUSHEIGHT 0    // 状态栏高度

#define SECONDS 10        // 倒计时秒数

typedef void(^PropertyChangeBlock)(AVCaptureDevice *captureDevice);

@interface IDVideoController ()<AVCaptureFileOutputRecordingDelegate, UIAlertViewDelegate>//视频文件输出代理

@property (strong,nonatomic) AVCaptureSession *captureSession; // 负责输入和输出设置之间的数据传递
@property (strong,nonatomic) AVCaptureDeviceInput *captureDeviceInput; // 负责从AVCaptureDevice获得输入数据
@property (strong,nonatomic) AVCaptureMovieFileOutput *captureMovieFileOutput; // 视频输出流
@property (strong,nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer; // 相机拍摄预览图层
@property (assign,nonatomic) BOOL enableRotation; // 是否允许旋转（注意在视频录制过程中禁止屏幕旋转）
@property (assign,nonatomic) CGRect *lastBounds; // 旋转的前大小
@property (assign,nonatomic) UIBackgroundTaskIdentifier backgroundTaskIdentifier; // 后台任务标识
@property (strong, nonatomic) UIView *viewContainer; // 视频图层
@property (strong, nonatomic) UIButton *takeButton; // 拍照按钮
@property (strong, nonatomic) UIImageView *focusCursor; // 聚焦光标
@property (nonatomic, strong) UIView *tabBarView; // 底部view
@property (nonatomic, strong) UIButton *backButton; // 返回按钮
@property (nonatomic, strong) UIView *headerView; // 头部条

@property (nonatomic, strong) NSTimer *timer; // 倒计时Timer
@property (nonatomic, strong) UILabel *timeLabel; // 时间显示
@property (nonatomic, assign) NSInteger seconds; // 倒计时时间
@property (nonatomic, assign) NSInteger movieTimeCount; // 视频时长
@property (nonatomic, strong) UILabel *tipsLabel; // 按钮状态提醒
@property (nonatomic, assign) BOOL isSave; // 是否存储

@property(nonatomic, strong) NSURL *mp4URL; // 删除的视频链接
@property(nonatomic, strong) MPMediaPickerController *moviePlayer; // 视频播放

@end

@implementation IDVideoController

#pragma mark - 控制器视图方法
- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.navigationController.navigationBar setHidden:YES];
    
    [self.view addSubview:self.headerView];
    [self.view addSubview:self.viewContainer];
    [self.view addSubview:self.tabBarView];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self.navigationController.navigationBar setHidden:NO];
}

// 更改状态栏样式
- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

// 隐藏状态栏
- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // 初始化会话
    _captureSession = [[AVCaptureSession alloc] init];
    if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset352x288]) { //设置分辨率
        _captureSession.sessionPreset = AVCaptureSessionPreset352x288;
    }
    // 获得输入设备
    AVCaptureDevice *captureDevice = [self getCameraDeviceWithPosition:AVCaptureDevicePositionBack];//取得后置摄像头
    if (!captureDevice) {
        NSLog(@"取得后置摄像头时出现问题.");
        return;
    }
    
    // 添加一个音频输入设备
    AVCaptureDevice *audioCaptureDevice = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
    
    NSError *error=nil;
    // 根据输入设备初始化设备输入对象，用于获得输入数据
    _captureDeviceInput = [[AVCaptureDeviceInput alloc]initWithDevice:captureDevice error:&error];
    if (error) {
        NSLog(@"取得设备输入对象时出错，错误原因：%@",error.localizedDescription);
        return;
    }
    AVCaptureDeviceInput *audioCaptureDeviceInput = [[AVCaptureDeviceInput alloc]initWithDevice:audioCaptureDevice error:&error];
    if (error) {
        NSLog(@"取得设备输入对象时出错，错误原因：%@",error.localizedDescription);
        return;
    }
    // 初始化设备输出对象，用于获得输出数据
    _captureMovieFileOutput=[[AVCaptureMovieFileOutput alloc]init];
    
    // 将设备输入添加到会话中
    if ([_captureSession canAddInput:_captureDeviceInput]) {
        [_captureSession addInput:_captureDeviceInput];
        [_captureSession addInput:audioCaptureDeviceInput];
        AVCaptureConnection *captureConnection = [_captureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
        if ([captureConnection isVideoStabilizationSupported ]) {
            captureConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
        }
    }
    
    // 将设备输出添加到会话中
    if ([_captureSession canAddOutput:_captureMovieFileOutput]) {
        [_captureSession addOutput:_captureMovieFileOutput];
    }
    
    // 创建视频预览层，用于实时展示摄像头状态
    _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc]initWithSession:self.captureSession];
    
    CALayer *layer = self.viewContainer.layer;
    layer.masksToBounds = YES;
    
    _captureVideoPreviewLayer.frame = layer.bounds;
    _captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;//填充模式
    // 将视频预览层添加到界面中
    //[layer addSublayer:_captureVideoPreviewLayer];
    [layer insertSublayer:_captureVideoPreviewLayer below:self.focusCursor.layer];
    
    _enableRotation=YES;
    [self addNotificationToCaptureDevice:captureDevice];
    [self addGenstureRecognizer];
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [self.captureSession startRunning];
}

- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    [self.captureSession stopRunning];
}

-(BOOL)shouldAutorotate{
    return self.enableRotation;
}

////屏幕旋转时调整视频预览图层的方向
//-(void)willTransitionToTraitCollection:(UITraitCollection *)newCollection withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator{
//    [super willTransitionToTraitCollection:newCollection withTransitionCoordinator:coordinator];
////    NSLog(@"%i,%i",newCollection.verticalSizeClass,newCollection.horizontalSizeClass);
//    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
//    NSLog(@"%i",orientation);
//    AVCaptureConnection *captureConnection = [self.captureVideoPreviewLayer connection];
//    captureConnection.videoOrientation = orientation;
//
//}

// 屏幕旋转时调整视频预览图层的方向
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration{
    
    AVCaptureConnection *captureConnection = [self.captureVideoPreviewLayer connection];
    captureConnection.videoOrientation = (AVCaptureVideoOrientation)toInterfaceOrientation;
}
// 旋转后重新设置大小
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation{

    _captureVideoPreviewLayer.frame = self.viewContainer.bounds;
}

- (void)dealloc{
    [self removeNotification];
}

#pragma mark - 视频输出代理
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections{
    NSLog(@"开始录制...");
    
    self.seconds = SECONDS;
    self.movieTimeCount = 0;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(timerCount) userInfo:nil repeats:YES];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error {
    
//    NSLog(@"outputFileURL == %@", outputFileURL);
    
    if (self.isSave == YES) { // 判断是否可以保存
        
        if (self.movieTimeCount < 2) {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:nil message:@"视频时间过短" delegate:nil cancelButtonTitle:@"cancel" otherButtonTitles: nil];
            [alertView show];

            [self.timer invalidate]; // 停止计时
            [self.takeButton setTitle:@"录制" forState:UIControlStateNormal];
            [self.captureMovieFileOutput stopRecording];//停止录制
            
            [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
            NSLog(@"删除缓存视频");
            
            return;
        }
        
        NSLog(@"视频录制完成.");
        
        // 视频录入完成之后在后台将视频存储到相簿
        self.enableRotation = YES;
        UIBackgroundTaskIdentifier lastBackgroundTaskIdentifier = self.backgroundTaskIdentifier;
        self.backgroundTaskIdentifier = UIBackgroundTaskInvalid;
        
        NSURL *mp4Url = [self convert2Mp4: outputFileURL];
        self.mp4URL = mp4Url;
        NSLog(@"mp4Url == %@", mp4Url);
        
        if (mp4Url != nil) {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:nil message:@"视频录制完成" delegate:self cancelButtonTitle:@"发送" otherButtonTitles:@"取消", nil];
            [alertView show];
        }
        
        [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
        if (lastBackgroundTaskIdentifier != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:lastBackgroundTaskIdentifier];
        }
    } else {
        
        [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
        NSLog(@"删除缓存视频");
    }
    
    
//    ALAssetsLibrary *assetsLibrary = [[ALAssetsLibrary alloc]init];
//    [assetsLibrary writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
//        if (error) {
//            NSLog(@"保存视频到相簿过程中发生错误，错误信息：%@",error.localizedDescription);
//        }
//        
//        NSLog(@"outputUrl:%@",outputFileURL);
//        
//        NSURL *mp4Url = [self convert2Mp4: outputFileURL];
//        NSLog(@"mp4Url == %@", mp4Url);
//        
//        [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
//        if (lastBackgroundTaskIdentifier != UIBackgroundTaskInvalid) {
//            [[UIApplication sharedApplication] endBackgroundTask:lastBackgroundTaskIdentifier];
//        }
//        
//        NSLog(@"成功保存视频到相簿.");
//        
//    }];
    
}

#pragma mark ===== 时间倒计时
- (void)timerCount {
    
    self.movieTimeCount ++;
    self.seconds --;
    self.timeLabel.text = [NSString stringWithFormat:@"00:%02d", self.seconds];
    
    if (0 == self.seconds) {
        self.isSave = YES;
        [self.timer invalidate]; // 停止计时
        [self.takeButton setTitle:@"录制" forState:UIControlStateNormal];
        [self.captureMovieFileOutput stopRecording];//停止录制
    }
}

#pragma mark - 转换为MP4格式
- (NSURL *)convert2Mp4:(NSURL *)movUrl {
    NSURL *mp4Url = nil;
    AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:movUrl options:nil];
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:avAsset];
    
    if ([compatiblePresets containsObject:AVAssetExportPresetHighestQuality]) {
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:avAsset
                                                                              presetName:AVAssetExportPresetHighestQuality];
        mp4Url = [movUrl copy];
        mp4Url = [mp4Url URLByDeletingPathExtension];
        mp4Url = [mp4Url URLByAppendingPathExtension:@"mp4"];
        exportSession.outputURL = mp4Url;
        exportSession.shouldOptimizeForNetworkUse = YES;
        exportSession.outputFileType = AVFileTypeMPEG4;
        dispatch_semaphore_t wait = dispatch_semaphore_create(0l);
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            switch ([exportSession status]) {
                case AVAssetExportSessionStatusFailed: {
                    NSLog(@"failed, error:%@.", exportSession.error);
                } break;
                case AVAssetExportSessionStatusCancelled: {
                    NSLog(@"cancelled.");
                } break;
                case AVAssetExportSessionStatusCompleted: {
                    NSLog(@"completed.");
                } break;
                default: {
                    NSLog(@"others.");
                } break;
            }
            dispatch_semaphore_signal(wait);
        }];
        
        long timeout = dispatch_semaphore_wait(wait, DISPATCH_TIME_FOREVER);
        if (timeout) {
            NSLog(@"timeout.");
        }
        if (wait) {
            //dispatch_release(wait);
            wait = nil;
        }
    }
    
    return mp4Url;
}

#pragma mark =====UIAlertView代理
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (0 == buttonIndex) {
        
        if ([self.delegate respondsToSelector:@selector(IDVideoControllerDidFinishedTakeMovie:)]) {
            [self.delegate IDVideoControllerDidFinishedTakeMovie:self.mp4URL];
        }
        
    } else {
        
        if (self.mp4URL) {
            [[NSFileManager defaultManager] removeItemAtURL:self.mp4URL error:nil];
            NSLog(@"视频删除成功");
        }
        
    }
}

#pragma mark - 通知
/**
 *  给输入设备添加通知
 */
-(void)addNotificationToCaptureDevice:(AVCaptureDevice *)captureDevice{
    //注意添加区域改变捕获通知必须首先设置设备允许捕获
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        captureDevice.subjectAreaChangeMonitoringEnabled=YES;
    }];
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //捕获区域发生改变
    [notificationCenter addObserver:self selector:@selector(areaChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
-(void)removeNotificationFromCaptureDevice:(AVCaptureDevice *)captureDevice{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
/**
 *  移除所有通知
 */
-(void)removeNotification{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self];
}

-(void)addNotificationToCaptureSession:(AVCaptureSession *)captureSession{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //会话出错
    [notificationCenter addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:captureSession];
}

/**
 *  设备连接成功
 *
 *  @param notification 通知对象
 */
-(void)deviceConnected:(NSNotification *)notification{
    NSLog(@"设备已连接...");
}
/**
 *  设备连接断开
 *
 *  @param notification 通知对象
 */
-(void)deviceDisconnected:(NSNotification *)notification{
    NSLog(@"设备已断开.");
}
/**
 *  捕获区域改变
 *
 *  @param notification 通知对象
 */
-(void)areaChange:(NSNotification *)notification{
//    NSLog(@"捕获区域改变...");
}

/**
 *  会话出错
 *
 *  @param notification 通知对象
 */
-(void)sessionRuntimeError:(NSNotification *)notification{
    NSLog(@"会话发生错误.");
}

#pragma mark - 私有方法

/**
 *  取得指定位置的摄像头
 *
 *  @param position 摄像头位置
 *
 *  @return 摄像头设备
 */
-(AVCaptureDevice *)getCameraDeviceWithPosition:(AVCaptureDevicePosition )position{
    NSArray *cameras= [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *camera in cameras) {
        if ([camera position]==position) {
            return camera;
        }
    }
    return nil;
}

/**
 *  改变设备属性的统一操作方法
 *
 *  @param propertyChange 属性改变操作
 */
-(void)changeDeviceProperty:(PropertyChangeBlock)propertyChange{
    AVCaptureDevice *captureDevice= [self.captureDeviceInput device];
    NSError *error;
    //注意改变设备属性前一定要首先调用lockForConfiguration:调用完之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error]) {
        propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    }else{
        NSLog(@"设置设备属性过程发生错误，错误信息：%@",error.localizedDescription);
    }
}

/**
 *  设置闪光灯模式
 *
 *  @param flashMode 闪光灯模式
 */
-(void)setFlashMode:(AVCaptureFlashMode )flashMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFlashModeSupported:flashMode]) {
            [captureDevice setFlashMode:flashMode];
        }
    }];
}
/**
 *  设置聚焦模式
 *
 *  @param focusMode 聚焦模式
 */
-(void)setFocusMode:(AVCaptureFocusMode )focusMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:focusMode];
        }
    }];
}
/**
 *  设置曝光模式
 *
 *  @param exposureMode 曝光模式
 */
- (void)setExposureMode:(AVCaptureExposureMode)exposureMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:exposureMode];
        }
    }];
}
/**
 *  设置聚焦点
 *
 *  @param point 聚焦点
 */
- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposureMode:(AVCaptureExposureMode)exposureMode atPoint:(CGPoint)point{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        if ([captureDevice isFocusPointOfInterestSupported]) {
            [captureDevice setFocusPointOfInterest:point];
        }
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
        }
        if ([captureDevice isExposurePointOfInterestSupported]) {
            [captureDevice setExposurePointOfInterest:point];
        }
    }];
}

/**
 *  添加点按手势，点按时聚焦
 */
- (void)addGenstureRecognizer {
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapScreen:)];
    [self.viewContainer addGestureRecognizer:tapGesture];
}

- (void)tapScreen:(UITapGestureRecognizer *)tapGesture{
    CGPoint point= [tapGesture locationInView:self.viewContainer];
    
    // 将UI坐标转化为摄像头坐标
    CGPoint cameraPoint = [self.captureVideoPreviewLayer captureDevicePointOfInterestForPoint:point];
    [self setFocusCursorWithPoint:point];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposureMode:AVCaptureExposureModeAutoExpose atPoint:cameraPoint];
}

/**
 *  设置聚焦光标位置
 *
 *  @param point 光标位置
 */
- (void)setFocusCursorWithPoint:(CGPoint)point{
    self.focusCursor.center = point;
    self.focusCursor.transform = CGAffineTransformMakeScale(1.5, 1.5);
    self.focusCursor.alpha = 1.0;
    [UIView animateWithDuration:1.0 animations:^{
        self.focusCursor.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.focusCursor.alpha = 0;
    }];
}

#pragma mark ======= 点击事件

#pragma mark 切换前后摄像头
- (void)toggleButtonClick:(UIButton *)sender {
    AVCaptureDevice *currentDevice = [self.captureDeviceInput device];
    AVCaptureDevicePosition currentPosition = [currentDevice position];
    [self removeNotificationFromCaptureDevice:currentDevice];
    AVCaptureDevice *toChangeDevice;
    AVCaptureDevicePosition toChangePosition = AVCaptureDevicePositionFront;
    if (currentPosition == AVCaptureDevicePositionUnspecified || currentPosition == AVCaptureDevicePositionFront) {
        toChangePosition = AVCaptureDevicePositionBack;
    }
    toChangeDevice = [self getCameraDeviceWithPosition:toChangePosition];
    [self addNotificationToCaptureDevice:toChangeDevice];
    // 获得要调整的设备输入对象
    AVCaptureDeviceInput *toChangeDeviceInput = [[AVCaptureDeviceInput alloc]initWithDevice:toChangeDevice error:nil];
    
    // 改变会话的配置前一定要先开启配置，配置完成后提交配置改变
    [self.captureSession beginConfiguration];
    // 移除原有输入对象
    [self.captureSession removeInput:self.captureDeviceInput];
    // 添加新的输入对象
    if ([self.captureSession canAddInput:toChangeDeviceInput]) {
        [self.captureSession addInput:toChangeDeviceInput];
        self.captureDeviceInput = toChangeDeviceInput;
    }
    // 提交会话配置
    [self.captureSession commitConfiguration];
    
}

- (void)backButtonClick {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark 视频录制
- (void)tackTouchDown:(UIButton *)sender withEvent:(UIEvent *)event {
    self.tipsLabel.text = @"上滑取消";
    [self.takeButton setTitle:@"录制" forState:UIControlStateNormal];
    
    _tipsLabel.text = @"手指上滑，取消发送";
    _tipsLabel.backgroundColor = [UIColor clearColor];
    
    // 根据设备输出获得连接
    AVCaptureConnection *captureConnection = [self.captureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
    // 根据连接取得设备输出的数据
    if (![self.captureMovieFileOutput isRecording]) {
        [self.takeButton setTitle:@"停止" forState:UIControlStateNormal];
        
        self.enableRotation = NO;
        // 如果支持多任务则则开始多任务
        if ([[UIDevice currentDevice] isMultitaskingSupported]) {
            self.backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
        }
        // 预览图层和视频方向保持一致
        captureConnection.videoOrientation = [self.captureVideoPreviewLayer connection].videoOrientation;
        
        
        NSString *movieCount = [[NSUserDefaults standardUserDefaults] objectForKey:@"MovieCount"];
        if (!movieCount) {
            [[NSUserDefaults standardUserDefaults] setObject:@"0" forKey:@"MovieCount"];
            movieCount = [[NSUserDefaults standardUserDefaults] objectForKey:@"MovieCount"];
        }
        
        NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingString:[NSString stringWithFormat:@"myMovie%@.mov", movieCount]];
        
        [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithFormat:@"%d", [movieCount integerValue] + 1] forKey:@"MovieCount"];
        
//        NSLog(@"save path is :%@",outputFilePath);
        NSURL *fileUrl = [NSURL fileURLWithPath:outputFilePath];
        NSLog(@"fileUrl:%@", fileUrl);
        [self.captureMovieFileOutput startRecordingToOutputFileURL:fileUrl recordingDelegate:self];
    }

}

- (void)btnDragged:(UIButton *)sender withEvent:(UIEvent *)event {
    UITouch *touch = [[event allTouches] anyObject];
    
    BOOL touchDragInside = CGRectContainsPoint(self.tabBarView.bounds, [touch locationInView:self.tabBarView]);
    if (touchDragInside) {
        
        self.tipsLabel.text = @"上滑取消";
        self.tipsLabel.backgroundColor = [UIColor clearColor];
        
    } else {

        self.tipsLabel.text = @"松开取消";
        self.tipsLabel.backgroundColor = [UIColor blueColor];
    }
}

- (void)btnTouchUp:(UIButton *)sender withEvent:(UIEvent *)event {

    UITouch *touch = [[event allTouches] anyObject];
    
    BOOL touchUpInside = CGRectContainsPoint(self.tabBarView.bounds, [touch locationInView:self.tabBarView]);
    if (touchUpInside) {
        self.isSave = YES;
        
//        NSLog(@"指鼠标在控件范围内抬起，前提先得按下");
    } else {
        self.isSave = NO;
        
//        NSLog(@"指鼠标在控件边界范围外抬起，前提先得按下，然后拖动到控件外");
    }

    [self.timer invalidate];
    [self.captureMovieFileOutput stopRecording];
    
    [self.takeButton setTitle:@"录制" forState:UIControlStateNormal];
    self.timeLabel.text = @"00:10";
    self.tipsLabel.text = @"";
    self.tipsLabel.backgroundColor = [UIColor clearColor];
}


#pragma mark  =====get方法

- (UIView *)headerView {
    if (!_headerView) {
        _headerView = [[UIView alloc] initWithFrame:CGRectMake(0, STATUSHEIGHT, iDeviceWidth, HEADERHEIGHT)];
        _headerView.userInteractionEnabled = YES;
        _headerView.backgroundColor = [UIColor grayColor];
        [_headerView addSubview:self.backButton];
        [_headerView addSubview:self.timeLabel];
    }
    return _headerView;
}

- (UIView *)viewContainer {
    if (_viewContainer == nil) {
        _viewContainer = [[UIView alloc] initWithFrame:CGRectMake(0, STATUSHEIGHT + HEADERHEIGHT, iDeviceWidth, iDeviceHeight - HEADERHEIGHT - STATUSHEIGHT - TABBARHEIGHT)];
        _viewContainer.backgroundColor = [UIColor grayColor];
        [_viewContainer addSubview:self.focusCursor];
        [_viewContainer addSubview:self.tipsLabel];
    }
    return _viewContainer;
}

- (UIButton *)takeButton {
    if (_takeButton == nil) {
        _takeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _takeButton.frame = CGRectMake(0, 0, 40, 40);
        _takeButton.center = CGPointMake(iDeviceWidth / 2, TABBARHEIGHT / 2);
        [_takeButton setTitle:@"录制" forState:UIControlStateNormal];
        [_takeButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        [_takeButton setBackgroundColor:[UIColor blueColor]];
        
        [_takeButton addTarget:self action:@selector(tackTouchDown:withEvent:) forControlEvents:UIControlEventTouchDown];
        [_takeButton addTarget:self action:@selector(btnDragged:withEvent:) forControlEvents:UIControlEventTouchDragInside];
        [_takeButton addTarget:self action:@selector(btnDragged:withEvent:) forControlEvents:UIControlEventTouchDragOutside];
        
        [_takeButton addTarget:self action:@selector(btnTouchUp:withEvent:) forControlEvents:UIControlEventTouchUpInside];
        [_takeButton addTarget:self action:@selector(btnTouchUp:withEvent:) forControlEvents:UIControlEventTouchUpOutside];
    }
    return _takeButton;
}

- (UIImageView *)focusCursor {
    if (_focusCursor == nil) {
        _focusCursor = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"camera_focus_red"]];
        _focusCursor.frame = CGRectMake(- 100, 0, 60, 60);
    }
    return _focusCursor;
}

- (UIView *)tabBarView {
    if (!_tabBarView) {
        _tabBarView = [[UIView alloc] initWithFrame:CGRectMake(0, iDeviceHeight - TABBARHEIGHT, iDeviceWidth, TABBARHEIGHT)];
        _tabBarView.userInteractionEnabled = YES;
        _tabBarView.backgroundColor = [UIColor orangeColor];
        [_tabBarView addSubview:self.takeButton];
    }
    return _tabBarView;
}

- (UIButton *)backButton {
    if (_backButton == nil) {
        _backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _backButton.frame = CGRectMake(20, 0, 40, 40);
        [_backButton setTitle:@"返回" forState:UIControlStateNormal];
        [_backButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_backButton addTarget:self action:@selector(backButtonClick) forControlEvents:UIControlEventTouchUpInside];
    }
    return _backButton;
}

- (UILabel *)timeLabel {
    if (!_timeLabel) {
        _timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, iDeviceWidth, HEADERHEIGHT)];
        _timeLabel.textColor = [UIColor redColor];
        _timeLabel.text = [NSString stringWithFormat:@"00:%02d", SECONDS];
        _timeLabel.textAlignment = NSTextAlignmentCenter;
    }
    return _timeLabel;
}

- (UILabel *)tipsLabel {
    if (!_tipsLabel) {
        _tipsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 20)];
        _tipsLabel.center = CGPointMake(iDeviceWidth / 2, self.viewContainer.bounds.size.height - 20);
        _tipsLabel.textColor = [UIColor redColor];
        _tipsLabel.font = [UIFont systemFontOfSize:14];
        _tipsLabel.textAlignment = NSTextAlignmentCenter;
    }
    return _tipsLabel;
}

@end
