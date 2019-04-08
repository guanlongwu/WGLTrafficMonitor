//
//  WGLTrafficCommon.h
//  WGLTrafficMonitor
//
//  Created by wugl on 2019/4/8.
//  Copyright © 2019 WGLKit. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 网络流量类型:
 
 WWAN: Wireless Wide Area Network.
 For example: 3G/4G.
 
 WIFI: Wi-Fi.
 
 AWDL: Apple Wireless Direct Link (peer-to-peer connection).
 For exmaple: AirDrop, AirPlay, GameKit.
 */
typedef NS_OPTIONS(NSUInteger, WGLNetworkTrafficType) {
    WGLNetworkTrafficTypeWWANSent     = 1 << 0,
    WGLNetworkTrafficTypeWWANReceived = 1 << 1,
    WGLNetworkTrafficTypeWIFISent     = 1 << 2,
    WGLNetworkTrafficTypeWIFIReceived = 1 << 3,
    WGLNetworkTrafficTypeAWDLSent     = 1 << 4,
    WGLNetworkTrafficTypeAWDLReceived = 1 << 5,
    
    WGLNetworkTrafficTypeWWAN = WGLNetworkTrafficTypeWWANSent | WGLNetworkTrafficTypeWWANReceived,
    WGLNetworkTrafficTypeWIFI = WGLNetworkTrafficTypeWIFISent | WGLNetworkTrafficTypeWIFIReceived,
    WGLNetworkTrafficTypeAWDL = WGLNetworkTrafficTypeAWDLSent | WGLNetworkTrafficTypeAWDLReceived,
    
    WGLNetworkTrafficTypeALL = WGLNetworkTrafficTypeWWAN |
    WGLNetworkTrafficTypeWIFI |
    WGLNetworkTrafficTypeAWDL,
};

@interface WGLTrafficCommon : NSObject

@end

NS_ASSUME_NONNULL_END
