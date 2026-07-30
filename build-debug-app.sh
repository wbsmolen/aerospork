#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

echo "Building debug .app bundle..."

# Build the executables using swift build
./generate.sh --ignore-xcodeproj
swift build
swift build --target AppBundleTests

# Clean and create .debug directory
rm -rf .debug && mkdir -p .debug

# Create .app bundle structure
APP_BUNDLE=".debug/AeroSpork-Debug.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
echo "Copying executable..."
cp .build/debug/aerosporkApp "$APP_BUNDLE/Contents/MacOS/AeroSporkApp"

# Sparkle. The executable links it as @rpath/Sparkle.framework/Versions/B/Sparkle, so without a
# copy inside the bundle the debug app does not start at all -- dyld kills it before main() with
# "Library not loaded". SwiftPM leaves the framework in .build, which the .app cannot reach.
#
# cp -R, never cp -r: the framework is a versioned bundle built out of symlinks, and -r replaces
# them with copies, which produces "bundle format is ambiguous".
echo "Copying Sparkle.framework..."
sparkle_src=".build/out/Products/Debug/Sparkle.framework"
if ! test -d "$sparkle_src"; then
    sparkle_src=$(find .build/artifacts -type d -name Sparkle.framework -path "*macos*" | head -1)
fi
if test -d "$sparkle_src"; then
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    cp -R "$sparkle_src" "$APP_BUNDLE/Contents/Frameworks/"
    # The release build gets this from LD_RUNPATH_SEARCH_PATHS in project.yml. SwiftPM does not
    # set it, so the debug binary searches @executable_path but never ../Frameworks, and dyld
    # fails even with the framework sitting right there. Ignore the error if it is already present.
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP_BUNDLE/Contents/MacOS/AeroSporkApp" 2>/dev/null || true
else
    echo "!!! Sparkle.framework not found; the debug app will not launch." > /dev/stderr
    exit 1
fi

# Copy Info.plist
echo "Copying Info.plist..."
cp resources/Info-Debug.plist "$APP_BUNDLE/Contents/Info.plist"

# Bundle the default config. Without it, Bundle.main lookup fails and Config.swift falls back to
# the #filePath baked in at build time -- which dies (or hangs) if the repo ever moves.
echo "Copying default config..."
cp resources/default-config.toml "$APP_BUNDLE/Contents/Resources/default-config.toml"

# Copy app icon if it exists (optional)
if [ -f "resources/AppIcon.icns" ]; then
    echo "Copying app icon..."
    cp resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Create PkgInfo file
echo "Creating PkgInfo..."
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Sign with a real identity, not ad-hoc. Ad-hoc signing derives the designated requirement from the
# binary's cdhash, so every rebuild looks like a different app to TCC and macOS makes you re-grant
# Accessibility each time. A cert-backed identity keeps the requirement stable across rebuilds.
# Detected from the keychain rather than hardcoded: a specific developer's certificate name is
# both personal data and useless on anyone else's machine.
source ./script/signing-identity.sh
codesign_identity="${AEROSPORK_CODESIGN_IDENTITY:-$(default_signing_identity)}"
if test -z "$codesign_identity"; then
    echo "No code-signing identity in the keychain; falling back to ad-hoc signing."
    echo "macOS will re-request Accessibility permission after every rebuild -- see dev-docs/development.md."
    codesign_identity="-"
fi
echo "Code signing bundle as '$codesign_identity'..."
codesign -s "$codesign_identity" -f --deep --entitlements resources/aerospork.entitlements "$APP_BUNDLE"

# Also copy CLI for convenience
echo "Copying CLI..."
cp .build/debug/aerospork .debug/aerospork

echo ""
echo "✅ Debug .app bundle created successfully!"
echo ""
echo "To launch:"
echo "  • Double-click: .debug/AeroSpork-Debug.app"
echo "  • Or from Terminal: open .debug/AeroSpork-Debug.app"
echo ""
echo "To view logs:"
echo "  • Open Console.app and filter by 'aerospork' or 'com.wbs.aerospork.debug'"
echo ""
echo "Config file location:"
echo "  • ~/.aerospork-debug.toml (will use bundled default if not exists)"
echo ""
