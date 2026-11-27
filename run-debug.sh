#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

# Only the app, not build-debug.sh, which also builds the tests.
./generate.sh --ignore-xcodeproj
swift build --product aerosporkApp
mkdir -p .debug
cp -r .build/debug/aerosporkApp .debug
./.debug/aerosporkApp "$@"
