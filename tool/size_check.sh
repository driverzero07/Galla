#!/usr/bin/env bash
# Builds the release app and fails if it is over the size budget (Part 0:
# APK under 40 MB). Run from the project root:   bash tool/size_check.sh
#
# Optional crash reporting / privacy link at build time:
#   SUPABASE_URL=... SUPABASE_ANON_KEY=... [SENTRY_DSN=...] [PRIVACY_URL=...] \
#     bash tool/size_check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
LIMIT_MB=40

# Release builds need the server settings, and never the debug tools.
: "${SUPABASE_URL:?set SUPABASE_URL}"
: "${SUPABASE_ANON_KEY:?set SUPABASE_ANON_KEY}"
DEFINES=("--dart-define=SUPABASE_URL=$SUPABASE_URL"
         "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
         "--dart-define=GALLA_DEBUG_TOOLS=false")
[ -n "${SENTRY_DSN:-}" ] && DEFINES+=("--dart-define=SENTRY_DSN=$SENTRY_DSN")
[ -n "${PRIVACY_URL:-}" ] && DEFINES+=("--dart-define=PRIVACY_URL=$PRIVACY_URL")

mkdir -p build/symbols
# Split per CPU: a phone downloads only its own part. Obfuscation + symbols
# keep the size down; keep build/symbols to read crash stack traces.
flutter build apk --release --split-per-abi --obfuscate \
  --split-debug-info=build/symbols "${DEFINES[@]}"
flutter build appbundle --release --obfuscate \
  --split-debug-info=build/symbols "${DEFINES[@]}"

fail=0
for apk in build/app/outputs/flutter-apk/*-release.apk; do
  [ -f "$apk" ] || continue
  bytes=$(stat -c%s "$apk" 2>/dev/null || stat -f%z "$apk")
  mb=$(awk "BEGIN{printf \"%.1f\", $bytes/1048576}")
  echo "$apk  ${mb} MB"
  awk "BEGIN{exit !($bytes/1048576 > $LIMIT_MB)}" && { echo "  OVER ${LIMIT_MB} MB"; fail=1; }
done
echo "App bundle for Play: build/app/outputs/bundle/release/app-release.aab"
[ "$fail" -eq 0 ] && echo "Size check passed (under ${LIMIT_MB} MB)." || exit 1
