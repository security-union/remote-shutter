#!/bin/bash
# Renders localized App Store screenshots for every locale in translations.js
# and copies them into fastlane/screenshots/<locale>/. Fully deterministic —
# strings come from the static translations.js table, no AI/API calls.
#
# Usage: ./ship-locales.sh [-p platforms] [locale ...]
#   -p platforms  comma-separated subset to regenerate: iphone,ipad,mac,banner
#                 (default: all). Only the selected platforms' files are
#                 replaced in fastlane/screenshots/<locale>/.
#   locale ...    locales to render (default: all 10).
# Examples:
#   ./ship-locales.sh                     # everything, all locales
#   ./ship-locales.sh -p mac              # only Mac screenshots, all locales
#   ./ship-locales.sh -p iphone,ipad ja   # iPhone+iPad, Japanese only
set -euo pipefail
cd "$(dirname "$0")"
FASTLANE="$(cd ../../fastlane/screenshots && pwd)"
# Mac screenshots ship to a separate tree: deliver uploads everything in its
# screenshots_path to ONE platform, and APP_DESKTOP display types are invalid
# on the iOS version (and iPhone/iPad types on macOS).
FASTLANE_MAC="$(cd ../../fastlane && pwd)/screenshots_mac"

PLATFORMS=""
while getopts "p:" opt; do
  case $opt in
    p) PLATFORMS="$OPTARG" ;;
    *) echo "usage: $0 [-p iphone,ipad,mac,banner] [locale ...]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

LOCALES=("$@")
if [ ${#LOCALES[@]} -eq 0 ]; then
  LOCALES=(en-US da de-DE es-MX fr-FR it ja ko pt-BR zh-Hans ru hi vi ms tr)
fi

# Map platform names to the fastlane filename patterns they own.
patterns_for() {
  local plats="$1" out=()
  if [ -z "$plats" ]; then
    out=("*_APP_IPHONE_*.png" "*_APP_IPAD_*.png" "*_APP_DESKTOP_*.png")
  else
    IFS=',' read -ra PS <<< "$plats"
    for p in "${PS[@]}"; do
      case "$p" in
        iphone)      out+=("*_APP_IPHONE_*.png") ;;
        ipad)        out+=("*_APP_IPAD_*.png") ;;
        mac|desktop) out+=("*_APP_DESKTOP_*.png") ;;
        banner)      ;; # event card is uploaded manually, not a fastlane asset
        *) echo "unknown platform: $p" >&2; exit 1 ;;
      esac
    done
  fi
  printf '%s\n' "${out[@]}"
}
PATTERNS=()
while IFS= read -r pat; do [ -n "$pat" ] && PATTERNS+=("$pat"); done < <(patterns_for "$PLATFORMS")

for L in "${LOCALES[@]}"; do
  echo "=== $L ==="
  node render.mjs --locale "$L" ${PLATFORMS:+--plans "$PLATFORMS"}
  SRC="out"; [ "$L" != "en-US" ] && SRC="out/$L"
  # Replace only the selected platforms' screenshots (keeps Watch captures;
  # the event card is not a fastlane asset).
  SHIPPED=0
  for pat in "${PATTERNS[@]}"; do
    DEST="$FASTLANE/$L"
    [ "$pat" = "*_APP_DESKTOP_*.png" ] && DEST="$FASTLANE_MAC/$L"
    mkdir -p "$DEST"
    find "$DEST" -maxdepth 1 -name "$pat" -delete
    find "$SRC" -maxdepth 1 -name "$pat" -exec cp {} "$DEST/" \;
    N=$(find "$SRC" -maxdepth 1 -name "$pat" | wc -l | tr -d ' ')
    SHIPPED=$((SHIPPED + N))
  done
  echo "shipped $SHIPPED files -> fastlane/screenshots[_mac]/$L/"
done
