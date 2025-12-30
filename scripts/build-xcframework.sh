#!/bin/bash
#
# Build AquaZig XCFramework for macOS
#
# This script builds the AquaZig library for multiple architectures
# and packages them into an XCFramework for use with Swift Package Manager.
#
# Usage: ./scripts/build-xcframework.sh
#
# Output: build/AquaZig.xcframework/
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

echo "==================================="
echo "Building AquaZig XCFramework"
echo "==================================="
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/macos-arm64"
mkdir -p "$BUILD_DIR/macos-x86_64"
mkdir -p "$BUILD_DIR/macos-universal"

cd "$PROJECT_DIR"

# Build for arm64 (Apple Silicon)
echo "Building for arm64-macos..."
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast
cp zig-out/lib/libaquazig.dylib "$BUILD_DIR/macos-arm64/"

# Build for x86_64 (Intel)
echo "Building for x86_64-macos..."
zig build -Dtarget=x86_64-macos -Doptimize=ReleaseFast
cp zig-out/lib/libaquazig.dylib "$BUILD_DIR/macos-x86_64/"

# Create universal binary with lipo
echo "Creating universal binary..."
lipo -create \
    "$BUILD_DIR/macos-arm64/libaquazig.dylib" \
    "$BUILD_DIR/macos-x86_64/libaquazig.dylib" \
    -output "$BUILD_DIR/macos-universal/libaquazig.dylib"

# Verify universal binary
echo "Verifying universal binary..."
lipo -info "$BUILD_DIR/macos-universal/libaquazig.dylib"

# Create XCFramework
echo "Creating XCFramework..."
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/macos-universal/libaquazig.dylib" \
    -headers "$PROJECT_DIR/include" \
    -output "$BUILD_DIR/AquaZig.xcframework"

echo ""
echo "==================================="
echo "XCFramework created successfully!"
echo "==================================="
echo ""
echo "Output: $BUILD_DIR/AquaZig.xcframework/"
echo ""

# Copy modulemap for Swift module import
echo "Adding modulemap..."
cp "$PROJECT_DIR/include/module.modulemap" "$BUILD_DIR/AquaZig.xcframework/macos-arm64_x86_64/Headers/"

# Show framework info
echo "Framework contents:"
ls -la "$BUILD_DIR/AquaZig.xcframework/"
