#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

# What this run changes is what fails it, so that local work in progress and untracked files don't.
status_before="$(git status --porcelain)"
tree_changed() { test "$status_before" != "$(git status --porcelain)"; }
log="$(mktemp -t aerospork-run-tests)"
trap 'rm -f "$log"' EXIT

# The cheap checks run first, so a formatting slip or a stale generated file fails in seconds, not
# after the whole suite.
./generate.sh --all
if tree_changed; then
    git status --short
    git diff | sed 's/^/    /'
    echo "!!! This run changed the tree: generated files are out of sync. Commit what ./generate.sh --all produces."
    exit 1
fi

./script/install-dep.sh --swiftformat
./.deps/swiftformat/swiftformat --lint .
./script/install-dep.sh --swiftlint
./.deps/swiftlint/swiftlint lint --quiet

command -v shellcheck > /dev/null || { echo "!!! Install shellcheck first: brew install shellcheck"; exit 1; }
shellcheck -S warning ./*.sh script/*.sh
# A cache prefix under .build, so the check leaves no __pycache__ in script/ to fail the tree check.
PYTHONPYCACHEPREFIX=.build/pycache python3 -m py_compile script/*.py
python3 script/release-notes-html.py --self-check

./build-debug.sh 2>&1 | tee "$log"
# Counted, not fatal: beta SDK deprecations would break the gate. An incremental build reports only
# the files it recompiled.
echo "Build warnings: $(grep -cE '^/[^ ]+: .*warning:' "$log" || true)"

./.debug/aerospork -h > /dev/null
./.debug/aerospork --help > /dev/null
# The version string comes from generate.sh's default (1.0.0), not build-release.sh's
# (0.0.0-SNAPSHOT). Asserting the latter made this script fail for everyone, which mattered because
# script/publish-release.sh runs run-tests.sh first -- so the whole publish path was gated behind a
# guaranteed failure. Assert the shape, not a hardcoded number.
# Case-insensitive: the product is written "AeroSpork" in prose, while the command, bundle and
# config file stay lowercase. This assertion is about the SHAPE of the version line, not its
# styling -- pinning the case made a branding fix fail the build.
./.debug/aerospork -v | grep -qiE '^aerospork CLI client version: [0-9]+\.[0-9]+\.[0-9]+ '
./.debug/aerospork --version | grep -qiE '^aerospork CLI client version: [0-9]+\.[0-9]+\.[0-9]+ '

# --skip-build is safe only here, after the build that compiled the tests.
swift test --skip-build 2>&1 | tee "$log"
# The AppBundleTests bundle once died before its first test while CommonTests passed, and the run
# looked green (Package.swift, the rpath comment). Require its suite line.
grep -q "Test Suite 'AppBundleTests.xctest' passed" "$log" || { echo "!!! AppBundleTests did not run."; exit 1; }

# Under tests defaultConfigUrl points into docs/config-examples/, so a test can write into the repo.
if tree_changed; then
    git status --short
    git diff | sed 's/^/    /'
    echo "!!! A test wrote into the tree. Tests must write only to temporary files."
    exit 1
fi

echo
echo "All tests have passed successfully"
