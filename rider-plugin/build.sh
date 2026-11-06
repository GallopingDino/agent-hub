#!/bin/bash
# Builds the plugin jar with the JDK bundled in Rider; no Gradle needed.
set -euo pipefail

readonly RIDER="/Applications/Rider.app/Contents"
readonly ROOT="$(cd "$(dirname "$0")" && pwd)"
readonly OUT="$ROOT/out"
readonly JAR="$OUT/agent-tabs.jar"

classpath=$(find "$RIDER/lib" "$RIDER/plugins/terminal" -name '*.jar' | tr '\n' ':')

sources=()
while IFS= read -r -d '' source; do
    sources+=("$source")
done < <(find "$ROOT/src" -name '*.java' -print0)

rm -rf "$OUT"
mkdir -p "$OUT/classes"

"$RIDER/jbr/Contents/Home/bin/javac" --release 21 -nowarn -cp "$classpath" -d "$OUT/classes" "${sources[@]}"
cp -R "$ROOT/resources/." "$OUT/classes/"
(cd "$OUT/classes" && zip -qr "$JAR" .)

echo "$JAR"
