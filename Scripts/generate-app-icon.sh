#!/bin/sh
# Regenerates the AppIcon asset catalog from Design/AppIcon/L9.png.
set -eu
cd "$(dirname "$0")/.."
master=DerivedData/AppIcon/master-1024.png
iconset=App/Assets.xcassets/AppIcon.appiconset
mkdir -p DerivedData/AppIcon "$iconset"
swift Scripts/AppIconMaster.swift Design/AppIcon/L9.png "$master"
# name:pixels for Apple's macOS slots (16, 32, 128, 256, 512 pt at 1x and 2x)
for entry in icon_16x16:16 icon_16x16@2x:32 icon_32x32:32 icon_32x32@2x:64 icon_128x128:128 \
    icon_128x128@2x:256 icon_256x256:256 icon_256x256@2x:512 icon_512x512:512 icon_512x512@2x:1024; do
  pixels=${entry#*:}
  sips -z "$pixels" "$pixels" "$master" --out "$iconset/${entry%%:*}.png" >/dev/null
done
