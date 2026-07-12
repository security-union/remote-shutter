#!/bin/bash
# Renders localized App Store screenshots for every locale in translations.js
# and copies them into fastlane/screenshots/<locale>/. Fully deterministic —
# strings come from the static translations.js table, no AI/API calls.
# Usage: ./ship-locales.sh [locale ...]   (default: all locales)
set -euo pipefail
cd "$(dirname "$0")"
FASTLANE="$(cd ../../fastlane/screenshots && pwd)"

LOCALES=("$@")
if [ ${#LOCALES[@]} -eq 0 ]; then
  LOCALES=(en-US da de-DE es-MX fr-FR it ja ko pt-BR zh-Hans)
fi

for L in "${LOCALES[@]}"; do
  echo "=== $L ==="
  node render.mjs --locale "$L"
  SRC="out"; [ "$L" != "en-US" ] && SRC="out/$L"
  mkdir -p "$FASTLANE/$L"
  # Replace all phone/iPad screenshots (keeps Watch captures); the event card
  # is not a fastlane asset.
  find "$FASTLANE/$L" -maxdepth 1 \( -name "*_APP_IPHONE_*.png" -o -name "*_APP_IPAD_*.png" -o -name "*_APP_DESKTOP_*.png" \) -delete
  find "$SRC" -maxdepth 1 -name "*_APP_*.png" -exec cp {} "$FASTLANE/$L/" \;
  echo "shipped $(find "$SRC" -maxdepth 1 -name '*_APP_*.png' | wc -l | tr -d ' ') files -> fastlane/screenshots/$L/"
done
