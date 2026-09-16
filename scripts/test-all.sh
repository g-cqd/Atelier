#!/bin/sh
# Tests every package, core first. Extra arguments go to `swift test`.
set -eu
cd "$(dirname "$0")/.."
. scripts/packages.sh
for package in $packages; do
    [ -f "$package/Package.swift" ] || continue
    printf '==> %s\n' "$package"
    $swift_bin test --package-path "$package" "$@"
done
