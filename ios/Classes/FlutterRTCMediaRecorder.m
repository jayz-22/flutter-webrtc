//
//  FlutterRTCMediaRecorder.m
//  Pods
//
//  Created by 周培杰 on 2024/6/24.
//

#import "FlutterRTCMediaRecorder.h"

#import <WebRTC/RTCYUVHelper.h>
#import <WebRTC/RTCYUVPlanarBuffer.h>

@interface FlutterRTCMediaRecorder () <RTCVideoRenderer>

@property (nonatomic, strong) NSString* outputPath;
@property (nonatomic, strong) RTCVideoTrack* videoTrack;
@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput* videoInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor* pixelBufferAdaptor;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) size_t outputFileWidth;
@property (nonatomic, assign) size_t outputFileHeight;
@property (nonatomic, assign) OSType pixelFormat;

@end

@implementation FlutterRTCMediaRecorder

- (instancetype)initWithOutputPath:(NSString *)outputPath videoTrack:(RTCVideoTrack *)videoTrack {
    self = [self init];
    if (self) {
        self.outputPath = outputPath;
        self.videoTrack = videoTrack;
    }
    return self;
}

// startRecordToFile 的对应实现
- (void)startWithCompletion:(void (^)(NSError* error))completion {
    NSLog(@"startWithCompletion");
    NSError *error = nil;
    if (self.isRecording) {
        error = [error initWithDomain:@"FlutterRTCMediaRecorder" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to finish writing"}];
        completion(error);
        return;
    }
    self.isRecording = YES;
    
    if (!self.outputPath) {
        error = [error initWithDomain:@"FlutterRTCMediaRecorder" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"outputPath cannot be empty"}];
        completion(error);
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];

    // 如果目录不存在，则创建目录
    NSString *directoryPath = [self.outputPath stringByDeletingLastPathComponent]; // 获取父目录路径
    BOOL isDirectory;
    if (![fileManager fileExistsAtPath:directoryPath isDirectory:&isDirectory]) {
        [fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"Failed to create video save directory: %@", error);
            completion(error);
            return;
        }
    }
    
    // 确保文件不存在
    if ([fileManager fileExistsAtPath:self.outputPath]) {
        [fileManager removeItemAtPath:self.outputPath error:&error];
        if (error) {
            NSLog(@"Failed to remove existing file: %@", error);
            completion(error);
            return;
        }
    }
    
    // 注册视频帧接受
    if (self.videoTrack) {
        [self.videoTrack addRenderer:self];
    }
}

// stopRecordToFile 的对应实现
- (void)stopWithCompletion:(void (^)(NSError* error))completion {
    NSLog(@"stopWithCompletion");
    NSError *error = nil;
    if (!self.isRecording) {
        error = [error initWithDomain:@"FlutterRTCMediaRecorder" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"already stop recording"}];
        completion(error);
        return;
    }
    self.isRecording = NO;
    
    // 注销视频帧接受
    if (self.videoTrack) {
        [self.videoTrack removeRenderer:self];
    }
    
    // 停止录制视频并完成写入操作
    [self.videoInput markAsFinished];
    [self.assetWriter finishWritingWithCompletionHandler:^{
        NSError *error = nil;
        if (self.assetWriter.status != AVAssetWriterStatusCompleted) {
            error = self.assetWriter.error ?: [NSError errorWithDomain:@"FlutterRTCMediaRecorder"
                                                             code:-1
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to finish writing"}];
            NSLog(@"Failed to finish writing: %@", error.localizedDescription);
            completion(error);
        } else {
            completion(nil);
        }
    }];

}

// iOS AVFoudation框架 处理音视频的 AVAssetWriter 配置和开启写入
- (void)setupAssetWriterWithPixelBuffer:(CVPixelBufferRef)pixelBufferRef withPresentationTime:(CMTime)presentationTime {
    NSLog(@"is First Frame Rendered");
    
    self.outputFileWidth = CVPixelBufferGetWidth(pixelBufferRef);
    self.outputFileHeight = CVPixelBufferGetHeight(pixelBufferRef);
    self.pixelFormat = (int)CVPixelBufferGetPixelFormatType(pixelBufferRef);
    
    NSURL *outputURL = [NSURL fileURLWithPath:self.outputPath];
    
    NSError *error = nil;
    self.assetWriter = [AVAssetWriter assetWriterWithURL:outputURL fileType:AVFileTypeMPEG4 error:&error];
    if (error) {
        NSLog(@"Error on creating AVAssetWriter: %@", error);
        self.isRecording = NO;
    } else {
        NSLog(@"Success to create AVAssetWriter");
        self.isRecording = YES;
    }
    
    NSDictionary *videoSettings = @{
                AVVideoCodecKey: AVVideoCodecTypeH264,
                AVVideoWidthKey: @(self.outputFileWidth),
                AVVideoHeightKey: @(self.outputFileHeight),
                AVVideoCompressionPropertiesKey: @{
                        AVVideoAverageBitRateKey: @(self.outputFileWidth * self.outputFileHeight * 4),// 比特率
                        AVVideoExpectedSourceFrameRateKey: @(30), // 设置帧率为30fps
                        AVVideoMaxKeyFrameIntervalKey: @(5 * 30),// 设置关键帧间隔为5秒 (5 * 30fps)
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                    }
            };
    NSLog(@"videoSetting %@", videoSettings);
    
    self.videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    self.videoInput.expectsMediaDataInRealTime = YES;
    
    NSDictionary *sourcePixelBufferAttributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(self.pixelFormat),
        (id)kCVPixelBufferWidthKey: @(self.outputFileWidth),
        (id)kCVPixelBufferHeightKey: @(self.outputFileHeight)
    };
    
    NSLog(@"sourcePixelBufferAttributes %@", sourcePixelBufferAttributes);
    
    self.pixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.videoInput sourcePixelBufferAttributes:sourcePixelBufferAttributes];
    
    if ([self.assetWriter canAddInput:self.videoInput]) {
        [self.assetWriter addInput:self.videoInput];
        NSLog(@"Success to add video input to AVAssetWriter");
        self.isRecording = YES;
    } else {
        NSLog(@"Unable to add video input to AVAssetWriter");
        self.isRecording = NO;
    }
    
    // 开始写入会话
    if (self.assetWriter.status == AVAssetWriterStatusUnknown) {
        if ([self.assetWriter startWriting]) {
            NSLog(@"Started writing successfully");
            self.isRecording = YES;
        } else {
            NSLog(@"Failed to start writing: %@", self.assetWriter.error);
            self.isRecording = NO;
        }
    } else {
        NSLog(@"AssetWriter not in unknown state");
        self.isRecording = NO;
    }
    [self.assetWriter startSessionAtSourceTime:presentationTime];
}

- (void)appendVideoPixelBuffer:(CVPixelBufferRef)pixelBufferRef withPresentationTime:(CMTime)presentationTime {
    if (self.assetWriter && self.assetWriter.status == AVAssetWriterStatusWriting) {
        if (self.videoInput.readyForMoreMediaData) {
            BOOL success = [self.pixelBufferAdaptor appendPixelBuffer:pixelBufferRef withPresentationTime:presentationTime];
            if (!success) {
                NSLog(@"Failed to append pixel buffer: %@", self.assetWriter.error);
            } else {
                NSLog(@"AssetWriter append sample buffer successfully");
            }
        }
    }
}

// 像素数据处理
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
                       width:i420Buffer.height];
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

// 接受到的视频帧处理
- (void)renderFrame:(nullable RTCVideoFrame *)frame {
    if (!self.isRecording) return;
    
    CMTime presentationTime = CMTimeMake(frame.timeStampNs, NSEC_PER_SEC);
    
    CVPixelBufferRef pixelBufferRef = [self convertToCVPixelBuffer:frame];

    if (self.outputFileWidth == 0 || self.outputFileHeight == 0) {
        [self setupAssetWriterWithPixelBuffer:pixelBufferRef withPresentationTime:presentationTime];
    }
    
    [self appendVideoPixelBuffer:pixelBufferRef withPresentationTime:presentationTime];
}

- (void)setSize:(CGSize)size {
    
}

@end

