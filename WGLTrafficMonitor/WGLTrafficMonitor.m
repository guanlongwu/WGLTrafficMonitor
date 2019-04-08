//
//  WGLTrafficMonitor.m
//  WGLTrafficMonitor
//
//  Created by wugl on 2019/4/8.
//  Copyright © 2019 WGLKit. All rights reserved.
//

#import "WGLTrafficMonitor.h"
#include <net/if.h>
#include <net/if_dl.h>
#include <arpa/inet.h>
#include <ifaddrs.h>

typedef struct {
    uint64_t en_in;
    uint64_t en_out;
    uint64_t pdp_ip_in;
    uint64_t pdp_ip_out;
    uint64_t awdl_in;
    uint64_t awdl_out;
} wgl_net_interface_counter;

static uint64_t wgl_net_counter_add(uint64_t counter, uint64_t bytes) {
    if (bytes < (counter % 0xFFFFFFFF)) {
        counter += 0xFFFFFFFF - (counter % 0xFFFFFFFF);
        counter += bytes;
    } else {
        counter = bytes;
    }
    return counter;
}

static uint64_t wgl_net_counter_get_by_type(wgl_net_interface_counter *counter, WGLNetworkTrafficType type) {
    uint64_t bytes = 0;
    if (type & WGLNetworkTrafficTypeWWANSent) {
        bytes += counter->pdp_ip_out;
    }
    if (type & WGLNetworkTrafficTypeWWANReceived) {
        bytes += counter->pdp_ip_in;
    }
    if (type & WGLNetworkTrafficTypeWIFISent) {
        bytes += counter->en_out;
    }
    if (type & WGLNetworkTrafficTypeWIFIReceived) {
        bytes += counter->en_in;
    }
    if (type & WGLNetworkTrafficTypeAWDLSent) {
        bytes += counter->awdl_out;
    }
    if (type & WGLNetworkTrafficTypeAWDLReceived) {
        bytes += counter->awdl_in;
    }
    return bytes;
}

static wgl_net_interface_counter wgl_get_net_interface_counter() {
    static dispatch_semaphore_t lock;
    static NSMutableDictionary *sharedInCounters;
    static NSMutableDictionary *sharedOutCounters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInCounters = [NSMutableDictionary new];
        sharedOutCounters = [NSMutableDictionary new];
        lock = dispatch_semaphore_create(1);
    });
    
    wgl_net_interface_counter counter = {0};
    struct ifaddrs *addrs;
    const struct ifaddrs *cursor;
    if (getifaddrs(&addrs) == 0) {
        cursor = addrs;
        dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
        while (cursor) {
            if (cursor->ifa_addr->sa_family == AF_LINK) {
                const struct if_data *data = cursor->ifa_data;
                NSString *name = cursor->ifa_name ? [NSString stringWithUTF8String:cursor->ifa_name] : nil;
                if (name) {
                    uint64_t counter_in = ((NSNumber *)sharedInCounters[name]).unsignedLongLongValue;
                    counter_in = wgl_net_counter_add(counter_in, data->ifi_ibytes);
                    sharedInCounters[name] = @(counter_in);
                    
                    uint64_t counter_out = ((NSNumber *)sharedOutCounters[name]).unsignedLongLongValue;
                    counter_out = wgl_net_counter_add(counter_out, data->ifi_obytes);
                    sharedOutCounters[name] = @(counter_out);
                    
                    if ([name hasPrefix:@"en"]) {
                        counter.en_in += counter_in;
                        counter.en_out += counter_out;
                    } else if ([name hasPrefix:@"awdl"]) {
                        counter.awdl_in += counter_in;
                        counter.awdl_out += counter_out;
                    } else if ([name hasPrefix:@"pdp_ip"]) {
                        counter.pdp_ip_in += counter_in;
                        counter.pdp_ip_out += counter_out;
                    }
                }
            }
            cursor = cursor->ifa_next;
        }
        dispatch_semaphore_signal(lock);
        freeifaddrs(addrs);
    }
    
    return counter;
}


@interface WGLTrafficMonitor ()

@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL isMonitoring;
@property (nonatomic, assign) uint64_t wwanTrafficForLastSecond, wifiTrafficForLastSecond, awdlTrafficForLastSecond, allTrafficForLastSecond, wwanTrafficSendForLastSecond, wwanTrafficReceivedForLastSecond, wifiTrafficSendForLastSecond, wifiTrafficReceivedForLastSecond, awdlTrafficSendForLastSecond, awdlTrafficReceivedForLastSecond;    //1秒之前的流量总字节数bytes
@property (nonatomic, assign) uint64_t wwanTrafficForCurrent, wifiTrafficForCurrent, awdlTrafficForCurrent, allTrafficForCurrent, wwanTrafficSendForCurrent, wwanTrafficReceivedForCurrent, wifiTrafficSendForCurrent, wifiTrafficReceivedForCurrent, awdlTrafficSendForCurrent, awdlTrafficReceivedForCurrent;    //此刻的流量总字节数bytes
@property (nonatomic, assign) uint64_t wwanTrafficBytesPerSecond, wifiTrafficBytesPerSecond, awdlTrafficBytesPerSecond, allTrafficBytesPerSecond, wwanTrafficSendBytesPerSecond, wwanTrafficReceivedBytesPerSecond, wifiTrafficSendBytesPerSecond, wifiTrafficReceivedBytesPerSecond, awdlTrafficSendBytesPerSecond, awdlTrafficReceivedBytesPerSecond;    //流量速度bytes per second

@end

@implementation WGLTrafficMonitor

+ (instancetype)sharedMonitor {
    static WGLTrafficMonitor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[[self class] alloc] init];
    });
    return instance;
}

- (void)startMonitoring {
    self.isMonitoring = YES;
    [self reCaculateTraffic];
    [self addTimer];
}

- (void)stopMonitoring {
    self.isMonitoring = NO;
    [self removeTimer];
}

#pragma mark - 网速

- (uint64_t)getNetworkTrafficSpeed:(WGLNetworkTrafficType)types {
    uint64_t speed = 0;     //单位kb/s
    switch (types) {
        case WGLNetworkTrafficTypeWWANSent: {
            speed = self.wwanTrafficSendBytesPerSecond / 1024;
        }
            break;
        case WGLNetworkTrafficTypeWWANReceived: {
            speed = self.wwanTrafficReceivedBytesPerSecond / 1024;
        }
            break;
        case WGLNetworkTrafficTypeWIFISent: {
            speed = self.wifiTrafficSendBytesPerSecond / 1024;
        }
            break;
        case WGLNetworkTrafficTypeWIFIReceived: {
            speed = self.wifiTrafficReceivedBytesPerSecond / 1024;
        }
            break;
        case WGLNetworkTrafficTypeAWDLSent: {
            speed = self.awdlTrafficSendBytesPerSecond / 1024;
        }
            break;
        case WGLNetworkTrafficTypeAWDLReceived: {
            speed = self.awdlTrafficReceivedBytesPerSecond / 1024;
        }
            break;
        case WGLNetworkTrafficTypeWWAN: {
            speed = self.wwanTrafficBytesPerSecond / 1024;
        }
            break;
        case WGLNetworkTrafficTypeWIFI: {
            speed = self.wifiTrafficBytesPerSecond / 1024;
        }
            break;
        case WGLNetworkTrafficTypeAWDL: {
            speed = self.awdlTrafficBytesPerSecond / 1024;
        }
            break;
        case WGLNetworkTrafficTypeALL: {
            speed = self.allTrafficBytesPerSecond / 1024;
        }
            break;
        default:
            break;
    }
    return speed;
}

#pragma mark - 流量数bytes

- (uint64_t)getNetworkTrafficBytes:(WGLNetworkTrafficType)types {
    wgl_net_interface_counter counter = wgl_get_net_interface_counter();
    return wgl_net_counter_get_by_type(&counter, types);
}

#pragma mark - private

//重新计算流量字节数bytes
- (void)reCaculateTraffic {
    //WWAN
    //上下行总流量
    self.wwanTrafficForLastSecond
    = self.wwanTrafficForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWWAN];
    //上行流量send
    self.wwanTrafficSendForLastSecond
    = self.wwanTrafficSendForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWWANSent];
    //下行流量received
    self.wwanTrafficReceivedForLastSecond
    = self.wwanTrafficReceivedForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWWANReceived];
    
    //WIFI
    //上下行总流量
    self.wifiTrafficForLastSecond
    = self.wifiTrafficForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWIFI];
    //上行流量send
    self.wifiTrafficSendForLastSecond
    = self.wifiTrafficSendForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWIFISent];
    //下行流量received
    self.wifiTrafficReceivedForLastSecond
    = self.wifiTrafficReceivedForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWIFIReceived];
    
    //AWDL
    //上下行总流量
    self.awdlTrafficForLastSecond
    = self.awdlTrafficForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeAWDL];
    //上行流量send
    self.awdlTrafficSendForLastSecond
    = self.awdlTrafficSendForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeAWDLSent];
    //下行流量received
    self.awdlTrafficReceivedForLastSecond
    = self.awdlTrafficReceivedForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeAWDLReceived];
    
    //ALL上下行总流量
    self.allTrafficForLastSecond
    = self.allTrafficForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeALL];
    
    
    //流量速度 = 当前流量 - 上一秒流量
    self.wwanTrafficBytesPerSecond = 0;
    self.wwanTrafficSendBytesPerSecond = 0;
    self.wwanTrafficReceivedBytesPerSecond = 0;
    
    self.wifiTrafficBytesPerSecond = 0;
    self.wifiTrafficSendBytesPerSecond = 0;
    self.wifiTrafficReceivedBytesPerSecond = 0;
    
    self.awdlTrafficBytesPerSecond = 0;
    self.awdlTrafficSendBytesPerSecond = 0;
    self.awdlTrafficReceivedBytesPerSecond = 0;
    
    self.allTrafficBytesPerSecond = 0;
    
}

//1秒定时计算一次流量
- (void)caculateTrafficPerSecond {
    //当前流量
    self.wwanTrafficForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWWAN];
    self.wwanTrafficSendForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWWANSent];
    self.wwanTrafficReceivedForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWWANReceived];
    
    self.wifiTrafficForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWIFI];
    self.wifiTrafficSendForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWIFISent];
    self.wifiTrafficReceivedForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeWIFIReceived];
    
    self.awdlTrafficForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeAWDL];
    self.awdlTrafficSendForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeAWDLSent];
    self.awdlTrafficReceivedForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeAWDLReceived];
    
    self.allTrafficForCurrent
    = [self getNetworkTrafficBytes:WGLNetworkTrafficTypeALL];
    
    //流量速度 = 当前流量 - 上一秒流量
    self.wwanTrafficBytesPerSecond
    = self.wwanTrafficForCurrent - self.wwanTrafficForLastSecond;
    self.wwanTrafficSendBytesPerSecond
    = self.wwanTrafficSendForCurrent - self.wwanTrafficSendForLastSecond;
    self.wwanTrafficReceivedBytesPerSecond
    = self.wwanTrafficReceivedForCurrent - self.wwanTrafficReceivedForLastSecond;
    
    self.wifiTrafficBytesPerSecond
    = self.wifiTrafficForCurrent - self.wifiTrafficForLastSecond;
    self.wifiTrafficSendBytesPerSecond
    = self.wifiTrafficSendForCurrent - self.wifiTrafficSendForLastSecond;
    self.wifiTrafficReceivedBytesPerSecond
    = self.wifiTrafficReceivedForCurrent - self.wifiTrafficReceivedForLastSecond;
    
    self.awdlTrafficBytesPerSecond
    = self.awdlTrafficForCurrent - self.awdlTrafficForLastSecond;
    self.awdlTrafficSendBytesPerSecond
    = self.awdlTrafficSendForCurrent - self.awdlTrafficSendForLastSecond;
    self.awdlTrafficReceivedBytesPerSecond
    = self.awdlTrafficReceivedForCurrent - self.awdlTrafficReceivedForLastSecond;
    
    self.allTrafficBytesPerSecond =
    self.allTrafficForCurrent - self.allTrafficForLastSecond;
    
    //记录流量
    self.wwanTrafficForLastSecond = self.wwanTrafficForCurrent;
    self.wwanTrafficSendForLastSecond = self.wwanTrafficSendForCurrent;
    self.wwanTrafficReceivedForLastSecond = self.wwanTrafficSendForCurrent;
    
    self.wifiTrafficForLastSecond = self.wifiTrafficForCurrent;
    self.wifiTrafficSendForLastSecond = self.wifiTrafficSendForCurrent;
    self.wifiTrafficReceivedForLastSecond = self.wifiTrafficReceivedForCurrent;
    
    self.awdlTrafficForLastSecond = self.awdlTrafficForCurrent;
    self.awdlTrafficSendForLastSecond = self.awdlTrafficSendForCurrent;
    self.awdlTrafficReceivedForLastSecond = self.awdlTrafficReceivedForCurrent;
    
    self.allTrafficForLastSecond = self.allTrafficForCurrent;
    
    //通知流量有变动
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:WGLNetworkTrafficSpeedDidChangeNotification object:nil];
    });
    
}

#pragma mark - 定时器

//开启定时器
- (void)addTimer {
    if ([self.timer isValid]) {
        return;
    }
    [self removeTimer];
    
    self.timer =
    [NSTimer scheduledTimerWithTimeInterval:1
                                     target:self
                                   selector:@selector(caculateTrafficPerSecond)
                                   userInfo:nil
                                    repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

//停止定时器
- (void)removeTimer {
    if (self.timer == nil) {
        return;
    }
    if ([self.timer isValid]) {
        [self.timer invalidate];
    }
    self.timer = nil;
}

@end
