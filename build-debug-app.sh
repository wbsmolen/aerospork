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
APP_BUNDLE=".debug/AeroSporkApp.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
echo "Copying executable..."
cp .build/debug/AeroSporkApp "$APP_BUNDLE/Contents/MacOS/AeroSporkApp"

# Copy Info.plist
echo "Copying Info.plist..."
cp resources/Info-Debug.plist "$APP_BUNDLE/Contents/Info.plist"

# Note: Default config removed with docs cleanup
# Users should create their own ~/.aerospork-debug.toml

# Copy app icon if it exists (optional)
if [ -f "resources/AppIcon.icns" ]; then
    echo "Copying app icon..."
    cp resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Create PkgInfo file
echo "Creating PkgInfo..."
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc code sign the bundle for double-click launch
echo "Code signing bundle..."
codesign -s - -f --deep --entitlements resources/AeroSpork.entitlements "$APP_BUNDLE"

# Also copy CLI for convenience
echo "Copying CLI..."
cp .build/debug/aerospork .debug/aerospork

echo ""
echo "✅ Debug .app bundle created successfully!"
echo ""
echo "To launch:"
echo "  • Double-click: .debug/AeroSporkApp.app"
echo "  • Or from Terminal: open .debug/AeroSporkApp.app"
echo ""
echo "To view logs:"
echo "  • Open Console.app and filter by 'aerospork' or 'com.wbs.aerospork.debug'"
echo ""
echo "Config file location:"
echo "  • ~/.aerospork.toml (will use default if not exists)"
echo ""
