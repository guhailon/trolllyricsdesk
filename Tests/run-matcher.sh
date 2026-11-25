#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sed '/^enum LRCLibError/,$d' Lyrics/LRCLibClient.swift > "$tmp/Record.swift"
swiftc MusicProviders/MusicTrack.swift "$tmp/Record.swift" PlaybackEngine/LyricMatcher.swift Tests/MatcherChecks.swift -o "$tmp/check"
"$tmp/check"
