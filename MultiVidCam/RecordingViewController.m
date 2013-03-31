//
// Copyright (c) 2013 Carson McDonald
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
// documentation files (the "Software"), to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
// and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions
// of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
// TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//

#import "RecordingViewController.h"

#import <AssetsLibrary/AssetsLibrary.h>

#import "VideoCameraInputManager.h"

@interface RecordingViewController (Private)

- (void)updateProgress:(NSTimer *)timer;

- (void)saveOutputToAssetLibrary:(NSURL *)outputFileURL completionBlock:(void (^)(NSError *error))completed;

@end

// Maximum and minumum length to record in seconds
#define MAX_RECORDING_LENGTH 6.0
#define MIN_RECORDING_LENGTH 2.0

// Set the recording preset to use
#define CAPTURE_SESSION_PRESET AVCaptureSessionPreset640x480

// Set the input device to use when first starting
#define INITIAL_CAPTURE_DEVICE_POSITION AVCaptureDevicePositionBack

// Set the initial torch mode
#define INITIAL_TORCH_MODE AVCaptureTorchModeOff

@implementation RecordingViewController
{
    VideoCameraInputManager *videoCameraInputManager;
    
    AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
    
    NSTimer *progressUpdateTimer;
}

- (void)viewDidLoad
{
    videoCameraInputManager = [[VideoCameraInputManager alloc] init];
    
    videoCameraInputManager.maxDuration = MAX_RECORDING_LENGTH;
    videoCameraInputManager.asyncErrorHandler = ^(NSError *error) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error" message:error.domain delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alertView show];
    };
    
    NSError *error;
    [videoCameraInputManager setupSessionWithPreset:CAPTURE_SESSION_PRESET
                                  withCaptureDevice:INITIAL_CAPTURE_DEVICE_POSITION
                                      withTorchMode:INITIAL_TORCH_MODE
                                          withError:&error];
    
    
    if(error)
    {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error" message:error.domain delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alertView show];
    }
    else
    {
        captureVideoPreviewLayer = [AVCaptureVideoPreviewLayer layerWithSession:videoCameraInputManager.captureSession];
        
        self.videoPreviewView.layer.masksToBounds = YES;
        captureVideoPreviewLayer.frame = self.videoPreviewView.bounds;
        
        captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        
        [self.videoPreviewView.layer insertSublayer:captureVideoPreviewLayer below:self.videoPreviewView.layer.sublayers[0]];
        
        // Start the session. This is done asychronously because startRunning doesn't return until the session is running.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            [videoCameraInputManager.captureSession startRunning];
            
        });
        
        self.busyView.frame = CGRectMake(self.busyView.frame.origin.x, -self.busyView.frame.size.height, self.busyView.frame.size.width, self.busyView.frame.size.height);
        self.saveButton.hidden = YES;
    }
    
    [super viewDidLoad];
}

- (void)updateProgress:(NSTimer *)timer
{
    CMTime duration = [videoCameraInputManager totalRecordingDuration];
    
    self.videoRecrodingProgress.progress = CMTimeGetSeconds(duration) / MAX_RECORDING_LENGTH;
    
    if(CMTimeGetSeconds(duration) >= MIN_RECORDING_LENGTH)
    {
        self.saveButton.hidden = NO;
    }
    
    if(CMTimeGetSeconds(duration) >= MAX_RECORDING_LENGTH)
    {
        self.recordButton.enabled = NO;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    captureVideoPreviewLayer.frame = self.videoPreviewView.bounds;
    
    [super viewDidAppear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark Record button

- (IBAction)cancelAction:(id)sender
{
    self.saveButton.hidden = YES;
    
    self.videoRecrodingProgress.progress = 0.0;

    [videoCameraInputManager reset];
}

- (IBAction)recordTouchDown:(id)sender
{
    progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                           target:self
                                                         selector:@selector(updateProgress:)
                                                         userInfo:nil
                                                          repeats:YES];
    
    if(videoCameraInputManager.isPaused)
    {
        [videoCameraInputManager resumeRecording];
    }
    else
    {
        [videoCameraInputManager startRecording];
    }
}

- (IBAction)recordTouchCancel:(id)sender
{
    [progressUpdateTimer invalidate];
    [videoCameraInputManager pauseRecording];
}

- (IBAction)recordTouchUp:(id)sender
{
    [progressUpdateTimer invalidate];
    [videoCameraInputManager pauseRecording];
}

- (IBAction)saveRecording:(id)sender
{
    self.saveButton.hidden = YES;
    
    self.busyView.hidden = NO;
    [UIView animateWithDuration:0.25 animations:^{
        self.busyView.frame = CGRectMake(self.busyView.frame.origin.x, 0, self.busyView.frame.size.width, self.busyView.frame.size.height);
    }];
    
    NSURL *finalOutputFileURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@%@-%ld.mp4", NSTemporaryDirectory(), @"final", (long)[[NSDate date] timeIntervalSince1970]]];
    
    [videoCameraInputManager finalizeRecordingToFile:finalOutputFileURL
                                       withVideoSize:self.videoPreviewView.frame.size
                                          withPreset:AVAssetExportPreset640x480
                               withCompletionHandler:^(NSError *error) {
        
        if(error)
        {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error" message:error.domain delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [alertView show];
        }
        else
        {
            [self saveOutputToAssetLibrary:finalOutputFileURL completionBlock:^(NSError *saveError) {
                
                [UIView animateWithDuration:0.25 animations:^{
                    self.busyView.frame = CGRectMake(self.busyView.frame.origin.x, -self.busyView.frame.size.height, self.busyView.frame.size.width, self.busyView.frame.size.height);
                } completion:^(BOOL finished) {
                    self.busyView.hidden = YES;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Done" message:@"The video has been saved to your camera roll." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                        [alertView show];
                    });
                }];
                
                [[NSFileManager defaultManager] removeItemAtURL:finalOutputFileURL error:nil];
                
                self.videoRecrodingProgress.progress = 0.0;
                self.recordButton.enabled = YES;
                
            }];
        }
        
    }];
}

- (void)saveOutputToAssetLibrary:(NSURL *)outputFileURL completionBlock:(void (^)(NSError *error))completed
{
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    
    [library writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
        
        completed(error);
        
    }];
}

@end
