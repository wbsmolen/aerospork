#!/bin/bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

./script/check-uncommitted-files.sh

rm -rf ~/Library/Developer/Xcode/DerivedData/aerospork-*
rm -rf ./.xcode-build

# The ignored directories that hold a developer's own state, not build output.
git clean -ffxd -e .local -e .claude -e .serena -e .agents -e AGENTS.md

./generate.sh
