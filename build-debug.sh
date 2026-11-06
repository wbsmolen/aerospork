#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

./generate.sh --ignore-xcodeproj
swift build
swift build --target AppBundleTests # swift build doesn't build test targets by default :(

# Not `rm -rf .debug`: `run-cli.sh` comes through here, and that would delete the debug app bundle.
mkdir -p .debug
cp -r .build/debug/aerospork .debug
cp -r .build/debug/aerosporkApp .debug
