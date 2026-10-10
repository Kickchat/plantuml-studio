#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/Smoke
PLANTUML_STUDIO_SMOKE_DIR="$PWD/.build/Smoke" "dist/PlantUML Studio.app/Contents/MacOS/PlantUMLStudio"
cat .build/Smoke/result.json
