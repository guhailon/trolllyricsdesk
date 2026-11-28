// TLDHUDRootViewController.mm
// HUD Test — floating window content + lock handling.
// Lock hide/show adapted from TrollSpeed (MIT © 2023 Lessica),
// sources/TLDHUDRootViewController.mm:
//   - Darwin notification "com.apple.springboard.lockstate" ->
//     SBGetScreenLockStatus() to confirm;
//   - locked: stop the timer, hide the view;
//   - unlocked: unhide the view, restart the timer.
//   - NO rebuild, NO re-register, NO re-sent system settings.
// Additions for this test (new code):
//   - UIApplicationProtectedDataDidBecomeAvailable as a second
//     unlock trigger (TrollLyricsDesk never subscribed to it; its 4s poll
//     could expire — see ARCHITECTURE_ANALYSIS.md §6). NOTE: in the
//     iPhoneOS 26.5 SDK the constant has no "Notification" suffix;
//     the old suffixed name does not compile.
//   - uninstall self-cleanup: if the main app is gone, unload + remove
//     the daemon plist (a TrollStore IPA has no .deb prerm) and exit;
//   - the content is test-only: fixed string + seconds-since-start +
//     lock state, 1s timer, log lines throttled to state changes + 60s.
// (Adapted code, © 2026 顾海龙集团, MIT — see README for attribution.)

#import <notify.h>
#import <spawn.h>
#import <unistd.h>
#import <sys/wait.h>
#import <objc/runtime.h>

#import "TLDHUDRootViewController.h"
#import "TLDHUDLog.h"
#import "TLDHUDPaths.h"
#import "TLDHUDHelper.h"
#import "TLDHUDLyricsSnapshot.h"
#import "SpringBoardServices.h"
#import "UIApplication+Private.h"
#import "LSApplicationWorkspace.h"
#import "LSApplicationProxy.h"

extern char **environ;

@interface TLDHUDRootViewController ()
- (void)updateDisplay;
- (void)hudDidLock;
- (void)hudDidUnlock;
@end

#define NOTIFY_UI_LOCKSTATE "com.apple.springboard.lockstate"
#define NOTIFY_LS_APP_CHANGED "com.apple.LaunchServices.ApplicationsChanged"
#define TLDHUD_MAIN_BUNDLE_ID @"com.ycwl.Lyrics"  // main app bundle id (NOT the daemon label com.ycwl.Lyrics.hud)

static void LaunchServicesApplicationStateChanged(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo)
{
    BOOL isAppInstalled = NO;
    for (LSApplicationProxy *app in [[objc_getClass("LSApplicationWorkspace") defaultWorkspace] allApplications]) {
        if ([app.applicationIdentifier isEqualToString:TLDHUD_MAIN_BUNDLE_ID]) {
            isAppInstalled = YES;
            break;
        }
    }
    if (!isAppInstalled) {
        // The main app was deleted. A TrollStore IPA has no .deb prerm, so
        // the daemon cleans up its own launchd plist, then exits — otherwise
        // launchd KeepAlive would relaunch a daemon whose app is gone.
        TLDHUDLog(@"hud: main app uninstalled, removing daemon plist and exiting");
        NSString *plistPath = TLDHUDDaemonPlistPath();
        NSString *launchctl = TLDHUDLaunchctlPath();
        if (launchctl) {
            char *args[] = { (char *)[launchctl UTF8String], (char *)"unload", (char *)[plistPath UTF8String], NULL };
            pid_t pid = 0;
            posix_spawn(&pid, [launchctl UTF8String], NULL, NULL, args, environ);
            int status = 0;
            waitpid(pid, &status, 0);
        }
        unlink([plistPath UTF8String]);
        [[UIApplication sharedApplication] terminateWithSuccess];
    }
}

static void SpringBoardLockStatusChanged(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo)
{
    TLDHUDRootViewController *rootViewController = (__bridge TLDHUDRootViewController *)observer;
    NSString *lockState = (__bridge NSString *)name;
    if ([lockState isEqualToString:@NOTIFY_UI_LOCKSTATE]) {
        mach_port_t sbsPort = SBSSpringBoardServerPort();
        if (sbsPort == MACH_PORT_NULL) return;
        BOOL isLocked = NO;
        BOOL isPasscodeSet = NO;
        SBGetScreenLockStatus(sbsPort, &isLocked, &isPasscodeSet);
        if (!isLocked) {
            [rootViewController hudDidUnlock];
        } else {
            [rootViewController hudDidLock];
        }
    }
}

@implementation TLDHUDRootViewController {
    UILabel *_testLabel;
    NSTimer *_timer;
    NSDate *_startDate;
    BOOL _isLocked;
    NSInteger _tickCount;
    // 0.2.0 lyric state: last resolved display + song identity, for
    // change-only logging (song change / entering / leaving fallback).
    TLDHUDLyricsDisplay *_lastLyrics;
    NSString *_lastSongIdentity;
    BOOL _inLyricsMode;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _startDate = [NSDate date];
        _isLocked = NO;
        _tickCount = 0;
        [self registerNotifications];
    }
    return self;
}

- (void)registerNotifications
{
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(
        darwinCenter,
        (__bridge const void *)self,
        LaunchServicesApplicationStateChanged,
        CFSTR(NOTIFY_LS_APP_CHANGED),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce);
    CFNotificationCenterAddObserver(
        darwinCenter,
        (__bridge const void *)self,
        SpringBoardLockStatusChanged,
        CFSTR(NOTIFY_UI_LOCKSTATE),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce);
    // Second unlock trigger: data-protection availability fires when the
    // device is unlocked and the keybag is open. TrollLyricsDesk polled
    // isProtectedDataAvailable for ~4s and could miss a slow unlock.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(protectedDataDidBecomeAvailable:)
                                                 name:UIApplicationProtectedDataDidBecomeAvailable
                                               object:nil];
}

- (void)hudDidLock
{
    _isLocked = YES;
    TLDHUDLog(@"hud: locked, view hidden");
    [self stopLoopTimer];
    [self.view setHidden:YES];
}

- (void)hudDidUnlock
{
    _isLocked = NO;
    TLDHUDLog(@"hud: unlocked, view shown");
    [self.view setHidden:NO];
    [self resetLoopTimer];
    [self updateDisplay];
}

- (void)protectedDataDidBecomeAvailable:(NSNotification *)note
{
    if (self.view.hidden) {
        [self hudDidUnlock];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    UIView *pill = [[UIView alloc] init];
    pill.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    pill.layer.cornerRadius = 10;
    pill.layer.masksToBounds = YES;
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:pill];

    _testLabel = [[UILabel alloc] init];
    _testLabel.numberOfLines = 0;
    _testLabel.textAlignment = NSTextAlignmentCenter;
    _testLabel.textColor = [UIColor whiteColor];
    _testLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _testLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [pill addSubview:_testLabel];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [pill.topAnchor constraintEqualToAnchor:guide.topAnchor constant:56],
        [pill.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [_testLabel.topAnchor constraintEqualToAnchor:pill.topAnchor constant:8],
        [_testLabel.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-8],
        [_testLabel.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:14],
        [_testLabel.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-14],
    ]];

    [self updateDisplay];
    [self resetLoopTimer];
}

- (void)updateDisplay
{
    // 0.2.0: read the shared snapshot once per tick (1s is enough — a
    // lyric line lasts seconds). No snapshot / no music -> the old
    // test text, never a blank window.
    BOOL noMusic = NO;
    NSString *reason = nil;
    TLDHUDLyricsDisplay *lyrics =
        [TLDHUDLyricsSnapshot currentDisplayAtDate:[NSDate date]
                                        noMusic:&noMusic
                                         reason:&reason];
    if (!lyrics) {
        if (_inLyricsMode) {
            _inLyricsMode = NO;
            _lastSongIdentity = nil;
            _lastLyrics = nil;
            TLDHUDLog(@"hud: lyrics fallback (%@)", reason ?: @"no snapshot");
        }
        [self showFallbackText];
        return;
    }

    // Song change: one log line, then keep quiet until the next change.
    if (![lyrics.songIdentity isEqualToString:_lastSongIdentity]) {
        _lastSongIdentity = lyrics.songIdentity;
        TLDHUDLog(@"hud: lyrics now %@ — %@ (%lu lines)",
               lyrics.track, lyrics.artist,
               (unsigned long)lyrics.lineCount);
    }
    if (!_inLyricsMode) {
        _inLyricsMode = YES;
    }
    _lastLyrics = lyrics;

    NSMutableAttributedString *text =
        [[NSMutableAttributedString alloc] init];
    NSDictionary *songAttrs = @{
        NSFontAttributeName :
            [UIFont systemFontOfSize:11 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName :
            [[UIColor whiteColor] colorWithAlphaComponent:0.65],
    };
    NSDictionary *dimAttrs = @{
        NSFontAttributeName :
            [UIFont systemFontOfSize:11 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName :
            [[UIColor whiteColor] colorWithAlphaComponent:0.45],
    };
    NSDictionary *currentAttrs = @{
        NSFontAttributeName :
            [UIFont boldSystemFontOfSize:17],
        NSForegroundColorAttributeName : [UIColor whiteColor],
    };
    if (lyrics.songLine.length > 0) {
        [text appendAttributedString:
            [[NSAttributedString alloc] initWithString:lyrics.songLine
                                            attributes:songAttrs]];
        [text appendAttributedString:
            [[NSAttributedString alloc] initWithString:@"\n"
                                            attributes:songAttrs]];
    }
    if (lyrics.previousLine.length > 0) {
        [text appendAttributedString:
            [[NSAttributedString alloc] initWithString:lyrics.previousLine
                                            attributes:dimAttrs]];
        [text appendAttributedString:
            [[NSAttributedString alloc] initWithString:@"\n"
                                            attributes:dimAttrs]];
    }
    [text appendAttributedString:
        [[NSAttributedString alloc] initWithString:lyrics.currentLine ?: @"♪"
                                        attributes:currentAttrs]];
    if (lyrics.nextLine.length > 0) {
        [text appendAttributedString:
            [[NSAttributedString alloc] initWithString:@"\n"
                                            attributes:dimAttrs]];
        [text appendAttributedString:
            [[NSAttributedString alloc] initWithString:lyrics.nextLine
                                            attributes:dimAttrs]];
    }
    _testLabel.attributedText = text;
}

// Fallback text, unchanged from the first release: fixed string +
// seconds-since-start + lock state. Shown when there is no snapshot
// (no music / main app not running / snapshot not yet written), so the
// window is never blank.
- (void)showFallbackText
{
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:_startDate];
    NSString *lockText = _isLocked ? @"LOCKED" : @"UNLOCKED";
    _testLabel.attributedText = [[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"桌面歌詞 2.0.1\nT+%.0fs · %@",
                        elapsed, lockText]
        attributes:@{
            NSFontAttributeName :
                [UIFont monospacedDigitSystemFontOfSize:15
                                                 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName : [UIColor whiteColor],
        }];
}

- (void)onTimerTick
{
    _tickCount++;
    [self updateDisplay];
    // Throttled logging: state changes are logged at the moment they
    // happen; timer ticks at most once every 60s. No log spam.
    if (_tickCount % 60 == 0) {
        NSString *line = _lastLyrics.currentLine ?: @"";
        if (line.length > 24) {
            line = [[line substringToIndex:24]
                stringByAppendingString:@"…"];
        }
        TLDHUDLog(@"hud: tick T+%.0fs (daemon alive)%@",
               [[NSDate date] timeIntervalSinceDate:_startDate],
               line.length > 0 ?
                   [NSString stringWithFormat:@" · %@", line] : @"");
    }
}

- (void)resetLoopTimer
{
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(onTimerTick) userInfo:nil repeats:YES];
}

- (void)stopLoopTimer
{
    [_timer invalidate];
    _timer = nil;
}

@end
