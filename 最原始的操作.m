//
//  VideoRecordViewController.m
//  Jasmine
//
//  Created by 杨胜超 on 13-12-31.
//  Copyright (c) 2013年 Huanrun. All rights reserved.
//

#import "VideoRecordViewController.h"

#define FrameDuration 24.0      //设置每秒多少帧
#define MaxVideoSeconds 15      //设置最多几秒
#define MinVideoSeconds 5       //设置最少几秒

#define VideoWidth  640.0f
#define VideoHeight 640.0f

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};

@interface VideoRecordViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

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

@property (nonatomic, retain) AVAssetWriter *assetWriter;
@property (nonatomic, retain) AVAssetWriterInput *assetWriterInput;
@property (nonatomic, strong) AVCaptureDevice *videoDevice;
@property (nonatomic, strong) AVCaptureDevice *audioDevice;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *captureVideoInput;
@property (nonatomic, strong) AVCaptureDeviceInput *captureAudioInput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *captureVideoOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *captureAudioOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preview;

@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;

@property (nonatomic, retain) NSURL *outputMovURL;
@property (nonatomic, retain) NSURL* outputMp4URL;
@property (nonatomic, assign) BOOL isStarted;
@property (nonatomic, assign) CMTime frameDuration;
@property (nonatomic, assign) CMTime nextPTS;
@property (nonatomic, assign) NSInteger currentFrame;   //当前第几帧
@property (nonatomic, assign) NSInteger maxFrame;       //最大多少帧
@property (nonatomic, assign) NSInteger minFrame;       //最少多少帧
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

- (void)dealloc {
    [self.session stopRunning];
    self.session = nil;
    self.videoDevice = nil;
    self.captureVideoInput = nil;
    
    self.audioDevice = nil;
    self.captureAudioInput = nil;
    
    self.assetWriter = nil;
    self.assetWriterInput = nil;
    
    self.captureVideoOutput = nil;
    self.outputMovURL = nil;
    self.outputMp4URL = nil;
    self.cameraView = nil;
    self.preview = nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self initSubviews];
    [self initCamera];
    
    [self.cameraView bringSubviewToFront:self.bottomTipImageView];
    [self.cameraView bringSubviewToFront:self.leftTipImageView];
    [self.cameraView bringSubviewToFront:self.rightTipImageView];
}

- (BOOL)shouldAutorotate {
    return YES;
}
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    HRLOG(@"toInterfaceOrientation = %d", toInterfaceOrientation);
}

- (void)initSubviews {
    self.isStarted = NO;
    self.topBarHidden = YES;
    self.backButton.hidden = YES;
    self.progressBar.progress = 0;
    self.nextStepButton.hidden = YES;
    self.view.backgroundColor = [UIColor blackColor];
    self.isLongScreen = [UIScreen mainScreen].bounds.size.height > 500;
    self.leftTipImageView.hidden = self.rightTipImageView.hidden = YES;
    self.topTipImageView.hidden = self.bottomTipImageView.hidden = NO;
    self.leftTipImageView.image = [UIImage imageNamed:@"video_left_labdscape_tip"];
    self.rightTipImageView.image = [UIImage imageNamed:@"video_right_labdscape_tip"];
    self.topTipImageView.image = [UIImage imageNamed:@"video_tip01"];
    WeakSelfType blockSelf = self;
    
    //设置按钮点击事件
    [self.cancelButton addTarget:self action:@selector(cancelButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.nextStepButton addTarget:self action:@selector(nextStepButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.reversalButton addTarget:self action:@selector(reversalButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    
    //设置缓存视频路径
    self.outputMovURL = [NSURL fileURLWithPath:[[[StorageManager sharedInstance] tmpDirectoryPath] stringByAppendingPathComponent:@"postvideo.mov"]];
    self.outputMp4URL = [NSURL fileURLWithPath:[[[StorageManager sharedInstance] tmpDirectoryPath] stringByAppendingPathComponent:@"postvideo.mp4"]];
    
    //设置每秒24帧
	self.frameDuration = CMTimeMakeWithSeconds(1.0 / FrameDuration, 90000);
    self.currentFrame = 0;
    self.maxFrame = FrameDuration * MaxVideoSeconds;
    self.minFrame = FrameDuration * MinVideoSeconds;
    
    //根据长短屏幕调整UI
    if (self.isLongScreen) {//长屏幕 TODO:需要统一判断
        self.cameraView.frame = CGRectSetY(self.cameraView.frame, 5 + CGRectGetMaxY(self.topTipImageView.frame));
    }
    else {//短屏幕
        self.cameraView.frame = CGRectSetY(self.cameraView.frame, self.topTipImageView.frame.origin.y);
    }
    
    //设置长按手势
    self.longPressGesture = [[UILongPressGestureRecognizer alloc] initWithHandler:^(UIGestureRecognizer *sender, UIGestureRecognizerState state, CGPoint location) {
        blockSelf.bottomTipImageView.hidden = YES;
        
        if (state == UIGestureRecognizerStateBegan) {
            if (blockSelf.currentFrame == 0) {//开始录制
                HRLOG(@"开始录制...");
                blockSelf.isStarted = YES;
                [blockSelf deleteFile:[blockSelf.outputMp4URL path]];
                [blockSelf deleteFile:[blockSelf.outputMovURL path]];
                blockSelf.topTipImageView.image = [UIImage imageNamed:@"video_tip02"];
            }
            else {//继续录制
                HRLOG(@"继续录制");
                blockSelf.isStarted = YES;
                blockSelf.topTipImageView.image = [UIImage imageNamed:@"video_tip02"];
            }
        }
        else if (state == UIGestureRecognizerStateEnded) {
            HRLOG(@"暂停");
            blockSelf.isStarted = NO;
            blockSelf.topTipImageView.image = [UIImage imageNamed:@"video_tip03"];
        }
    }];
    [self.cameraView addGestureRecognizer:self.longPressGesture];
    
    //注册监听设备的方向属性
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDeviceOrientationChange) name:UIDeviceOrientationDidChangeNotification object:nil];
}

-(void)onDeviceOrientationChange {
    UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
    switch (orientation) {
        case 3:
            self.rightTipImageView.hidden = NO;
            self.topTipImageView.hidden = self.leftTipImageView.hidden = YES;
            break;
        case 4:
            self.leftTipImageView.hidden = NO;
            self.topTipImageView.hidden = self.rightTipImageView.hidden = YES;
            break;
        default:
            self.topTipImageView.hidden = NO;
            self.leftTipImageView.hidden = self.rightTipImageView.hidden = YES;
            break;
    }
}

- (void)initCamera {
    NSError *error;
    
    //1.创建会话层
    self.session = [[AVCaptureSession alloc] init];
    [self.session setSessionPreset:AVCaptureSessionPresetiFrame960x540];
    [self.session beginConfiguration];
    
    //2.创建设备配置视频输入
    self.videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [self.videoDevice lockForConfiguration:nil];
    [self.videoDevice unlockForConfiguration];
	self.captureVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:self.videoDevice error:&error];
	if ( ! self.captureVideoInput){
		HRLOG(@"Error: %@", error);
		return;
	}
    [self.session addInput:self.captureVideoInput];
    
    //3.创建设备配置音频输入
    self.audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    [self.audioDevice lockForConfiguration:nil];
    [self.audioDevice unlockForConfiguration];
    self.captureAudioInput = [AVCaptureDeviceInput deviceInputWithDevice:self.audioDevice error:&error];
    if ( ! self.captureAudioInput){
		HRLOG(@"Error: %@", error);
		return;
	}
    [self.session addInput:self.captureAudioInput];
    
    //4.配置视频输出
    self.captureVideoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.captureVideoOutput setAlwaysDiscardsLateVideoFrames:YES];
    self.captureVideoOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};//录像设置
	[self.session addOutput:self.captureVideoOutput];
    [self.captureVideoOutput setSampleBufferDelegate:self queue:dispatch_queue_create("myQueue", NULL)];
    
    //5.配置视频输出
    self.captureAudioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [self.session addOutput:self.captureAudioOutput];
    
    //6.创建显示层
    self.preview = [AVCaptureVideoPreviewLayer layerWithSession: self.session];
    self.preview.frame = CGRectMake(0, 0, self.cameraView.frame.size.width, self.cameraView.frame.size.height);
    self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [self.cameraView.layer addSublayer:self.preview];
    [self.session commitConfiguration];
    [self.session startRunning];
}

#pragma mark -  ButtonClickedEvent

- (IBAction)cancelButtonClicked:(id)sender {
    WeakSelfType blockSelf = self;
    if (self.isStarted) {
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
    WeakSelfType blockSelf = self;
    self.isStarted = NO;
    //取消camera上的长按手势
    [self.cameraView removeGestureRecognizer:self.longPressGesture];
    //计算时长
    self.duration = self.currentFrame * 1.0f / FrameDuration;
    
    if (self.assetWriter) {
        [self showHUDLoadingWithString:@"正在保存"];
        [self.assetWriterInput markAsFinished];
        [self.assetWriter finishWritingWithCompletionHandler:^{
            [blockSelf convertToMp4];
        }];
    }
}

- (void)convertToMp4 {
    WeakSelfType blockSelf = self;
    NSString* _mp4Quality = AVAssetExportPresetMediumQuality;
    
    // 试图删除原mp4
    [self deleteFile:[self.outputMp4URL path]];
    
    // 生成mp4
    AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:self.outputMovURL options:nil];
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:avAsset];
    
    if ([compatiblePresets containsObject:_mp4Quality]) {
        __block AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:avAsset
                                                                                       presetName:_mp4Quality];
        
        exportSession.outputURL = self.outputMp4URL;
        exportSession.outputFileType = AVFileTypeMPEG4;
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            [blockSelf hideHUDLoading];
            switch ([exportSession status]) {
                case AVAssetExportSessionStatusFailed:
                    [blockSelf showResultThenHide:@"转换mp4出错"];
                    break;
                case AVAssetExportSessionStatusCancelled:
                    [blockSelf showResultThenHide:@"转换被取消"];
                    break;
                case AVAssetExportSessionStatusCompleted:
                    [blockSelf performSelectorOnMainThread:@selector(convertFinish) withObject:nil waitUntilDone:NO];
                    break;
                default:
                    break;
            }
        }];
    }
    else {
        [self hideHUDLoading];
        [self showResultThenHide:@"转换mp4出错！"];
    }
}

- (void)convertFinish {
    [self deleteFile:[self.outputMovURL path]];
    if ([self.delegate respondsToSelector:@selector(videoRecordViewController:didFinishVideoRecordWithVideoPath:andVideoDuration:)]) {
        [self.delegate videoRecordViewController:self didFinishVideoRecordWithVideoPath:[self.outputMp4URL path] andVideoDuration:self.duration];
    }
}

- (IBAction)reversalButtonClicked:(id)sender {
    [self flipFromCALayer:self.preview];
    
    NSArray *inputs = self.session.inputs;
    for ( AVCaptureDeviceInput *input in inputs ) {
        AVCaptureDevice *device = input.device;
        if ([device hasMediaType:AVMediaTypeVideo]) {
            AVCaptureDevicePosition position = device.position;
            AVCaptureDevice *newCamera = nil;
            AVCaptureDeviceInput *newInput = nil;
            
            if (position == AVCaptureDevicePositionFront) {
                newCamera = [self cameraWithPosition:AVCaptureDevicePositionBack];
            }
            else {
                newCamera = [self cameraWithPosition:AVCaptureDevicePositionFront];
            }
            self.videoDevice = newCamera;
            newInput = [AVCaptureDeviceInput deviceInputWithDevice:newCamera error:nil];
            
            // beginConfiguration ensures that pending changes are not applied immediately
            [self.session beginConfiguration];
            
            [self.session removeInput:input];
            [self.session addInput:newInput];
            
            // Changes take effect once the outermost commitConfiguration is invoked.
            [self.session commitConfiguration];
            break;
        }
    }
}

#pragma mark -  AVCaptureVideoDataOutputSampleBufferDelegate

// Delegate routine that is called when a sample buffer was written
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (self.isStarted) {
        // set up the AVAssetWriter using the format description from the first sample buffer captured
        if ( self.assetWriter == nil ) {
            //NSLog(@"Writing movie to \"%@\"", outputURL);
            CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
            if ( NO == [self setupAssetWriterForURL:self.outputMovURL formatDescription:formatDescription] ) {
                return;
            }
        }
        // re-time the sample buffer - in this sample frameDuration is set to 5 fps
        CMSampleTimingInfo timingInfo = kCMTimingInfoInvalid;
        timingInfo.duration = self.frameDuration;
        timingInfo.presentationTimeStamp = self.nextPTS;
        CMSampleBufferRef sbufWithNewTiming = NULL;
        
        
        OSStatus err = CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault,
                                                             sampleBuffer,
                                                             1, // numSampleTimingEntries
                                                             &timingInfo,
                                                             &sbufWithNewTiming);
        if (err) {
            HRLOG(@"CMSampleBufferCreateCopyWithNewTiming error");
            return;
        }
        
        // append the sample buffer if we can and increment presnetation time
        if ( [self.assetWriterInput isReadyForMoreMediaData] ) {
            if ([self.assetWriterInput appendSampleBuffer:sbufWithNewTiming]) {
                self.nextPTS = CMTimeAdd(self.frameDuration, self.nextPTS);
            }
            else {
                NSError *error = [self.assetWriter error];
                HRLOG(@"failed to append sbuf: %@", error);
            }
        }
        else {
            HRLOG(@"isReadyForMoreMediaData error");
        }
        
        // release the copy of the sample buffer we made
        CFRelease(sbufWithNewTiming);
        
        self.currentFrame ++;   //累加一帧
        dispatch_async(dispatch_get_main_queue(), ^{
            CGFloat p = (CGFloat)((CGFloat)self.currentFrame / (CGFloat)self.maxFrame);
            [self.progressBar setProgress:p animated:YES];
            
            if (self.currentFrame >= self.minFrame && self.nextStepButton.hidden) {
                self.nextStepButton.hidden = NO;
                self.topTipImageView.image = [UIImage imageNamed:@"video_tip04"];
            }
            if (self.currentFrame >= self.maxFrame) {
                self.topTipImageView.hidden = YES;
                [self nextStepButtonClicked:nil];
            }
        });
    }
}

#pragma mark - private method

- (void)flipFromCALayer:(CALayer *)layer {
    CATransition *animation = [CATransition animation];
    animation.delegate = self;
    animation.duration = 0.2f;
    animation.timingFunction = UIViewAnimationCurveEaseInOut;
    animation.type = @"flip";
    if (self.videoDevice.position == AVCaptureDevicePositionFront) {
        animation.subtype = kCATransitionFromRight;
    }
    else if(self.videoDevice.position == AVCaptureDevicePositionBack) {
        animation.subtype = kCATransitionFromLeft;
    }
    [layer addAnimation:animation forKey:@"Transition1"];
}

- (void)deleteFile:(NSString *) filePath {
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    }
}

//切换前后摄像头
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices)
    {
        if (device.position == position)
        {
            return device;
        }
    }
    return nil;
}

- (BOOL)setupAssetWriterForURL:(NSURL *)fileURL formatDescription:(CMFormatDescriptionRef)formatDescription {
	NSError *error = nil;
	self.assetWriter = [[AVAssetWriter alloc] initWithURL:fileURL fileType:AVFileTypeQuickTimeMovie error:&error];
	if (error)
		return NO;
	
    // initialized a new input for video to receive sample buffers for writing
    // passing nil for outputSettings instructs the input to pass through appended samples, doing no processing before they are written
    // 下面这个参数，设置图像质量，数字越大，质量越好
    NSDictionary *videoCompressionProps = [NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSNumber numberWithDouble:512*1024.0], AVVideoAverageBitRateKey,
                                           nil ];
    // 设置编码和宽高比。宽高比最好和摄像比例一致，否则图片可能被压缩或拉伸
    NSDictionary* dic = [NSDictionary dictionaryWithObjectsAndKeys:AVVideoCodecH264, AVVideoCodecKey,
                         [NSNumber numberWithFloat:VideoWidth], AVVideoWidthKey,
                         [NSNumber numberWithFloat:VideoHeight], AVVideoHeightKey,
                         AVVideoScalingModeResizeAspectFill, AVVideoScalingModeKey,
                         videoCompressionProps, AVVideoCompressionPropertiesKey, nil];
	self.assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:dic];
	[self.assetWriterInput setExpectsMediaDataInRealTime:YES];
	if ([self.assetWriter canAddInput:self.assetWriterInput])
		[self.assetWriter addInput:self.assetWriterInput];
	
    // specify the prefered transform for the output file
	CGFloat rotationDegrees;
	switch ([[UIDevice currentDevice] orientation]) {
		case UIDeviceOrientationPortraitUpsideDown:
			rotationDegrees = -90.;
			break;
		case UIDeviceOrientationLandscapeLeft: // no rotation
			rotationDegrees = 0.;
			break;
		case UIDeviceOrientationLandscapeRight:
			rotationDegrees = 180.;
			break;
		case UIDeviceOrientationPortrait:
		case UIDeviceOrientationUnknown:
		case UIDeviceOrientationFaceUp:
		case UIDeviceOrientationFaceDown:
		default:
			rotationDegrees = 90.;
			break;
	}
	CGFloat rotationRadians = DegreesToRadians(rotationDegrees);
	[self.assetWriterInput setTransform:CGAffineTransformMakeRotation(rotationRadians)];
	
    // initiates a sample-writing at time 0
	self.nextPTS = kCMTimeZero;
	[self.assetWriter startWriting];
	[self.assetWriter startSessionAtSourceTime:self.nextPTS];
	
    return YES;
}

@end
