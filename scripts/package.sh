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
# macOS uses the ICNS for Finder, Launch Services, the Dock and Installer's
# installed-app presentation. The menu bar keeps its original vector symbol;
# loading the 1024px source at launch previously cost ~32 MB.
icon_source="Sources/LogiMXLite/Resources/lite-appicon.png"
iconset="$(mktemp -d)/LogiMXLite.iconset"
mkdir -p "$iconset"
for points in 16 32 128 256 512; do
    sips -s format png -z "$points" "$points" "$icon_source" --out "$iconset/icon_${points}x${points}.png" >/dev/null
    doubled=$((points * 2))
    sips -s format png -z "$doubled" "$doubled" "$icon_source" --out "$iconset/icon_${points}x${points}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$app/Contents/Resources/LogiMXLite.icns"
rm -rf "$(dirname "$iconset")"
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
    --filter '(^|/)\._[^/]*$' --filter '(^|/)\.DS_Store$' \
    --filter '(^|/)\.svn(/|$)' --filter '(^|/)CVS(/|$)' \
    --identifier com.h4rithd.LogiMXLite.pkg --version "$version" "$pkg"
pkgutil --payload-files "$pkg" | grep -q 'Applications/LogiMXLite.app/Contents/MacOS/LogiMXLite'
echo "Packaged $app ($(lipo -archs "$app/Contents/MacOS/LogiMXLite")), $pkg, $zip, $dmg"
