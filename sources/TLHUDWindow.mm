// TLHUDWindow.mm — TLHUDWindow 的实现。原创文件，机制照公开的上游做法。
#import "TLHUDWindow.h"
#import "TLPrivate.h"

@implementation TLHUDWindow

// 脱离默认 Scene 建窗口：挂在 Scene 上的窗口命中测试会被渲染服务端接管，
// 触摸到不了我们这里；脱离 Scene + 自己做命中测试才行。老系统没有这个
// 私有初始化方法时退回普通 initWithFrame:。
- (instancetype)initWithFrame:(CGRect)frame {
    if ([UIWindow instancesRespondToSelector:@selector(_initWithFrame:attached:)]) {
        self = [super _initWithFrame:frame attached:NO];
    } else {
        self = [super initWithFrame:frame];
    }
    if (self) {
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

// 和 AssistiveTouch / TrollSpeed 一样的三个系统窗口标志。
+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }

// 命中测试在进程内做，不交给渲染服务端；否则窗口收不到任何触摸。
- (BOOL)_usesWindowServerHitTesting { return NO; }

// 我们要吃触摸（卡片拖动、关闭按钮），所以不忽略命中测试。
- (BOOL)_ignoresHitTest { return NO; }

// 只让歌词卡片区域吃触摸：命中点落在根视图控制器自身（全屏透明背景）
// 或没命中任何东西时返回 nil，触摸透传给下面的 App；命中卡片或它的
// 子视图（关闭按钮）时正常返回，触摸归我们。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit || hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}

@end
