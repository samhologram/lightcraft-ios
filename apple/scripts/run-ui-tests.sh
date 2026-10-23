#!/usr/bin/env bash
# Run the unit tests, the screenshot scenario, the Photos test and the coverage tours on simulators: iPad first,
# iPhone second (apple/docs/COOKBOOK.md §7), and export each result's attachments (screenshots, notes, summaries).
#
# Usage: apple/scripts/run-ui-tests.sh [--ipad NAME_OR_UDID] [--iphone NAME_OR_UDID] [--only Target[/Class[/method]]]... [--skip-build]
#   defaults: --ipad "iPad Pro 11-inch (M5)" --iphone "iPhone 17 Pro"
# Output: apple/build/results/<device>-<test>.xcresult and apple/build/results/<device>-<test>/ (exported attachments).
# Each simulator gets two generated test photos (needs ImageMagick) and Photos access for the app before the run.
set -euo pipefail

IPAD="iPad Pro 11-inch (M5)"; IPHONE="iPhone 17 Pro"; ONLY=(); BUILD=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ipad) IPAD="$2"; shift 2 ;;
    --iphone) IPHONE="$2"; shift 2 ;;
    --only) ONLY+=("$2"); shift 2 ;;
    --skip-build) BUILD=0; shift ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

APPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APPLE_DIR"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DD=build/dd; OUT=build/results; mkdir -p "$OUT"
BUNDLE=ca.hologram.lightcraft

if [[ ${#ONLY[@]} -eq 0 ]]; then
  ONLY=(LightCraftTests LightCraftUITests/LightCraftUITests LightCraftUITests/DevicePhotosUITests
        LightCraftUITests/PanelTourUITests LightCraftUITests/ToolTourUITests LightCraftUITests/CommandTourUITests)
fi

if [[ "$BUILD" == 1 ]]; then
  xcodegen generate >/dev/null
  xcodebuild build-for-testing -scheme LightCraft -destination 'generic/platform=iOS Simulator' ARCHS=arm64 \
    CODE_SIGNING_ALLOWED=NO -derivedDataPath "$DD" > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log"; exit 1; }
fi

udid() { # name or UDID -> UDID of an available device
  if [[ "$1" =~ ^[0-9A-F-]{36}$ ]]; then echo "$1"; return; fi
  xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F-]{36}'
}

seed() { # boot, add test photos, install, grant Photos access
  local d="$1" tmp; tmp="$(mktemp -d)"
  xcrun simctl boot "$d" 2>/dev/null || true
  xcrun simctl bootstatus "$d" -b >/dev/null
  if command -v magick >/dev/null; then
    magick -size 3000x2000 gradient:orange-blue "$tmp/lc-test-1.jpg"
    magick -size 2000x3000 plasma:fractal "$tmp/lc-test-2.jpg"
    xcrun simctl addmedia "$d" "$tmp"/lc-test-*.jpg
  fi
  xcrun simctl install "$d" "$DD/Build/Products/Debug-iphonesimulator/LightCraft.app"
  xcrun simctl privacy "$d" grant photos "$BUNDLE" || true
  rm -rf "$tmp"
}

killall Simulator 2>/dev/null || true
STATUS=0
for device in "$IPAD" "$IPHONE"; do        # iPad first, iPhone second
  D="$(udid "$device")"; [[ -n "$D" ]] || { echo "no simulator named $device" >&2; exit 1; }
  kind=$([[ "$device" == iPad* ]] && echo ipad || echo iphone)
  echo "==> $device ($D)"
  seed "$D"
  for t in "${ONLY[@]}"; do
    name="$kind-$(echo "$t" | tr '/' '-')"
    rm -rf "$OUT/$name.xcresult" "$OUT/$name"
    echo "  -> $t"
    if ! xcodebuild test-without-building -scheme LightCraft -destination "id=$D" -derivedDataPath "$DD" \
        -resultBundlePath "$OUT/$name.xcresult" -only-testing:"$t" > "$OUT/$name.log" 2>&1; then
      STATUS=1; echo "     FAILED (see $OUT/$name.log)"
    fi
    xcrun xcresulttool export attachments --path "$OUT/$name.xcresult" --output-path "$OUT/$name" >/dev/null 2>&1 || true
  done
  xcrun simctl shutdown "$D" 2>/dev/null || true
done
echo "==> Results in $APPLE_DIR/$OUT (read every *-notes and *-tour-summary attachment: a green run can be hollow)"
exit $STATUS
