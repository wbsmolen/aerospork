#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

./build-debug.sh
./run-swift-test.sh

./.debug/aerospork -h > /dev/null
./.debug/aerospork --help > /dev/null
./.debug/aerospork -v | grep -q "0.0.0-SNAPSHOT SNAPSHOT"
./.debug/aerospork --version | grep -q "0.0.0-SNAPSHOT SNAPSHOT"

./format.sh
./generate.sh --all
./script/check-uncommitted-files.sh

echo
echo "All tests have passed successfully"
