#!/usr/bin/env bash
# usage: measure.sh "<device name>" <app path> <output dir>
set -uo pipefail

DEVICE_NAME="$1"
APP_PATH="$2"
OUT_DIR="$3"
BUNDLE_ID="dev.probe.KeyboardProbe"
SAFE_NAME="$(echo "$DEVICE_NAME" | tr -c 'A-Za-z0-9' '_')"
mkdir -p "$OUT_DIR"

# iOS 27 ランタイムを探す(無ければ最新のiOSランタイムで代用し、ログに残す)
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"]
      if r.get("isAvailable") and "SimRuntime.iOS-" in r["identifier"]]
def key(r): return [int(x) for x in r["version"].split(".") if x.isdigit()]
rs.sort(key=key)
print(rs[-1]["identifier"] + " " + rs[-1]["version"] if rs else "")')
if [ -z "$RUNTIME" ]; then
  echo "::error::No iOS simulator runtime found"; xcrun simctl list runtimes; exit 1
fi
RUNTIME_ID="${RUNTIME% *}"; RUNTIME_VER="${RUNTIME#* }"
echo "Using runtime: $RUNTIME_ID ($RUNTIME_VER)"

# デバイスタイプID
TYPE_ID=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
name = sys.argv[1]
for d in json.load(sys.stdin)["devicetypes"]:
    if d["name"] == name:
        print(d["identifier"]); break' "$DEVICE_NAME")
if [ -z "$TYPE_ID" ]; then
  echo "::warning::Device type not found: $DEVICE_NAME (skipped)"
  xcrun simctl list devicetypes | grep -i iphone || true
  exit 0
fi

# ソフトウェアキーボードを出すため、ハードウェアキーボード接続をOFF
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false || true

UDID=$(xcrun simctl create "probe-$SAFE_NAME" "$TYPE_ID" "$RUNTIME_ID") || {
  echo "::warning::Could not create $DEVICE_NAME on $RUNTIME_ID (skipped)"; exit 0; }

cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl delete "$UDID" >/dev/null 2>&1; }
trap cleanup EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID"

DATA_DIR=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
JSON="$DATA_DIR/Documents/keyboard.json"

for _ in $(seq 1 40); do
  [ -f "$JSON" ] && break
  sleep 1
done
sleep 2   # アニメーション完了待ち

xcrun simctl io "$UDID" screenshot "$OUT_DIR/$SAFE_NAME.png" || true

if [ -f "$JSON" ]; then
  python3 - "$JSON" "$DEVICE_NAME" "$RUNTIME_VER" "$OUT_DIR/$SAFE_NAME.json" <<'PY'
import json, sys
src, dev, ver, dst = sys.argv[1:5]
d = json.load(open(src))
d["device"] = dev
d["ios_runtime"] = ver
json.dump(d, open(dst, "w"), indent=2, ensure_ascii=False)
print(json.dumps(d, indent=2, ensure_ascii=False))
PY
else
  echo "::warning::keyboard.json was not produced for $DEVICE_NAME (keyboard may not have appeared). See screenshot."
fi
