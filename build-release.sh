#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="aerospork-codesign-certificate"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

generate-git-hash() {
cat > Sources/Common/gitHashGenerated.swift <<EOF
public let gitHash = "$(git rev-parse HEAD)"
public let gitShortHash = "$(git rev-parse --short HEAD)"
EOF
}

#############
### BUILD ###
#############

./build-docs.sh
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity"

generate-git-hash
swift build -c release --arch arm64 --arch x86_64 --product aerospork # CLI

# todo: make xcodebuild use the same toolchain as swift
# toolchain="$(plutil -extract CFBundleIdentifier raw ~/Library/Developer/Toolchains/swift-6.1-RELEASE.xctoolchain/Info.plist)"
# xcodebuild -toolchain "$toolchain" \
# Unfortunately, Xcode 16 fails with:
#     2025-05-05 15:51:15.618 xcodebuild[4633:13690815] Writing error result bundle to /var/folders/s1/17k6s3xd7nb5mv42nx0sd0800000gn/T/ResultBundle_2025-05-05_15-51-0015.xcresult
#     xcodebuild: error: Could not resolve package dependencies:
#       <unknown>:0: warning: legacy driver is now deprecated; consider avoiding specifying '-disallow-use-new-driver'
#     <unknown>:0: error: unable to execute command: <unknown>

rm -rf .release && mkdir .release

xcode_configuration="Release"
xcodebuild -version
xcodebuild-pretty .release/xcodebuild.log clean build \
    -scheme AeroSpork \
    -destination "generic/platform=macOS" \
    -configuration "$xcode_configuration" \
    -derivedDataPath .xcode-build

git checkout .

cp -r ".xcode-build/Build/Products/$xcode_configuration/AeroSpork.app" .release
cp -r .build/apple/Products/Release/aerospork .release

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/aerospork

################
### VALIDATE ###
################

expected_layout=$(cat <<EOF
.release/AeroSpork.app
.release/AeroSpork.app/Contents
.release/AeroSpork.app/Contents/_CodeSignature
.release/AeroSpork.app/Contents/_CodeSignature/CodeResources
.release/AeroSpork.app/Contents/MacOS
.release/AeroSpork.app/Contents/MacOS/AeroSpace
.release/AeroSpork.app/Contents/Resources
.release/AeroSpork.app/Contents/Resources/default-config.toml
.release/AeroSpork.app/Contents/Resources/AppIcon.icns
.release/AeroSpork.app/Contents/Resources/Assets.car
.release/AeroSpork.app/Contents/Info.plist
.release/AeroSpork.app/Contents/PkgInfo
EOF
)

if test "$expected_layout" != "$(find .release/AeroSpork.app)"; then
    echo "!!! Expect/Actual layout don't match !!!"
    find .release/AeroSpork.app
    exit 1
fi

check-universal-binary() {
    if ! file "$1" | grep --fixed-string -q "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64"; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-universal-binary .release/AeroSpork.app/Contents/MacOS/AeroSpace
check-universal-binary .release/aerospork

check-contains-hash .release/AeroSpork.app/Contents/MacOS/AeroSpace
check-contains-hash .release/aerospork

codesign -v .release/AeroSpork.app
codesign -v .release/aerospork

############
### PACK ###
############

mkdir -p ".release/AeroSpork-v$build_version/manpage" && cp .man/*.1 ".release/AeroSpork-v$build_version/manpage"
cp -r ./legal ".release/AeroSpork-v$build_version/legal"
cp -r .shell-completion ".release/AeroSpork-v$build_version/shell-completion"
cd .release
    mkdir -p "AeroSpork-v$build_version/bin" && cp -r aerospork "AeroSpork-v$build_version/bin"
    cp -r AeroSpork.app "AeroSpork-v$build_version"
    zip -r "AeroSpork-v$build_version.zip" "AeroSpork-v$build_version"
cd -

#################
### Brew Cask ###
#################
for cask_name in aerospork aerospork-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --app-bundle-dir-name "AeroSpork.app" \
        --zip-uri ".release/AeroSpork-v$build_version.zip" \
        --build-version "$build_version"
done
