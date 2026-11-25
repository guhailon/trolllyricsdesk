// TLHUDWindow.h — 悬浮歌词的全屏系统窗口。
// 原创文件（TL_ 前缀）。机制照公开的上游做法：脱离默认 Scene 建窗口，
// 三个系统窗口标志，backboardd 托管后浮在所有 App 之上；代码自己写。
#import <UIKit/UIKit.h>

// 全屏、透明的系统窗口。歌词卡片那块区域吃触摸（拖动、点关闭），
// 其余区域一律透传给下面的 App——窗口再大也不会挡住别的 App 操作。
@interface TLHUDWindow : UIWindow
@end
