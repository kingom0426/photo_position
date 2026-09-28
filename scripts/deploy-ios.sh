#!/bin/bash
set -euo pipefail

# Run with access to macOS device services and Xcode signing credentials.
# In a sandboxed agent, request elevated execution for this script.
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
device_id="C2564A70-2D79-52AE-990E-1FB4685E2CB7"
build_dir="/Users/duxin/Library/Caches/LumenDeviceBuild"

xcrun devicectl list devices
xcodebuild -project "$repo_dir/ios/Lumen/Lumen.xcodeproj" \
  -scheme Lumen -configuration Debug \
  -destination 'platform=iOS,name=杜鑫' \
  -derivedDataPath "$build_dir" -allowProvisioningUpdates build
xcrun devicectl device install app --device "$device_id" \
  "$build_dir/Build/Products/Debug-iphoneos/Lumen.app"
xcrun devicectl device process launch --device "$device_id" \
  --terminate-existing com.lumen.photo
