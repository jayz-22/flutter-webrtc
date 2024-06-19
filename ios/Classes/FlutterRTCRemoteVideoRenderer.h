//
//  FlutterRTCRemoteVideoRenderer.h
//  WebRTC-SDK
//
//  Created by 周培杰 on 2024/6/18.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <WebRTC/WebRTC.h>

@interface FlutterRTCRemoteVideoRenderer : NSObject

- (void)startRecordingToPath:(NSString *)path
                  videoTrack:(RTCVideoTrack *)videoTrack
                  completion:(void (^)(NSError *error))completion;

- (void)stopRecordingWithCompletion:(void (^)(NSError *error))completion;

@end
