#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
BUILD="$ROOT/.build/checks"
BRIDGE_OBJECT="$BUILD/AuthorizationBridge.o"
CONTRACT_ONLY=0
if [[ "${1:-}" == "--contract-only" ]]; then
  CONTRACT_ONLY=1
  shift
fi
if (( $# != 0 )); then
  echo "Usage: ./verify.sh [--contract-only]" >&2
  exit 2
fi

source "$ROOT/scripts/toolchain.sh"
terminal_settings_toolchain verify

mkdir -p "$BUILD" "$MODULE_CACHE"
TEST_RESOURCES="$BUILD/LocalizationTests.bundle"
mkdir -p "$TEST_RESOURCES/Contents/Resources"
cp -R "$ROOT/Resources/en.lproj" "$ROOT/Resources/zh-Hans.lproj" "$TEST_RESOURCES/Contents/Resources/"
cp "$ROOT/Info.plist" "$TEST_RESOURCES/Contents/Info.plist"
export TERMINAL_SETTINGS_TEST_RESOURCE_BUNDLE="$TEST_RESOURCES"

"$CLANG" \
  -target arm64-apple-macos14.0 \
  -isysroot "$SDK" \
  -Wno-deprecated-declarations \
  -c "$ROOT/Source/AuthorizationBridge.c" \
  -o "$BRIDGE_OBJECT"

# Type-check the complete application, including SwiftUI views and app entry.
"$SWIFTC" \
  -swift-version 5 \
  -D TERMINAL_SETTINGS_TESTING \
  -parse-as-library \
  -typecheck \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Security \
  "$ROOT/Source/Localization.swift" \
  "$ROOT/Source/Models.swift" \
  "$ROOT/Source/Catalog.swift" \
  "$ROOT/Source/Dependencies.swift" \
  "$ROOT/Source/PowerSettingsExecutor.swift" \
  "$ROOT/Source/PreferencesStore.swift" \
  "$ROOT/Source/Views.swift" \
  "$ROOT/Source/TerminalSettingsApp.swift"

"$SWIFTC" \
  -swift-version 5 \
  -D TERMINAL_SETTINGS_TESTING \
  -parse-as-library \
  -Onone \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
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
  "$ROOT/Tests/TerminalSettingsChecks.swift" \
  "$BRIDGE_OBJECT" \
  -o "$BUILD/TerminalSettingsChecks"

if (( CONTRACT_ONLY )); then
  TERMINAL_SETTINGS_CONTRACT_ONLY=1 "$BUILD/TerminalSettingsChecks"
else
  # Do not let a caller's inherited environment silently downgrade a full
  # verification run into the contract-only path.
  TERMINAL_SETTINGS_CONTRACT_ONLY=0 "$BUILD/TerminalSettingsChecks"
fi
