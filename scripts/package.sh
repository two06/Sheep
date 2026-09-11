#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
product="${2:-Sheep}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then print -u2 "Use release or debug"; exit 2; fi
if [[ "$product" != Sheep && "$product" != SheepProbe ]]; then print -u2 "Use Sheep or SheepProbe"; exit 2; fi
swift build -c "$configuration" --product "$product" --arch arm64
binary_dir=".build/arm64-apple-macosx/$configuration"
mkdir -p dist
destination="$PWD/dist/$product.app"
staging_dir="$(mktemp -d "$PWD/dist/.package.XXXXXX")"
app="$staging_dir/$product.app"
# Build a new inode rather than overwriting an executable that may be running.
# Restore the old bundle if installing the new bundle fails between the renames.
cleanup() {
    if [[ -d "$staging_dir/previous.app" && ! -e "$destination" ]]; then
        mv "$staging_dir/previous.app" "$destination"
    fi
    rm -rf -- "$staging_dir"
}
trap cleanup EXIT
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/$product" "$app/Contents/MacOS/$product"
cp Sources/SheepCore/Resources/animations.xml "$app/Contents/Resources/animations.xml"
cp Vendor/NOTICE.md "$app/Contents/Resources/NOTICE.md"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$product</string>
<key>CFBundleIdentifier</key><string>local.james.$product</string>
<key>CFBundleName</key><string>$product</string>
<key>CFBundleDisplayName</key><string>$product</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier "local.james.$product" "$app"
codesign --verify --strict "$app"
if [[ -e "$destination" ]]; then mv "$destination" "$staging_dir/previous.app"; fi
mv "$app" "$destination"
print "Built $destination"
