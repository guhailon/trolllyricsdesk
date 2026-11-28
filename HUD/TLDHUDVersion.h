// TLDHUDVersion.h
// HUD daemon version marking (2.0.2/build 32).
// The daemon is a bare tool binary with no Info.plist, so its version
// lives here as compile-time constants — the only marking it has.
// Keep in sync with TrollLyricsDesk/Info.plist, TrollLyricsWidget/
// Info.plist and the pbxproj MARKETING_VERSION / CURRENT_PROJECT_VERSION
// (check_2.0.2.py §2 asserts all of them); LyricStore.versionTag is the
// Swift-side twin ("build 32（2.0.2）").
#ifndef TLDHUDVersion_h
#define TLDHUDVersion_h
#define TLDHUD_VERSION_STRING @"2.0.2"
#define TLDHUD_BUILD_STRING @"32"
#endif
