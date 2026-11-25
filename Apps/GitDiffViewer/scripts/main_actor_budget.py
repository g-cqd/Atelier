#!/usr/bin/env python3
"""Ranks GitDiffViewerTests' suites by the main-thread time of their tests, from a `sample` report of a whole run.

Every main-actor test shares the one main thread, so a run lasts at least as long as their main-thread time added up,
and under load that sum stretches until bounded waits fail together. Each main-thread sample goes to the outermost
test-module frame that names a suite (a type whose name ends in Tests or Benchmark), and then to the first test named
below it. The samples in which dyld waits for the sampler to acknowledge a library load are left out: that wait exists
only while `sample` is attached.

Usage: main_actor_budget.py SAMPLE RUN_SECONDS [BUDGET_SECONDS] [TOP_TESTS]
       main_actor_budget.py --self-test
  SAMPLE          the report of `sample PID ... -file SAMPLE` over the whole test process
  RUN_SECONDS     how long the run lasted, which the main thread's samples span
  BUDGET_SECONDS  the main-thread time a suite may take (default 1.0); exits 1 when a suite takes more
  TOP_TESTS       how many of the heaviest tests to list (default 10)
Exits 2 when the report holds no usable sample: it is missing, or has no main thread.
"""

import collections
import re
import sys

SUITE = re.compile(r"\b([A-Z]\w*(?:Tests|Benchmark))\b")
TEST = re.compile(r"`([^`]+)`")
NODE = re.compile(r"^(\s*[+!:| ]*)(\d+) (.*)$")
# dyld blocks here until the sampler has read a newly loaded image; without the sampler, the load does not wait.
SAMPLER_WAIT = "RemoteNotificationResponder::blockOnSynchronousEvent"


def main_thread(lines):
    """The main thread's call tree: (depth, samples, symbol) for each node, in the report's order.

    A report without a main thread, such as one whose sampler stopped before its first sample, yields nothing.
    """
    start = next((i for i, line in enumerate(lines) if "Thread_" in line and "Main Thread" in line), None)
    if start is None:
        return
    for index, line in enumerate(lines[start:]):
        match = NODE.match(line)
        # The tree ends at a blank line or at the next thread's root.
        if not match or (index > 0 and "Thread_" in match.group(3)):
            return
        yield len(match.group(1)), int(match.group(2)), match.group(3)


def attribute(nodes):
    """Samples per suite and per (suite, test), the sampler's own waits left out, and the thread's sample count."""
    suites, tests = collections.Counter(), collections.Counter()
    stack = []  # (depth, suite this node named, test this node named)
    total = None
    for depth, count, symbol in nodes:
        if total is None:
            total = count
            continue
        while stack and stack[-1][0] >= depth:
            stack.pop()
        suite = next((named for _, named, _ in reversed(stack) if named), None)
        test = next((named for _, _, named in reversed(stack) if named), None)
        if SAMPLER_WAIT in symbol:
            if suite:
                suites[suite] -= count
                if test:
                    tests[(suite, test)] -= count
            stack.append((depth, None, None))
            continue
        named_suite = named_test = None
        if "GitDiffViewerTests" in symbol:
            bare = symbol.replace("(in GitDiffViewerTests)", "").replace("GitDiffViewerTests", "")
            if suite is None and (match := SUITE.search(bare)):
                named_suite = match.group(1)
                suites[named_suite] += count
            owner = suite or named_suite
            if owner and test is None and (match := TEST.search(bare)):
                named_test = match.group(1)
                tests[(owner, named_test)] += count
        stack.append((depth, named_suite, named_test))
    return suites, tests, total or 0


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    run = float(argv[2])
    budget = float(argv[3]) if len(argv) > 3 else 1.0
    top_tests = int(argv[4]) if len(argv) > 4 else 10
    try:
        with open(argv[1], errors="replace") as report:
            lines = report.read().splitlines()
    except OSError as error:
        print(f"error: no usable sample: the sampler wrote no report ({error.strerror}: {argv[1]})", file=sys.stderr)
        return 2
    suites, tests, total = attribute(main_thread(lines))
    if not total:
        print(f"error: no usable sample: {argv[1]} has no main-thread samples; the sampler did not attach to the "
              "test process or stopped before sampling it. Run the script again.", file=sys.stderr)
        return 2
    per_sample = run / total
    in_tests = sum(suites.values())
    print(f"main thread: {total} samples over {run:.2f} s; tests hold it for {in_tests * per_sample:.2f} s "
          f"({100 * in_tests / total:.0f}%). Budget per suite: {budget:.2f} s.")
    over = []
    for suite, count in suites.most_common():
        seconds = count * per_sample
        if seconds < 0.05:
            break
        flag = "  OVER BUDGET" if seconds > budget else ""
        print(f"{seconds:7.2f} s {100 * count / total:5.1f}%  {suite}{flag}")
        if flag:
            over.append(suite)
    print("heaviest tests:")
    for (suite, test), count in tests.most_common(top_tests):
        print(f"{count * per_sample:7.2f} s  {suite} / {test}")
    if over:
        print(f"{len(over)} suite(s) over the budget: {', '.join(over)}", file=sys.stderr)
        return 1
    return 0


HEADER = "Analysis of sampling swiftpm-testing-helper (pid 1) every 1 millisecond\n----\n\n"
# A report of a sampler that attached but stopped before it took a sample: the call graph is empty.
NO_SAMPLES = HEADER + "Call graph:\n\nTotal number in stack (recursive counted multiple, when >=5):\n"
# A report whose threads include none labelled the main thread.
NO_MAIN_THREAD = HEADER + (
    "Call graph:\n"
    "    47 Thread_2   DispatchQueue_1: com.apple.main-thread  (serial)\n"
    "    + 47 start  (in dyld) + 6992  [0x1]\n"
    "    47 Thread_3: com.apple.NSEventThread\n"
    "    + 47 thread_start  (in libsystem_pthread.dylib) + 8  [0x2]\n"
    "\nTotal number in stack (recursive counted multiple, when >=5):\n")
WITH_MAIN_THREAD = HEADER + (
    "Call graph:\n"
    "    10 Thread_1: Main Thread   DispatchQueue_<multiple>\n"
    "    + 10 start  (in dyld) + 6992  [0x1]\n"
    "    + ! 6 closure in FooTests.`draws the panel`()  (in GitDiffViewerTests) + 8  [0x2]\n"
    "    + ! 4 CFRunLoopRun  (in CoreFoundation) + 64  [0x3]\n"
    "    47 Thread_3: com.apple.NSEventThread\n"
    "    + 47 thread_start  (in libsystem_pthread.dylib) + 8  [0x2]\n"
    "\nTotal number in stack (recursive counted multiple, when >=5):\n")


def self_test():
    """Checks the parser on reports without a usable sample, and on one with a main thread."""
    import contextlib
    import io
    import os
    import tempfile

    def run(report):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "main-thread.txt")
            if report is not None:
                with open(path, "w") as file:
                    file.write(report)
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                status = main(["main_actor_budget.py", path, "5.0", "1.0"])
            return status, err.getvalue()

    failures = []
    for name, report in [("no samples", NO_SAMPLES), ("no main thread", NO_MAIN_THREAD), ("no report", None)]:
        status, err = run(report)
        if status != 2 or "no usable sample" not in err:
            failures.append(f"{name}: expected status 2 and 'no usable sample', got {status}: {err.strip()!r}")
    suites, tests, total = attribute(main_thread(WITH_MAIN_THREAD.splitlines()))
    if (dict(suites), dict(tests), total) != ({"FooTests": 6}, {("FooTests", "draws the panel"): 6}, 10):
        failures.append(f"with a main thread: got {dict(suites)}, {dict(tests)}, {total}")
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    print(f"self-test: {3 + 1 - len(failures)} passed, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(self_test() if sys.argv[1:] == ["--self-test"] else main(sys.argv))
