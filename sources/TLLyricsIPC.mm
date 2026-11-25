#import "TLLyricsIPC.h"
#import "TLPrivate.h"

@implementation TLLyricsIPC

+ (void)publishLyrics:(NSDictionary *)lyrics {
    if (![lyrics isKindOfClass:NSDictionary.class]) {
        return;
    }

    BOOL saved = [lyrics writeToFile:@(TL_LYRICS_PATH)
                           atomically:YES];

    if (!saved) {
        NSLog(@"[TrollLyricsDesk] Cannot save lyrics");
        return;
    }

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)
            [NSString stringWithUTF8String:TL_NOTIFY_LYRICS],
        NULL,
        NULL,
        YES
    );
}

+ (NSDictionary *)readLyrics {
    NSDictionary *data =
        [NSDictionary dictionaryWithContentsOfFile:
            @(TL_LYRICS_PATH)];

    return [data isKindOfClass:NSDictionary.class]
        ? data
        : @{};
}

// Darwin 通知的 C 回调：CFNotificationCenterAddObserver 的回调参数是
// C 函数指针，不能直接传 block 字面量（编不过，跑起来也可能崩）。
// observer 传进来的是 __bridge_retained 的 block 副本，进程生命周期内
// 一直持有，是故意的（和上游的做法一样）。
static void TL_LyricsNotifyCallback(CFNotificationCenterRef center,
                                    void *observer,
                                    CFStringRef name,
                                    const void *object,
                                    CFDictionaryRef userInfo) {
    void (^handler)(NSDictionary *) =
        (__bridge void (^)(NSDictionary *))observer;
    if (!handler) return;

    NSDictionary *lyrics = [TLLyricsIPC readLyrics];

    dispatch_async(dispatch_get_main_queue(), ^{
        handler(lyrics);
    });
}
+ (void)observeLyrics:(void (^)(NSDictionary *))handler {
    if (!handler) return;

    void (^copied)(NSDictionary *) = [handler copy];

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge_retained void *)copied,
        TL_LyricsNotifyCallback,
        (__bridge CFStringRef)
            [NSString stringWithUTF8String:TL_NOTIFY_LYRICS],
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );
}

@end
