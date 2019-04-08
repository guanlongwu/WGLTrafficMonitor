//
//  WGLTrafficMonitor.h
//  WGLTrafficMonitor
//
//  Created by wugl on 2019/4/8.
//  Copyright © 2019 WGLKit. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WGLTrafficCommon.h"

NS_ASSUME_NONNULL_BEGIN

@interface WGLTrafficMonitor : NSObject

/**
 是否在监控中状态
 */
@property (nonatomic, assign, readonly) BOOL isMonitoring;

//流量状态监控
+ (instancetype)sharedMonitor;

/**
 从此刻开始监控
 */
- (void)startMonitoring;

/**
 从此刻结束监控
 */
- (void)stopMonitoring;

/**
 网速 (单位：KB/s)
 @param types traffic types
 @return speed for traffic.
 */
- (uint64_t)getNetworkTrafficSpeed:(WGLNetworkTrafficType)types;

/**
 获取设备的网络流量字节数bytes.
 @discussion 获取的是设备上一次开机开始的总网络流量字节数bytes.
 @param types traffic types
 @return bytes counter.
 */
- (uint64_t)getNetworkTrafficBytes:(WGLNetworkTrafficType)types;


/**
 Usage:
 
 uint64_t bytes = [WGLNetworkTrafficHelper getNetworkTrafficBytes:WGLNetworkTrafficTypeALL];
 NSTimeInterval time = CACurrentMediaTime();
 
 uint64_t bytesPerSecond = (bytes - _lastBytes) / (time - _lastTime);
 
 _lastBytes = bytes;
 _lastTime = time;
 */

@end

NS_ASSUME_NONNULL_END

