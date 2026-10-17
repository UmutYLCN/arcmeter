#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ ! -r "$HOME/Library/Application Support/AIQuotaWidget/snapshot.json" ]; then
  echo "Launch Arcmeter.app and wait for its first successful refresh before running this check." >&2
  exit 1
fi
python3 - <<'CHECK'
import json
from pathlib import Path
snapshot = Path.home() / 'Library/Application Support/AIQuotaWidget/snapshot.json'
if json.loads(snapshot.read_text())['version'] != 2:
    raise SystemExit('Wait for the updated host to finish its first refresh with both quota windows.')
CHECK
probe=DerivedData/SandboxProbe.app
mkdir -p "$probe/Contents/MacOS"
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  -I DerivedData/Build/Products/Debug \
  Shared/SnapshotStore.swift Scripts/SandboxProbe.swift \
  DerivedData/Build/Products/Debug/QuotaCore.o -o "$probe/Contents/MacOS/SandboxProbe"
python3 - <<'PY'
import plistlib
from pathlib import Path
path = Path('DerivedData/SandboxProbe.app/Contents/Info.plist')
path.write_bytes(plistlib.dumps(dict(CFBundleExecutable='SandboxProbe',
    CFBundleIdentifier='local.ai-quota-widget.sandbox-probe', CFBundlePackageType='APPL')))
PY
codesign --force --sign - --entitlements Config/Widget.entitlements "$probe"
"$probe/Contents/MacOS/SandboxProbe"
