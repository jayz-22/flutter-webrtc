//
//  FlutterRTCRemoteVideoRenderer.m
//  Pods
//
//  Created by 周培杰 on 2024/6/18.
//

#import "FlutterRTCRemoteVideoRenderer.h"

@interface FlutterRTCRemoteVideoRenderer () <RTCVideoRenderer>

@property (nonatomic, strong) AVAssetWriter *writer;
@property (nonatomic, strong) AVAssetWriterInput *videoInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *pixelBufferAdaptor;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) size_t outputFileWidth;
@property (nonatomic, assign) size_t outputFileHeight;

@end

@implementation FlutterRTCRemoteVideoRenderer

- (void)startRecordingToPath:(NSString *)path
                  videoTrack:(RTCVideoTrack *)videoTrack
                  completion:(void (^)(NSError *error))completion {
    if (self.isRecording) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"FlutterRTCRemoteVideoRenderer"
                                                 code:1001
                                             userInfo:@{NSLocalizedDescriptionKey: @"Recording is already in progress"}];
            completion(error);
        }
        return;
    }
    
    [videoTrack addRenderer:self];
    
    NSURL *outputURL = [NSURL fileURLWithPath:path];
    NSError *error = nil;
    self.writer = [AVAssetWriter assetWriterWithURL:outputURL fileType:AVFileTypeMPEG4 error:&error];
    if (error) {
        NSLog(@"Error creating AVAssetWriter: %@", error);
        completion(error);
        return;
    }
    
    [self setupVideoInput];
    
    self.isRecording = YES;
    
    if (![self.writer startWriting]) {
        NSError *error = [NSError errorWithDomain:@"FlutterRTCRemoteVideoRenderer"
                                             code:1003
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to start writing with AVAssetWriter"}];
        if (completion) {
            completion(error);
        }
        return;
    }
    
    [self.writer startSessionAtSourceTime:kCMTimeZero];
    
    completion(nil);
}

- (void)stopRecordingWithCompletion:(void (^)(NSError *error))completion {
    NSLog(@"stopRecordingWithCompletion");
    if (!self.isRecording) {
        completion(nil);
        return;
    }
    
    self.isRecording = NO;
    
    [self.videoInput markAsFinished];
    
    [self.writer finishWritingWithCompletionHandler:^{
        NSError *error = self.writer.error;
        if (error) {
            completion(error);
        } else {
            self.writer = nil;
            completion(nil);
        }
    }];
}

- (void)setupVideoInput {
    NSDictionary *videoSettings = @{
                AVVideoCodecKey: AVVideoCodecTypeH264,
                AVVideoWidthKey: @(self.outputFileWidth),
                AVVideoHeightKey: @(self.outputFileHeight),
            };
    
    self.videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    self.videoInput.expectsMediaDataInRealTime = YES;
    
    NSDictionary *sourcePixelBufferAttributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @(self.outputFileWidth),
        (id)kCVPixelBufferHeightKey: @(self.outputFileHeight)
    };
    
    self.pixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.videoInput sourcePixelBufferAttributes:sourcePixelBufferAttributes];
    
    if ([self.writer canAddInput:self.videoInput]) {
        [self.writer addInput:self.videoInput];
    }
}

- (void)appendVideoPixelBuffer:(CVPixelBufferRef)pixelBuffer withPresentationTime:(CMTime)presentationTime {
    if (self.isRecording && self.writer.status == AVAssetWriterStatusWriting) {
        if (self.videoInput.readyForMoreMediaData) {
            while (!self.videoInput.isReadyForMoreMediaData) {
                NSLog(@"Waiting...");
                usleep(10);
            }
                
            BOOL success = [self.pixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:presentationTime];
            if (!success) {
                NSLog(@"Failed to append pixel buffer");
            }
        }
    }
}

- (void)appendVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (self.isRecording && self.writer.status == AVAssetWriterStatusWriting) {
        if (self.videoInput.readyForMoreMediaData) {
            BOOL success = [self.videoInput appendSampleBuffer:sampleBuffer];
            if (!success) {
                NSLog(@"Failed to append sample buffer");
            }
        }
    }
}

- (CVPixelBufferRef)convertToCVPixelBuffer:(RTCVideoFrame*)frame {
  id<RTCI420Buffer> i420Buffer = [frame.buffer toI420];
  CVPixelBufferRef outputPixelBuffer;
  size_t w = (size_t)roundf(i420Buffer.width);
  size_t h = (size_t)roundf(i420Buffer.height);
  NSDictionary* pixelAttributes = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
  CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                      (__bridge CFDictionaryRef)(pixelAttributes), &outputPixelBuffer);
  CVPixelBufferLockBaseAddress(outputPixelBuffer, 0);
  const OSType pixelFormat = CVPixelBufferGetPixelFormatType(outputPixelBuffer);
  if (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
      pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
    // NV12
    uint8_t* dstY = CVPixelBufferGetBaseAddressOfPlane(outputPixelBuffer, 0);
    const size_t dstYStride = CVPixelBufferGetBytesPerRowOfPlane(outputPixelBuffer, 0);
    uint8_t* dstUV = CVPixelBufferGetBaseAddressOfPlane(outputPixelBuffer, 1);
    const size_t dstUVStride = CVPixelBufferGetBytesPerRowOfPlane(outputPixelBuffer, 1);

    [RTCYUVHelper I420ToNV12:i420Buffer.dataY
                  srcStrideY:i420Buffer.strideY
                        srcU:i420Buffer.dataU
                  srcStrideU:i420Buffer.strideU
                        srcV:i420Buffer.dataV
                  srcStrideV:i420Buffer.strideV
                        dstY:dstY
                  dstStrideY:(int)dstYStride
                       dstUV:dstUV
                 dstStrideUV:(int)dstUVStride
                       width:i420Buffer.width
                      height:i420Buffer.height];
  } else {
    uint8_t* dst = CVPixelBufferGetBaseAddress(outputPixelBuffer);
    const size_t bytesPerRow = CVPixelBufferGetBytesPerRow(outputPixelBuffer);

    if (pixelFormat == kCVPixelFormatType_32BGRA) {
      // Corresponds to libyuv::FOURCC_ARGB
      [RTCYUVHelper I420ToARGB:i420Buffer.dataY
                    srcStrideY:i420Buffer.strideY
                          srcU:i420Buffer.dataU
                    srcStrideU:i420Buffer.strideU
                          srcV:i420Buffer.dataV
                    srcStrideV:i420Buffer.strideV
                       dstARGB:dst
                 dstStrideARGB:(int)bytesPerRow
                         width:i420Buffer.width
                        height:i420Buffer.height];
    } else if (pixelFormat == kCVPixelFormatType_32ARGB) {
      // Corresponds to libyuv::FOURCC_BGRA
      [RTCYUVHelper I420ToBGRA:i420Buffer.dataY
                    srcStrideY:i420Buffer.strideY
                          srcU:i420Buffer.dataU
                    srcStrideU:i420Buffer.strideU
                          srcV:i420Buffer.dataV
                    srcStrideV:i420Buffer.strideV
                       dstBGRA:dst
                 dstStrideBGRA:(int)bytesPerRow
                         width:i420Buffer.width
                        height:i420Buffer.height];
    }
  }
  CVPixelBufferUnlockBaseAddress(outputPixelBuffer, 0);
  return outputPixelBuffer;
}

#pragma mark - RTCVideoRenderer methods

- (void)renderFrame:(RTCVideoFrame *)frame {
    if (!self.isRecording) {
        return;
    }
    
    CVPixelBufferRef pixelBufferRef = [self convertToCVPixelBuffer:frame];
    CMTime presentationTime = CMTimeMake(frame.timeStampNs, NSEC_PER_SEC);
    
    [self appendVideoPixelBuffer:pixelBufferRef withPresentationTime:presentationTime];
}

- (void)setSize:(CGSize)size { 
    if (self.outputFileWidth != size.width || self.outputFileHeight != size.height) {
        self.outputFileWidth = size.width;
        self.outputFileHeight = size.height;
        
        [self setupVideoInput];
    }
}
@end
