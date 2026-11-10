#!/bin/bash
# DICOM Studio DMG Packaging Script
# Creates a distributable DMG disk image for the DICOM Studio macOS application
#
# Usage: ./package-dicom-studio-dmg.sh [--version VERSION] [--sign IDENTITY] [--notarize]
#
# Prerequisites:
#   - Xcode 26.0+ with command line tools
#   - Swift 6.4+
#   - (Optional) Apple Developer ID for signing and notarization

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
VERSION="3.0.0"
SIGN_IDENTITY=""
NOTARIZE=false
BUILD_DIR=".build/release"
APP_NAME="DICOMStudio"
BUNDLE_ID="com.dicomkit.DICOMStudio"
DMG_NAME=""
STAGING_DIR=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--version VERSION] [--sign IDENTITY] [--notarize]"
            echo ""
            echo "Creates a DMG disk image installer for DICOM Studio."
            echo ""
            echo "Options:"
            echo "  --version VERSION    Set the version number (default: $VERSION)"
            echo "  --sign IDENTITY      Code signing identity (Developer ID Application)"
            echo "  --notarize           Submit for Apple notarization (requires --sign)"
            echo "  --help               Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 --version 3.0.0"
            echo "  $0 --version 3.0.0 --sign \"Developer ID Application: Your Name (TEAM_ID)\""
            echo "  $0 --version 3.0.0 --sign \"Developer ID Application: Your Name\" --notarize"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
STAGING_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo -e "${GREEN}DICOM Studio DMG Packager${NC}"
echo "========================="
echo -e "Version:  ${BLUE}${VERSION}${NC}"
echo -e "Output:   ${BLUE}${DMG_NAME}${NC}"
echo ""

# Step 1: Build the application
echo -e "${GREEN}Step 1:${NC} Building ${APP_NAME}..."
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift is not installed${NC}"
    exit 1
fi

swift build -c release --product "$APP_NAME" --disable-sandbox
echo -e "  ${GREEN}✓${NC} Build successful"

# Step 2: Create app bundle structure
echo -e "${GREEN}Step 2:${NC} Creating app bundle..."

APP_BUNDLE="${STAGING_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

mkdir -p "$MACOS" "$RESOURCES"

# Copy the built executable
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>DICOM Studio</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>DCMS</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.medical</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Raster Images Private Limited. All rights reserved.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>DICOM File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.nema.dicom</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>dcm</string>
                <string>dicom</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo -e "  ${GREEN}✓${NC} App bundle created"

# Step 3: Code signing (optional)
if [ -n "$SIGN_IDENTITY" ]; then
    echo -e "${GREEN}Step 3:${NC} Code signing with identity: ${SIGN_IDENTITY}..."
    codesign --force --options runtime --sign "$SIGN_IDENTITY" \
        --entitlements /dev/stdin "$APP_BUNDLE" << ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS
    echo -e "  ${GREEN}✓${NC} Code signed"
else
    echo -e "${YELLOW}Step 3:${NC} Skipping code signing (no --sign identity provided)"
fi

# Step 4: Create DMG
echo -e "${GREEN}Step 4:${NC} Creating DMG..."

DMG_STAGING="${STAGING_DIR}/dmg_contents"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create a symlink to /Applications for drag-install
ln -s /Applications "$DMG_STAGING/Applications"

# Create a README file
cat > "${DMG_STAGING}/README.txt" << README
DICOM Studio v${VERSION}

Drag DICOMStudio.app to the Applications folder to install.

System Requirements:
  - macOS 26.0 (Tahoe) or later
  - Apple Silicon or Intel processor

Features:
  - DICOM file browsing and metadata inspection
  - Medical image viewing with window/level controls
  - PACS connectivity (C-ECHO, C-FIND, C-MOVE, C-STORE)
  - DICOMweb integration (QIDO-RS, WADO-RS, STOW-RS)
  - DICOM file anonymization and validation
  - Structured report viewing
  - Volume visualization (MPR, 3D)
  - Measurement and annotation tools

For documentation and source code:
  https://github.com/Raster-Lab/DICOMKit

License: MIT
README

# Create the DMG
hdiutil create -volname "DICOM Studio" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_NAME"

echo -e "  ${GREEN}✓${NC} DMG created: ${DMG_NAME}"

# Step 5: Notarization (optional)
if [ "$NOTARIZE" = true ]; then
    if [ -z "$SIGN_IDENTITY" ]; then
        echo -e "${RED}Error: --notarize requires --sign${NC}"
        exit 1
    fi
    echo -e "${GREEN}Step 5:${NC} Submitting for notarization..."
    xcrun notarytool submit "$DMG_NAME" \
        --keychain-profile "notarization" \
        --wait
    echo -e "  ${GREEN}✓${NC} Notarization submitted"

    # Staple the notarization ticket
    xcrun stapler staple "$DMG_NAME"
    echo -e "  ${GREEN}✓${NC} Notarization ticket stapled"
else
    echo -e "${YELLOW}Step 5:${NC} Skipping notarization (use --notarize to enable)"
fi

# Step 6: Generate checksum
echo -e "${GREEN}Step 6:${NC} Generating SHA-256 checksum..."
SHA256=$(shasum -a 256 "$DMG_NAME" | awk '{print $1}')
echo -e "  SHA-256: ${BLUE}${SHA256}${NC}"
echo "$SHA256" > "${DMG_NAME}.sha256"

echo ""
echo -e "${GREEN}Done!${NC}"
echo -e "DMG:      ${BLUE}${DMG_NAME}${NC} ($(du -h "$DMG_NAME" | awk '{print $1}'))"
echo -e "Checksum: ${BLUE}${DMG_NAME}.sha256${NC}"
echo ""
echo "To install via Homebrew Cask, update Formula/dicomstudio.rb with:"
echo "  version \"${VERSION}\""
echo "  sha256 \"${SHA256}\""
