#!/bin/sh
# Takedawn.app from a built game and a built setup window: the one bundle with both
# executables, the way a release ships them (docs/installer.md, "The setup window").
#
#   Takedawn.app/Contents/
#     Info.plist                 CFBundleExecutable Takedawn
#     MacOS/Takedawn             the game (bin/burnout3 of the build)
#     MacOS/takedawn-setup       the setup window; the game looks for it beside itself
#     Frameworks/                Qt (Core, Gui, Widgets, DBus) and the game's own libraries
#     PlugIns/platforms, styles  Qt's cocoa platform and macOS style
#     Resources/Takedawn.icns    from assets/icon/takedawn-macos.svg
#     Resources/qt.conf, licenses/, enhance.toml.default
#
#   packaging/make-macos-bundle.sh <out dir> [game binary] [setup build dir]
#
# Environment: QT_DIR (the Qt kit the window was built with, for macdeployqt; default
# from the build's CMakeCache), ICON_PYTHON (a Python for ../render_icon.py),
# XBOXRECOMP_DIR (the toolkit, for its licence texts).
#
# This is a development bundle, a way to try the layout. The release is made by
# tools/release/build-macos.sh (the game's own libraries, the licences, the dmg),
# which deploys Qt with the same deploy-qt-macos.sh.
# Signed ad hoc only, as Apple silicon asks for: no developer identity is used.
set -e
here=$(cd "$(dirname "$0")" && pwd)
gui=$(cd "$here/.." && pwd)
repo=$(cd "$gui/../../.." && pwd)
out=${1:?usage: make-macos-bundle.sh <out dir> [game binary] [setup build dir]}
game=${2:-$repo/bin/burnout3}
build=${3:-$gui/build}
setup="$build/takedawn-setup"
[ -x "$game" ] || { echo "no game binary at $game" >&2; exit 1; }
[ -x "$setup" ] || { echo "no setup window at $setup (build tools/install/gui first)" >&2; exit 1; }
qt=${QT_DIR:-$(sed -n 's|^Qt6_DIR:PATH=\(.*\)/lib/cmake/Qt6$|\1|p' "$build/CMakeCache.txt")}
python=${ICON_PYTHON:-$(sed -n 's|^TAKEDAWN_ICON_PYTHON:FILEPATH=||p' "$build/CMakeCache.txt")}
python=${python:-python3}
version=$(sed -n 1p "$repo/VERSION")

app="$out/Takedawn.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/licenses"
cp "$game" "$app/Contents/MacOS/Takedawn"
cp "$setup" "$app/Contents/MacOS/takedawn-setup"

# The icon, in the shape an .icns wants, rendered from the SVG.
iconset="$out/Takedawn.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
svg="$repo/assets/icon/takedawn-macos.svg"
"$python" "$gui/render_icon.py" "$svg" \
    "$iconset/icon_16x16.png" 16 "$iconset/icon_16x16@2x.png" 32 \
    "$iconset/icon_32x32.png" 32 "$iconset/icon_32x32@2x.png" 64 \
    "$iconset/icon_128x128.png" 128 "$iconset/icon_128x128@2x.png" 256 \
    "$iconset/icon_256x256.png" 256 "$iconset/icon_256x256@2x.png" 512 \
    "$iconset/icon_512x512.png" 512 "$iconset/icon_512x512@2x.png" 1024
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Takedawn.icns"
rm -rf "$iconset"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Takedawn</string>
  <key>CFBundleDisplayName</key><string>Takedawn</string>
  <key>CFBundleIdentifier</key><string>com.stevencol.takedawn</string>
  <key>CFBundleExecutable</key><string>Takedawn</string>
  <key>CFBundleIconFile</key><string>Takedawn</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.racing-games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

# Licence texts (the window's "About and licences" reads Resources/licenses) and
# the list of enhance.toml keys, for reference: the file itself is the player's,
# in ~/Library/Application Support/Takedawn.
cp "$gui"/licenses/Qt-*.txt "$app/Contents/Resources/licenses/"
cp "$repo/LICENSE" "$app/Contents/Resources/licenses/takedawn-LICENSE.txt"
toolkit=${XBOXRECOMP_DIR:-$repo/../xboxrecomp}
if [ -f "$toolkit/LICENSE" ]; then
    cp "$toolkit/LICENSE" "$app/Contents/Resources/licenses/xboxrecomp-LICENSE.txt"
    cp "$toolkit/NOTICE" "$app/Contents/Resources/licenses/xboxrecomp-NOTICE.txt"
    lgpl=$(ls "$toolkit"/LICENSES/*LGPL* 2>/dev/null | head -1)
    [ -n "$lgpl" ] && cp "$lgpl" "$app/Contents/Resources/licenses/xboxrecomp-LGPL-2.1.txt"
fi
cp "$repo/config/enhance.toml.default" "$app/Contents/Resources/enhance.toml.default"

# Qt beside the window: Frameworks, PlugIns and qt.conf, thinned to the game's
# architecture and checked (deploy-qt-macos.sh, which the release script uses too).
arch=$(lipo -archs "$app/Contents/MacOS/Takedawn")
case "$arch" in *" "*) arch=$(uname -m) ;; esac
"$here/deploy-qt-macos.sh" "$setup" "$qt" "$app/Contents" "$arch"
# The game's own libraries (SDL2, OpenSSL, ...) are the release script's to bring
# into Frameworks; a development bundle runs with Homebrew's.
otool -L "$app/Contents/MacOS/Takedawn" | grep -E "^[[:space:]]+(/opt/homebrew|/usr/local)/" \
    | sed 's|^|note: the game still links |' >&2 || true

codesign --force --deep --sign - "$app" 2>/dev/null
codesign --verify --deep --strict "$app"
echo "built: $app"
du -sh "$app" "$app/Contents/Frameworks" "$app/Contents/PlugIns" "$app/Contents/MacOS"/* | sed 's|^|  |'
