#import "TLDSPassThroughWindow.h"
#import <objc/runtime.h>

@implementation TLDSPassThroughWindow

// 让窗口所在场景在 App 退到后台后依然存活
- (BOOL)_extendsScreenSceneLifetime {
    return YES;
}

// 允许覆盖系统遮挡检测，配合 FBScene 的 ignoreOcclusionReasons=SystemApp
- (BOOL)_allowsOcclusionDetectionOverride {
    return YES;
}

// 事件分发：只有命中歌词卡片（rootViewController.view 的子视图）时才接收，
// 否则穿透。这样歌词窗不会挡住桌面上的其他操作。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];

    // nil 或命中窗口自身（透明背景区域）→ 穿透
    if (!hit || hit == self) {
        return nil;
    }

    // 命中 rootViewController 的 view（透明容器）→ 穿透；
    // 命中其内部卡片（UILabel / cardView）→ 接收，支持拖动 / 双击。
    UIView *rootView = self.rootViewController.view;
    if (hit == rootView) {
        return nil;
    }
    return hit;
}

@end
