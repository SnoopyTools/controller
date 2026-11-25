#!/bin/bash
# Build controller.ipa (unsigned, for LiveContainer / sideloading).
# Place this script in the repo root (next to project.yml) and run: ./build.sh
set -e

# Always run from the repo root, wherever this script lives.
cd "$(dirname "$0")"

echo "==> Checking tools"
command -v xcodegen >/dev/null || brew install xcodegen
command -v ldid     >/dev/null || brew install ldid

echo "==> Fetching ChOma headers"
rm -rf /tmp/ChOma
git clone --depth=1 https://github.com/opa334/ChOma.git /tmp/ChOma
cp /tmp/ChOma/src/*.h controller/headers/

echo "==> Regenerating Xcode project from project.yml"
xcodegen generate

echo "==> Building archive (unsigned)"
rm -rf build && mkdir build
xcodebuild archive \
  -project controller.xcodeproj \
  -scheme controller \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/controller.xcarchive \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM=""

echo "==> Packaging and signing IPA with ldid"
APP=$(find build/controller.xcarchive -name "*.app" | head -1)
if [ -z "$APP" ]; then echo "No .app found in archive"; exit 1; fi
rm -rf Payload && mkdir Payload
cp -R "$APP" Payload/
ldid -Scontroller/controller.entitlements "Payload/controller.app/controller"
zip -qry controller.ipa Payload
rm -rf Payload

echo "==> Done: $(pwd)/controller.ipa"
ls -lh controller.ipa
