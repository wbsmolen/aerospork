#!/bin/bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

./script/check-uncommitted-files.sh

rm -rf ~/Library/Developer/Xcode/DerivedData/AeroSpork-*
rm -rf ./.xcode-build

rm -rf AeroSpork.xcodeproj
./generate.sh
