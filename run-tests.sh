#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

./build-debug.sh
./run-swift-test.sh

./.debug/j4 -h > /dev/null
./.debug/j4 --help > /dev/null
./.debug/j4 -v | grep -q "0.0.0-SNAPSHOT SNAPSHOT"
./.debug/j4 --version | grep -q "0.0.0-SNAPSHOT SNAPSHOT"

./format.sh
./generate.sh --all
./script/check-uncommitted-files.sh

echo
echo "All tests have passed successfully"
