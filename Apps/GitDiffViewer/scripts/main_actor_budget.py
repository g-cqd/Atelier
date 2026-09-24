#!/usr/bin/env python3
"""Ranks GitDiffViewerTests' suites by the main-thread time of their tests, from a `sample` report of a whole run.

Every main-actor test shares the one main thread, so a run lasts at least as long as their main-thread time added up,
and under load that sum stretches until bounded waits fail together. Each main-thread sample goes to the outermost
test-module frame that names a suite (a type whose name ends in Tests or Benchmark), and then to the first test named
below it. The samples in which dyld waits for the sampler to acknowledge a library load are left out: that wait exists
only while `sample` is attached.

Usage: main_actor_budget.py SAMPLE RUN_SECONDS [BUDGET_SECONDS] [TOP_TESTS]
  SAMPLE          the report of `sample PID ... -file SAMPLE` over the whole test process
  RUN_SECONDS     how long the run lasted, which the main thread's samples span
  BUDGET_SECONDS  the main-thread time a suite may take (default 1.0); exits 1 when a suite takes more
  TOP_TESTS       how many of the heaviest tests to list (default 10)
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
    """The main thread's call tree: (depth, samples, symbol) for each node, in the report's order."""
    start = next(i for i, line in enumerate(lines) if "Thread_" in line and "Main Thread" in line)
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
    with open(argv[1], errors="replace") as report:
        lines = report.read().splitlines()
    suites, tests, total = attribute(main_thread(lines))
    if not total:
        sys.exit("no main thread in the report")
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


if __name__ == "__main__":
    sys.exit(main(sys.argv))
