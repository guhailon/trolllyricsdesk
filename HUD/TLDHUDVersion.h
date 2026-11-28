// TLDHUDVersion.h
// HUD daemon version marking (2.0.4/build 91, hid-probe verification build).
// The daemon is a bare tool binary with no Info.plist, so its version
// lives here as compile-time constants — the only marking it has.
// Keep in sync with TrollLyricsDesk/Info.plist, TrollLyricsWidget/
// Info.plist and the pbxproj MARKETING_VERSION / CURRENT_PROJECT_VERSION
// (check_hid-probe.py §2 asserts all of them); LyricStore.versionTag is the
// Swift-side twin ("build 91（2.0.4）").
#ifndef TLDHUDVersion_h
#define TLDHUDVersion_h
#define TLDHUD_VERSION_STRING @"2.0.4"
#define TLDHUD_BUILD_STRING @"91"
#endif
