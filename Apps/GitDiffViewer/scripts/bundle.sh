#!/bin/sh
# Builds a release binary and wraps it in a minimal app bundle at .build/GitDiffViewer.app.
set -eu
script_dir=$(cd "$(dirname "$0")" && pwd)
cd "$script_dir/.."
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

helpers="$app/Contents/Helpers"
mkdir -p "$helpers"

tools_dir="${GDV_TOOLS_DIR:-$script_dir/../../..}"

for tool in swiftlint swift-format arcleak dolly deadwood; do
    # env override, e.g. GDV_BUNDLE_SWIFT_FORMAT
    upper=$(echo "$tool" | tr 'a-z-' 'A-Z_')
    eval "override=\${GDV_BUNDLE_${upper}:-}"
    if [ -n "$override" ]; then
        cp "$override" "$helpers/$tool"
        continue
    fi

    built=0
    case "$tool" in
        arcleak|dolly|deadwood)
            checkout="$tools_dir/$tool"
            if [ -f "$checkout/Package.swift" ]; then
                if (cd "$checkout" && swiftly run swift build -c release); then
                    cp "$checkout/.build/release/$tool" "$helpers/$tool"
                    built=1
                else
                    echo "warning: $tool build failed, skipping" >&2
                    built=1
                fi
            fi
            ;;
    esac
    [ "$built" = 1 ] && continue

    if command -v "$tool" >/dev/null 2>&1; then
        cp "$(command -v "$tool")" "$helpers/$tool"
        continue
    fi

    echo "warning: $tool not bundled" >&2
done

# sign ad-hoc unless CODESIGN_IDENTITY is set
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    sign_id="$CODESIGN_IDENTITY"
else
    sign_id="-"
fi

for helper in "$helpers"/*; do
    [ -f "$helper" ] || continue
    codesign --force --options runtime --sign "$sign_id" "$helper"
done

codesign --force --options runtime --sign "$sign_id" "$app"

echo "$app"
