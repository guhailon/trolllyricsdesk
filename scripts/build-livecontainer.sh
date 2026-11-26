#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Build an isolated project copy, so TrollStore settings are unchanged.
tar --exclude=.git --exclude=build --exclude=dist -cf - . | tar -xf - -C "$TMP"
cd "$TMP"
python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('TrollLyricsDesk/Info.plist')
d=plistlib.loads(p.read_bytes())
for k in ('BSServiceDomains','UIBackgroundModes','NSSupportsLiveActivities'): d.pop(k,None)
d['TLDSLiveContainer']=True
d['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes']=False
d['CFBundleDisplayName']='桌面歌词 LC'
p.write_bytes(plistlib.dumps(d))
PY
xcodebuild -project TrollLyricsDesk.xcodeproj -scheme TrollLyricsDesk -configuration Release -archivePath "$TMP/build/LC.xcarchive" archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 'OTHER_CFLAGS=$(inherited) -DTLDS_LIVE_CONTAINER=1'
mkdir -p Payload "$ROOT/dist"
cp -R build/LC.xcarchive/Products/Applications/TrollLyricsDesk.app Payload/
rm -rf Payload/TrollLyricsDesk.app/PlugIns
# LiveContainer handles guest signing on import.
rm -f "$ROOT/dist/TrollLyricsDesk-1.0.5-LiveContainer.ipa"
zip -qr "$ROOT/dist/TrollLyricsDesk-1.0.5-LiveContainer.ipa" Payload
