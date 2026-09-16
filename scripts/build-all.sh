#!/bin/sh
# Builds every package, core first. Extra arguments go to `swift build` (for example `-c release`).
set -eu
cd "$(dirname "$0")/.."
. scripts/packages.sh
for package in $packages; do
    [ -f "$package/Package.swift" ] || continue
    printf '==> %s\n' "$package"
    $swift_bin build --package-path "$package" "$@"
done
