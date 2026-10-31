#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"

echo "=================================================="
echo " Starting SafeCircle Android Emulator (Mac M2 GUI)"
echo "=================================================="

# Check if emulator is already running
if adb devices | grep -q "emulator-"; then
    echo "An emulator is already running. Connected devices:"
    adb devices
else
    echo "Launching SafeCircleM2 AVD with visible phone display..."
    "$ANDROID_HOME/emulator/emulator" -avd SafeCircleM2 -gpu swiftshader_indirect &
    echo "Waiting for emulator to boot up..."
    adb wait-for-device
    while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
        sleep 2
    done
    echo "Emulator boot completed."
fi

echo "Installing latest SafeCircle APK..."
APK="$DIR/mobile/build/app/outputs/flutter-apk/app-debug.apk"
if [ -f "$APK" ]; then
    adb install -r "$APK"
    echo "Launching SafeCircle app..."
    adb shell monkey -p com.example.safecircle -c android.intent.category.LAUNCHER 1
    echo "SafeCircle is now running on your emulator window!"
else
    echo "APK not found at $APK. Build it with: cd mobile && flutter build apk --debug"
fi
