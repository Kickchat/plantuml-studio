#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

TASK_VERSION=$(python3 scripts/version.py show)
TASK_APP="$PWD/dist/PlantUML Studio.app"
TASK_OUTPUT="$PWD/dist/PlantUMLStudio-$TASK_VERSION-arm64.dmg"
if [ ! -d "$TASK_APP" ]; then
    printf 'Build the application with scripts/build.sh first.\n' >&2
    exit 1
fi
codesign --verify --deep --strict "$TASK_APP"
TASK_STAGING=$(mktemp -d "$PWD/dist/.dmg.XXXXXXXX")
trap 'rm -rf "$TASK_STAGING"' EXIT
mkdir "$TASK_STAGING/contents"
ditto "$TASK_APP" "$TASK_STAGING/contents/PlantUML Studio.app"
ln -s /Applications "$TASK_STAGING/contents/Applications"
hdiutil create -volname 'PlantUML Studio' -srcfolder "$TASK_STAGING/contents" \
    -format UDZO -ov "$TASK_STAGING/PlantUMLStudio.dmg"
hdiutil verify "$TASK_STAGING/PlantUMLStudio.dmg"
mv -f "$TASK_STAGING/PlantUMLStudio.dmg" "$TASK_OUTPUT"
printf 'DMG: %s\n' "$TASK_OUTPUT"
