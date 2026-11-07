#!/usr/bin/env bash
# Build SWARM.app, sign it with Developer ID, notarize it, and (with --publish)
# release it and point the cask at the release.
#
#   ./build.sh <version>                 build, sign, notarize into dist/
#   ./build.sh <version> --no-notarize   build and sign only (local testing)
#   ./build.sh <version> --publish       ...then create GitHub release v<version>
#                                        and update Casks/swarm.rb
#
# Needs: Xcode command line tools, the Developer ID Application identity in the
# keychain, and (unless --no-notarize) a notarytool keychain profile created once
# with `xcrun notarytool store-credentials "$NOTARY_PROFILE"`. --publish needs `gh`.
set -euo pipefail

IDENTITY=${SIGN_IDENTITY:-"Developer ID Application: JACEK DARIUSZ KWIECIEN (X2FFQ95MA9)"}
NOTARY_PROFILE=${NOTARY_PROFILE:-swarm-notary}
REPO=${REPO:-jkwiecien/homebrew-swarm}

die() { printf 'build: %s\n' "$*" >&2; exit 1; }
say() { printf 'build: %s\n' "$*" >&2; }

[ $# -ge 1 ] || die "usage: $0 <version> [--no-notarize] [--publish]"
VERSION=$1; shift
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z, got '$VERSION'"
NOTARIZE=1 PUBLISH=0
for arg in "$@"; do
	case $arg in
		--no-notarize) NOTARIZE=0 ;;
		--publish) PUBLISH=1 ;;
		*) die "unknown flag: $arg" ;;
	esac
done
[ $PUBLISH -eq 0 ] || [ $NOTARIZE -eq 1 ] || die "--publish needs a notarized build"

ROOT=$(cd "$(dirname "$0")" && pwd)
APP="$ROOT/build/SWARM.app"
ZIP="$ROOT/dist/SWARM-$VERSION.zip"
rm -rf "$ROOT/build" && mkdir -p "$APP/Contents/MacOS" "$ROOT/dist"

say "compiling (arm64 + x86_64)"
clang -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 -O2 -Wall -Wextra -Werror \
	-o "$APP/Contents/MacOS/swarm" "$ROOT/launcher/swarm.c"

cp "$ROOT/app/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
[ ! -f "$ROOT/app/SWARM.icns" ] || {
	mkdir -p "$APP/Contents/Resources"
	cp "$ROOT/app/SWARM.icns" "$APP/Contents/Resources/SWARM.icns"
	plutil -replace CFBundleIconFile -string SWARM "$APP/Contents/Info.plist"
}

say "signing with $IDENTITY"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [ $NOTARIZE -eq 1 ]; then
	say "notarizing (profile $NOTARY_PROFILE)"
	ditto -c -k --keepParent "$APP" "$ZIP"
	xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
	xcrun stapler staple "$APP"
	spctl --assess --type execute --verbose=2 "$APP"
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
say "built $ZIP"
say "sha256 $SHA"

if [ $PUBLISH -eq 1 ]; then
	say "publishing v$VERSION"
	gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "SWARM.app $VERSION" \
		--notes "SWARM.app $VERSION, signed with Developer ID and notarized."
	sed -i '' -E \
		-e "s/^  version \".*\"/  version \"$VERSION\"/" \
		-e "s/^  sha256 .*/  sha256 \"$SHA\"/" \
		"$ROOT/Casks/swarm.rb"
	git -C "$ROOT" add Casks/swarm.rb
	git -C "$ROOT" commit -m "swarm $VERSION"
	git -C "$ROOT" push
	say "cask updated; machines get it with: brew upgrade --cask swarm"
fi
