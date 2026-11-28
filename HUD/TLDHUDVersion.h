// TLDHUDVersion.h
// HUD daemon version marking (2.0.6/build 36, full HID touch port).
// The daemon is a bare tool binary with no Info.plist, so its version
// lives here as compile-time constants — the only marking it has.
// Keep in sync with TrollLyricsDesk/Info.plist, TrollLyricsWidget/
// Info.plist and the pbxproj MARKETING_VERSION / CURRENT_PROJECT_VERSION
// (check_2.0.6.py §2 asserts all of them); LyricStore.versionTag is the
// Swift-side twin ("build 36（2.0.6）").
#ifndef TLDHUDVersion_h
#define TLDHUDVersion_h
#define TLDHUD_VERSION_STRING @"2.0.6"
#define TLDHUD_BUILD_STRING @"36"
#endif
