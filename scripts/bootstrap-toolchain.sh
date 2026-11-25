#!/bin/sh
# Installs the swift.org 6.4 snapshot toolchain that aemi's CI action pins, for a machine without Xcode 27.
# Prints the TOOLCHAINS identifier to export afterwards. Mirrors Aemi-Studio/aemi/.github/actions/setup-swift.
set -eu
snapshot="${SWIFT_SNAPSHOT:-swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-06-15-a}"
pkg="$snapshot-osx.pkg"
url="https://download.swift.org/swift-6.4-branch/xcode/$snapshot/$pkg"
tmp="$(mktemp -d)"
printf 'downloading %s\n' "$url"
curl -fsSL "$url" -o "$tmp/$pkg"
sudo installer -pkg "$tmp/$pkg" -target /
rm -rf "$tmp"
plist="/Library/Developer/Toolchains/$snapshot.xctoolchain/Info.plist"
id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")"
printf 'export TOOLCHAINS=%s\n' "$id"
