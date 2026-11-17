#!/bin/bash
# Builds build/Recall-<version>.dmg: a universal app signed with a Developer ID certificate,
# in a disk image that is notarized by Apple and has the ticket stapled to it.
#
# Signing identity:  $RECALL_RELEASE_IDENTITY, else the first line of .release-identity
# Notary profile:    $RECALL_NOTARY_PROFILE, else the first line of .notary-profile
#                    (a keychain profile created with `xcrun notarytool store-credentials`)
# Without a notary profile the image is built and signed but not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

setting() { # setting <ENV_VALUE> <file>
    if [ -n "$1" ]; then
        echo "$1"
    elif [ -f "$2" ]; then
        sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}' "$2"
    fi
}

IDENTITY="$(setting "${RECALL_RELEASE_IDENTITY:-}" .release-identity)"
PROFILE="$(setting "${RECALL_NOTARY_PROFILE:-}" .notary-profile)"
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
    echo "No release identity. Set RECALL_RELEASE_IDENTITY or create .release-identity." >&2
    exit 1
fi

# Sends a file to Apple and waits. Stops the script unless the answer is "Accepted".
notarize() {
    local output id
    if ! output="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)"; then
        echo "$output" >&2
        exit 1
    fi
    if ! grep -q "status: Accepted" <<<"$output"; then
        echo "$output" >&2
        id="$(awk '$1 == "id:" { print $2; exit }' <<<"$output")"
        if [ -n "$id" ]; then
            xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
        fi
        echo "Apple did not accept $1" >&2
        exit 1
    fi
    echo "Notarized $1"
}

RECALL_SIGN_IDENTITY="$IDENTITY" scripts/build-app.sh --universal

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/Recall-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# The app gets its own ticket, so it opens without a network connection
# after it has been copied out of the disk image.
if [ -n "$PROFILE" ]; then
    ditto -c -k --keepParent build/Recall.app "$STAGE/Recall.zip"
    notarize "$STAGE/Recall.zip"
    rm "$STAGE/Recall.zip"
    xcrun stapler staple build/Recall.app
fi

cp -R build/Recall.app "$STAGE/Recall.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Recall" -srcfolder "$STAGE" -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ -z "$PROFILE" ]; then
    echo "Built $DMG (signed, not notarized: no notary profile)"
    exit 0
fi

notarize "$DMG"
xcrun stapler staple "$DMG"
echo "Built $DMG (signed and notarized)"
