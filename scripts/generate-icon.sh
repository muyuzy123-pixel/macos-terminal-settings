#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
ICON="$ROOT/AppIcon.icns"
if (( $# != 0 )); then
  print -u2 -r -- "Usage: ./scripts/generate-icon.sh"
  exit 2
fi
if [[ -L "$ICON" || ( -e "$ICON" && ! -f "$ICON" ) ]]; then
  print -u2 -r -- "AppIcon.icns must be a regular file, not a symlink or directory."
  exit 1
fi

source "$ROOT/scripts/toolchain.sh"
terminal_settings_toolchain build
for required in sips iconutil awk; do
  if ! command -v "$required" >/dev/null 2>&1; then
    print -u2 -r -- "Required icon tool '$required' was not found."
    exit 1
  fi
done

STAGING="$(mktemp -d /tmp/TerminalSettingsIcon.XXXXXX)"
NEXT_ICON=""
cleanup() {
  rm -rf "$STAGING"
  if [[ -n "$NEXT_ICON" ]]; then
    rm -f "$NEXT_ICON"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ICONSET="$STAGING/AppIcon.iconset"
VERIFIED_ICONSET="$STAGING/Verified.iconset"
mkdir -p "$ICONSET" "$STAGING/module-cache"

# Compile the existing drawing source directly. Both the executable and Swift
# module cache stay in the temporary directory; no interpreter cache is needed.
"$SWIFTC" -swift-version 5 -sdk "$SDK" \
  -module-cache-path "$STAGING/module-cache" -framework AppKit \
  "$ROOT/Source/GenerateIcon.swift" -o "$STAGING/GenerateIcon"
"$STAGING/GenerateIcon" "$STAGING/master.png"

# AppKit may render the master at the current display's backing scale. Resize
# every representation explicitly so the result has standard pixel dimensions.
for point_size in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$(( point_size * scale ))
    suffix=""
    if (( scale == 2 )); then suffix="@2x"; fi
    sips -z "$pixels" "$pixels" "$STAGING/master.png" \
      --out "$ICONSET/icon_${point_size}x${point_size}${suffix}.png" >/dev/null
  done
done
iconutil -c icns "$ICONSET" -o "$STAGING/AppIcon.icns"

# Validate the actual encoded archive by extracting it again. Do not replace
# the existing project icon until all ten representations can be read back.
iconutil -c iconset "$STAGING/AppIcon.icns" -o "$VERIFIED_ICONSET"
for point_size in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$(( point_size * scale ))
    suffix=""
    if (( scale == 2 )); then suffix="@2x"; fi
    representation="$VERIFIED_ICONSET/icon_${point_size}x${point_size}${suffix}.png"
    [[ -f "$representation" ]] || {
      print -u2 -r -- "Generated icon is missing ${representation:t}."
      exit 1
    }
    dimensions="$(sips -g pixelWidth -g pixelHeight "$representation" |
      awk '/pixelWidth:/ { w=$2 } /pixelHeight:/ { h=$2 } END { print w, h }')"
    if [[ "$dimensions" != "$pixels $pixels" ]]; then
      print -u2 -r -- "Invalid dimensions for ${representation:t}: $dimensions"
      exit 1
    fi
  done
done

# The final rename happens on the same filesystem, protecting the prior icon
# if drawing, conversion, validation, or the copy into this directory fails.
NEXT_ICON="$(mktemp "$ROOT/.AppIcon.icns.XXXXXX")"
cp "$STAGING/AppIcon.icns" "$NEXT_ICON"
chmod 644 "$NEXT_ICON"
mv -f "$NEXT_ICON" "$ICON"
NEXT_ICON=""
print -r -- "Generated $ICON with 16/32/128/256/512 point images at 1x and 2x."
