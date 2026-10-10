#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Runtime
TASK_TEMP=$(mktemp -d)
trap 'rm -rf "$TASK_TEMP"' EXIT
fetch() {
    curl --fail --location --retry 3 "$1" --output "$2"
    printf '%s  %s\n' "$3" "$2" | shasum -a 256 -c -
}
fetch 'https://repo.maven.apache.org/maven2/net/sourceforge/plantuml/plantuml/1.2025.0/plantuml-1.2025.0.jar' "$TASK_TEMP/plantuml.jar" f37f171fe61ba4522ea469ec5732b8b64defd6b2bf548b75bb94881b5001c1da
fetch 'https://repo.maven.apache.org/maven2/net/sourceforge/plantuml/plantuml/1.2025.0/plantuml-1.2025.0-sources.jar' "$TASK_TEMP/sources.jar" fcbb18883ac746e9c71ff0a991d869199f5d3daaac240813b301813b59fd7f50
fetch 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.6%2B7/OpenJDK21U-jre_aarch64_mac_hotspot_21.0.6_7.tar.gz' "$TASK_TEMP/jre.tar.gz" 9b792bbd408676483caaeb619439190abf1552fe11ab05b19c80d408e5f49c25
cp "$TASK_TEMP/plantuml.jar" Runtime/plantuml-1.2025.0.jar
cp "$TASK_TEMP/sources.jar" Runtime/plantuml-1.2025.0-sources.jar
tar -xzf "$TASK_TEMP/jre.tar.gz" -C Runtime
Runtime/jdk-21.0.6+7-jre/Contents/Home/bin/java -Djava.awt.headless=true -jar Runtime/plantuml-1.2025.0.jar -license > Runtime/PlantUML-LICENSE.txt
mkdir -p Runtime/ThirdPartyNotices
for NOTICE in COPYING LICENSE LICENSE.txt; do
    unzip -p Runtime/plantuml-1.2025.0.jar "META-INF/$NOTICE" > "Runtime/ThirdPartyNotices/$NOTICE"
done
curl --fail --location --retry 3 'https://www.gnu.org/licenses/gpl-3.0.txt' --output Runtime/ThirdPartyNotices/GPL-3.0.txt
