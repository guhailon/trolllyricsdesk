# TrollLyricsDesk 1.0.5 — run log

1.0.4 cycle is in RUN_1.0.4.md (1.0.4 pushed 2026-11-25 20:59, run 45619128056
pool-cancelled after ~15 min queued, 0 steps; byproduct run 45619068205 on
938d282 got a machine and failed at link: ld: framework 'BackBoardServices'
not found — pbxproj lacks FRAMEWORK_SEARCH_PATHS; fix: Lee 2026-11-25 21:19
chose fold-into-1.0.5 — App target Debug + Release gain
FRAMEWORK_SEARCH_PATHS = ($(inherited),
$(SDKROOT)/System/Library/PrivateFrameworks). That fix failed too (run
45622690915, 2026-11-25 21:21): iPhoneOS26.5.sdk has no such directory.
Second fix (Lee 2026-11-25 21:41): the three private frameworks are no longer
linked at all (removed from Link Binary With Libraries; file refs kept),
OTHER_LDFLAGS gains -undefined dynamic_lookup in both App configs, symbols
resolve at runtime.
1.0.5 = 1.0.4 + audit-patch IPC (App Group container JSON +
notify_register_dispatch/notify_post + stopObserving; publishLyrics now BOOL)
+ pinch-zoom on the HUD card (LyricsHUDController, 0.65–1.8 clamp; Lee's
LyricsHUDView.swift untouched). Version bump CFBundleShortVersionString 1.0.5,
build 6, both targets; IPA/artifact renamed TrollLyricsDesk-1.0.5; check script
renamed check_1.0.5.py.
