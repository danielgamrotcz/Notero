#!/bin/bash
# Usage: ./release.sh 1.2.0
set -e

VERSION=$1
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version>  (e.g. ./release.sh 1.2.0)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE_PATH="/tmp/Notero.xcarchive"
APP_PATH="/tmp/Notero-release"
ZIP_NAME="Notero-$VERSION.zip"
ZIP_PATH="$SCRIPT_DIR/$ZIP_NAME"

# Determine next build number from appcast
LAST_BUILD=$(grep 'sparkle:version>' "$SCRIPT_DIR/appcast.xml" | sed 's/[^0-9]//g' | sort -n | tail -1)
if [ -z "$LAST_BUILD" ]; then
    LAST_BUILD=0
fi
BUILD_NUMBER=$((LAST_BUILD + 1))
echo "→ Version $VERSION (build $BUILD_NUMBER)"

# 1. Archive
echo "→ Archiving (Release build)..."
xcodebuild archive \
    -project "$SCRIPT_DIR/Notero.xcodeproj" \
    -scheme Notero \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    2>&1 | grep -E "(error:|warning:|ARCHIVE SUCCEEDED|ARCHIVE FAILED)" || true

# Verify archive succeeded
if [ ! -d "$ARCHIVE_PATH/Products/Applications/Notero.app" ]; then
    echo "ERROR: Archive failed — Notero.app not found"
    exit 1
fi

# 2. Extract .app from archive
rm -rf "$APP_PATH" && mkdir -p "$APP_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/Notero.app" "$APP_PATH/"

# 3. Re-sign (ad-hoc)
echo "→ Re-signing app (ad-hoc)..."
if [ -d "$APP_PATH/Notero.app/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --sign - "$APP_PATH/Notero.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
    codesign --force --sign - "$APP_PATH/Notero.app/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --deep --sign - "$APP_PATH/Notero.app"

# 4. Zip
echo "→ Creating $ZIP_NAME..."
cd "$APP_PATH"
zip -r "$ZIP_PATH" Notero.app -x "*.DS_Store"
cd "$SCRIPT_DIR"

# 5. Sign with Sparkle and update appcast
echo "→ Signing update for Sparkle..."
SIGN_UPDATE="/tmp/sparkle-tools/Build/Products/Release/sign_update"
if [ ! -f "$SIGN_UPDATE" ]; then
    echo "  Building Sparkle tools..."
    SPARKLE_CHECKOUT=$(find "$SCRIPT_DIR/build/SourcePackages/checkouts" -name "Sparkle.xcodeproj" 2>/dev/null | head -1)
    if [ -z "$SPARKLE_CHECKOUT" ]; then
        SPARKLE_CHECKOUT=$(find ~/Library/Developer/Xcode/DerivedData -path "*/checkouts/Sparkle/Sparkle.xcodeproj" 2>/dev/null | head -1)
    fi
    if [ -n "$SPARKLE_CHECKOUT" ]; then
        xcodebuild build \
            -project "$SPARKLE_CHECKOUT" \
            -scheme sign_update -configuration Release \
            -derivedDataPath /tmp/sparkle-tools ONLY_ACTIVE_ARCH=YES \
            2>&1 | tail -2
    else
        echo "ERROR: Sparkle checkout not found"
        exit 1
    fi
fi

SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" 2>&1 | grep 'sparkle:edSignature=' | sed 's/.*sparkle:edSignature="//;s/".*//')
LENGTH=$(stat -f%z "$ZIP_PATH")
PUB_DATE=$(date -u '+%a, %d %b %Y %H:%M:%S %z')

if [ -z "$SIGNATURE" ]; then
    echo "WARNING: Could not generate edSignature"
fi

# Insert new item before </channel>
ENCLOSURE="url=\"https://github.com/danielgamrotcz/Notero/releases/download/v$VERSION/$ZIP_NAME\""
if [ -n "$SIGNATURE" ]; then
    ENCLOSURE+=" sparkle:edSignature=\"$SIGNATURE\""
fi
ENCLOSURE+=" length=\"$LENGTH\" type=\"application/octet-stream\""

perl -i -0777 -pe "s|    </channel>|        <item>
            <title>$VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure $ENCLOSURE/>
        </item>\n    </channel>|" "$SCRIPT_DIR/appcast.xml"

# 6. GitHub release
echo "→ Creating GitHub release v$VERSION..."
gh release create "v$VERSION" "$ZIP_PATH" \
    --title "Notero $VERSION" \
    --notes "" \
    --repo danielgamrotcz/Notero

# 7. Clean up zip
rm -f "$ZIP_PATH"

# 8. Commit & push appcast
echo "→ Pushing appcast.xml..."
git -C "$SCRIPT_DIR" add appcast.xml
git -C "$SCRIPT_DIR" commit -m "Release v$VERSION"
git -C "$SCRIPT_DIR" push

echo ""
echo "✓ Notero $VERSION released."
