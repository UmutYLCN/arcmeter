#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ ! -r "$HOME/Library/Application Support/AIQuotaWidget/snapshot.json" ]; then
  echo "Launch AIQuotaWidget.app and wait for its first successful refresh before running this check." >&2
  exit 1
fi
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
