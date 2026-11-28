// TLDHUDLyricsSnapshot.h
// HUD Test 0.2.0 — read-only lyric snapshot reader.
//
// The main TrollLyricsDesk app (1.0.6/build 28) writes a JSON snapshot of
// the currently playing song into the shared App Group
// (com.apple.security.application-groups entitlement,
// group.com.hailong.TrollLyricsDesk). This daemon only READS it, once per
// 1s timer tick, and turns it into display lines. It never writes the
// snapshot, never contacts the network, and never touches playback.
//
// Faithful ObjC ports of two small pure functions from the main project
// (Lyrics/LyricStore.swift, branch v1.0.6-lc): stableSongIdentity and the
// currentLyric elapsed + per-song offset algorithm, plus the " · "
// searchTerms split used for the song title line. Separator table and
// algorithm are copied verbatim, not re-imagined — see RUN_0.2.0.md for
// the field-by-field alignment table with source line numbers.
// (New code, © 2026 顾海龙集团, MIT.)

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One resolved display frame: what the HUD pill should show right now.
/// nil currentLine means "no usable snapshot — show the old test text".
@interface TLDHUDLyricsDisplay : NSObject
@property (nonatomic, copy, nullable) NSString *songLine;     // "歌名 · 歌手"
@property (nonatomic, copy, nullable) NSString *currentLine;  // 粗體主行
@property (nonatomic, copy, nullable) NSString *previousLine; // 上一句（有才有）
@property (nonatomic, copy, nullable) NSString *nextLine;     // 下一句（有才有）
@property (nonatomic, copy) NSString *songIdentity;           // 穩定換歌判定鍵
@property (nonatomic, assign) NSUInteger lineCount;           // 歌詞總行數
@property (nonatomic, copy) NSString *track;                  // 拆出的真歌名
@property (nonatomic, copy) NSString *artist;                 // 拆出的真歌手
// 2.0.2: appearance the daemon applies every tick — the snapshot's lyric
// opacity (label alpha, multiplies the colour tiers) and font size
// (current line = fontSize, the other lines scale 11/17). Defaults live
// in the .mm parser (1.0 / 23.0 when the field is absent).
@property (nonatomic, assign) double opacity;
@property (nonatomic, assign) double fontSize;
// 2.0.4: karaoke — elapsed in the song (incl. per-song offset, same axis
// as the line/word times) and the current line's per-word timings
// (@{@"time": NSNumber, @"text": NSString}, display-converted). Nil/empty
// means "no word timings — fall back to whole-line highlight".
@property (nonatomic, assign) NSTimeInterval elapsed;
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *currentWords;
@end

@interface TLDHUDLyricsSnapshot : NSObject

/// App Group shared by the main app and this daemon.
+ (NSString *)groupID;

/// Read the snapshot once and resolve the display frame for `date`.
/// Returns nil when there is no snapshot at all (caller shows fallback).
/// `outNoMusic` is set YES when the suite's "lyric.noMusic" flag is set
/// (player not detected — also fallback, but logged with its own reason).
/// `outReason` is a short English reason for the fallback log line
/// (@"no snapshot" / @"no music" / @"bad snapshot"), nil on success.
+ (nullable TLDHUDLyricsDisplay *)currentDisplayAtDate:(NSDate *)date
                                            noMusic:(BOOL *)outNoMusic
                                             reason:(NSString * __nullable * __nullable)outReason;

@end

NS_ASSUME_NONNULL_END
