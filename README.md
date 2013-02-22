MultiVidCam
===========

*work in progress*

This is an example of taking multiple videos using the video camera on an iOS
device then stitching those video segments together into one output file.

The two main classes that do the heavy lifting for the video capture and processing are:

VideoCameraInputManager - Pulls together the input sources and manages the recording session. Allows for pausing and resuming video recording. Keeps track of the total runtime of all the segements of video created by pausing and resuming.

AVAssetStitcher - Stitches together multiple input videos and generate a single mpeg4 output. Along the way it applies a CGAffineTransform to each video segment

License
=======

MIT, see the LICENSE file.
