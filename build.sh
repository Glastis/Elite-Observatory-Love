#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

LOVE_VERSION="${LOVE_VERSION:-11.5}"
APP_ID="EliteObservatory"
APP_NAME="Elite Observatory"

BUILD_DIR="$PROJECT_ROOT/build"
CACHE_DIR="$BUILD_DIR/cache"
WORK_DIR="$BUILD_DIR/work"
DIST_DIR="$PROJECT_ROOT/dist"

LOVE_WIN_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-win64.zip"
LOVE_APPIMAGE_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-x86_64.AppImage"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

LOVE_WIN_ZIP="$CACHE_DIR/love-${LOVE_VERSION}-win64.zip"
LOVE_APPIMAGE="$CACHE_DIR/love-${LOVE_VERSION}-x86_64.AppImage"
APPIMAGETOOL="$CACHE_DIR/appimagetool-x86_64.AppImage"

LOVE_FILE="$DIST_DIR/${APP_ID}.love"
WIN_ZIP="$DIST_DIR/${APP_ID}-${LOVE_VERSION}-win64.zip"
APPIMAGE_OUT="$DIST_DIR/${APP_ID}-${LOVE_VERSION}-x86_64.AppImage"

LOVE_SOURCES=(
    main.lua
    conf.lua
    observatory
    plugins
    lib
    assets
    LICENSE
    README.md
)

REQUIRED_TOOL_HINTS="\
zip: zip / zip
unzip: unzip / unzip
curl: curl / curl
find: findutils / coreutils
file: file / file"

require_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        return
    fi
    local hint
    hint="$(echo "$REQUIRED_TOOL_HINTS" | awk -F': ' -v tool="$1" '$1==tool { print $2 }')"
    echo "missing required tool: $1" >&2
    if [ -n "$hint" ]; then
        echo "    install package (debian/ubuntu / arch): $hint" >&2
    fi
    exit 1
}

download_to() {
    local url="$1"
    local dest="$2"
    if [ -f "$dest" ]; then
        return
    fi
    echo "    downloading $(basename "$dest")"
    mkdir -p "$(dirname "$dest")"
    curl -fL --retry 3 -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
}

build_love_archive() {
    echo "==> packaging ${APP_ID}.love"
    rm -f "$LOVE_FILE"
    local missing=()
    for entry in "${LOVE_SOURCES[@]}"; do
        if [ ! -e "$entry" ]; then
            missing+=("$entry")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "missing project entries: ${missing[*]}" >&2
        exit 1
    fi
    zip -r -9 -q "$LOVE_FILE" "${LOVE_SOURCES[@]}" \
        -x "*.DS_Store" \
           "**/.git/*" \
           "**/.idea/*" \
           "**/.claude/*"
    echo "    -> $LOVE_FILE"
}

build_windows_portable() {
    echo "==> packaging Windows portable"
    download_to "$LOVE_WIN_URL" "$LOVE_WIN_ZIP"

    local win_work="$WORK_DIR/windows"
    rm -rf "$win_work"
    mkdir -p "$win_work"
    unzip -q "$LOVE_WIN_ZIP" -d "$win_work"

    local love_win_dir
    love_win_dir="$(find "$win_work" -maxdepth 1 -mindepth 1 -type d -name 'love-*' | head -n1)"
    if [ -z "$love_win_dir" ]; then
        echo "could not locate extracted LÖVE windows folder" >&2
        exit 1
    fi

    local win_payload="$win_work/${APP_ID}-win64"
    mkdir -p "$win_payload"
    cp "$love_win_dir"/*.dll "$win_payload/"
    if [ -f "$love_win_dir/license.txt" ]; then
        cp "$love_win_dir/license.txt" "$win_payload/LICENSE-LOVE.txt"
    fi
    cat "$love_win_dir/love.exe" "$LOVE_FILE" > "$win_payload/${APP_ID}.exe"

    rm -f "$WIN_ZIP"
    ( cd "$win_work" && zip -r -9 -q "$WIN_ZIP" "${APP_ID}-win64" )
    echo "    -> $WIN_ZIP"
}

write_apprun() {
    local appdir="$1"
    cat > "$appdir/AppRun" <<APPRUN_EOF
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\$0")")"
LOVE_BIN=""
for candidate in "\$HERE/bin/love" "\$HERE/usr/bin/love"; do
    if [ -x "\$candidate" ]; then
        LOVE_BIN="\$candidate"
        break
    fi
done
if [ -z "\$LOVE_BIN" ]; then
    echo "embedded love runtime not found in AppImage" >&2
    exit 1
fi
for libdir in "\$HERE/lib" "\$HERE/usr/lib"; do
    if [ -d "\$libdir" ]; then
        LD_LIBRARY_PATH="\$libdir:\${LD_LIBRARY_PATH:-}"
    fi
done
export LD_LIBRARY_PATH
exec "\$LOVE_BIN" "\$HERE/${APP_ID}.love" "\$@"
APPRUN_EOF
    chmod +x "$appdir/AppRun"
}

write_desktop() {
    local appdir="$1"
    find "$appdir" -maxdepth 1 -name '*.desktop' -delete
    local desktop="$appdir/${APP_ID}.desktop"
    cat > "$desktop" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=Live monitor for Elite Dangerous journals
Exec=AppRun
Icon=${APP_ID}
Categories=Game;
Terminal=false
DESKTOP_EOF
}

setup_icon() {
    local appdir="$1"
    local icon_src
    icon_src="$(find "$appdir" -maxdepth 1 -name 'love.png' -o -name 'love.svg' | head -n1)"
    if [ -z "$icon_src" ]; then
        icon_src="$(find "$appdir" -maxdepth 1 -name '.DirIcon' | head -n1)"
    fi
    if [ -z "$icon_src" ]; then
        echo "no source icon found in extracted AppImage" >&2
        exit 1
    fi
    local ext="${icon_src##*.}"
    if [ "$ext" = "$icon_src" ]; then
        ext="png"
    fi
    local icon_dest="$appdir/${APP_ID}.${ext}"
    cp "$icon_src" "$icon_dest"
    ln -sf "${APP_ID}.${ext}" "$appdir/.DirIcon"
    find "$appdir" -maxdepth 1 -name 'love.png' -delete
    find "$appdir" -maxdepth 1 -name 'love.svg' -delete
}

build_appimage() {
    echo "==> packaging Linux AppImage"
    download_to "$LOVE_APPIMAGE_URL" "$LOVE_APPIMAGE"
    download_to "$APPIMAGETOOL_URL" "$APPIMAGETOOL"
    chmod +x "$LOVE_APPIMAGE" "$APPIMAGETOOL"

    local appimage_work="$WORK_DIR/appimage"
    rm -rf "$appimage_work"
    mkdir -p "$appimage_work"
    ( cd "$appimage_work" && "$LOVE_APPIMAGE" --appimage-extract >/dev/null )
    local appdir="$appimage_work/squashfs-root"

    cp "$LOVE_FILE" "$appdir/${APP_ID}.love"
    write_apprun "$appdir"
    setup_icon "$appdir"
    write_desktop "$appdir"

    rm -f "$APPIMAGE_OUT"
    ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run --no-appstream "$appdir" "$APPIMAGE_OUT" >/dev/null
    chmod +x "$APPIMAGE_OUT"
    echo "    -> $APPIMAGE_OUT"
}

main() {
    for tool in zip unzip curl find file; do
        require_cmd "$tool"
    done

    rm -rf "$WORK_DIR"
    mkdir -p "$CACHE_DIR" "$WORK_DIR" "$DIST_DIR"

    build_love_archive
    build_windows_portable
    build_appimage

    echo
    echo "build complete:"
    ls -lh "$DIST_DIR"
}

main "$@"
