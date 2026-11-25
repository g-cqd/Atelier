#!/bin/sh
# Builds GitDiffViewer in release and wraps it in .build/GitDiffViewer.app, with the diagnostic tools the app runs
# in Contents/Helpers and the grammar corpus bundle in Contents/Resources. Each helper has one known source, and
# none comes from PATH:
#   arcleak, dolly, deadwood  built at the commit helpers.lock pins, in a private checkout under
#                             ~/Library/Caches/fr.gcqd.GitDiffViewer.build/tools, with only the dependencies
#                             their committed Package.resolved pins
#   swift-format              the Swift 6.4 toolchain that builds the app
#   swiftlint, swiftformat    Homebrew's prefix
# One swift command builds the app and the analyzers: $SWIFT, else `xcrun swift` (AGENTS.md), on Swift 6.4.
# Each helper is checked, signed with the hardened runtime and run once for its version, which
# Contents/Resources/helpers.txt records; the app is signed last and verified. A failed run leaves any previous
# bundle in place.
#
# Usage: bundle.sh [--dry-run]
#   --dry-run  print each helper, its source and its checks; fetch, build, copy and sign nothing
#
# Environment:
#   CODESIGN_IDENTITY          the signing identity; ad-hoc when unset
#   GDV_ALLOW_MISSING_HELPERS  1: leave out, with a warning, a helper that fails to build or fails a check;
#                              otherwise such a helper stops the script
#   GDV_BUNDLE_<TOOL>          the absolute path of a binary to bundle instead of the tool's own source, for
#                              example GDV_BUNDLE_SWIFT_FORMAT; checked the same way, and reported as an override
#   GDV_BUILD_JOBS             parallel build jobs (default 2)
#   SWIFT                      the swift command (default `xcrun swift`); it must be Swift 6.4
#   TOOLCHAINS                 the toolchain `xcrun swift` runs; when unset and the default is not Swift 6.4, the
#                              first installed Swift 6.4 toolchain

set -eu

usage() { sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; }
error() { printf 'error: %s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
    error "$*"
    exit 1
}
# One line of a helper's plan: a label, then its value.
row() { printf '  %-9s %s\n' "$1" "$2"; }

dry_run=0
for argument in "$@"; do
    case "$argument" in
        --dry-run) dry_run=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

script_dir=$(cd "$(dirname "$0")" && pwd)
package_dir=$(dirname "$script_dir")
lock="$script_dir/helpers.lock"
cache_dir="$HOME/Library/Caches/fr.gcqd.GitDiffViewer.build"
jobs=${GDV_BUILD_JOBS:-2}
analyzers="arcleak dolly deadwood"
required_swift=6.4
# Apple, or the Developer ID that signs the swift.org toolchains.
toolchain_signer='anchor apple or (anchor apple generic and certificate leaf[subject.OU] = "V9AUD2URP3")'
sign_id=${CODESIGN_IDENTITY:--}
failed=

case "$jobs" in "" | *[!0-9]* | 0) die "GDV_BUILD_JOBS must be a positive number, not '$jobs'" ;; esac
if [ -n "${GDV_TOOLS_DIR:-}" ]; then
    warn "GDV_TOOLS_DIR is no longer read: the analyzers build from helpers.lock (GDV_BUNDLE_<TOOL> bundles a binary)"
fi

# MARK: - Swift

# Runs $swift_cmd, split into words on purpose, as scripts/packages.sh splits $SWIFT.
swift_run() {
    # shellcheck disable=SC2086
    $swift_cmd "$@"
}

json_value() { printf '%s' "$1" | plutil -extract "$2" raw -o - - 2>/dev/null; }

is_required_swift() {
    case "$1" in *"Swift version $required_swift "* | *"Swift version $required_swift."*) return 0 ;; esac
    return 1
}

# Chooses the swift that builds the app and the analyzers: $SWIFT, else `xcrun swift`. When neither SWIFT nor
# TOOLCHAINS chooses and xcrun's default is not Swift 6.4, selects the first installed Swift 6.4 toolchain through
# TOOLCHAINS. Sets swift_cmd, swift_shown, swift_version and toolchain_bin; fails unless the choice is Swift 6.4.
resolve_swift() {
    swift_cmd=${SWIFT:-xcrun swift}
    info=$(swift_run -print-target-info 2>/dev/null) || info=
    swift_version=$(json_value "$info" compilerVersion) || swift_version=
    if ! is_required_swift "$swift_version" && [ -z "${SWIFT:-}" ] && [ -z "${TOOLCHAINS:-}" ]; then
        for toolchain in "$HOME"/Library/Developer/Toolchains/*.xctoolchain /Library/Developer/Toolchains/*.xctoolchain
        do
            if [ ! -d "$toolchain" ] || [ -L "$toolchain" ]; then continue; fi
            id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$toolchain/Info.plist" 2>/dev/null) || continue
            candidate=$(TOOLCHAINS=$id && export TOOLCHAINS && swift_run -print-target-info 2>/dev/null) || continue
            if is_required_swift "$(json_value "$candidate" compilerVersion)"; then
                printf 'xcrun runs %s by default; selecting %s\n' "${swift_version:-no swift}" "$toolchain"
                TOOLCHAINS=$id
                export TOOLCHAINS
                info=$candidate
                swift_version=$(json_value "$info" compilerVersion)
                break
            fi
        done
    fi
    swift_shown=$swift_cmd
    if [ -z "${SWIFT:-}" ] && [ -n "${TOOLCHAINS:-}" ]; then swift_shown="TOOLCHAINS=$TOOLCHAINS $swift_cmd"; fi
    is_required_swift "$swift_version" || return 1
    resource_dir=$(json_value "$info" paths.runtimeResourcePath) || return 1
    toolchain_bin=${resource_dir%/lib/swift}/bin
}

# MARK: - helpers.lock

# Checks that helpers.lock pins each analyzer exactly once, as `<name> <repository URL> <40-character commit SHA>`.
validate_lock() {
    if [ ! -f "$lock" ]; then
        error "$lock is missing"
        return 1
    fi
    awk -v names="$analyzers" '
        function bad(message) { printf "error: %s:%d: %s\n", FILENAME, FNR, message; failed = 1 }
        BEGIN { split(names, list, " "); for (i in list) known[list[i]] = 1 }
        /^[[:space:]]*(#|$)/ { next }
        NF != 3 { bad("expected <name> <repository URL> <commit SHA>"); next }
        !($1 in known) { bad("unknown analyzer " $1); next }
        $3 !~ /^[0-9a-f]+$/ || length($3) != 40 { bad($1 ": " $3 " is not a full 40-character commit SHA"); next }
        $1 in seen { bad($1 " is pinned twice"); next }
        { seen[$1] = 1 }
        END {
            for (name in known) if (!(name in seen)) { printf "error: %s: no pin for %s\n", FILENAME, name; failed = 1 }
            exit failed
        }
    ' "$lock" >&2
}

# Prints field $2 of analyzer $1's pin: 2 for the repository URL, 3 for the commit SHA.
pinned() { awk -v name="$1" -v field="$2" '$1 == name { print $field; exit }' "$lock"; }

# MARK: - Checks

# Fails, saying why, unless $1 is a Mach-O executable.
check_executable() {
    if [ ! -f "$1" ] || [ ! -x "$1" ]; then
        error "$tool: $1 is not an executable file"
        return 1
    fi
    kind=$(file -bL "$1") || kind=unknown
    case "$kind" in
        *Mach-O*executable*) ;;
        *)
            error "$tool: $1 is not a Mach-O executable ($kind)"
            return 1
            ;;
    esac
}

# Prints the first line `$1 --version` prints; fails when $1 does not run.
version_of() {
    output=$("$1" --version 2>&1) || return 1
    printf '%s\n' "$output" | sed -n 1p
}

# MARK: - Sources

# git in the current analyzer's private checkout, which never runs a hook.
checkout_git() { git -C "$checkout" -c core.hooksPath=/dev/null -c advice.detachedHead=false "$@"; }

# Describes the private checkout against the pin, reading only; fails when it holds local changes.
describe_checkout() {
    if [ ! -d "$checkout/.git" ]; then
        echo "absent, to be fetched"
        return 0
    fi
    head=$(checkout_git rev-parse -q --verify HEAD) || head=
    if [ "$head" != "$sha" ]; then
        echo "at ${head:-no commit}, to be moved to the pinned commit"
        return 0
    fi
    if [ -n "$(checkout_git --no-optional-locks status --porcelain --untracked-files=all 2>/dev/null)" ]; then
        echo "at the pinned commit, with local changes"
        return 1
    fi
    echo "at the pinned commit, clean"
}

# Creates or updates the private checkout at the pinned commit. The commit is fetched by its SHA, not by a branch.
sync_checkout() {
    if [ ! -d "$checkout/.git" ]; then
        rm -rf "$checkout"
        mkdir -p "$checkout" || return 1
        git init --quiet --template= "$checkout" || return 1
        checkout_git remote add origin "$url" || return 1
    fi
    checkout_git remote set-url origin "$url" || return 1
    if ! checkout_git cat-file -e "$sha^{commit}" 2>/dev/null; then
        if ! checkout_git fetch --quiet --depth 1 origin "$sha"; then
            error "$tool: could not fetch $sha from $url"
            return 1
        fi
    fi
    if [ "$(checkout_git rev-parse -q --verify HEAD)" != "$sha" ]; then
        if ! checkout_git checkout --quiet --detach "$sha"; then
            error "$tool: could not check out $sha in $checkout"
            return 1
        fi
    fi
}

# Fails unless the private checkout is at the pinned commit with a clean tree; $1 says when, before or after.
verify_checkout() {
    head=$(checkout_git rev-parse -q --verify HEAD) || head=
    if [ "$head" != "$sha" ]; then
        error "$tool: $checkout is at ${head:-no commit}, not at the pinned $sha ($1 the build)"
        return 1
    fi
    if ! changes=$(checkout_git status --porcelain --untracked-files=all); then
        error "$tool: git status failed in $checkout"
        return 1
    fi
    if [ -n "$changes" ]; then
        error "$tool: $checkout has local changes ($1 the build); delete it to fetch it again:"
        printf '%s\n' "$changes" >&2
        return 1
    fi
}

# Builds the analyzer $tool at its pinned commit. Sets source_path and provenance.
build_analyzer() {
    url=$(pinned "$tool" 2)
    sha=$(pinned "$tool" 3)
    checkout="$cache_dir/tools/$tool"
    row source "$url $sha (helpers.lock)"
    if state=$(describe_checkout); then clean=1; else clean=0; fi
    row checkout "$checkout, $state"
    row build "$swift_shown build -c release --product $tool --force-resolved-versions --jobs $jobs"
    row check "HEAD is the pinned commit and the tree is clean, before and after the build; a Mach-O executable"
    if [ "$dry_run" = 1 ]; then
        if [ "$clean" = 0 ]; then error "$tool: $checkout has local changes; delete it to fetch it again"; fi
        [ "$clean" = 1 ]
        return
    fi
    sync_checkout || return 1
    verify_checkout before || return 1
    if ! swift_run build --package-path "$checkout" -c release --product "$tool" --force-resolved-versions \
        --jobs "$jobs"; then
        error "$tool: the release build of $sha failed"
        return 1
    fi
    if ! bin_dir=$(swift_run build --package-path "$checkout" -c release --show-bin-path); then
        error "$tool: could not locate the build products"
        return 1
    fi
    verify_checkout after || return 1
    source_path=$bin_dir/$tool
    provenance="$url $sha"
    check_executable "$source_path"
}

# Resolves swiftlint or swiftformat in Homebrew's prefix. Sets source_path and provenance.
resolve_homebrew() {
    if [ -z "${brew_prefix:-}" ]; then brew_prefix=$(brew --prefix 2>/dev/null) || brew_prefix=; fi
    if [ -z "$brew_prefix" ]; then
        error "$tool: Homebrew not found, and $tool comes from Homebrew's prefix"
        return 1
    fi
    link=$brew_prefix/bin/$tool
    if [ ! -e "$link" ]; then
        error "$tool: $link does not exist; install it with \`brew install $tool\`"
        return 1
    fi
    source_path=$(realpath "$link") || return 1
    row source "$link -> $source_path (Homebrew)"
    row check "a Mach-O executable"
    provenance="Homebrew $source_path"
    check_executable "$source_path"
}

# Resolves swift-format in the toolchain that builds the app. Sets source_path and provenance.
resolve_swift_format() {
    if [ -z "${toolchain_bin:-}" ]; then
        error "swift-format: no Swift $required_swift toolchain to take it from"
        return 1
    fi
    source_path=$toolchain_bin/swift-format
    row source "$source_path (the Swift $required_swift toolchain of the build)"
    row check "a Mach-O executable signed by Apple or by Swift Open Source (V9AUD2URP3)"
    provenance="Swift toolchain $source_path"
    check_executable "$source_path" || return 1
    if ! codesign --verify --strict --test-requirement="=$toolchain_signer" "$source_path" 2>/dev/null; then
        error "swift-format: $source_path is not signed by Apple or by Swift Open Source"
        return 1
    fi
}

# Resolves the binary GDV_BUNDLE_<TOOL> names in place of $tool's own source. Sets source_path and provenance.
resolve_override() {
    warn "$tool: bundling $2 from $1 instead of $tool's own source"
    row source "$2 (override $1)"
    row check "a Mach-O executable"
    case "$2" in
        /*) ;;
        *)
            error "$tool: $1 must be an absolute path"
            return 1
            ;;
    esac
    source_path=$2
    provenance="override $1=$2"
    check_executable "$source_path"
}

# Resolves or builds the helper $tool, then, unless this is a dry run, copies it into the staged bundle, signs it
# and runs the signed copy for its version. Fails, having said why, when a step or a check fails.
stage_helper() {
    printf '%s\n' "$tool"
    source_path=
    variable=GDV_BUNDLE_$(printf '%s' "$tool" | tr 'a-z-' 'A-Z_')
    eval "override=\${$variable:-}"
    if [ -n "$override" ]; then
        resolve_override "$variable" "$override" || return 1
    else
        case "$tool" in
            swiftlint | swiftformat) resolve_homebrew || return 1 ;;
            swift-format) resolve_swift_format || return 1 ;;
            *) build_analyzer || return 1 ;;
        esac
    fi
    if [ "$dry_run" = 1 ]; then
        if [ -n "$source_path" ]; then row version "$(version_of "$source_path" || echo 'does not run')"; fi
        return 0
    fi
    target="$helpers/$tool"
    cp "$source_path" "$target" || return 1
    if ! codesign --force --options runtime --sign "$sign_id" "$target"; then
        error "$tool: signing failed"
        rm -f "$target"
        return 1
    fi
    if ! version=$(version_of "$target"); then
        error "$tool: the signed copy does not run"
        rm -f "$target"
        return 1
    fi
    row bundled "$version"
    printf '%-13s %-10s %s\n' "$tool" "$version" "$provenance" >>"$record"
}

# MARK: - Main

swift_missing=0
if resolve_swift; then
    printf 'Swift      %s: %s\n' "$swift_shown" "$swift_version"
else
    swift_missing=1
    error "$swift_shown is ${swift_version:-not a working swift}, and the build needs Swift $required_swift;" \
        "install Xcode 27 or a Swift $required_swift toolchain, or choose one with TOOLCHAINS or SWIFT"
    [ "$dry_run" = 1 ] || exit 1
fi
validate_lock || die "$lock is malformed"
printf 'App        %s build -c release --product GitDiffViewer --force-resolved-versions --jobs %s\n' \
    "$swift_shown" "$jobs"
if [ "$sign_id" = - ]; then
    printf 'Signing    ad-hoc, hardened runtime: each helper, then the app\n'
else
    printf 'Signing    %s, hardened runtime: each helper, then the app\n' "$sign_id"
fi

cd "$package_dir"
app=.build/GitDiffViewer.app
staging=.build/bundle-staging
staged_app=$staging/GitDiffViewer.app
helpers=$staged_app/Contents/Helpers
record=$staged_app/Contents/Resources/helpers.txt
if [ "$dry_run" = 0 ]; then
    trap 'rm -rf "$staging"' EXIT
    trap 'exit 1' HUP INT TERM
    rm -rf "$staging"
    mkdir -p "$helpers" "$(dirname "$record")"
    printf '# The helpers bundle.sh put in Contents/Helpers: name, version, source. Built with %s.\n' \
        "$swift_version" >"$record"
fi

# A real run stops at the first helper that fails, unless GDV_ALLOW_MISSING_HELPERS=1; a dry run lists them all.
for tool in swiftlint swift-format swiftformat $analyzers; do
    if stage_helper; then continue; fi
    failed="$failed $tool"
    if [ "$dry_run" = 0 ] && [ "${GDV_ALLOW_MISSING_HELPERS:-}" != 1 ]; then
        die "$tool failed. Fix it, or set GDV_ALLOW_MISSING_HELPERS=1 to bundle without it"
    fi
done

if [ -n "$failed" ]; then
    if [ "${GDV_ALLOW_MISSING_HELPERS:-}" = 1 ]; then
        warn "bundling without:$failed (GDV_ALLOW_MISSING_HELPERS=1)"
        if [ "$dry_run" = 0 ]; then printf '# Left out:%s\n' "$failed" >>"$record"; fi
    else
        die "failed:$failed. Fix them, or set GDV_ALLOW_MISSING_HELPERS=1 to bundle without them"
    fi
fi
if [ "$dry_run" = 1 ]; then
    echo "Dry run: nothing was fetched, built, copied or signed."
    exit "$swift_missing"
fi

echo GitDiffViewer
swift_run build -c release --product GitDiffViewer --force-resolved-versions --jobs "$jobs" ||
    die "the GitDiffViewer release build failed"
bin_dir=$(swift_run build -c release --show-bin-path)
mkdir -p "$staged_app/Contents/MacOS"
cp "$bin_dir/GitDiffViewer" "$staged_app/Contents/MacOS/GitDiffViewer"
# The grammars grammar colour reads, where GrammarCorpus.bundled() looks: the app's Contents/Resources.
corpus=AtelierCore_AtelierGrammarCorpus.bundle
[ -f "$bin_dir/$corpus/Contents/Resources/Grammars/languages.json" ] ||
    [ -f "$bin_dir/$corpus/Grammars/languages.json" ] ||
    die "the build made no $corpus with its grammars"
mkdir -p "$staged_app/Contents/Resources"
ditto "$bin_dir/$corpus" "$staged_app/Contents/Resources/$corpus"
cat >"$staged_app/Contents/Info.plist" <<'PLIST'
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

codesign --force --options runtime --sign "$sign_id" "$staged_app"
codesign --verify --deep --strict "$staged_app"
rm -rf "$app"
mv "$staged_app" "$app"
echo "$app"
