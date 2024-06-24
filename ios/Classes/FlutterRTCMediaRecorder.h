//
//  FlutterRTCMediaRecorder.h
//  Pods
//
//  Created by 周培杰 on 2024/6/24.
//

#import <WebRTC/WebRTC.h>

@interface FlutterRTCMediaRecorder : NSObject

- (instancetype)initWithOutputPath:(NSString *)outputPath videoTrack:(RTCVideoTrack *)videoTrack;

- (void)startWithCompletion:(void (^)(NSError* error))completion;

- (void)stopWithCompletion:(void (^)(NSError* error))completion;

@end
