// TLHUDApplication.h — HUD 子进程的 UIApplication 子类 + delegate。
// 原创文件（TL_ 前缀）。机制照公开的上游做法：手工接事件分发器和 fetcher，
// 建全屏系统窗口并注册给 backboardd 托管；代码自己写。
#import <UIKit/UIKit.h>

// HUD 进程的 Application 子类：init 里手工接事件分发器和 fetcher
//（没走 UIApplicationMain，没人替我们接），否则窗口收不到任何触摸。
@interface TLHUDApplication : UIApplication
@end

@interface TLHUDAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
