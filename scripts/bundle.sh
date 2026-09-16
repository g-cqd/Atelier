#!/bin/sh
# Builds a release binary and wraps it in a minimal app bundle at .build/GitDiffViewer.app.
set -eu
cd "$(dirname "$0")/.."
swift build -c release
app=".build/GitDiffViewer.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/GitDiffViewer "$app/Contents/MacOS/GitDiffViewer"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>GitDiffViewer</string>
    <key>CFBundleIdentifier</key><string>fr.gcqd.GitDiffViewer</string>
    <key>CFBundleName</key><string>Git Diff Viewer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.1</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
echo "$app"
