# TrollLyricsDesk 1.0.0 — Build run 1 (push 2026-11-25 ~02:41 CST)

## Push

- **Repo:** https://github.com/guhailon/trolllyricsdesk (public, `main`, created new)
- **Commit:** `2da2a20618531570302324651738c038b6a80ed5` — "TrollLyricsDesk 1.0.0: App + Widget, MediaRemote follow, LRCLIB lyrics" (49 files, root commit)
- **Method:** `gh_init_push.py` (create repo + bootstrap) then `gh_push.py check/push`; remote `main` verified in sync with local HEAD (`already_in_sync`).
- **Note:** no LICENSE file existed in the project, so a standard MIT LICENSE (same text as the lyricwall repo, Copyright (c) 2026 顾海龙集团) plus a `.gitignore` (build/, *.ipa, *.xcarchive, DerivedData, xcuserdata) were added before the commit. No `.ipa` or build artifacts were pushed.

## Build run

- **Run id:** 45462437871, head `2da2a20`
- **Run status_field:** `completed`, run conclusion `failure`
- **Job "Build":** conclusion `cancelled`, steps 0 (none ever ran)
- **Verdict:** free-pool cancellation (queued ~15 min, cancelled before running a step). NOT a code failure — the build never started, so no compile or signing error exists to fix.
- **Artifacts:** none (no `.ipa`, no size/SHA to report).

## Next

- Morning rerun when the free pool is empty (no autonomous retries per Lee's standing rule for pool cancellations).
- Deploy is a separate approval — not done, not requested here.
- Still unverified: sandboxed MediaRemote read needs Lee's device test; widget reads snapshot opacity/fontSize, not the shared Settings keys (wiring question still open with Lee, does not block this build).

## Immediate rerun — 2026-11-25 07:52 CST (Lee said「跑」)

- **Trigger:** POST rerun-failed-jobs on run 45462437871 → 201; same run id, head `2da2a20`.
- **Result:** run `completed` 07:53:20 CST, conclusion `failure`. **Job "Build": conclusion `failure`, 12/12 steps done — NOT a pool cancellation** (build actually ran, ~1 min).
- **Failed step:** step 5 **"Archive (unsigned)"** (exit code 74); steps 6–9 skipped as a consequence.
- **xcodebuild error (from job log, job id 138867252553):**
  - `xcodebuild: error: Unable to read project 'TrollLyricsDesk.xcodeproj'.`
  - `Reason: The project 'TrollLyricsDesk' is damaged and cannot be opened due to a parse error. Examine the project file for invalid edits or unresolved source control conflicts.`
  - Also: `NSCocoaErrorDomain Code=3840 "JSON text did not start with array or object..."` (project.pbxproj parse failure).
- **Verdict: code failure — the .xcodeproj project file is damaged (parse error).** Likely from the SettingsView swap / App Group settings migration edit. Needs a fix to the project file; no rerun will help until it is repaired. Do NOT rerun, do NOT add a schedule.
- **Artifacts:** none (no `.ipa`, no size/SHA to report).
- **Morning 10:10 one-off rerun cron (trolllyricsdesk-morning-rerun):** now redundant as a rerun — the build runs and fails on the project file; rerunning the same commit will fail the same way. Cancel it unless the project file is fixed first.

## Fix + rebuild — 2026-11-25 10:04 CST (Lee tapped「修」)

### The fix (commit `0cccf6e`, pushed, remote `main` in sync)

- **Commit:** `0cccf6e` — "Fix project.pbxproj parse error: missing semicolon at line 302" (1 file, +1/−4).
- **Method:** `gh_push.py` check (`fast_forward_one_commit`, 1 missing blob + 1 tree) then push; `remote_after: 0cccf6e` — matches local HEAD.
- **Three edits, nothing else touched (verified by `git diff`):**
  1. Line 302: bare `)` after `files = ( 1EC1FE630EABD0B29C5446FA, )` in the App target's PBXFrameworksBuildPhase → `);`. This was the parse-error root cause. Confirmed beforehand it was the only bare `)` in the file.
  2. Release config: deleted the duplicated `DEBUG_INFORMATION_FORMAT = dwarf;` (line 201) and `MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;` (line 214), keeping the Release values `dwarf-with-dsym` / `NO` (lines 220/225). Deleting the Debug-style values is behaviour-preserving (OpenStep keeps the last duplicate).
  3. Debug config: deleted the duplicated `MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;` (line 453, identical value to line 441).
- **SettingsView untouched and exonerated** — its file ref D5C30227 appears 3× (definition + build file + App group), path `App/SettingsView.swift` intact. The earlier guess blaming the SettingsView swap was wrong.

### Verification (before push — all passed)

- OpenStep parse of the whole pbxproj: **OK** — 91 objects, rootObject valid PBXProject, **zero dangling refs**; braces 108/108, parens 48/48, zero bare `)` lines.
- `check_1.0.0.py`: **252 PASS, FAILED: none** (same 252 as the pre-fix baseline), OPEN: 12 known gaps.

### New build run — parse error GONE, new code failure

- **Run id:** 45530493072, head `0cccf6e`, job id 138924276251.
- **Result:** `completed` 10:06:36 CST (02:06:36Z), run conclusion `failure`. **Job "Build": conclusion `failure`, 12/12 steps done — NOT a pool cancellation** (job ran 40 s: 02:05:56–02:06:36Z; steps 1–4 passed).
- **Failed step:** step 5 **"Archive (unsigned)"** again; steps 6–9 skipped.
- **xcodebuild error (from job log):** `error: Build input files cannot be found: '.../Lyrics/Lyrics/LyricLine.swift', '.../Lyrics/Lyrics/LyricParser.swift', '.../Lyrics/Lyrics/LyricStore.swift', '.../TrollLyricsWidget/TrollLyricsWidget/TrollLyricsWidget.swift', '.../TrollLyricsWidget/TrollLyricsWidget/WidgetView.swift', '.../TrollLyricsWidget/TrollLyricsWidget/TrollLyricsWidgetBundle.swift' (in target 'TrollLyricsWidget' from project 'TrollLyricsDesk')`.
- **Mechanism (confirmed in the pbxproj):** the folder name is doubled — PBXGroup `Lyrics` has `path = "Lyrics"` AND its file refs have `path = "Lyrics/LyricLine.swift"` (same for group `TrollLyricsWidget` + `TrollLyricsWidget/*.swift`). Xcode resolves group path + file path = `Lyrics/Lyrics/...`. **Pre-existing in commit 2da2a20** (the fix commit touched no file refs or groups); it was only masked by the parse error before.
- **Artifacts:** none (no `.ipa`, no size/SHA to report).
- **Stopped here per instructions** — the doubled-path issue is NOT fixed in this commit; it needs a separate decision/fix (strip the folder prefix from the file refs, or drop the `path` from the groups). Do NOT rerun the same commit; it will fail the same way.
- **Deploy:** not done — separate approval. No channel post (paused).

## run 45536337461 — head dc861bd — 2026-11-25 10:56 CST — FAILURE (code, not pool)
- Install ldid step: `brew install ldid-procursus` installed 2.1.5-procursus7_3 (old), NOT procursus8 — runner's Homebrew tap was stale (no `brew update` before install).
- Archive (unsigned) passed; step 7 Sign with ldid failed with the same error as run 45535776981: `ldid: Unknown header magic / Are you sure that is a Mach-O?` (Xcode 26.6).
- Next fix: `brew update` before `brew install ldid-procursus` so the runner fetches the procursus8 formula (released 2026-11-17). No macOS binary asset for procursus8 on GitHub releases; Homebrew/MacPorts are the macOS routes.
- No IPA, no artifact.

## run 45549765086 — head 4b74e93 — 2026-11-25 12:54 CST — FAILURE (code, not pool)
- `brew update` worked: installed ldid-procursus 2.1.5-procursus8 (2026-11-17, latest), confirmed in log.
- But procursus8 fails the same way: step 7 Sign with ldid, `ldid: Unknown header magic / Are you sure that is a Mach-O?` (Xcode 26.6). The new-ldid route is exhausted.
- Archive (unsigned) passed; dlopen changes unaffected.
- Remaining directions: zsign, pin runner Xcode to an older version, codesign ad-hoc (least certain for TrollStore).
- No IPA, no artifact.

## run 45552553347 — head 3ba65ac — 2026-11-25 13:20 CST — SUCCESS
- zsign route worked: step 4 Install zsign, step 7 Sign with zsign (TrollStore), step 8 Package IPA, step 9 Upload artifact — all 9 Build steps success. ldid route was exhausted (procursus7 and procursus8 both failed on Xcode 26.6 Mach-O).
- Artifact: TrollLyricsDesk-1.0.0 (id 14994357835, zip 197,815 B), IPA 199,510 B, SHA256 b68dac20a59a186cc3d34669d45f241637effc6ea1ac30626110822dbafe11ae.
- Verified locally (~/workspace/trolllyricsdesk/hidden_files/artifact-45552553347/):
  - Bundle ID com.hailong.TrollLyricsDesk, version 1.0.0, MinimumOSVersion 16.0.
  - App binary: Mach-O 64 arm64 thin (magic cffaedfe, subtype 0), LC_CODE_SIGNATURE present; entitlements strings present: group.com.hailong.TrollLyricsDesk, com.apple.mediaremote.now-playing-read-access, com.apple.mediaremote.full-now-playing-read-access.
  - Widget binary: Mach-O 64 arm64 thin, LC_CODE_SIGNATURE present; app group string present, MediaRemote keys absent (correct — widget entitlements are app-group only).
  - Note: thin arm64 is normal for an Xcode device archive (dual-arch applies to Theos dylibs, not Xcode apps).
- Deploy NOT approved — separate approval. No channel post (paused).

## run 45558310842 — head e0b50b3 — 2026-11-25 14:10 CST — SUCCESS
- About page extended: author row (China fly) + Telegram channel row (@seadragonjb, tap to open https://t.me/seadragonjb), on top of the 2015c3e three items (log viewer, current version, join QQ group 166623677).
- 9 Build steps success (Install zsign, Sign with zsign, Package IPA, Upload artifact all green).
- Artifact: TrollLyricsDesk-1.0.0 (id 14996861688, zip 208,737 B), IPA 210,489 B, SHA256 25fd356900edef9f45f7555d599ad3da9719796d573599324281cc8f9db5c5d9.
- Verified locally (~/workspace/trolllyricsdesk/hidden_files/artifact-45558310842/):
  - Bundle ID com.hailong.TrollLyricsDesk, version 1.0.0, MinimumOSVersion 16.0; widget com.hailong.TrollLyricsDesk.TrollLyricsWidget.
  - App binary: Mach-O 64 arm64 thin (magic cffaedfe, subtype 0), LC_CODE_SIGNATURE present; entitlements strings present: group.com.hailong.TrollLyricsDesk, com.apple.mediaremote.now-playing-read-access, com.apple.mediaremote.full-now-playing-read-access.
  - Widget binary: Mach-O 64 arm64 thin, LC_CODE_SIGNATURE present; app group string present, MediaRemote keys absent (correct — widget entitlements are app-group only).
  - Note: thin arm64 is normal for an Xcode device archive (dual-arch applies to Theos dylibs, not Xcode apps).
- Deploy NOT approved — separate approval. No channel post (paused).
