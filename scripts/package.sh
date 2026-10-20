#!/bin/bash
# Builds an Apple Silicon app, installer package, DMG and ZIP.
set -euo pipefail
export COPYFILE_DISABLE=1
cd "$(dirname "$0")/.."
archs=(--arch arm64)
# SwiftPM does not prune removed resource bundles from an existing products
# directory. Start clean so deleted private resources cannot enter a release.
swift package clean
swift build -c release "${archs[@]}"
bin_dir="$(swift build -c release "${archs[@]}" --show-bin-path)"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/Info.plist)"
app="dist/LogiMXLite.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/LogiMXLite" "$app/Contents/MacOS/LogiMXLite"
bundle="$bin_dir/LogiMXLite_LogiMXLite.bundle"
test -d "$bundle"
cp -R "$bundle" "$app/Contents/Resources/"
cp scripts/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp docs/THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.txt"
# Ad-hoc signature with an identifier-based requirement, so permission grants survive rebuilds.
# Not Developer ID signed or notarized: other Macs must allow it once (see README).
codesign --force --deep --sign - --identifier com.h4rithd.LogiMXLite -r='designated => identifier "com.h4rithd.LogiMXLite"' "$app"
codesign --verify --strict "$app"

zip="dist/LogiMXLite-$version.zip"
dmg="dist/LogiMXLite-$version.dmg"
pkg="dist/LogiMXLite-$version.pkg"
rm -f "$zip" "$dmg" "$pkg"
ditto --norsrc -c -k --keepParent "$app" "$zip"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto --norsrc "$app" "$stage/LogiMXLite.app"
# Finder provenance extended attributes are local metadata, not app resources.
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "LogiMXLite" -srcfolder "$stage" -ov -format UDZO "$dmg"
mkdir -p "$stage/pkgroot/Applications"
ditto --norsrc "$app" "$stage/pkgroot/Applications/LogiMXLite.app"
codesign --verify --strict "$stage/pkgroot/Applications/LogiMXLite.app"
pkgbuild --quiet --root "$stage/pkgroot" --install-location / \
    --identifier com.h4rithd.LogiMXLite.pkg --version "$version" "$pkg"
pkgutil --payload-files "$pkg" | grep -q 'Applications/LogiMXLite.app/Contents/MacOS/LogiMXLite'
echo "Packaged $app ($(lipo -archs "$app/Contents/MacOS/LogiMXLite")), $pkg, $zip, $dmg"
