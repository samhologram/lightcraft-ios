#!/usr/bin/env bash
# Run the unit tests, the screenshot scenario, the Photos test and the coverage tours on simulators: iPad first,
# iPhone second (apple/docs/COOKBOOK.md §7), and export each result's attachments (screenshots, notes, summaries).
#
# Usage: apple/scripts/run-ui-tests.sh [--ipad NAME_OR_UDID] [--iphone NAME_OR_UDID] [--device ipad|iphone|both]
#        [--photos denied|limited|granted] [--only Target[/Class[/method]]]... [--skip-build] [--no-screenshots]
#   defaults: the shared devices --ipad 81A653B3-… (iPad Pro 11-inch (M5)) --iphone FF7E37C5-… (iPhone 17) --device both
#   Photos permission per test: methods named *Denied* run with access revoked, *Limited* with it reset (the test
#   picks "Select Photos..." in the system prompt; simctl cannot set limited directly), all others granted.
#   --photos forces one state for every test instead. The expected state is passed to the tests (LC_EXPECT_PHOTOS)
#   so a denied/limited test that cannot reach its state FAILS instead of being skipped (a skip counts as a pass).
#   Class-level DevicePhotosUITests targets are expanded into one run per method. Skipped tests are flagged.
#   --no-screenshots: tests attach no screenshots (LC_NO_SCREENSHOTS=1); notes and summaries are kept.
#   SIM_LOCK overrides the simulator lock directory (default /Users/samuelhalle/Code/CraftApps/.sim.lock).
# Output: apple/build/results/<device>-<test>.xcresult and apple/build/results/<device>-<test>/ (exported attachments).
# Each simulator gets two generated test photos (needs ImageMagick) and Photos access for the app before the run.
set -euo pipefail

IPAD=81A653B3-9027-4C16-8335-320CB937C66C; IPHONE=FF7E37C5-12E6-483D-8887-D09D18EEB4A4; ONLY=(); BUILD=1; DEVICE=both; PHOTOS=""; NOSHOTS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ipad) IPAD="$2"; shift 2 ;;
    --iphone) IPHONE="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --photos) PHOTOS="$2"; shift 2 ;;
    --only) ONLY+=("$2"); shift 2 ;;
    --skip-build) BUILD=0; shift ;;
    --no-screenshots) NOSHOTS=1; shift ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$DEVICE" in ipad|iphone|both) ;; *) echo "--device must be ipad|iphone|both" >&2; exit 2 ;; esac
case "$PHOTOS" in ""|denied|limited|granted) ;; *) echo "--photos must be denied|limited|granted" >&2; exit 2 ;; esac

APPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APPLE_DIR"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DD=build/dd; OUT=build/results; mkdir -p "$OUT"
BUNDLE=ca.hologram.lightcraft

methods_of() { # <Class> -> its test method names, one per line
  grep -ho 'func test[A-Za-z0-9_]*' "LightCraftUITests/$1.swift" | sed 's/^func //' | sort -u
}

if [[ ${#ONLY[@]} -eq 0 ]]; then
  ONLY=(LightCraftTests)
  for cls in LightCraftUITests DevicePhotosUITests PresetImportUITests PanelTourUITests ToolTourUITests CommandTourUITests; do
    found=0
    while IFS= read -r m; do
      [[ -n "$m" ]] || continue
      ONLY+=("LightCraftUITests/$cls/$m"); found=1
    done < <(methods_of "$cls")
    [[ "$found" == 1 ]] || { echo "no test methods found for $cls" >&2; exit 1; }
  done
fi

# Class-level DevicePhotosUITests targets run per method so each gets its own Photos state.
EXPANDED=()
for t in "${ONLY[@]}"; do
  if [[ "$t" == LightCraftUITests/DevicePhotosUITests ]]; then
    while IFS= read -r m; do
      if [[ -n "$m" ]]; then EXPANDED+=("$t/$m"); fi
    done < <(methods_of DevicePhotosUITests)
  else
    EXPANDED+=("$t")
  fi
done
ONLY=("${EXPANDED[@]}")

if [[ "$BUILD" == 1 ]]; then
  xcodegen generate >/dev/null
  xcodebuild build-for-testing -scheme LightCraft -destination 'generic/platform=iOS Simulator' ARCHS=arm64 \
    CODE_SIGNING_ALLOWED=NO -derivedDataPath "$DD" > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log"; exit 1; }
fi

udid() { # name or UDID -> UDID of an available device
  if [[ "$1" =~ ^[0-9A-F-]{36}$ ]]; then echo "$1"; return; fi
  xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F-]{36}' || true
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
  # Preset fixture for PresetImportUITests: our own minimal Lightroom-style XMP, in the app's Documents
  # (shown in the document picker under On My iPad/iPhone > LightCraft; the app sets UIFileSharingEnabled).
  local container
  if ! container="$(xcrun simctl get_app_container "$d" "$BUNDLE" data 2>&1)" || [[ -z "$container" ]]; then
    echo "error: cannot find the data container of $BUNDLE on $d (install failed or wrong bundle id): $container" >&2
    exit 1
  fi
  local docs="$container/Documents"
  mkdir -p "$docs"
  cat > "$docs/TestWarm.xmp" <<'XMP'
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
    crs:PresetType="Normal"
    crs:UUID="6C0F5E52-1D0B-4C57-9B7A-5A1E7C0D0001"
    crs:Version="15.0"
    crs:ProcessVersion="15.4"
    crs:HasSettings="True"
    crs:Exposure2012="+1.00"
    crs:Temperature="6500">
   <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">LC Test Warm</rdf:li></rdf:Alt></crs:Name>
   <crs:Group><rdf:Alt><rdf:li xml:lang="x-default">LC Tests</rdf:li></rdf:Alt></crs:Group>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
XMP
  rm -rf "$tmp"
}

set_photos() { # <udid> <denied|limited|granted>
  case "$2" in
    denied) xcrun simctl privacy "$1" revoke photos "$BUNDLE" || true ;;
    limited) xcrun simctl privacy "$1" reset photos "$BUNDLE" || true ;;
    *) xcrun simctl privacy "$1" grant photos "$BUNDLE" || true ;;
  esac
}

LOCK="${SIM_LOCK:-/Users/samuelhalle/Code/CraftApps/.sim.lock}"
HAVE_LOCK=0
release_lock() { if [[ "$HAVE_LOCK" == 1 ]]; then rm -rf "$LOCK"; HAVE_LOCK=0; fi; }
trap release_lock EXIT
trap 'exit 130' INT TERM
acquire_lock() {
  local announced=0 owner pid marker
  until mkdir "$LOCK" 2>/dev/null; do
    owner="$(tr '\n' ' ' < "$LOCK/owner" 2>/dev/null || true)"
    pid="$(head -1 "$LOCK/owner" 2>/dev/null | grep -oE '^[0-9]+' || true)"
    # Reclaim a lock whose owner process is gone, or a stale one (owner file > 90 min old, no simulator booted).
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      echo "reclaiming sim lock: owner pid $pid is gone ($owner)"; rm -rf "$LOCK"; continue
    fi
    marker="$LOCK/owner"; [[ -e "$marker" ]] || marker="$LOCK"
    if [[ -n "$(find "$marker" -maxdepth 0 -mmin +90 2>/dev/null || true)" ]] \
       && ! xcrun simctl list devices booted 2>/dev/null | grep -q Booted; then
      echo "reclaiming sim lock: older than 90 min and no simulator booted ($owner)"; rm -rf "$LOCK"; continue
    fi
    if [[ "$announced" == 0 ]]; then echo "waiting for ${owner:-unknown owner} (lock $LOCK)"; announced=1; fi
    sleep 20
  done
  HAVE_LOCK=1
  printf '%s\nLightCraft %s\n' "$$" "$(date)" > "$LOCK/owner"
}

STATUS=0
SKIPPED=()
DEVICES=()
[[ "$DEVICE" != iphone ]] && DEVICES+=("$IPAD")
[[ "$DEVICE" != ipad ]] && DEVICES+=("$IPHONE")
for device in "${DEVICES[@]}"; do        # iPad first, iPhone second
  D="$(udid "$device" || true)"; [[ -n "$D" ]] || { echo "no simulator named $device" >&2; exit 1; }
  kind=$([[ "$device" == "$IPAD" ]] && echo ipad || echo iphone)
  echo "==> $device ($D)"
  acquire_lock
  killall Simulator 2>/dev/null || true
  seed "$D"
  for t in "${ONLY[@]}"; do
    name="$kind-$(echo "$t" | tr '/' '-')"
    rm -rf "$OUT/$name.xcresult" "$OUT/$name"
    echo "  -> $t"
    state="${PHOTOS:-granted}"
    if [[ -z "$PHOTOS" ]]; then
      case "$t" in *Denied*) state=denied ;; *Limited*) state=limited ;; esac
    fi
    set_photos "$D" "$state"
    expect=""   # tests fail (not skip) when they cannot reach the state they exist to check
    case "$t" in *Denied*|*Limited*) expect="$state" ;; esac
    noshots=""; [[ "$NOSHOTS" == 1 ]] && noshots=1
    # A previous test's app still running can stall the next app.launch() at "Terminate".
    xcrun simctl terminate "$D" "$BUNDLE" 2>/dev/null || true
    if ! env TEST_RUNNER_LC_EXPECT_PHOTOS="$expect" TEST_RUNNER_LC_NO_SCREENSHOTS="$noshots" \
        xcodebuild test-without-building -scheme LightCraft -destination "id=$D" -derivedDataPath "$DD" \
        -test-timeouts-enabled YES -maximum-test-execution-time-allowance 1800 \
        -resultBundlePath "$OUT/$name.xcresult" -only-testing:"$t" > "$OUT/$name.log" 2>&1; then
      STATUS=1; echo "     FAILED (see $OUT/$name.log)"
    fi
    if grep -qE "Test [Cc]ase .* skipped" "$OUT/$name.log" 2>/dev/null; then
      echo "     SKIPPED (a skip is not a pass: see $OUT/$name.log)"; SKIPPED+=("$kind $t")
    fi
    xcrun xcresulttool export attachments --path "$OUT/$name.xcresult" --output-path "$OUT/$name" >/dev/null 2>&1 || true
  done
  # Leave no compiled app behind on the shared simulators.
  xcrun simctl uninstall "$D" "$BUNDLE" 2>/dev/null || true
  xcrun simctl uninstall "$D" "$BUNDLE.uitests.xctrunner" 2>/dev/null || true
  xcrun simctl shutdown "$D" 2>/dev/null || true
  release_lock
done
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "==> SKIPPED tests (not verified):"; printf '    %s\n' "${SKIPPED[@]}"
fi
echo "==> Results in $APPLE_DIR/$OUT (read every *-notes and *-tour-summary attachment: a green run can be hollow)"
exit $STATUS
