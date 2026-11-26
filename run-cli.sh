#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

# Only the CLI, not build-debug.sh: building the app and the tests on every call cost seconds.
# generate.sh stays, so an edited docs/aerospork-*.adoc never leaves stale --help text.
build() { ./generate.sh --ignore-xcodeproj && swift build --product aerospork; }
build > /dev/null || build
# Not `rm -rf .debug`: that would delete the debug app bundle.
mkdir -p .debug
cp -r .build/debug/aerospork .debug
./.debug/aerospork "$@"
