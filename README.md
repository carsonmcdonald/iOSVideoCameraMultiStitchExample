MultiVidCam
===========

*work in progress*

This is an example of taking multiple videos using the video camera on an iOS
device then stitching those video segments together into one output file.

When you save a video it is saved to your camera roll.

Configuration Options
=====================

You can adjust the min/max recording times by modifying the following lines in 
RecordingViewController.m:

```
#define MAX_RECORDING_LENGTH 6.0
#define MIN_RECORDING_LENGTH 2.0
```

You can change the recording preset by modifying the following line
inRecordingViewController.m:

```
#define CAPTURE_SESSION_PRESET AVCaptureSessionPreset640x480
```

You can adjsut the initial input capture device by modifying the following
line in RecordingViewController.m:

```
#define INITIAL_CAPTURE_DEVICE_POSITION AVCaptureDevicePositionBack
```

You can adjust the initial mode of the torch by modifying the following line
in the RecordingViewController.m:

```
#define INITIAL_TORCH_MODE AVCaptureTorchModeOff
```

License
=======

MIT, see the LICENSE file.
