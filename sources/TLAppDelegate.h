// TLAppDelegate.h — 普通模式（主 App）的 delegate。
// 原创文件（TL_ 前缀）。main.mm 无参数启动时走 UIApplicationMain + 它。
#import <UIKit/UIKit.h>

@interface TLAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
