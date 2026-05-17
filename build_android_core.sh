#!/bin/bash

# Lightning Android Core Build Script
# Requirements: Go 1.21+, gomobile, Android NDK

set -e

# Configuration
export GO111MODULE=on
export GOPROXY=https://goproxy.cn,direct
export PATH=$PATH:/d/GO/bin:/c/Users/admin/go/bin

# Android NDK path (adjust if necessary)
export ANDROID_HOME="/d/SDK"
export ANDROID_SDK_ROOT="/d/SDK"
export ANDROID_NDK_HOME="/d/SDK/ndk/26.2.11394342"

CORE_DIR="go_core"
OUTPUT_DIR="android/app/libs"
TARGET="libxray.aar"

echo "Building Go core for Android..."

# Create libs directory if not exists
mkdir -p $OUTPUT_DIR

# Run gomobile bind
cd $CORE_DIR
# Build for arm64, armeabi-v7a, and x86_64 (amd64) to support all modern devices
gomobile bind -v -target="android/arm,android/arm64,android/amd64" -androidapi 24 -ldflags="-s -w" -trimpath -o ../$OUTPUT_DIR/$TARGET .

echo "Build successful: $OUTPUT_DIR/$TARGET"
