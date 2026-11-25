#import "TLLyricsIPC.h"

#import <notify.h>

static NSString * const kTLLyricsAppGroup =
    @"group.com.hailong.TrollLyricsDesk";

static NSString * const kTLLyricsNotification =
    @"com.hailong.TrollLyricsDesk.v05.lyrics.changed";

static NSString * const kTLLyricsRelativePath =
    @"Library/Caches/TrollLyricsDesk/lyrics.json";

static int gTLLyricsNotifyToken = NOTIFY_TOKEN_INVALID;
static void (^gTLLyricsObserver)(NSDictionary<NSString *, id> *) = nil;

@implementation TLLyricsIPC

+ (NSURL *)lyricsFileURLCreatingDirectory:(BOOL)createDirectory {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSURL *containerURL =
        [fileManager containerURLForSecurityApplicationGroupIdentifier:
            kTLLyricsAppGroup];

    if (containerURL == nil) {
        NSLog(@"[TrollLyricsDesk] App Group container unavailable: %@",
              kTLLyricsAppGroup);
        return nil;
    }

    NSURL *fileURL =
        [containerURL URLByAppendingPathComponent:kTLLyricsRelativePath];

    if (createDirectory) {
        NSURL *directoryURL =
            [fileURL URLByDeletingLastPathComponent];

        NSError *directoryError = nil;
        BOOL created =
            [fileManager createDirectoryAtURL:directoryURL
                  withIntermediateDirectories:YES
                                   attributes:nil
                                        error:&directoryError];

        if (!created) {
            NSLog(@"[TrollLyricsDesk] Cannot create lyrics cache: %@",
                  directoryError);
            return nil;
        }
    }

    return fileURL;
}

+ (BOOL)publishLyrics:(NSDictionary<NSString *, id> *)lyrics {
    if (![lyrics isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSError *jsonError = nil;
    NSData *jsonData =
        [NSJSONSerialization dataWithJSONObject:lyrics
                                        options:0
                                          error:&jsonError];

    if (jsonData == nil) {
        NSLog(@"[TrollLyricsDesk] Lyrics JSON serialization failed: %@",
              jsonError);
        return NO;
    }

    NSURL *fileURL = [self lyricsFileURLCreatingDirectory:YES];
    if (fileURL == nil) {
        return NO;
    }

    NSError *writeError = nil;
    BOOL written =
        [jsonData writeToURL:fileURL
                     options:NSDataWritingAtomic
                       error:&writeError];

    if (!written) {
        NSLog(@"[TrollLyricsDesk] Lyrics write failed: %@", writeError);
        return NO;
    }

    uint32_t notifyStatus =
        notify_post([kTLLyricsNotification UTF8String]);

    if (notifyStatus != NOTIFY_STATUS_OK) {
        NSLog(@"[TrollLyricsDesk] notify_post failed: %u", notifyStatus);
        return NO;
    }

    return YES;
}

+ (NSDictionary<NSString *, id> *)readLyrics {
    NSURL *fileURL = [self lyricsFileURLCreatingDirectory:NO];
    if (fileURL == nil) {
        return @{};
    }

    NSData *jsonData = [NSData dataWithContentsOfURL:fileURL];
    if (jsonData == nil) {
        return @{};
    }

    NSError *jsonError = nil;
    id object =
        [NSJSONSerialization JSONObjectWithData:jsonData
                                        options:NSJSONReadingFragmentsAllowed
                                          error:&jsonError];

    if (![object isKindOfClass:[NSDictionary class]]) {
        if (jsonError != nil) {
            NSLog(@"[TrollLyricsDesk] Lyrics JSON read failed: %@", jsonError);
        }
        return @{};
    }

    return (NSDictionary<NSString *, id> *)object;
}

+ (void)observeLyrics:(void (^)(NSDictionary<NSString *, id> *))handler {
    if (handler == nil) {
        return;
    }

    @synchronized(self) {
        gTLLyricsObserver = [handler copy];

        if (gTLLyricsNotifyToken != NOTIFY_TOKEN_INVALID) {
            return;
        }

        int token = NOTIFY_TOKEN_INVALID;
        uint32_t status =
            notify_register_dispatch(
                [kTLLyricsNotification UTF8String],
                &token,
                dispatch_get_main_queue(),
                ^(int callbackToken) {
                    (void)callbackToken;

                    NSDictionary<NSString *, id> *lyrics =
                        [self readLyrics];

                    void (^callback)(NSDictionary<NSString *, id> *) = nil;
                    @synchronized(self) {
                        callback = [gTLLyricsObserver copy];
                    }

                    if (callback != nil) {
                        callback(lyrics);
                    }
                });

        if (status == NOTIFY_STATUS_OK) {
            gTLLyricsNotifyToken = token;
        } else {
            gTLLyricsObserver = nil;
            NSLog(@"[TrollLyricsDesk] notify_register_dispatch failed: %u",
                  status);
        }
    }
}

+ (void)stopObserving {
    int tokenToCancel = NOTIFY_TOKEN_INVALID;

    @synchronized(self) {
        tokenToCancel = gTLLyricsNotifyToken;
        gTLLyricsNotifyToken = NOTIFY_TOKEN_INVALID;
        gTLLyricsObserver = nil;
    }

    if (tokenToCancel != NOTIFY_TOKEN_INVALID) {
        notify_cancel(tokenToCancel);
    }
}

@end
