#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

./generate.sh --ignore-xcodeproj
# One build for everything, test targets included: run-tests.sh follows it with `swift test --skip-build`.
swift build --build-tests

# Not `rm -rf .debug`: that would delete the debug app bundle.
mkdir -p .debug
cp -r .build/debug/aerospork .debug
cp -r .build/debug/aerosporkApp .debug
