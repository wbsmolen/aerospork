#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

./generate.sh --ignore-xcodeproj
swift build
swift build --target AppBundleTests # swift build doesn't build test targets by default :(

rm -rf .debug && mkdir .debug
cp -r .build/debug/aerospork .debug
cp -r .build/debug/aerosporkApp .debug
