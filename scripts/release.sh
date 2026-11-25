#!/bin/bash
# Builds Barback.app and packages it for the website.
#
#   scripts/release.sh                    sign, notarize, make the DMG and the update feed
#   scripts/release.sh --adhoc            the same app and DMG, signed ad hoc, for this Mac only
#   scripts/release.sh --make-update-key  make the key that signs updates (once)
#
# The version comes from Resources/Info.plist: raise CFBundleShortVersionString (what people
# see) and CFBundleVersion (what the updater compares) before a release. Release notes are
# optional: release-notes/<version>.md, shown in the update window.
#
# A release needs, all set up once (see scripts/release.conf and the README):
#   - a Developer ID Application certificate in the keychain
#   - a notarytool keychain profile
#   - the update key, with its public half in scripts/release.conf
#
# What comes out:
#   dist/Barback.app             the app
#   dist/Barback-<version>.dmg   the download
#   updates/                     everything to upload: the DMGs and appcast.xml
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/release.conf
# For a test run or a build machine: a file holding the private update key, instead of the keychain.
SPARKLE_KEY_FILE="${SPARKLE_KEY_FILE:-}"

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'release: %s\n' "$*" >&2; exit 1; }

MODE=release
case "${1:-}" in
    "") ;;
    --adhoc) MODE=adhoc ;;
    --make-update-key) MODE=key ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1 (try --help)" ;;
esac
[[ $# -le 1 ]] || die "one option at a time (try --help)"

SPARKLE=.build/artifacts/sparkle/Sparkle
[[ -x $SPARKLE/bin/generate_appcast ]] || swift package resolve
[[ -x $SPARKLE/bin/generate_appcast ]] || die "Sparkle's tools are not in $SPARKLE/bin"

if [[ $MODE == key ]]; then
    "$SPARKLE/bin/generate_keys" --account "$SPARKLE_ACCOUNT"
    cat <<NOTE

Put the public key above in scripts/release.conf as SPARKLE_PUBLIC_KEY.
Keep a copy of the private key somewhere safe (a password manager); without it you
cannot ship an update to anyone who already has Barback:
    $SPARKLE/bin/generate_keys --account $SPARKLE_ACCOUNT -x <file>
NOTE
    exit 0
fi

plist() { /usr/libexec/PlistBuddy -c "$1" "${2:-Resources/Info.plist}"; }
VERSION=$(plist "Print :CFBundleShortVersionString")
BUILD=$(plist "Print :CFBundleVersion")
BUNDLE_ID=$(plist "Print :CFBundleIdentifier")
APP=dist/$APP_NAME.app
DMG=dist/$APP_NAME-$VERSION.dmg

# MARK: Before building, check that a release can be finished

if [[ $MODE == release ]]; then
    say "Checking what a release needs"
    IDENTITY=$(security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" | head -1 | awk '{print $2}') || true
    [[ -n ${IDENTITY:-} ]] || die "no certificate matching \"$SIGN_IDENTITY\" in the keychain.
Make a Developer ID Application certificate at https://developer.apple.com/account/resources/certificates
(or in Xcode: Settings > Accounts > Manage Certificates), or use --adhoc for a build for this Mac only."
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || die "no working notarytool profile \"$NOTARY_PROFILE\". Make it with:
    xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <you> --team-id <TEAMID>
It asks for an app-specific password, made at https://account.apple.com."
    [[ -n $SPARKLE_PUBLIC_KEY ]] || die "SPARKLE_PUBLIC_KEY is empty in scripts/release.conf. Make the key with:
    scripts/release.sh --make-update-key"
    if [[ -z $SPARKLE_KEY_FILE ]]; then
        KEYCHAIN_KEY=$("$SPARKLE/bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null) || die "no update key for the account \"$SPARKLE_ACCOUNT\" in the keychain."
        [[ $KEYCHAIN_KEY == "$SPARKLE_PUBLIC_KEY" ]] || die "SPARKLE_PUBLIC_KEY in scripts/release.conf is not the public half of the key in the keychain ($KEYCHAIN_KEY)."
    fi
    if [[ -e updates/$APP_NAME-$VERSION.dmg ]]; then
        die "updates/$APP_NAME-$VERSION.dmg is already there. Raise the version in Resources/Info.plist, or remove that file to release $VERSION again."
    fi
fi

# MARK: Build

say "Building $APP_NAME $VERSION ($BUILD)"
swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
ditto "$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# Barback has an updater only when the app says where the feed is and which key to trust.
if [[ -n $SPARKLE_PUBLIC_KEY ]]; then
    plist "Add :SUFeedURL string $SITE_URL/appcast.xml" "$APP/Contents/Info.plist"
    plist "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
fi

# MARK: Sign

FRAMEWORK=$APP/Contents/Frameworks/Sparkle.framework/Versions/B
if [[ $MODE == release ]]; then
    say "Signing with $(security find-identity -v -p codesigning | grep -F "$IDENTITY" | head -1 | sed 's/.*"\(.*\)"/\1/')"
    SIGN=(codesign --force --sign "$IDENTITY" --options runtime --timestamp)
    APP_SIGN=("${SIGN[@]}")
else
    say "Signing ad hoc"
    # No hardened runtime: it would refuse to load a framework signed ad hoc.
    SIGN=(codesign --force --sign -)
    # An ad hoc signature is known by the binary's hash, so every build would lose its
    # Accessibility and file permissions. Known by its identifier, it keeps them.
    APP_SIGN=("${SIGN[@]}" "-r=designated => identifier \"$BUNDLE_ID\"")
fi
# Inside out, as Sparkle's documentation says to for an app signed outside Xcode.
"${SIGN[@]}" "$FRAMEWORK/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$FRAMEWORK/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FRAMEWORK/Autoupdate"
"${SIGN[@]}" "$FRAMEWORK/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${APP_SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"

# MARK: Notarize

# Sends a file to Apple and waits for the answer; on a refusal, prints Apple's reasons.
notarize() {
    local result id status
    result=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json) || true
    id=$(printf '%s' "$result" | plutil -extract id raw -o - - 2>/dev/null || true)
    status=$(printf '%s' "$result" | plutil -extract status raw -o - - 2>/dev/null || true)
    if [[ $status != Accepted ]]; then
        printf '%s\n' "$result" >&2
        [[ -z $id ]] || xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        die "Apple did not notarize $1"
    fi
}

if [[ $MODE == release ]]; then
    say "Notarizing the app (a few minutes)"
    ditto -c -k --keepParent "$APP" dist/notarize.zip
    notarize dist/notarize.zip
    rm dist/notarize.zip
    # Stapled, the app opens the first time without asking Apple, so also offline.
    xcrun stapler staple "$APP"
fi

# MARK: Disk image

say "Making $DMG"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -format UDZO -ov "$DMG"

if [[ $MODE == adhoc ]]; then
    say "Done"
    echo "$APP and $DMG are signed ad hoc: they run on this Mac, and Gatekeeper refuses them on any other."
    [[ -n $SPARKLE_PUBLIC_KEY ]] || echo "This build has no updater (SPARKLE_PUBLIC_KEY is empty in scripts/release.conf)."
    exit 0
fi

codesign --force --sign "$IDENTITY" --timestamp "$DMG"
say "Notarizing the disk image (a few minutes)"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"
spctl --assess --type execute "$APP"

# MARK: Update feed

say "Writing the update feed"
mkdir -p updates
cp "$DMG" updates/
if [[ -f release-notes/$VERSION.md ]]; then
    cp "release-notes/$VERSION.md" "updates/$APP_NAME-$VERSION.md"
fi
KEY=(--account "$SPARKLE_ACCOUNT")
[[ -z $SPARKLE_KEY_FILE ]] || KEY=(--ed-key-file "$SPARKLE_KEY_FILE")
# Keeps the entries already in updates/appcast.xml and adds this version, signed.
"$SPARKLE/bin/generate_appcast" "${KEY[@]}" --download-url-prefix "$SITE_URL/" --link "$SITE_URL/" \
    --embed-release-notes --maximum-versions 0 --maximum-deltas 0 -o updates/appcast.xml updates

say "Done: $APP_NAME $VERSION ($BUILD)"
cat <<NOTE
Upload to $SITE_URL/ :
    updates/$APP_NAME-$VERSION.dmg
    updates/appcast.xml   (last: the moment it is up, every Barback offers the update)

Then tag the release:  git tag v$VERSION && git push --tags
NOTE
