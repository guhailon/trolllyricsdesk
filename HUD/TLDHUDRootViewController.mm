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
- (NSUserDefaults *)pillDefaults;
- (BOOL)readPositionLocked;
- (UIColor *)pillLyricColor;
- (CGFloat)pillCardAlpha;
- (CGPoint)clampedPillCenterForCenter:(CGPoint)center;
- (void)applySavedPillPositionIfNeeded;
- (void)savePillPosition;
- (void)handlePillLongPress:(UILongPressGestureRecognizer *)recognizer;
@end

#define NOTIFY_UI_LOCKSTATE "com.apple.springboard.lockstate"
#define NOTIFY_LS_APP_CHANGED "com.apple.LaunchServices.ApplicationsChanged"
#define TLDHUD_MAIN_BUNDLE_ID @"com.ycwl.Lyrics"  // main app bundle id (NOT the daemon label com.ycwl.Lyrics.hud)

// 2.0.2: pill position / lock / appearance keys in the shared App Group.
// New keys — never reuse the dead FrontBoard keys (floatingLyric.enabled /
// floatingLyric.positionLocked / floatingLyric.textColorHex is the ONE
// reused key: the colour picker, whose storage survived build 30).
// cardOpacity is also reused (the Settings slider kept writing it;
// the daemon just never read it — the 2.0.2 opacity bug).
#define TLDHUD_PILL_GROUP_ID @"group.com.hailong.TrollLyricsDesk"
#define TLDHUD_PILL_POSITION_X_KEY @"hudPill.positionX"
#define TLDHUD_PILL_POSITION_Y_KEY @"hudPill.positionY"
#define TLDHUD_PILL_POSITION_LOCKED_KEY @"hudPill.positionLocked"
#define TLDHUD_PILL_CARD_OPACITY_KEY @"floatingLyric.cardOpacity"
#define TLDHUD_PILL_TEXT_COLOR_KEY @"floatingLyric.textColorHex"
// Card background alpha when the key was never written: 0.75, the look
// Lee already sees. NOT the slider's 0.23 initial value.
#define TLDHUD_PILL_DEFAULT_CARD_ALPHA 0.75

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
    // 2.0.2: pill drag — the pill is an ivar now (was a viewDidLoad local)
    // and is positioned by two adjustable constraints (top + centerX), so
    // Auto Layout still sizes it from the label and no frame math fights
    // the layout engine. _dragging also freezes nothing else: the 1s tick
    // keeps updating the text, the pill just keeps its centre.
    UIView *_pill;
    NSLayoutConstraint *_pillTopConstraint;
    NSLayoutConstraint *_pillCenterXConstraint;
    BOOL _dragging;
    CGPoint _dragTouchOffset;  // touch point minus pill centre, view coords
    BOOL _positionRestored;    // saved centre applied once, after 1st layout
    BOOL _positionLocked;      // re-read from the suite every timer tick
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
    _positionLocked = [self readPositionLocked];
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

    // 2.0.2: the pill is an ivar positioned by two adjustable constraints
    // (top + centerX). Its size still comes from the label via Auto Layout;
    // dragging only moves the two constants, so nothing fights the engine.
    _pill = [[UIView alloc] init];
    _pill.backgroundColor = [[UIColor blackColor]
        colorWithAlphaComponent:TLDHUD_PILL_DEFAULT_CARD_ALPHA];
    _pill.layer.cornerRadius = 10;
    _pill.layer.masksToBounds = YES;
    _pill.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_pill];

    // Long-press drag only — no tap / double-tap gestures are added.
    // allowableMovement is deliberately huge: the finger may already be
    // moving when the 0.5s press fires, and the default 10pt would kill
    // the gesture before Began. Once Began fires, movement is unlimited.
    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(handlePillLongPress:)];
    longPress.minimumPressDuration = 0.5;
    longPress.allowableMovement = 10000;
    [_pill addGestureRecognizer:longPress];

    _testLabel = [[UILabel alloc] init];
    _testLabel.numberOfLines = 0;
    _testLabel.textAlignment = NSTextAlignmentCenter;
    _testLabel.textColor = [UIColor whiteColor];
    _testLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _testLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_pill addSubview:_testLabel];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    _pillTopConstraint =
        [_pill.topAnchor constraintEqualToAnchor:guide.topAnchor constant:56];
    _pillCenterXConstraint =
        [_pill.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor];
    [NSLayoutConstraint activateConstraints:@[
        _pillTopConstraint,
        _pillCenterXConstraint,
        [_testLabel.topAnchor constraintEqualToAnchor:_pill.topAnchor constant:8],
        [_testLabel.bottomAnchor constraintEqualToAnchor:_pill.bottomAnchor constant:-8],
        [_testLabel.leadingAnchor constraintEqualToAnchor:_pill.leadingAnchor constant:14],
        [_testLabel.trailingAnchor constraintEqualToAnchor:_pill.trailingAnchor constant:-14],
    ]];

    _positionLocked = [self readPositionLocked];
    [self updateDisplay];
    [self resetLoopTimer];
}

// The saved centre can only be applied once the pill has a real size
// (its height comes from the label), so the first layout pass does it.
- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self applySavedPillPositionIfNeeded];
}

- (CGRect)pillFrameInWindow
{
    if (!_pill) return CGRectZero;
    return [self.view convertRect:_pill.frame toView:nil];
}

- (NSUserDefaults *)pillDefaults
{
    return [[NSUserDefaults alloc] initWithSuiteName:TLDHUD_PILL_GROUP_ID];
}

- (BOOL)readPositionLocked
{
    return [[self pillDefaults] boolForKey:TLDHUD_PILL_POSITION_LOCKED_KEY];
}

// Lyric text colour, from the main app's colour picker
// (floatingLyric.textColorHex, 0xRRGGBB). Key absent = white, as before.
- (UIColor *)pillLyricColor
{
    NSUserDefaults *defaults = [self pillDefaults];
    if (!defaults || ![defaults objectForKey:TLDHUD_PILL_TEXT_COLOR_KEY]) {
        return [UIColor whiteColor];
    }
    NSInteger hex = [defaults integerForKey:TLDHUD_PILL_TEXT_COLOR_KEY];
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:1.0];
}

// Pill background alpha, from the Settings slider
// (floatingLyric.cardOpacity). Key absent = 0.75, the look Lee already
// sees — NOT the slider's 0.23 initial value.
- (CGFloat)pillCardAlpha
{
    NSUserDefaults *defaults = [self pillDefaults];
    if (!defaults || ![defaults objectForKey:TLDHUD_PILL_CARD_OPACITY_KEY]) {
        return TLDHUD_PILL_DEFAULT_CARD_ALPHA;
    }
    CGFloat alpha = (CGFloat)[defaults doubleForKey:TLDHUD_PILL_CARD_OPACITY_KEY];
    if (alpha < 0) alpha = 0;
    if (alpha > 1) alpha = 1;
    return alpha;
}

// Clamp a desired pill centre so no edge of the pill leaves the screen.
- (CGPoint)clampedPillCenterForCenter:(CGPoint)center
{
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    CGSize pillSize = _pill.bounds.size;
    CGFloat halfW = pillSize.width / 2;
    CGFloat halfH = pillSize.height / 2;
    CGFloat x = center.x;
    CGFloat y = center.y;
    if (x < halfW) x = halfW;
    if (x > screenBounds.size.width - halfW) x = screenBounds.size.width - halfW;
    if (y < halfH) y = halfH;
    if (y > screenBounds.size.height - halfH) y = screenBounds.size.height - halfH;
    return CGPointMake(x, y);
}

// Move the pill so its centre lands on `center` (clamped), by rewriting
// the two stored constraint constants.
- (void)movePillToCenter:(CGPoint)center
{
    CGPoint clamped = [self clampedPillCenterForCenter:center];
    CGFloat safeTop = self.view.safeAreaInsets.top;
    _pillCenterXConstraint.constant =
        clamped.x - self.view.bounds.size.width / 2;
    _pillTopConstraint.constant =
        clamped.y - _pill.bounds.size.height / 2 - safeTop;
}

- (void)applySavedPillPositionIfNeeded
{
    if (_positionRestored || !_pill) return;
    _positionRestored = YES;
    NSUserDefaults *defaults = [self pillDefaults];
    if (!defaults) return;
    if (![defaults objectForKey:TLDHUD_PILL_POSITION_X_KEY] ||
        ![defaults objectForKey:TLDHUD_PILL_POSITION_Y_KEY]) {
        return;  // never dragged: keep the default top-centre spot
    }
    CGPoint saved = CGPointMake(
        [defaults doubleForKey:TLDHUD_PILL_POSITION_X_KEY],
        [defaults doubleForKey:TLDHUD_PILL_POSITION_Y_KEY]);
    [self movePillToCenter:saved];
    [self.view layoutIfNeeded];
}

- (void)savePillPosition
{
    if (!_pill) return;
    CGPoint center = CGPointMake(
        self.view.bounds.size.width / 2 + _pillCenterXConstraint.constant,
        self.view.safeAreaInsets.top + _pillTopConstraint.constant
            + _pill.bounds.size.height / 2);
    NSUserDefaults *defaults = [self pillDefaults];
    if (!defaults) return;
    [defaults setDouble:center.x forKey:TLDHUD_PILL_POSITION_X_KEY];
    [defaults setDouble:center.y forKey:TLDHUD_PILL_POSITION_Y_KEY];
    [defaults synchronize];
}

// Long-press drag. Locked = return immediately, no feedback, pill stays.
// Began: remember the grab offset, dim the pill. Changed: follow the
// finger (clamped on-screen). Ended/Cancelled: restore looks, persist.
- (void)handlePillLongPress:(UILongPressGestureRecognizer *)recognizer
{
    if (_positionLocked) return;
    CGPoint location = [recognizer locationInView:self.view];
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan: {
            _dragging = YES;
            CGPoint pillCenter = CGPointMake(
                self.view.bounds.size.width / 2 + _pillCenterXConstraint.constant,
                self.view.safeAreaInsets.top + _pillTopConstraint.constant
                    + _pill.bounds.size.height / 2);
            _dragTouchOffset = CGPointMake(location.x - pillCenter.x,
                                           location.y - pillCenter.y);
            _pill.alpha = 0.6;
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (!_dragging) return;
            CGPoint target = CGPointMake(location.x - _dragTouchOffset.x,
                                         location.y - _dragTouchOffset.y);
            [self movePillToCenter:target];
            [self.view layoutIfNeeded];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            if (!_dragging) return;
            _dragging = NO;
            _pill.alpha = 1.0;
            [self savePillPosition];
            break;
        }
        default:
            break;
    }
}

- (void)updateDisplay
{
    // 0.2.0: read the shared snapshot once per tick (1s is enough — a
    // lyric line lasts seconds). No snapshot / no music -> the old
    // test text, never a blank window.
    // 2.0.2: the pill background follows the Settings slider every tick,
    // snapshot or not — the pill is always visible, so its alpha is too.
    if (_pill) {
        _pill.backgroundColor = [[UIColor blackColor]
            colorWithAlphaComponent:[self pillCardAlpha]];
    }
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

    // 2.0.2: lyric colour comes from the main app's picker (white when the
    // key was never written); sizes come from the snapshot fontSize
    // (default 23): the current line IS fontSize, the other three lines
    // scale by the old 11/17 ratio. The snapshot opacity rides on the
    // label's own alpha, so the final alpha is tier x opacity, never
    // overwritten by either side.
    UIColor *baseColor = [self pillLyricColor];
    CGFloat baseSize = lyrics.fontSize;
    CGFloat smallSize = baseSize * 11.0 / 17.0;
    NSMutableAttributedString *text =
        [[NSMutableAttributedString alloc] init];
    NSDictionary *songAttrs = @{
        NSFontAttributeName :
            [UIFont systemFontOfSize:smallSize weight:UIFontWeightRegular],
        NSForegroundColorAttributeName :
            [baseColor colorWithAlphaComponent:0.65],
    };
    NSDictionary *dimAttrs = @{
        NSFontAttributeName :
            [UIFont systemFontOfSize:smallSize weight:UIFontWeightRegular],
        NSForegroundColorAttributeName :
            [baseColor colorWithAlphaComponent:0.45],
    };
    NSDictionary *currentAttrs = @{
        NSFontAttributeName :
            [UIFont boldSystemFontOfSize:baseSize],
        NSForegroundColorAttributeName : baseColor,
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
    _testLabel.alpha = lyrics.opacity;
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
    // 2.0.2: fallback text keeps its 15pt monospaced size (the fontSize
    // slider only scales real lyrics), but follows the picker colour;
    // no snapshot means no lyric opacity, so label alpha is 1.0.
    _testLabel.alpha = 1.0;
    _testLabel.attributedText = [[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"桌面歌詞 2.0.2\nT+%.0fs · %@",
                        elapsed, lockText]
        attributes:@{
            NSFontAttributeName :
                [UIFont monospacedDigitSystemFontOfSize:15
                                                 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName : [self pillLyricColor],
        }];
}

- (void)onTimerTick
{
    _tickCount++;
    // 2.0.2: re-read the lock flag every tick — cheap, and no unlock
    // event is needed for the main app's toggle to take effect.
    _positionLocked = [self readPositionLocked];
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
