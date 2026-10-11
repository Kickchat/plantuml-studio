#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for TASK_REQUIRED in RELEASE_TAG DEVELOPER_ID_APPLICATION APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD SPARKLE_PRIVATE_KEY_FILE UPDATE_BASE_URL SPARKLE_PUBLIC_KEY; do
  if [ -z "${!TASK_REQUIRED:-}" ]; then printf 'Missing release setting: %s\n' "$TASK_REQUIRED" >&2; exit 1; fi
done
python3 scripts/version.py check --tag "$RELEASE_TAG"
export UPDATE_FEED_URL="${UPDATE_BASE_URL%/}/stable/appcast.xml"
swift -module-cache-path "$PWD/.build/ModuleCache" scripts/verify-key.swift "$SPARKLE_PRIVATE_KEY_FILE"
./scripts/build.sh
APP="$PWD/dist/PlantUML Studio.app"
python3 scripts/sign-release.py "$APP"
./scripts/smoke.sh
TASK_NOTARY_ZIP="$RUNNER_TEMP/notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$TASK_NOTARY_ZIP"
# notarytool consumes credentials from environment via a temporary keychain profile.
xcrun notarytool store-credentials PlantUMLStudio-notary --keychain "$RUNNER_TEMP/release.keychain-db" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
xcrun notarytool submit "$TASK_NOTARY_ZIP" --keychain "$RUNNER_TEMP/release.keychain-db" --keychain-profile PlantUMLStudio-notary --wait --output-format json > "$RUNNER_TEMP/notary-result.json"
python3 - "$RUNNER_TEMP/notary-result.json" <<'PY'
import json,sys
if json.load(open(sys.argv[1])).get('status') != 'Accepted':
    raise SystemExit('Apple notarization did not accept this release')
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
mkdir -p dist/updates
TASK_VERSION=$(python3 scripts/version.py show)
TASK_ARCHIVE="PlantUMLStudio-$TASK_VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/updates/$TASK_ARCHIVE"
git log -20 --pretty=format:'- %s' > "dist/updates/PlantUMLStudio-$TASK_VERSION.md"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" --maximum-deltas 0 --embed-release-notes --download-url-prefix "${UPDATE_BASE_URL%/}/stable/" dist/updates
python3 scripts/validate-appcast.py dist/updates/appcast.xml --archive "dist/updates/$TASK_ARCHIVE" --base-url "${UPDATE_BASE_URL%/}/stable/"
.build/artifacts/sparkle/Sparkle/bin/sign_update --verify --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" dist/updates/appcast.xml
shasum -a 256 "dist/updates/$TASK_ARCHIVE" > dist/updates/SHA256SUMS
