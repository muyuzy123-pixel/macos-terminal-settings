#!/bin/zsh
# Shared by build.sh and verify.sh; source this file, then call
# terminal_settings_toolchain with either "build" or "verify".

terminal_settings_error() {
  print -u2 -r -- "TerminalSettings: $*"
  return 1
}

terminal_settings_sdk_version() {
  local canonical_name
  [[ -f "$1/SDKSettings.plist" ]] || return 1
  canonical_name="$(plutil -extract CanonicalName raw "$1/SDKSettings.plist" 2>/dev/null)" || return 1
  [[ "$canonical_name" == macosx* ]] || return 1
  plutil -extract Version raw "$1/SDKSettings.plist" 2>/dev/null
}

terminal_settings_toolchain() {
  local action="$1" required host_version resolved_sdk candidate version
  local -a sdk_candidates

  if [[ "$(uname -s)" != Darwin ]]; then
    terminal_settings_error "Building and verification require macOS; this host is unsupported."
    return 1
  fi
  for required in sw_vers xcrun plutil mkdir cp; do
    if ! command -v "$required" >/dev/null 2>&1; then
      terminal_settings_error "Required tool '$required' was not found. Install Apple's Command Line Tools or Xcode."
      return 1
    fi
  done
  host_version="$(sw_vers -productVersion)"
  if [[ "${host_version%%.*}" != <-> ]] || (( ${host_version%%.*} < 14 )); then
    terminal_settings_error "macOS 14 or later is required; this host reports $host_version."
    return 1
  fi
  if [[ "$action" == verify && "$(uname -m)" != arm64 ]]; then
    terminal_settings_error "Verification runs arm64 executables and requires a native Apple Silicon shell. On Apple Silicon, run: arch -arm64 /bin/zsh ./verify.sh [--contract-only]. Intel hosts can only cross-build the arm64 app."
    return 1
  fi
  if [[ "$action" == build ]]; then
    for required in codesign ditto xattr mktemp mv rm cmp; do
      if ! command -v "$required" >/dev/null 2>&1; then
        terminal_settings_error "Required packaging tool '$required' was not found."
        return 1
      fi
    done
  fi

  # An explicit developer directory always wins. Otherwise prefer standalone
  # CLT, which also avoids a separately selected Xcode's license prompt.
  if (( ${+DEVELOPER_DIR} )); then
    if [[ -z "$DEVELOPER_DIR" || ! -d "$DEVELOPER_DIR" ]]; then
      terminal_settings_error "DEVELOPER_DIR must name an existing Xcode or Command Line Tools developer directory."
      return 1
    fi
    export DEVELOPER_DIR
  elif [[ -x /Library/Developer/CommandLineTools/usr/bin/clang &&
          -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  fi
  if ! CLANG="$(xcrun --find clang)" || [[ ! -x "$CLANG" ]]; then
    terminal_settings_error "Cannot resolve clang. Check DEVELOPER_DIR and install a complete Apple developer toolchain."
    return 1
  fi
  if ! SWIFTC="$(xcrun --find swiftc)" || [[ ! -x "$SWIFTC" ]]; then
    terminal_settings_error "Cannot resolve swiftc. Check DEVELOPER_DIR and install a complete Apple developer toolchain."
    return 1
  fi

  SDK=""
  if (( ${+SDKROOT} )); then
    if [[ -z "$SDKROOT" ]]; then
      terminal_settings_error "SDKROOT was provided but is empty; use a macOS 26 SDK path or identifier, or unset it."
      return 1
    fi
    if [[ -d "$SDKROOT" ]]; then
      SDK="${SDKROOT:A}"
    elif ! SDK="$(xcrun --sdk "$SDKROOT" --show-sdk-path)"; then
      terminal_settings_error "Cannot resolve the explicitly requested SDKROOT '$SDKROOT'."
      return 1
    fi
    if ! SDK_VERSION="$(terminal_settings_sdk_version "$SDK")"; then
      terminal_settings_error "SDKROOT must reference a macOS SDK with readable CanonicalName and Version in '$SDK/SDKSettings.plist'."
      return 1
    fi
  else
    # Start with the selected toolchain's default SDK, then its other installed
    # SDKs. Aliases such as MacOSX.sdk are valid; folder names are not versions.
    resolved_sdk="$(xcrun --sdk macosx --show-sdk-path)" || {
      terminal_settings_error "Cannot locate a macOS SDK in the selected developer toolchain."
      return 1
    }
    sdk_candidates=("$resolved_sdk" "${resolved_sdk:h}"/*.sdk(NOn))
    for candidate in "${sdk_candidates[@]}"; do
      version="$(terminal_settings_sdk_version "$candidate")" || continue
      if [[ "$version" =~ '^[0-9]+(\.[0-9]+)*$' && "${version%%.*}" == 26 ]]; then
        SDK="${candidate:A}"
        SDK_VERSION="$version"
        break
      fi
    done
    if [[ -z "$SDK" ]]; then
      terminal_settings_error "A macOS 26.x SDK is required. None was found beside '$resolved_sdk'. Install a matching Apple toolchain or set DEVELOPER_DIR / SDKROOT explicitly."
      return 1
    fi
  fi
  if [[ ! "$SDK_VERSION" =~ '^[0-9]+(\.[0-9]+)*$' || "${SDK_VERSION%%.*}" != 26 ]]; then
    terminal_settings_error "A macOS 26.x SDK is required; SDKROOT resolves to SDK version '$SDK_VERSION' at '$SDK'."
    return 1
  fi
  SDK_TAG="macOS-$SDK_VERSION"
  MODULE_CACHE="$ROOT/.build/module-cache-$SDK_TAG"
  print -r -- "Using macOS SDK $SDK_VERSION at $SDK"
  print -r -- "Using Swift compiler $SWIFTC"
  print -r -- "Target: arm64, macOS 14.0 or later"
}
