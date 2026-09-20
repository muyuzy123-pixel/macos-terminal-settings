#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/TerminalSettings.app"
ARCHIVE="$ROOT/TerminalSettings.zip"
if (( $# != 0 )); then
  echo "Usage: ./build.sh" >&2
  exit 2
fi
source "$ROOT/scripts/toolchain.sh"
terminal_settings_toolchain build

# Refuse unusual output types rather than following symlinks or replacing an
# unrelated directory. Prior releases remain untouched until packaging passes.
if [[ -L "$APP" || ( -e "$APP" && ! -d "$APP" ) ||
      -L "$ARCHIVE" || ( -e "$ARCHIVE" && ! -f "$ARCHIVE" ) ]]; then
  terminal_settings_error "Output paths must be an app directory and a regular zip file, not symlinks or other file types."
  exit 1
fi
STAGING="$(mktemp -d /tmp/TerminalSettingsBuild.XXXXXX)"
PUBLISHING=""
PUBLISH_STARTED=0
PUBLISH_COMPLETE=0
HAD_APP=0
HAD_ARCHIVE=0
STAGED_APP="$STAGING/TerminalSettings.app"
STAGED_ARCHIVE="$STAGING/TerminalSettings.zip"
CONTENTS="$STAGED_APP/Contents"
BRIDGE_OBJECT="$STAGING/AuthorizationBridge.o"

# A failed replacement restores the preceding pair. Keep backup files if a
# rollback itself fails so they can be recovered manually. As with any shell
# cleanup, SIGKILL and power loss cannot run this handler.
cleanup() {
  local exit_status="$1" recovery_failed=0
  set +e
  if (( PUBLISH_STARTED && ! PUBLISH_COMPLETE )); then
    if [[ -d "$PUBLISHING/previous.app" ]]; then
      rm -rf "$APP" && mv "$PUBLISHING/previous.app" "$APP" || recovery_failed=1
    elif (( ! HAD_APP )); then
      rm -rf "$APP" || recovery_failed=1
    fi
    if [[ -f "$PUBLISHING/previous.zip" ]]; then
      rm -f "$ARCHIVE" && mv "$PUBLISHING/previous.zip" "$ARCHIVE" || recovery_failed=1
    elif (( ! HAD_ARCHIVE )); then
      rm -f "$ARCHIVE" || recovery_failed=1
    fi
    if (( recovery_failed )); then
      print -u2 -r -- "Rollback could not finish. Recover prior outputs from: $PUBLISHING"
      exit_status=1
    fi
  fi
  rm -rf "$STAGING"
  if [[ -n "$PUBLISHING" ]] && (( ! recovery_failed )); then
    rm -rf "$PUBLISHING"
  fi
  return "$exit_status"
}
trap 'cleanup $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$MODULE_CACHE"

"$CLANG" \
  -target arm64-apple-macos14.0 \
  -isysroot "$SDK" \
  -Wno-deprecated-declarations \
  -c "$ROOT/Source/AuthorizationBridge.c" \
  -o "$BRIDGE_OBJECT"

"$SWIFTC" \
  -swift-version 5 \
  -parse-as-library \
  -O \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Security \
  -Xlinker -platform_version \
  -Xlinker macos \
  -Xlinker 14.0 \
  -Xlinker "$SDK_VERSION" \
  "$ROOT/Source/Localization.swift" \
  "$ROOT/Source/Models.swift" \
  "$ROOT/Source/Catalog.swift" \
  "$ROOT/Source/Dependencies.swift" \
  "$ROOT/Source/PowerSettingsExecutor.swift" \
  "$ROOT/Source/PreferencesStore.swift" \
  "$ROOT/Source/Views.swift" \
  "$ROOT/Source/TerminalSettingsApp.swift" \
  "$BRIDGE_OBJECT" \
  -o "$CONTENTS/MacOS/TerminalSettings"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/LICENSE" "$CONTENTS/Resources/LICENSE"
cp -R "$ROOT/Resources/en.lproj" "$ROOT/Resources/zh-Hans.lproj" "$CONTENTS/Resources/"

if [[ -f "$ROOT/AppIcon.icns" ]]; then
  cp "$ROOT/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

xattr -cr "$STAGED_APP"
codesign --force --sign - --options runtime --timestamp=none "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

# Validate the distributable after extraction as well as the source bundle.
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
  "$STAGED_APP" "$STAGED_ARCHIVE"
ditto -x -k "$STAGED_ARCHIVE" "$STAGING/extracted"
codesign --verify --deep --strict "$STAGING/extracted/TerminalSettings.app"

# Prepare a fresh destination on the same filesystem so mv replaces whole
# bundles, never merges new files into an older release. Signing stays in /tmp
# to avoid Finder/File Provider metadata during bundle assembly. Documents can
# reattach that metadata asynchronously, including in this temporary directory.
# Verify the copied bundle's signature normally; strict verification above
# remains mandatory for the clean source bundle and independently extracted ZIP.
PUBLISHING="$(mktemp -d "$ROOT/.TerminalSettingsPublish.XXXXXX")"
ditto --norsrc --noextattr --noqtn --noacl "$STAGED_APP" "$PUBLISHING/TerminalSettings.app"
xattr -cr "$PUBLISHING/TerminalSettings.app"
codesign --verify --deep "$PUBLISHING/TerminalSettings.app"
cp "$STAGED_ARCHIVE" "$PUBLISHING/TerminalSettings.zip"
cmp -s "$STAGED_ARCHIVE" "$PUBLISHING/TerminalSettings.zip"

[[ ! -e "$APP" ]] || HAD_APP=1
[[ ! -e "$ARCHIVE" ]] || HAD_ARCHIVE=1
PUBLISH_STARTED=1
if (( HAD_APP )); then
  mv "$APP" "$PUBLISHING/previous.app"
fi
if (( HAD_ARCHIVE )); then
  mv "$ARCHIVE" "$PUBLISHING/previous.zip"
fi
mv "$PUBLISHING/TerminalSettings.app" "$APP"
mv "$PUBLISHING/TerminalSettings.zip" "$ARCHIVE"
# The working copy can receive Finder/File Provider metadata again on rename.
# That metadata does not change the already strictly verified source or ZIP.
# Any failure of normal signature verification still restores the prior release.
xattr -cr "$APP"
codesign --verify --deep "$APP"
cmp -s "$STAGED_ARCHIVE" "$ARCHIVE"
PUBLISH_COMPLETE=1
echo "Built $APP"
echo "Archive $ARCHIVE"
