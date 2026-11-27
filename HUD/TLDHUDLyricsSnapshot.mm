// TLDHUDLyricsSnapshot.mm
// HUD Test 0.2.0 — read-only lyric snapshot reader (see .h).
// Ports, verbatim where noted, from the main project:
//   Lyrics/LyricStore.swift (branch v1.0.6-lc, HEAD c5c2c27)
//   Overlay/FloatingLyricViewController.swift refresh() (fallback order)
// (New code, © 2026 顾海龙集团, MIT.)

#import "TLDHUDLyricsSnapshot.h"
#import "TLDHUDVersion.h"

@implementation TLDHUDLyricsDisplay
@end

// ---------------------------------------------------------------------------
// Snapshot field names — LyricStore.swift L21-L24, L62, L75.
// ---------------------------------------------------------------------------
static NSString * const kGroupID = @"group.com.hailong.TrollLyricsDesk";
static NSString * const kSnapshotKey = @"lyric.snapshot";
static NSString * const kNoMusicKey = @"lyric.noMusic";
static NSString * const kOffsetKeyPrefix = @"lyric.timeOffset|";
// 2.0.0: forced test text (LyricStore.testTextKey / testText()).
// In 1.0.6 this switch fed the FrontBoard window; the daemon reads it now
// so the Settings toggle still means something after the FrontBoard removal.
static NSString * const kTestTextKey = @"floatingLyric.testTextEnabled";

// Separator table — LyricStore.songIdentityParts L218-L236, one character
// different and the whole port is wrong. Order matters: the first separator
// with non-empty head and tail wins, exactly as in Swift.
static NSArray<NSString *> *TLDHUDSnapshotSeparators(void)
{
    static NSArray<NSString *> *seps = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        seps = @[@" — ", @" – ", @" - ", @" · ", @"—", @"–"];
    });
    return seps;
}

static NSString *TLDHUDTrim(NSString *s)
{
    return [s stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// songIdentityParts (LyricStore.swift L218-L236): split text on the first
// separator that leaves a non-empty head and tail; nil otherwise.
static BOOL TLDHUDSongIdentityParts(NSString *text, NSString **outHead, NSString **outTail)
{
    for (NSString *sep in TLDHUDSnapshotSeparators()) {
        NSRange range = [text rangeOfString:sep];
        if (range.location == NSNotFound) continue;
        NSString *head = TLDHUDTrim([text substringToIndex:range.location]);
        NSString *tail = TLDHUDTrim([text substringFromIndex:NSMaxRange(range)]);
        if (head.length > 0 && tail.length > 0) {
            if (outHead) *outHead = head;
            if (outTail) *outTail = tail;
            return YES;
        }
    }
    return NO;
}

// stableSongIdentity (LyricStore.swift L296-L300): the field carrying a
// separator is the fixed per-song identity; otherwise fall back to title.
static NSString *TLDHUDStableSongIdentity(NSString *title, NSString *artist)
{
    if (TLDHUDSongIdentityParts(title, NULL, NULL)) return title;
    if (TLDHUDSongIdentityParts(artist, NULL, NULL)) return artist;
    return title;
}

// searchTerms (LyricStore.swift L311-L328): only split on " · " — head is
// the real track, tail the real artist. " — " order is ambiguous (both
// orders seen in the wild), so it is never guessed here.
static void TLDHUDSearchTerms(NSString *title, NSString *artist,
                           NSString **outTrack, NSString **outArtist)
{
    for (NSString *field in @[artist, title]) {
        NSRange range = [field rangeOfString:@" · "];
        if (range.location == NSNotFound) continue;
        NSString *head = TLDHUDTrim([field substringToIndex:range.location]);
        NSString *tail = TLDHUDTrim([field substringFromIndex:NSMaxRange(range)]);
        if (head.length > 0 && tail.length > 0) {
            if (outTrack) *outTrack = head;
            if (outArtist) *outArtist = tail;
            return;
        }
    }
    if (outTrack) *outTrack = title;
    if (outArtist) *outArtist = artist;
}

// lyricLocation helpers (LyricStore.swift L254-L294). `norm` strips spaces;
// identity(text, hasPart:) checks whether either side of the identity
// string equals the part (space-insensitive), used to exclude the case
// where the other field is just the singer's name inside the identity.
static NSString *TLDHUDNorm(NSString *s)
{
    return [s stringByReplacingOccurrencesOfString:@" " withString:@""];
}

static BOOL TLDHUDIdentityHasPart(NSString *text, NSString *part)
{
    NSString *head = nil, *tail = nil;
    if (!TLDHUDSongIdentityParts(text, &head, &tail)) return NO;
    NSString *p = TLDHUDNorm(TLDHUDTrim(part));
    return [TLDHUDNorm(head) isEqualToString:p] || [TLDHUDNorm(tail) isEqualToString:p];
}

typedef NS_ENUM(NSInteger, TLDHUDLyricLocation) {
    HUDLyricLocationArtist,  // 歌詞在 artist 欄位
    HUDLyricLocationTitle,   // 歌詞在 title 欄位
    HUDLyricLocationUnknown
};

static TLDHUDLyricLocation TLDHUDLyricLocationFor(NSString *title, NSString *artist,
                                            NSSet<NSString *> *lyricTexts)
{
    NSString *t = TLDHUDTrim(title);
    NSString *a = TLDHUDTrim(artist);
    if (t.length == 0 || a.length == 0) return HUDLyricLocationUnknown;

    BOOL titleIsIdentity = TLDHUDSongIdentityParts(t, NULL, NULL);
    BOOL artistIsIdentity = TLDHUDSongIdentityParts(a, NULL, NULL);

    if (titleIsIdentity && !artistIsIdentity) {
        return TLDHUDIdentityHasPart(t, a) ? HUDLyricLocationUnknown
                                        : HUDLyricLocationArtist;
    }
    if (artistIsIdentity && !titleIsIdentity) {
        return TLDHUDIdentityHasPart(a, t) ? HUDLyricLocationUnknown
                                        : HUDLyricLocationTitle;
    }

    // Neither side looks like an identity string: match against the lyric
    // library (space-insensitive), as the main project does.
    BOOL inTitle = [lyricTexts containsObject:TLDHUDNorm(t)];
    BOOL inArtist = [lyricTexts containsObject:TLDHUDNorm(a)];
    if (inArtist && !inTitle) return HUDLyricLocationArtist;
    if (inTitle && !inArtist) return HUDLyricLocationTitle;

    // Last resort: artist is a >= 8-char pure-CJK short sentence — lyric.
    NSString *normA = TLDHUDNorm(a);
    if (normA.length >= 8) {
        BOOL allCJK = YES;
        for (NSUInteger i = 0; i < normA.length; i++) {
            unichar c = [normA characterAtIndex:i];
            if (c < 0x4E00 || c > 0x9FFF) { allCJK = NO; break; }
        }
        if (allCJK) return HUDLyricLocationArtist;
    }
    return HUDLyricLocationUnknown;
}

@implementation TLDHUDLyricsSnapshot

+ (NSString *)groupID { return kGroupID; }

+ (nullable TLDHUDLyricsDisplay *)currentDisplayAtDate:(NSDate *)date
                                            noMusic:(BOOL *)outNoMusic
                                             reason:(NSString * __nullable * __nullable)outReason
{
    if (outNoMusic) *outNoMusic = NO;
    NSUserDefaults *defaults =
        [[NSUserDefaults alloc] initWithSuiteName:kGroupID];
    if (!defaults) {
        if (outReason) *outReason = @"no snapshot";
        return nil;
    }

    // noMusic flag — PlaybackCoordinator.poll() writes it; the main
    // project's floating window checks it before the snapshot
    // (FloatingLyricViewController.swift L218-L221).
    if ([defaults boolForKey:kNoMusicKey]) {
        if (outNoMusic) *outNoMusic = YES;
        if (outReason) *outReason = @"no music";
        return nil;
    }

    // 2.0.0: forced test text wins over the snapshot (same format as
    // LyricStore.testText(): "懸浮測試 · 桌面歌詞 <version> · HH:mm:ss").
    // The timestamp updates every tick, proving the pill is alive.
    if ([defaults boolForKey:kTestTextKey]) {
        static NSDateFormatter *testFmt = nil;
        static dispatch_once_t testFmtToken;
        dispatch_once(&testFmtToken, ^{
            testFmt = [[NSDateFormatter alloc] init];
            testFmt.dateFormat = @"HH:mm:ss";
        });
        TLDHUDLyricsDisplay *testDisplay = [[TLDHUDLyricsDisplay alloc] init];
        testDisplay.songIdentity = @"__test__";
        testDisplay.lineCount = 0;
        testDisplay.track = @"";
        testDisplay.artist = @"";
        testDisplay.songLine = @"";
        testDisplay.currentLine = [NSString stringWithFormat:
            @"懸浮測試 · 桌面歌詞 %@ · %@",
            TLDHUD_VERSION_STRING, [testFmt stringFromDate:date]];
        return testDisplay;
    }

    NSData *data = [defaults dataForKey:kSnapshotKey];
    if (!data) {
        if (outReason) *outReason = @"no snapshot";
        return nil;
    }
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                         options:0
                                                           error:&error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (outReason) *outReason = @"bad snapshot";
        return nil;
    }

    NSString *title = json[@"title"];
    NSString *artist = json[@"artist"];
    if (![title isKindOfClass:[NSString class]]) title = @"";
    if (![artist isKindOfClass:[NSString class]]) artist = @"";
    NSArray *lyricDicts = json[@"lyrics"];
    if (![lyricDicts isKindOfClass:[NSArray class]]) lyricDicts = @[];

    // startedAt: JSONEncoder default = seconds since 2001-01-01
    // (LyricSnapshot.startedAt, LyricStore.swift L10).
    NSTimeInterval startedAtInterval = 0;
    id startedAtRaw = json[@"startedAt"];
    if ([startedAtRaw isKindOfClass:[NSNumber class]]) {
        startedAtInterval = [startedAtRaw doubleValue];
    }
    NSDate *startedAt =
        [NSDate dateWithTimeIntervalSinceReferenceDate:startedAtInterval];

    BOOL isPlaying = NO;
    id playingRaw = json[@"isPlaying"];
    if ([playingRaw isKindOfClass:[NSNumber class]]) {
        isPlaying = [playingRaw boolValue];
    }
    NSTimeInterval elapsedWhenPaused = 0;
    id pausedRaw = json[@"elapsedWhenPaused"];
    if ([pausedRaw isKindOfClass:[NSNumber class]]) {
        elapsedWhenPaused = [pausedRaw doubleValue];
    }

    // Lyric lines, in file order (times ascending, as LRCLIB returns them).
    NSMutableArray<NSDictionary *> *lines = [NSMutableArray array];
    for (id entry in lyricDicts) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *text = entry[@"text"];
        id timeRaw = entry[@"time"];
        if (![text isKindOfClass:[NSString class]]) continue;
        if (![timeRaw isKindOfClass:[NSNumber class]]) continue;
        [lines addObject:@{@"time": timeRaw, @"text": text}];
    }

    // currentElapsed (LyricStore.swift L134-L150) + per-song offset
    // (L152-L171): elapsed = playing ? paused + (now - startedAt) : paused,
    // then add this song's own timeOffset, then take the last line whose
    // time <= elapsed.
    NSTimeInterval elapsed;
    if (isPlaying) {
        elapsed = elapsedWhenPaused + [date timeIntervalSinceDate:startedAt];
    } else {
        elapsed = elapsedWhenPaused;
    }
    if (elapsed < 0) elapsed = 0;

    NSString *identity = TLDHUDStableSongIdentity(title, artist);
    NSString *offsetKey =
        [kOffsetKeyPrefix stringByAppendingString:[identity lowercaseString]];
    NSTimeInterval offset = 0;
    id offsetRaw = [defaults objectForKey:offsetKey];
    if ([offsetRaw isKindOfClass:[NSNumber class]]) {
        offset = [offsetRaw doubleValue];
    }
    elapsed += offset;

    TLDHUDLyricsDisplay *display = [[TLDHUDLyricsDisplay alloc] init];
    display.songIdentity = identity;
    display.lineCount = lines.count;
    NSString *track = nil, *songArtist = nil;
    TLDHUDSearchTerms(title, artist, &track, &songArtist);
    display.track = track ?: title;
    display.artist = songArtist ?: artist;
    if (display.track.length > 0 && display.artist.length > 0 &&
        ![display.track isEqualToString:display.artist]) {
        display.songLine = [NSString stringWithFormat:@"%@ · %@",
                            display.track, display.artist];
    } else {
        display.songLine = display.track;
    }

    if (lines.count == 0) {
        // No timed lyrics: fall back to the lyricLocation判定, exactly
        // like the main floating window (FloatingLyricViewController.swift
        // L232-L268): the field that is NOT the fixed identity string is
        // the lyric line; otherwise "♪ <title>".
        NSMutableSet<NSString *> *lyricTexts = [NSMutableSet set];
        TLDHUDLyricLocation location =
            TLDHUDLyricLocationFor(title, artist, lyricTexts);
        switch (location) {
            case HUDLyricLocationArtist:
                display.currentLine = artist;
                break;
            case HUDLyricLocationTitle:
                display.currentLine = title;
                break;
            case HUDLyricLocationUnknown:
            default:
                display.currentLine =
                    [NSString stringWithFormat:@"♪ %@", title];
                break;
        }
        return display;
    }

    NSInteger currentIndex = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        NSTimeInterval lineTime = [lines[i][@"time"] doubleValue];
        if (lineTime <= elapsed) {
            currentIndex = i;
        } else {
            break;
        }
    }
    if (currentIndex == NSNotFound) currentIndex = 0;
    display.currentLine = lines[currentIndex][@"text"];
    if (currentIndex > 0) {
        display.previousLine = lines[currentIndex - 1][@"text"];
    }
    if (currentIndex + 1 < (NSInteger)lines.count) {
        display.nextLine = lines[currentIndex + 1][@"text"];
    }
    return display;
}

@end
