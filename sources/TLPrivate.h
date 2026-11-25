// TLPrivate.h — TrollLyricsDesk v0.5 悬浮歌词 HUD 的私有声明。
//
// 原创文件（TrollLyricsDesk 自有命名 TL_ 前缀）。声明的都是 iOS 私有 API 的
// 函数签名和接口——功能性机制声明，不是复制上游代码：同样的私有 API、同样的
// 调用顺序，命名和注释都是我们自己的。上游无许可证源码没有逐字复制；
// TrollSpeed（MIT，Lessica）是机制参考，见 BUILD_NOTES.md 的致谢。
#ifndef TROLLLYRICSDESK_TLPRIVATE_H
#define TROLLLYRICSDESK_TLPRIVATE_H

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <spawn.h>

#ifdef __cplusplus
extern "C" {
#endif

// 不走 UIApplicationMain、手工拉起 UIKit 要用的私有入口
//（GraphicsServices / BackBoardServices / UIKitCore）。
void GSInitialize(void);
void GSEventInitialize(Boolean registerPurple);
void GSEventPushRunLoopMode(CFStringRef mode);
void BKSDisplayServicesStart(void);
void UIApplicationInitialize(void);
void UIApplicationInstantiateSingleton(id aClass);

#ifdef __cplusplus
}
#endif

// 指针鉴别（PAC）小工具：TLHUDApplication 里 ARM64 扫描兜底用的。
// arm64e 上方法 IMP 的高位带 PAC 签名——读它指向的指令前要先剥掉，
// 扫描算出来的裸代码地址调之前要先签上，才能当函数指针调。
// 非 arm64e 目标上这两个就是原样返回，不做任何事。
#if defined(__arm64e__)
static inline void *TLStripPAC(void *ptr) {
#if __has_builtin(__builtin_ptrauth_strip)
    return __builtin_ptrauth_strip(ptr, 0);
#else
    return ptr;
#endif
}
static inline void *TLSignForCall(void *ptr) {
#if __has_builtin(__builtin_ptrauth_sign_unauthenticated)
    return __builtin_ptrauth_sign_unauthenticated(ptr, 0, 0);
#else
    return ptr;
#endif
}
#else
static inline void *TLStripPAC(void *ptr) { return ptr; }
static inline void *TLSignForCall(void *ptr) { return ptr; }
#endif

// 手工启动流程 + 事件投递要用的 UIApplication 私有方法。
@interface UIApplication (TLPrivate)
- (void)_accessibilityInit;
- (void)__completeAndRunAsPlugin;
- (void)_run;
@end

// UIKit 事件管线：没走 UIApplicationMain 就没人替我们接，
// 不接上 HUD 窗口收不到任何触摸。
@interface UIEventDispatcher : NSObject
- (void)_installEventRunLoopSources:(CFRunLoopRef)runLoop;
@end

@interface UIEventFetcher : NSObject
- (void)setEventFetcherSink:(id)sink;
@end

// 私有 UIWindow 方法：交给 backboardd 的渲染上下文 id，
// 以及脱离默认 Scene 建窗口的私有初始化方法。
@interface UIWindow (TLPrivate)
- (unsigned)_contextId;
- (instancetype)_initWithFrame:(CGRect)frame attached:(BOOL)attached;
@end

// 把窗口注册给 backboardd、让它浮在所有 App 之上的控制器。
// 运行时用 objc_getClass 取，不直接链接。
@interface SBSAccessibilityWindowHostingController : NSObject
- (void)registerWindowWithContextID:(unsigned)contextID atLevel:(double)level;
@end

// 主 App 和 HUD 子进程之间的 Darwin 通知名 + 共享文件路径。
// 上游用的是它自己的名字；这里一律用我们自己的 v05 命名空间，
// 绝不复用上游的配置文件名和通知名。
#define TL_NOTIFY_LYRICS \
    "com.trolllyricsdesk.v05/lyrics"
#define TL_NOTIFY_DISMISS \
    "com.trolllyricsdesk.v05/dismiss"

// 歌词共享 plist：主 App 写四行词，HUD 进程读。
#define TL_LYRICS_PATH \
    "/var/mobile/Library/Preferences/com.trolllyricsdesk.v05.plist"

// HUD 子进程的 pid 文件：主 App 靠它判断 HUD 在不在跑、杀掉它。
#define TL_PID_PATH \
    "/var/mobile/Library/Caches/com.trolllyricsdesk.v05.pid"

#endif /* TROLLLYRICSDESK_TLPRIVATE_H */
