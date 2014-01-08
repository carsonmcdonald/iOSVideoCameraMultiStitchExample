//
//  VideoRecordViewController.m
//  Jasmine
//
//  Created by 杨胜超 on 13-12-31.
//  Copyright (c) 2013年 Huanrun. All rights reserved.
//

#import "VideoRecordViewController.h"
#import "CameraEngine.h"

#define MaxVideoSeconds 15.0f      //设置最多几秒
#define MinVideoSeconds 5.0f       //设置最少几秒

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};

@interface VideoRecordViewController ()

@property (nonatomic, weak) IBOutlet UIProgressView* progressBar;
@property (nonatomic, weak) IBOutlet UIImageView *topTipImageView;

@property (nonatomic, weak) IBOutlet UIView *cameraView;
@property (nonatomic, weak) IBOutlet UIImageView *leftTipImageView;
@property (nonatomic, weak) IBOutlet UIImageView *rightTipImageView;
@property (nonatomic, weak) IBOutlet UIImageView *bottomTipImageView;

@property (nonatomic, weak) IBOutlet UIView *bottomContainerView;
@property (nonatomic, weak) IBOutlet UIButton *cancelButton;    //取消录像
@property (nonatomic, weak) IBOutlet UIButton *nextStepButton;  //下一步
@property (nonatomic, weak) IBOutlet UIButton *reversalButton;  //翻转

@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, assign) NSTimeInterval startInterval;
@property (nonatomic, assign) double duration;          //录制时长
@property (nonatomic, assign) BOOL isLongScreen;

@end

@implementation VideoRecordViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewWillDisappear:(BOOL)animated {
    [[CameraEngine engine] shutdown];
    [super viewWillDisappear:animated];
}

- (void)viewDidLoad {
    HRLOG(@"in viewdidload");
    [super viewDidLoad];
    [[CameraEngine engine] startup];
    
    [self initSubviews];
    
    [self.cameraView bringSubviewToFront:self.bottomTipImageView];
    [self.cameraView bringSubviewToFront:self.leftTipImageView];
    [self.cameraView bringSubviewToFront:self.rightTipImageView];
    HRLOG(@"finish viewdidload");
}

- (BOOL)shouldAutorotate {
    return YES;
}
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    HRLOG(@"toInterfaceOrientation = %d", toInterfaceOrientation);
}

- (void)initSubviews {
    HRLOG(@"start init subviews");
    self.duration = 0;
    self.topBarHidden = YES;
    self.backButton.hidden = YES;
    self.progressBar.progress = 0;
    self.nextStepButton.hidden = YES;
    self.view.backgroundColor = [UIColor blackColor];
    self.isLongScreen = [UIScreen mainScreen].bounds.size.height > 500;
    self.leftTipImageView.alpha = self.rightTipImageView.alpha = 0;
    self.topTipImageView.alpha = self.bottomTipImageView.alpha = 1;
    self.leftTipImageView.image = [UIImage imageNamed:@"video_left_labdscape_tip"];
    self.rightTipImageView.image = [UIImage imageNamed:@"video_right_labdscape_tip"];
    self.topTipImageView.image = [UIImage imageNamed:@"video_tip01"];
    WeakSelfType blockSelf = self;
    
    //根据长短屏幕调整UI
    if (self.isLongScreen) {//长屏幕 TODO:需要统一判断
        self.cameraView.frame = CGRectSetY(self.cameraView.frame, 5 + CGRectGetMaxY(self.topTipImageView.frame));
    }
    else {//短屏幕
        self.cameraView.frame = CGRectSetY(self.cameraView.frame, self.topTipImageView.frame.origin.y);
    }
    HRLOG(@"display previewlayer");
    //设置显示层
    AVCaptureVideoPreviewLayer* preview = [[CameraEngine engine] getPreviewLayer];
    [preview removeFromSuperlayer];
    preview.frame = self.cameraView.bounds;
    [self.cameraView.layer addSublayer:preview];
    
    HRLOG(@"startup camera engine");
    //设置按钮点击事件
    [self.cancelButton addTarget:self action:@selector(cancelButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.nextStepButton addTarget:self action:@selector(nextStepButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.reversalButton addTarget:self action:@selector(reversalButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    
    //设置长按手势
    self.longPressGesture = [[UILongPressGestureRecognizer alloc] initWithHandler:^(UIGestureRecognizer *sender, UIGestureRecognizerState state, CGPoint location) {
        [blockSelf displayImageView:blockSelf.bottomTipImageView withAlpha:0];
        
        if (state == UIGestureRecognizerStateBegan) {
            if (blockSelf.duration == 0) {//开始录制
                HRLOG(@"开始录制...");
                blockSelf.topTipImageView.image = [UIImage imageNamed:@"video_tip02"];
                [[CameraEngine engine] startCapture];
                blockSelf.startInterval = [NSDate date].timeIntervalSince1970;
            }
            else {//继续录制
                HRLOG(@"继续录制");
                blockSelf.topTipImageView.image = [UIImage imageNamed:@"video_tip02"];
                [[CameraEngine engine] resumeCapture];
                blockSelf.startInterval = [NSDate date].timeIntervalSince1970;
            }
        }
        else if (state == UIGestureRecognizerStateEnded) {
            HRLOG(@"暂停");
            blockSelf.topTipImageView.image = [UIImage imageNamed:@"video_tip03"];
            [[CameraEngine engine] pauseCapture];
            blockSelf.duration += [NSDate date].timeIntervalSince1970 - blockSelf.startInterval;//累计时长
            HRLOG(@"duration = %f", blockSelf.duration);
        }
    }];
    [self.cameraView addGestureRecognizer:self.longPressGesture];
    
    //注册监听设备的方向属性
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDeviceOrientationChange) name:UIDeviceOrientationDidChangeNotification object:nil];
    
    //设置定时器
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1f
                                          block:^(NSTimer *timer) {
                                              if ([CameraEngine engine].isCapturing && ! [CameraEngine engine].isPaused) {
                                                  dispatch_async(dispatch_get_main_queue(), ^{
                                                      double currentDuration = [NSDate date].timeIntervalSince1970 - blockSelf.startInterval;
                                                      double totalDuration = currentDuration + blockSelf.duration;
                                                      HRLOG(@"totalDuration = %f", totalDuration);
                                                      //1. 更新进度条
                                                      [blockSelf.progressBar setProgress:totalDuration / MaxVideoSeconds animated:YES];
                                                      //2. 达到最少秒数才显示【下一步】按钮
                                                      if (totalDuration >= MinVideoSeconds && blockSelf.nextStepButton.hidden) {
                                                          blockSelf.nextStepButton.hidden = NO;
                                                          blockSelf.topTipImageView.image = [UIImage imageNamed:@"video_tip04"];
                                                      }
                                                      //3. 达到最大秒数，自动停止拍摄
                                                      if (totalDuration >= MaxVideoSeconds) {
                                                          blockSelf.topTipImageView.hidden = YES;
                                                          blockSelf.duration = totalDuration;
                                                          [blockSelf nextStepButtonClicked:nil];
                                                      }
                                                  });
                                              }
                                          }
                                        repeats:YES];
    HRLOG(@"finish init subviews");
}

-(void)onDeviceOrientationChange {
    UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
    switch (orientation) {
        case 3:
            [self displayImageView:self.rightTipImageView withAlpha:1];
            [self displayImageView:self.topTipImageView withAlpha:0];
            [self displayImageView:self.leftTipImageView withAlpha:0];
            break;
        case 4:
            [self displayImageView:self.leftTipImageView withAlpha:1];
            [self displayImageView:self.topTipImageView withAlpha:0];
            [self displayImageView:self.rightTipImageView withAlpha:0];
            break;
        default:
            [self displayImageView:self.topTipImageView withAlpha:1];
            [self displayImageView:self.leftTipImageView withAlpha:0];
            [self displayImageView:self.rightTipImageView withAlpha:0];
            break;
    }
}

- (void)displayImageView:(UIImageView *)imageView withAlpha:(float) alpha {
    [UIView animateWithDuration:0.3f
                     animations:^{
                         imageView.alpha = alpha;
                     }];
}

#pragma mark -  ButtonClickedEvent

- (IBAction)cancelButtonClicked:(id)sender {
    WeakSelfType blockSelf = self;
    if (self.duration > 0) {
        [UIAlertView showAlertViewWithTitle:@"取消录制"
                                    message:@"您已经录制了一段视频了，确定要放弃？"
                          cancelButtonTitle:@"按错了"
                          otherButtonTitles:@[@"确定放弃"]
                                    handler:^(UIAlertView *alertView, NSInteger buttonIndex) {
                                        if (buttonIndex == 1) {
                                            if ([blockSelf.delegate respondsToSelector:@selector(videoRecordViewControllerDidCancel:)]) {
                                                [blockSelf.delegate videoRecordViewControllerDidCancel:blockSelf];
                                            }
                                        }
                                    }];
    }
    else {
        if ([self.delegate respondsToSelector:@selector(videoRecordViewControllerDidCancel:)]) {
            [self.delegate videoRecordViewControllerDidCancel:self];
        }
    }
}

- (IBAction)nextStepButtonClicked:(id)sender {
    //1. 取消camera上的长按手势
    [self.cameraView removeGestureRecognizer:self.longPressGesture];
    //2. 停止拍摄
    [[CameraEngine engine] stopCapture];
    HRLOG(@"录制总时长：%f", self.duration);
    //3. 回调
    if ([self.delegate respondsToSelector:@selector(videoRecordViewController:didFinishVideoRecordWithVideoPath:andVideoDuration:)]) {
        [self.delegate videoRecordViewController:self didFinishVideoRecordWithVideoPath:[[CameraEngine engine].outputMp4URL path] andVideoDuration:self.duration];
    }
}

- (void)reversalButtonClicked:(id)sender {
    [[CameraEngine engine] reversalCapture];
}

@end
