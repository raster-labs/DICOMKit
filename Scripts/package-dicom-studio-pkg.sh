#!/bin/bash
# DICOM Studio macOS .pkg Installer Script
# Creates a distributable macOS installer package (.pkg) for DICOM Studio
#
# Usage: ./package-dicom-studio-pkg.sh [--version VERSION] [--sign IDENTITY] [--notarize]
#
# Prerequisites:
#   - Xcode 26.0+ with command line tools
#   - Swift 6.4+
#   - (Optional) Apple Developer ID Installer certificate for signing
#   - (Optional) Notarization credentials in keychain

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
VERSION="3.1.0"
SIGN_IDENTITY=""
NOTARIZE=false
BUILD_DIR=".build/release"
APP_NAME="DICOMStudio"
BUNDLE_ID="com.dicomkit.DICOMStudio"
PKG_NAME=""
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
            echo "Creates a macOS .pkg installer for DICOM Studio."
            echo ""
            echo "Options:"
            echo "  --version VERSION    Set the version number (default: $VERSION)"
            echo "  --sign IDENTITY      Installer signing identity (Developer ID Installer)"
            echo "  --notarize           Submit for Apple notarization (requires --sign)"
            echo "  --help               Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 --version 3.0.0"
            echo "  $0 --version 3.0.0 --sign \"Developer ID Installer: Your Name (TEAM_ID)\""
            echo "  $0 --version 3.0.0 --sign \"Developer ID Installer: Your Name\" --notarize"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

PKG_NAME="${APP_NAME}-${VERSION}.pkg"
STAGING_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo -e "${GREEN}DICOM Studio .pkg Installer Builder${NC}"
echo "===================================="
echo -e "Version:  ${BLUE}${VERSION}${NC}"
echo -e "Output:   ${BLUE}${PKG_NAME}${NC}"
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

# Step 3: Prepare payload for pkgbuild
echo -e "${GREEN}Step 3:${NC} Preparing installer payload..."

PAYLOAD_DIR="${STAGING_DIR}/payload"
SCRIPTS_DIR="${STAGING_DIR}/scripts"
mkdir -p "${PAYLOAD_DIR}/Applications"
mkdir -p "$SCRIPTS_DIR"

# Copy app bundle to payload
cp -R "$APP_BUNDLE" "${PAYLOAD_DIR}/Applications/"

# Create postinstall script
cat > "${SCRIPTS_DIR}/postinstall" << 'POSTINSTALL'
#!/bin/bash
# Post-installation script for DICOM Studio

# Register DICOM file type association
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f /Applications/DICOMStudio.app 2>/dev/null || true

exit 0
POSTINSTALL
chmod +x "${SCRIPTS_DIR}/postinstall"

echo -e "  ${GREEN}✓${NC} Payload prepared"

# Step 4: Build the component package
echo -e "${GREEN}Step 4:${NC} Building component package..."

COMPONENT_PKG="${STAGING_DIR}/DICOMStudio-component.pkg"
pkgbuild \
    --root "${PAYLOAD_DIR}" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "/" \
    --scripts "$SCRIPTS_DIR" \
    "$COMPONENT_PKG"

echo -e "  ${GREEN}✓${NC} Component package built"

# Step 5: Create distribution XML for productbuild
echo -e "${GREEN}Step 5:${NC} Creating installer product..."

cat > "${STAGING_DIR}/distribution.xml" << DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>DICOM Studio</title>
    <organization>${BUNDLE_ID}</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true" />

    <welcome file="welcome.html" mime-type="text/html" />
    <license file="license.html" mime-type="text/html" />
    <conclusion file="conclusion.html" mime-type="text/html" />

    <os-version min="26.0" />

    <choices-outline>
        <line choice="default">
            <line choice="${BUNDLE_ID}"/>
        </line>
    </choices-outline>

    <choice id="default"/>
    <choice id="${BUNDLE_ID}" visible="false">
        <pkg-ref id="${BUNDLE_ID}"/>
    </choice>

    <pkg-ref id="${BUNDLE_ID}" version="${VERSION}" onConclusion="none">DICOMStudio-component.pkg</pkg-ref>
</installer-gui-script>
DIST

# Create installer resource files
RESOURCES_DIR="${STAGING_DIR}/resources"
mkdir -p "$RESOURCES_DIR"

cat > "${RESOURCES_DIR}/welcome.html" << 'WELCOME'
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; color: #333; }
h1 { color: #0066cc; } h2 { color: #555; } .feature { margin: 8px 0; } .check { color: #28a745; }
</style></head>
<body>
<h1>DICOM Studio</h1>
<h2>Professional Medical Imaging Workstation</h2>
<p>DICOM Studio is a native macOS application for viewing, analyzing, and managing DICOM medical imaging files.</p>
<h3>Features</h3>
<div class="feature"><span class="check">✓</span> DICOM file browsing and metadata inspection</div>
<div class="feature"><span class="check">✓</span> Medical image viewing with window/level controls</div>
<div class="feature"><span class="check">✓</span> PACS connectivity (C-ECHO, C-FIND, C-MOVE, C-STORE)</div>
<div class="feature"><span class="check">✓</span> DICOMweb integration (QIDO-RS, WADO-RS, STOW-RS)</div>
<div class="feature"><span class="check">✓</span> Anonymization, validation, and structured reports</div>
<div class="feature"><span class="check">✓</span> Volume visualization (MPR, 3D rendering)</div>
<div class="feature"><span class="check">✓</span> Measurement and annotation tools</div>
<p><strong>System Requirements:</strong> macOS 26.0 (Tahoe) or later</p>
</body>
</html>
WELCOME

cat > "${RESOURCES_DIR}/license.html" << 'LICENSE_HTML'
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>
body { font-family: -apple-system, BlinkMacSystemFont, monospace; padding: 20px; font-size: 12px; color: #333; }
</style></head>
<body>
<h2>MIT License</h2>
<p>Copyright (c) 2026 Raster Images Private Limited</p>
<p>Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:</p>
<p>The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.</p>
<p>THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.</p>
</body>
</html>
LICENSE_HTML

cat > "${RESOURCES_DIR}/conclusion.html" << 'CONCLUSION'
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; color: #333; }
h1 { color: #28a745; } .step { margin: 8px 0; }
</style></head>
<body>
<h1>Installation Complete</h1>
<p>DICOM Studio has been installed to your Applications folder.</p>
<h3>Getting Started</h3>
<div class="step">1. Open DICOM Studio from your Applications folder or Launchpad</div>
<div class="step">2. Import DICOM files using File → Open or drag and drop</div>
<div class="step">3. Configure PACS connections under Settings → Networking</div>
<h3>Resources</h3>
<p>Documentation: <a href="https://github.com/Raster-Lab/DICOMKit">github.com/Raster-Lab/DICOMKit</a></p>
<p>Issues: <a href="https://github.com/Raster-Lab/DICOMKit/issues">Report a bug</a></p>
</body>
</html>
CONCLUSION

# Build the product package
if [ -n "$SIGN_IDENTITY" ]; then
    echo -e "${GREEN}Step 5a:${NC} Building signed product package..."
    productbuild \
        --distribution "${STAGING_DIR}/distribution.xml" \
        --resources "$RESOURCES_DIR" \
        --package-path "$STAGING_DIR" \
        --sign "$SIGN_IDENTITY" \
        "$PKG_NAME"
    echo -e "  ${GREEN}✓${NC} Signed product package built"
else
    productbuild \
        --distribution "${STAGING_DIR}/distribution.xml" \
        --resources "$RESOURCES_DIR" \
        --package-path "$STAGING_DIR" \
        "$PKG_NAME"
    echo -e "  ${GREEN}✓${NC} Product package built (unsigned)"
fi

# Step 6: Notarization (optional)
if [ "$NOTARIZE" = true ]; then
    if [ -z "$SIGN_IDENTITY" ]; then
        echo -e "${RED}Error: --notarize requires --sign${NC}"
        exit 1
    fi
    echo -e "${GREEN}Step 6:${NC} Submitting for notarization..."
    xcrun notarytool submit "$PKG_NAME" \
        --keychain-profile "notarization" \
        --wait
    echo -e "  ${GREEN}✓${NC} Notarization submitted"

    # Staple the notarization ticket
    xcrun stapler staple "$PKG_NAME"
    echo -e "  ${GREEN}✓${NC} Notarization ticket stapled"
else
    echo -e "${YELLOW}Step 6:${NC} Skipping notarization (use --notarize to enable)"
fi

# Step 7: Generate checksum
echo -e "${GREEN}Step 7:${NC} Generating SHA-256 checksum..."
SHA256=$(shasum -a 256 "$PKG_NAME" | awk '{print $1}')
echo -e "  SHA-256: ${BLUE}${SHA256}${NC}"
echo "$SHA256" > "${PKG_NAME}.sha256"

echo ""
echo -e "${GREEN}Done!${NC}"
echo -e "PKG:      ${BLUE}${PKG_NAME}${NC} ($(du -h "$PKG_NAME" | awk '{print $1}'))"
echo -e "Checksum: ${BLUE}${PKG_NAME}.sha256${NC}"
echo ""
echo "The .pkg installer will install DICOM Studio to /Applications."
