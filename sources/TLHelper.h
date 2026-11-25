// TLHelper.h — 主 App 和 HUD 子进程共用的小工具：
// 共享 plist 读写 + Darwin 通知 + HUD 子进程的生命周期。
// 原创文件（TL_ 前缀，自有命名）；机制照公开的上游做法，代码自己写。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLHelper : NSObject

// --- 共享配置（主 App 和 HUD 进程共用 TL_LYRICS_PATH 这一个 plist）---
+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)def;
+ (double)doubleForKey:(NSString *)key defaultValue:(double)def;
+ (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)def;
+ (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)def;
+ (void)setObject:(nullable id)value forKey:(NSString *)key;
+ (void)removeObjectForKey:(NSString *)key;

// --- Darwin 通知 ---
+ (void)postNotification:(const char *)name;
+ (void)observeNotification:(const char *)name block:(dispatch_block_t)block;

// --- HUD 进程生命周期 ---
+ (BOOL)isHUDRunning;        // 跑一次 "<self> -check" 子进程，看退出码
+ (BOOL)isHUDRunningByPid;   // 读 pid 文件 + kill(pid, 0)（-check 内部用）
+ (void)startHUD;            // 以 "-hud" 参数重起自己，独立进程
+ (void)stopHUD;             // 先发 dismiss 通知，再用 "-exit" 兜底
+ (void)writePidFile;        // HUD 进程启动时写自己的 pid
+ (void)killHUDByPid;        // "<self> -exit" 内部用：SIGKILL + 删 pid 文件

@end

NS_ASSUME_NONNULL_END
