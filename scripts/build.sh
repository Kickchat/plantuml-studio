#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox
mkdir -p dist
TASK_STAGING=$(mktemp -d "$PWD/dist/.build.XXXXXXXX")
trap 'rm -rf "$TASK_STAGING"' EXIT
APP="$TASK_STAGING/PlantUML Studio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PlantUMLStudio "$APP/Contents/MacOS/PlantUMLStudio"
cp -R Runtime "$APP/Contents/Resources/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
TASK_LOGO="Assets/AppLogo.png"
if [ ! -f "$TASK_LOGO" ]; then TASK_LOGO="Assets/PlantUML App Icon.png"; fi
if [ ! -f "$TASK_LOGO" ]; then TASK_LOGO="Assets/image.png"; fi
if [ -f "$TASK_LOGO" ]; then
    ./scripts/build-icon.sh "$TASK_LOGO" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP/Contents/Info.plist"
fi
codesign --force --deep --sign - "$APP"
if [ -d "$PWD/dist/PlantUML Studio.app" ]; then
    mv "$PWD/dist/PlantUML Studio.app" "$TASK_STAGING/previous.app"
fi
mv "$APP" "$PWD/dist/PlantUML Studio.app"
printf 'Application: %s\n' "$PWD/dist/PlantUML Studio.app"
