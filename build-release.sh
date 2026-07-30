#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

source ./script/signing-identity.sh

build_version="0.0.0-SNAPSHOT"
# Detected, not hardcoded. The old default was `aerospork-codesign-certificate`, a name that has
# never existed in any keychain -- so a plain `./build-release.sh` built everything and then died at
# the CLI signing step with "no identity found", after ~10 minutes of work.
codesign_identity=""
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done
if test -z "$codesign_identity"; then codesign_identity="$(default_signing_identity)"; fi
warn_if_only_app_store_distribution
# Fail here rather than after the build: signing is the last step, and discovering there is no
# identity then wastes the entire universal build.
if test -z "$codesign_identity"; then
    echo "No code-signing identity found in the keychain." > /dev/stderr
    echo "Create a 'Developer ID Application' certificate (required for notarization), or pass" > /dev/stderr
    echo "--codesign-identity <name>. See dev-docs/development.md for the signing setup." > /dev/stderr
    exit 1
fi
echo "Signing with: $codesign_identity"

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
# Shell completions are vendored in ./shell-completion (see build-shell-completion.sh). Building
# them here required complgen/rust, fish and bash >= 5, which broke the release on a stock macOS.

./generate.sh
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity"

generate-git-hash
swift build -c release --arch arm64 --arch x86_64 --product aerospork # CLI
# SwiftPM moved the universal product out of .build/apple/Products/Release (it is
# .build/out/Products/Release on Swift 6.x), so the old hardcoded path silently stopped existing and
# the `cp` below died. Ask the toolchain where it put the binary instead of guessing.
cli_bin_path="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path | tail -1)"

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
# `-project` is not optional, even though there is only one .xcodeproj here. Without it xcodebuild
# resolves `-scheme aerospork` against whatever it finds in the working directory, and this
# directory offers two things by that name: the app target in aerospork.xcodeproj, and the
# `aerospork` executable product in Package.swift. When it picks the package it builds a bare
# Mach-O, reports "BUILD SUCCEEDED", and the next line fails on a missing AeroSpork.app -- after
# the full universal build. Naming the project makes the choice deterministic.
xcodebuild-pretty .release/xcodebuild.log clean build \
    -project aerospork.xcodeproj \
    -scheme aerospork \
    -destination "generic/platform=macOS" \
    -configuration "$xcode_configuration" \
    -derivedDataPath .xcode-build

# Revert ONLY the file `generate-git-hash` stamped above. This used to be a bare `git checkout .`,
# which discards every uncommitted change in the working tree -- and the "guard" that was supposed
# to prevent that (script/check-uncommitted-files.sh) exits 0 after merely printing a warning.
git checkout -- Sources/Common/gitHashGenerated.swift

# -R, not -r: a framework's Versions/Current and top-level stubs are symlinks, and flattening
# them into regular files makes codesign fail with "bundle format is ambiguous".
cp -R ".xcode-build/Build/Products/$xcode_configuration/AeroSpork.app" .release
cp -r "$cli_bin_path/aerospork" .release

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" --options runtime --timestamp .release/aerospork

# Put the CLI INSIDE the app bundle, and ship that copy.
#
# A notarization ticket cannot be stapled to a bare Mach-O -- only to a bundle, .dmg or .pkg. So a
# standalone `bin/aerospork` is un-stapleable no matter how many times it is notarized, and Apple's
# own preflight agrees:
#     $ syspolicy_check distribution .release/aerospork
#     Notary Ticket Missing ... Severity: Fatal
# which in practice means first run needs a working network round trip to Apple, and fails without
# one. Inside the bundle it inherits the app's stapled ticket and works offline.
#
# `Contents/MacOS/` specifically: the bundle validation below rejects nested Mach-O anywhere else,
# because that is the classic notarization rejection.
# Sign Sparkle's nested code BEFORE the CLI and the outer bundle. Signing is inside-out: sealing
# the app first and then touching anything inside it invalidates the outer signature, which
# notarization rejects. Sparkle's XPC helpers each need their own signature.
if test -d .release/AeroSpork.app/Contents/Frameworks; then
    # Deepest first, so each nested bundle is sealed before the thing that contains it. Sparkle's
    # helpers live at fixed paths inside the framework, so they are named rather than globbed --
    # a glob also matched Versions/B/... and signed the same code twice through two paths, which
    # is how the framework ended up reported as an ambiguous bundle format.
    sparkle=.release/AeroSpork.app/Contents/Frameworks/Sparkle.framework
    for nested in \
        "$sparkle/Versions/Current/XPCServices/Downloader.xpc" \
        "$sparkle/Versions/Current/XPCServices/Installer.xpc" \
        "$sparkle/Versions/Current/Updater.app" \
        "$sparkle/Versions/Current/Autoupdate" \
        "$sparkle"
    do
        test -e "$nested" || continue
        codesign -s "$codesign_identity" --options runtime --timestamp --force "$nested"
    done
fi

cp .release/aerospork .release/AeroSpork.app/Contents/MacOS/aerospork-cli
# --force: the copy already carries the signature from the line above; codesign refuses to
# re-sign otherwise with "is already signed".
codesign -s "$codesign_identity" --options runtime --timestamp --force .release/AeroSpork.app/Contents/MacOS/aerospork-cli
# Re-sign the bundle: adding a file invalidates the enclosing signature and its CodeResources seal.
codesign -s "$codesign_identity" --options runtime --timestamp --force \
    --entitlements resources/aerospork.entitlements .release/AeroSpork.app
# --options runtime and --timestamp are not optional extras: notarization REJECTS a binary without
# the hardened runtime or a secure timestamp. The .app already gets both from ENABLE_HARDENED_RUNTIME
# in project.yml; the CLI is signed here by hand and was getting neither.

####################
### NOTARIZE     ###
####################
#
# Gatekeeper blocks a downloaded, un-notarized app on first launch. The cask used to paper over
# that with `xattr -d com.apple.quarantine`, which only works because Homebrew ran it locally —
# it does nothing for someone who downloads the zip directly, and Homebrew rejects casks that
# strip quarantine.
#
# Notarization needs a **Developer ID Application** certificate; an Apple Development cert cannot
# notarize. When one is not present we sign, skip notarization, and say so loudly, so a local
# release build still works and only *distribution* is blocked.
notarize() {
    local artifact="$1"
    if ! grep -q "^Developer ID Application" <<< "$codesign_identity"; then
        echo "!!! Skipping notarization: '$codesign_identity' is not a Developer ID Application certificate."
        echo "!!! The build is signed and runs locally, but Gatekeeper will block it on any other Mac."
        return 0
    fi
    if test -z "${AEROSPORK_NOTARY_PROFILE:-}"; then
        echo "!!! Skipping notarization: AEROSPORK_NOTARY_PROFILE is not set."
        echo "!!! Create one once. An App Store Connect API key is the better route -- it needs no"
        echo "!!! app-specific password, and the same key works for every project:"
        echo "!!!   xcrun notarytool store-credentials aerospork-notary \\"
        echo "!!!     --key <AuthKey_XXXXXXXXXX.p8> --key-id <key id> --issuer <issuer uuid>"
        echo "!!! Then: export AEROSPORK_NOTARY_PROFILE=aerospork-notary"
        return 0
    fi
    # notarytool accepts ONLY .zip / .pkg / .dmg -- handing it a bare .app bundle fails with
    # "must be a zip archive". So a bundle is zipped purely for transport; the ticket that comes
    # back is stapled to the original .app, and the archive is thrown away.
    #
    # `ditto -c -k --keepParent` rather than `zip -r`: it preserves the symlinks and extended
    # attributes inside a bundle, which plain zip mangles, and Apple documents it as the way to
    # package a bundle for the notary service.
    # This applies to a bare executable exactly as much as to a .app -- the CLI failed the same way
    # until this stopped keying on `-d`.
    local submission="$artifact" tmpdir=""
    case "$artifact" in
        *.zip | *.pkg | *.dmg) ;; # already a container the notary service accepts
        *)
            tmpdir="$(mktemp -d)"
            submission="$tmpdir/$(basename "$artifact").zip"
            ditto -c -k --keepParent "$artifact" "$submission"
            ;;
    esac

    echo "Submitting $artifact for notarization (this waits for Apple)..."
    # `notarytool submit --wait` exits 0 even when Apple returns "status: Invalid" -- so the script
    # used to sail past a rejection and die at `stapler` with "Record not found", which says nothing
    # about the cause. Check the status, and on failure print Apple's own issue list, which names
    # the offending binary and reason per architecture.
    local out submission_id
    out=$(xcrun notarytool submit "$submission" --keychain-profile "$AEROSPORK_NOTARY_PROFILE" --wait 2>&1) || true
    echo "$out"
    if ! grep -q "status: Accepted" <<< "$out"; then
        submission_id=$(sed -n 's/^ *id: \([0-9a-f-]\{36\}\).*/\1/p' <<< "$out" | head -1)
        echo "!!! Notarization FAILED. Apple's reasons:" > /dev/stderr
        if test -n "$submission_id"; then
            xcrun notarytool log "$submission_id" --keychain-profile "$AEROSPORK_NOTARY_PROFILE" > /dev/stderr || true
        fi
        exit 1
    fi

    # Stapling attaches the ticket so the artifact validates with no network. Only bundles can be
    # stapled; a bare executable is covered by the ticket but has nowhere to put it, so it needs an
    # online check on first run.
    if test -d "$artifact"; then xcrun stapler staple "$artifact"; fi
    if test -n "$tmpdir"; then rm -rf "$tmpdir"; fi
}

################
### VALIDATE ###
################

# This used to be a strict `find` == 13-line manifest compare, which exited 1 for a bundle that was
# perfectly fine: project.yml lists all of resources/ as target sources, so Xcode also copies
# PrivacyInfo.xcprivacy in. Any future resource broke the release build. Check the two things that
# actually matter instead: everything required is present, and nothing unsigned-executable snuck in.
required_paths=(
    Contents/MacOS/AeroSpork
    Contents/MacOS/aerospork-cli
    Contents/Info.plist
    Contents/PkgInfo
    Contents/Resources/default-config.toml
    Contents/Resources/AppIcon.icns
    Contents/Frameworks/Sparkle.framework
    Contents/Resources/Assets.car
    Contents/_CodeSignature/CodeResources
)
for required_path in "${required_paths[@]}"; do
    if ! test -e ".release/AeroSpork.app/$required_path"; then
        echo "!!! Missing from app bundle: $required_path !!!"
        find .release/AeroSpork.app
        exit 1
    fi
done

# Nested Mach-O code outside Contents/MacOS needs its own signature and is the classic
# notarization rejection. Extra *data* resources are harmless, so they are not an error.
#
# Contents/Frameworks is now legitimate: Sparkle ships as an XCFramework and brings its own
# Autoupdate and Updater.app helpers. So the check is no longer "is there nested code" -- it is
# "is every piece of nested code independently signed", which is what the notary service actually
# enforces. An unsigned stray still fails, which is the case the original check was written for.
while IFS= read -r bundle_file; do
    case "$bundle_file" in .release/AeroSpork.app/Contents/MacOS/*) continue ;; esac
    file -b "$bundle_file" | grep -q 'Mach-O' || continue
    if ! codesign -v --strict "$bundle_file" > /dev/null 2>&1; then
        echo "!!! Unsigned nested binary will fail notarization: $bundle_file !!!"
        codesign -dv "$bundle_file" 2>&1 | head -3
        exit 1
    fi
done < <(find .release/AeroSpork.app -type f)

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

# Sparkle fails soft. A build with no SUFeedURL simply never finds an update, silently, which is
# exactly what shipped the first time: INFOPLIST_KEY_SUFeedURL was dropped by Xcode because that
# prefix only supports keys Apple knows about, and nothing in the build noticed.
for su_key in SUFeedURL SUPublicEDKey; do
    if ! /usr/libexec/PlistBuddy -c "Print :$su_key" .release/AeroSpork.app/Contents/Info.plist > /dev/null 2>&1; then
        echo "!!! $su_key missing from Info.plist: this build can never find an update !!!"
        exit 1
    fi
done

check-universal-binary .release/AeroSpork.app/Contents/MacOS/AeroSpork
check-universal-binary .release/aerospork

check-contains-hash .release/AeroSpork.app/Contents/MacOS/AeroSpork
check-contains-hash .release/aerospork

codesign -v .release/AeroSpork.app
codesign -v .release/aerospork

# Notarize the .app before it is zipped, so the stapled ticket travels inside the archive and the
# app validates on a machine that is offline or behind a firewall.
notarize .release/AeroSpork.app

# The standalone .release/aerospork is deliberately NOT notarized separately. It is the same binary
# that was embedded at Contents/MacOS/aerospork-cli before the .app was notarized, so it is already
# covered -- and a bare Mach-O cannot be stapled anyway, which is the whole reason it moved inside.

############
### PACK ###
############

mkdir -p ".release/aerospork-v$build_version/manpage" && cp .man/*.1 ".release/aerospork-v$build_version/manpage"
cp -R ./legal ".release/aerospork-v$build_version/legal"
cp -R ./shell-completion ".release/aerospork-v$build_version/shell-completion"
cd .release
    cp -R AeroSpork.app "aerospork-v$build_version"
    # bin/aerospork is a RELATIVE SYMLINK into the bundle, not a copy. A second copy on disk would
    # be a bare Mach-O with no stapled ticket -- exactly what moving the CLI inside the bundle was
    # meant to avoid. The symlink resolves inside the extracted folder, so a direct download still
    # gets a working ./bin/aerospork.
    mkdir -p "aerospork-v$build_version/bin"
    ln -sf "../AeroSpork.app/Contents/MacOS/aerospork-cli" "aerospork-v$build_version/bin/aerospork"
    zip -ry "aerospork-v$build_version.zip" "aerospork-v$build_version"

    # A SECOND archive, for Sparkle only. The zip above is a distribution bundle: the .app sits
    # under aerospork-v$VERSION/ next to bin/, manpage/ and legal/. Sparkle refuses that outright
    # -- "No supported items ... only .app bundles are supported" -- because it expects the bundle
    # at the archive root. Pointing the appcast at the distribution zip produces a feed that every
    # client fails to install.
    #
    # ditto rather than zip: it preserves the bundle's internal symlinks, extended attributes and
    # the stapled notarization ticket, which plain zip mangles.
    ditto -c -k --keepParent AeroSpork.app "AeroSpork-$build_version.zip"
cd -

#################
### Brew Cask ###
#################
for cask_name in aerospork aerospork-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --app-bundle-dir-name "AeroSpork.app" \
        --zip-uri ".release/aerospork-v$build_version.zip" \
        --build-version "$build_version"
done
