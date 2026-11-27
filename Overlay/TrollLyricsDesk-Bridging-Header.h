//
//  TrollLyricsDesk-Bridging-Header.h
//  Swift / Objective-C 互操作桥接头。
//
//  保留此文件（即使为空）会强制 Xcode 为 App target 生成
//  TrollLyricsDesk-Swift.h，从而让 ObjC 的 AppDelegate / SceneDelegate
//  能 #import 并使用 Swift 类（TLDSRuntime、FloatingLyricViewController）。
//
//  Swift 侧目前不需要调用任何 ObjC 类型，所以这里不 import 任何东西。
//
//  2.0.0：Swift 侧需要调 HUD 守护进程的 ObjC 控制面（设置页的 Enable／
//  Disable／状态／日志），所以这里 import HUD 的三个公开头。daemon 侧的
//  其余 ObjC 类（窗口／快照／delegate）只在 daemon target 里编，不進 App。
#import "TLDHUDHelper.h"
#import "TLDHUDLog.h"
#import "TLDHUDPaths.h"
//
