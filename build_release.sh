#!/bin/bash
set -e

echo "============================================================"
echo "[NUCLEAR BUILD] Starting Pure Release Build Workflow..."
echo "============================================================"

# 1. Rebuild Go Core (Physical Overwrite)
echo "[1/4] Rebuilding Go Core (.aar)..."
# Assuming build_android_core.sh exists or using the gomobile command directly
cd go_core
gomobile bind -v -target="android/arm,android/arm64,android/amd64" -androidapi 24 -ldflags="-s -w" -trimpath -o ../android/app/libs/libxray.aar .
cd ..

# 2. Deep Clean Flutter
echo "[2/4] Flutter Deep Cleaning..."
flutter clean

# 3. Deep Clean Android (Smash Gradle Cache)
echo "[3/4] Android Deep Cleaning..."
cd android
./gradlew clean
cd ..

# 4. Final APK Build (Split per ABI)
echo "[4/4] Executing Final Release Build..."
flutter build apk --release --split-per-abi

echo "============================================================"
echo "[SUCCESS] Nuclear build completed successfully!"
echo "Artifacts: android/app/build/outputs/apk/release/"
echo "============================================================"
