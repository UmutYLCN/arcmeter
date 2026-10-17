#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  -I DerivedData/Build/Products/Debug \
  Widget/QuotaWidget.swift Shared/SnapshotStore.swift Scripts/Preview.swift \
  DerivedData/Build/Products/Debug/QuotaCore.o -o DerivedData/widget-preview
DerivedData/widget-preview
