#import <UIKit/UIKit.h>

/// 悬浮歌词窗：整窗透明，只有歌词卡片内部（UILabel 区域）接收触摸，
/// 其余区域点击穿透到底层桌面 / App，不影响正常操作。
@interface TLDSPassThroughWindow : UIWindow
@end
