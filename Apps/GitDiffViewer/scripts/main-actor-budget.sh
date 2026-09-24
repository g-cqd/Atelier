#!/bin/sh
# Runs GitDiffViewerTests whole with its main thread sampled, then ranks the suites by the main-thread time their tests
# take, and fails when one takes more than its budget (main_actor_budget.py does the ranking).
#
# Every main-actor test shares the one main thread, so a run lasts at least as long as their main-thread time added
# up; under load that sum stretches until the tests' bounded waits fail together. Run this after adding a test that
# draws, lays out, sweeps or reads the file system on the main actor, on a machine no other job loads
# (`work run --weight <CPU count>`): the budget is a quiet machine's, and load stretches every suite's time.
#
# Usage: main-actor-budget.sh
#
# Environment:
#   GDV_MAIN_ACTOR_BUDGET  the main-thread seconds a suite may take (default 1.0)
#   GDV_BUILD_JOBS         parallel build jobs (default 2)
#   SWIFT                  the swift command (default `swift`)

set -eu

here=$(cd "$(dirname "$0")" && pwd)
cd "$here/.."
swift=${SWIFT:-swift}
budget=${GDV_MAIN_ACTOR_BUDGET:-1.0}
out=$(mktemp -d "${TMPDIR:-/tmp}/gdv-main-actor.XXXXXX")

$swift build --build-tests --jobs "${GDV_BUILD_JOBS:-2}"

# The descendant of `pid` that runs the test bundle, if it has started.
test_process() {
    for child in $(pgrep -P "$1"); do
        if ps -o command= -p "$child" | grep -q 'swiftpm-testing-helper.*GitDiffViewerTests'; then
            echo "$child"
            return
        fi
        test_process "$child"
    done
}

start=$(date +%s)
$swift test --skip-build --disable-xctest --xunit-output "$out/run.xml" >"$out/run.log" 2>&1 &
runner=$!
# swift test starts the test process within a second of starting, having nothing to build: look for it until then.
pid=""
while [ -z "$pid" ] && kill -0 "$runner" 2>/dev/null; do
    pid=$(test_process "$runner")
done
[ -n "$pid" ] || {
    echo "error: the test process did not start; see $out/run.log" >&2
    exit 1
}
sample "$pid" 600 1 -mayDie -file "$out/main-thread.txt" >/dev/null 2>&1 &
sampler=$!
status=0
wait "$runner" || status=$?
wait "$sampler" || true
seconds=$(($(date +%s) - start))
[ "$status" -eq 0 ] || {
    echo "error: the test run failed with status $status; see $out/run.log" >&2
    exit "$status"
}
# The sample report spans the test process's life, which the xunit report times; the wall clock is the fallback.
run=$(sed -n 's/.*<testsuite [^>]* time="\([0-9.]*\)".*/\1/p' "$out/run.xml" | head -n 1)
python3 "$here/main_actor_budget.py" "$out/main-thread.txt" "${run:-$seconds}" "$budget"
