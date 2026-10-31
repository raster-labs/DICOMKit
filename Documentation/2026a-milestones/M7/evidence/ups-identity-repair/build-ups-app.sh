#!/bin/bash
# Execute after UPS verification. Native acceptance requires a fresh app relaunch after this build.
# Adapted from work/m7/build_final_app.sh; preserves its flags/signing/settings.
set -euo pipefail
task_root=/Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3
repo="$task_root/work/DICOMKit-milestones"
result="$task_root/work/m7/native-2026-10-26/ups-identity-repair/app-build"
test ! -e "$result"
mkdir -p "$result"
cd "$repo"
scheme=DICOMStudio.xcodeproj/xcshareddata/xcschemes/DICOMStudio-M7App.xcscheme
test ! -e "$scheme"
cp DICOMStudio.xcodeproj/xcshareddata/xcschemes/DICOMStudio.xcscheme "$scheme"
trap 'rm -f "$scheme"' EXIT
cp "$scheme" "$result/DICOMStudio-M7App.xcscheme"
xcodebuild -project DICOMStudio.xcodeproj -scheme DICOMStudio-M7App \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /Volumes/DICOMKit-M1-build/xcode \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -enable-cross-import-overlays' \
  build > "$result/build.log" 2>&1
python3 - <<'PY'
from pathlib import Path
import plistlib
p = Path('/Volumes/DICOMKit-M1-build/xcode/Build/Products/Debug/DICOMStudio.app/Contents/Info.plist')
d = plistlib.loads(p.read_bytes())
d.setdefault('LSEnvironment', {})['DICOMKIT_PRINT_TEST_SETTINGS_DIRECTORY'] = '/Users/raster/Library/Containers/com.rasterlab.DICOMStudio/Data/Library/Caches/DICOMKitM7PrintQualification'
p.write_bytes(plistlib.dumps(d))
PY
app=/Volumes/DICOMKit-M1-build/xcode/Build/Products/Debug/DICOMStudio.app
codesign --force --deep --sign - --entitlements DICOMStudio.entitlements "$app" > "$result/signing.log" 2>&1
codesign --verify --deep --strict "$app" >> "$result/signing.log" 2>&1
codesign -d --entitlements - "$app" > "$result/entitlements.plist" 2> "$result/code-identity.log"
codesign -dv --verbose=4 "$app" >> "$result/code-identity.log" 2>&1
# Root captures new full app/product hashes and performs the real native AX gate.
