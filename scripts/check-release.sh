#!/bin/zsh
# Verify the ZIP independently, then publish its checksum and release manifest.
# This checks the distributable and never launches the app or writes preferences.
set -euo pipefail

ROOT="${0:A:h:h}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $0 [archive.zip [output-directory]]"
  echo "Defaults: $ROOT/TerminalSettings.zip and $ROOT/dist"
  exit 0
fi
if (( $# > 2 )); then
  echo "Usage: $0 [archive.zip [output-directory]]" >&2
  exit 2
fi
if [[ "$(uname -s)" != Darwin || ! -x /usr/bin/python3 ]]; then
  echo "Release verification requires macOS and Apple's Command Line Tools Python 3." >&2
  exit 1
fi

ARCHIVE="${1:-$ROOT/TerminalSettings.zip}"
OUTPUT="${2:-$ROOT/dist}"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/TerminalSettingsRelease.XXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT

/usr/bin/python3 - "$ROOT" "$ARCHIVE" "$OUTPUT" "$STAGING" <<'PY'
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_codesign(arguments):
    result = subprocess.run(
        ["/usr/bin/codesign", *arguments],
        capture_output=True, text=True, check=False,
        env={**os.environ, "LC_ALL": "C"},
    )
    require(result.returncode == 0,
            "codesign failed:\n" + result.stdout + result.stderr)
    return result.stdout + result.stderr


def read_macho(path):
    # Parse the on-disk Mach-O instead of depending on the selected Xcode's otool.
    data = path.read_bytes()
    require(len(data) >= 32, "Executable has a truncated Mach-O header")
    header = struct.unpack_from("<8I", data)
    magic, cpu, subtype, filetype, count, command_bytes, flags, reserved = header
    require(magic == 0xFEEDFACF, "Expected a thin, little-endian 64-bit Mach-O")
    require(cpu == 0x0100000C and (subtype & 0x00FFFFFF) == 0,
            "Expected the arm64 architecture (not arm64e or a universal binary)")
    require(filetype == 2, "Mach-O must be an executable")
    end = 32 + command_bytes
    require(end <= len(data), "Mach-O load commands exceed the executable")
    offset = 32
    versions = []
    signatures = []
    for _ in range(count):
        require(offset + 8 <= end, "Truncated Mach-O load command")
        command, length = struct.unpack_from("<II", data, offset)
        require(length >= 8 and length % 8 == 0 and offset + length <= end,
                "Invalid Mach-O load command size")
        if command == 0x32:  # LC_BUILD_VERSION
            require(length >= 24, "Truncated LC_BUILD_VERSION")
            platform, minimum, sdk, tool_count = struct.unpack_from(
                "<IIII", data, offset + 8)
            require(length == 24 + tool_count * 8, "Invalid LC_BUILD_VERSION size")
            versions.append((platform, minimum, sdk))
        elif command == 0x24:  # LC_VERSION_MIN_MACOSX would contradict this build.
            raise ValueError("Unexpected legacy minimum macOS load command")
        elif command == 0x1D:  # LC_CODE_SIGNATURE
            require(length == 16, "Invalid LC_CODE_SIGNATURE size")
            signature_offset, signature_size = struct.unpack_from(
                "<II", data, offset + 8)
            require(signature_size > 0 and signature_offset >= end and
                    signature_offset + signature_size <= len(data),
                    "Invalid embedded signature range")
            signatures.append((signature_offset, signature_size))
        offset += length
    require(offset == end, "Mach-O load command lengths do not match the header")
    require(len(versions) == 1, "Expected exactly one LC_BUILD_VERSION")
    require(len(signatures) == 1, "Expected exactly one embedded code signature")
    platform, minimum, sdk = versions[0]
    require(platform == 1, "Executable platform must be macOS")
    require(minimum == 0x000E0000, "Executable minimum macOS must be 14.0")
    require(sdk >> 16 == 26, "Executable must be built with a macOS 26 SDK")
    return {
        "architectures": ["arm64"],
        "minimum_macos": "14.0",
        "sdk_version": "{}.{}.{}".format(sdk >> 16, (sdk >> 8) & 255, sdk & 255),
    }


def main():
    root, original_archive, output, staging = map(Path, sys.argv[1:])
    root, original_archive, output, staging = (
        path.resolve() for path in (root, original_archive, output, staging))
    require(original_archive.is_file(), "Archive does not exist: " + str(original_archive))
    require(original_archive.stat().st_size <= 512 * 1024 * 1024,
            "Archive exceeds the 512 MiB release-verification limit")

    # Every check and the published ZIP use one immutable snapshot, including if
    # another build replaces the original archive while verification is running.
    archive_path = staging / "TerminalSettings.zip"
    shutil.copyfile(original_archive, archive_path)
    require(archive_path.stat().st_size <= 512 * 1024 * 1024,
            "Archive snapshot exceeds the 512 MiB verification limit")

    app_name = "TerminalSettings.app"
    source_resources = {
        "Contents/Info.plist": "Info.plist",
        "Contents/Resources/AppIcon.icns": "AppIcon.icns",
        "Contents/Resources/LICENSE": "LICENSE",
    }
    for language in ("en", "zh-Hans"):
        for filename in ("InfoPlist.strings", "Localizable.strings"):
            relative = "Resources/{}/{}".format(language + ".lproj", filename)
            source_resources["Contents/" + relative] = relative
    expected_files = {
        app_name + "/" + relative for relative in source_resources
    } | {
        app_name + "/Contents/MacOS/TerminalSettings",
        app_name + "/Contents/_CodeSignature/CodeResources",
    }
    expected_directories = set()
    for filename in expected_files:
        for parent in Path(filename).parents:
            if str(parent) != ".":
                expected_directories.add(parent.as_posix() + "/")

    extracted = staging / "extracted"
    extracted.mkdir()
    with zipfile.ZipFile(archive_path) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        require(len(names) == len(set(names)), "ZIP contains duplicate paths")
        require(len(names) == len({name.casefold() for name in names}),
                "ZIP contains case-colliding paths")
        require(sum(entry.file_size for entry in entries) <= 512 * 1024 * 1024,
                "ZIP exceeds the 512 MiB unpacked-size limit")
        actual_files = set()
        for entry in entries:
            name = entry.filename
            # A strict allowlist also excludes traversal, absolute paths,
            # AppleDouble, __MACOSX, .DS_Store, and unanticipated bundle files.
            require(entry.orig_filename == name and "\\" not in name and
                    name in expected_files | expected_directories,
                    "Unexpected or unsafe ZIP path: " + repr(name))
            require(not (entry.flag_bits & 1), "Encrypted ZIP entries are unsupported")
            mode = (entry.external_attr >> 16) & 0xFFFF
            file_type = stat.S_IFMT(mode)
            if entry.is_dir():
                require(name in expected_directories and entry.file_size == 0,
                        "Unexpected directory entry: " + name)
                require(file_type in (0, stat.S_IFDIR), "Non-directory mode: " + name)
                (extracted / name).mkdir(parents=True, exist_ok=True)
            else:
                require(name in expected_files, "Expected a directory: " + name)
                require(file_type in (0, stat.S_IFREG),
                        "ZIP contains a symlink or other non-regular file: " + name)
                require(not (mode & (stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX)),
                        "ZIP contains special permission bits: " + name)
                actual_files.add(name)
        require(actual_files == expected_files,
                "ZIP is missing expected files: " + ", ".join(sorted(expected_files - actual_files)))
        for entry in entries:
            if entry.is_dir():
                continue
            destination = extracted / entry.filename
            destination.parent.mkdir(parents=True, exist_ok=True)
            # Streaming to EOF also verifies the ZIP CRC for every file.
            with archive.open(entry) as source, destination.open("xb") as target:
                shutil.copyfileobj(source, target)
            require(destination.stat().st_size == entry.file_size,
                    "Extracted file size mismatch: " + entry.filename)
            permissions = (entry.external_attr >> 16) & 0o777
            require(permissions != 0, "ZIP must preserve UNIX permissions: " + entry.filename)
            destination.chmod(permissions)

    app = extracted / app_name
    executable = app / "Contents/MacOS/TerminalSettings"
    require(executable.stat().st_mode & stat.S_IXUSR,
            "The packaged executable is missing its executable permission")
    source_hashes = {}
    source_data = {}
    for relative, source in source_resources.items():
        source_path = root / source
        require(source_path.is_file(), "Missing source resource: " + source)
        source_data[source] = source_path.read_bytes()
        require((app / relative).read_bytes() == source_data[source],
                "Packaged resource differs from source: " + source)
        source_hashes[source] = hashlib.sha256(source_data[source]).hexdigest()

    expected_info = plistlib.loads(source_data["Info.plist"])
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    for key in ("CFBundleShortVersionString", "CFBundleVersion", "CFBundleIdentifier"):
        require(isinstance(info.get(key), str) and bool(info[key]) and
                info[key] == expected_info.get(key), "Invalid or mismatched " + key)
    require(info.get("CFBundleExecutable") == "TerminalSettings", "Unexpected executable name")
    require(info.get("CFBundlePackageType") == "APPL", "Unexpected bundle package type")
    require(info.get("LSMinimumSystemVersion") == "14.0", "Info.plist minimum macOS must be 14.0")
    require(sorted(info.get("CFBundleLocalizations", [])) == ["en", "zh-Hans"],
            "Expected exactly the en and zh-Hans bundle localizations")
    require(info.get("CFBundleIconFile") in ("AppIcon", "AppIcon.icns"), "Unexpected icon name")
    macho = read_macho(executable)

    run_codesign(["--verify", "--deep", "--strict", "--verbose=2", str(app)])
    signature = run_codesign(["--display", "--verbose=4", str(app)])
    signature_lines = signature.splitlines()
    require("Signature=adhoc" in signature_lines, "Expected an ad-hoc preview signature")
    require("TeamIdentifier=not set" in signature_lines and
            not any(line.startswith("Authority=") for line in signature_lines),
            "Unexpected signing identity; update release policy before publishing")
    code_directories = [line for line in signature_lines if line.startswith("CodeDirectory ")]
    require(len(code_directories) == 1, "Expected exactly one displayed CodeDirectory")
    flag_match = re.search(r"\bflags=0x([0-9a-fA-F]+)\b", code_directories[0])
    require(flag_match is not None and int(flag_match.group(1), 16) & 0x10000,
            "CodeDirectory must enable hardened runtime")

    digest = sha256(archive_path)
    manifest = {
        "schema_version": 1,
        "artifact": {
            "filename": "TerminalSettings.zip",
            "size_bytes": archive_path.stat().st_size,
            "sha256": digest,
        },
        "bundle": {
            "name": app_name,
            "identifier": info["CFBundleIdentifier"],
            "version": info["CFBundleShortVersionString"],
            "build": info["CFBundleVersion"],
            "localizations": ["en", "zh-Hans"],
            **macho,
        },
        "distribution": {
            "channel": "ad-hoc-preview",
            "signature": "ad-hoc",
            "hardened_runtime": True,
            "developer_id_signed": False,
            "notarization": "not_claimed",
            "gatekeeper_acceptance": "not_tested",
        },
        "license": {
            "source_file": "LICENSE",
            "bundle_file": app_name + "/Contents/Resources/LICENSE",
            "sha256": source_hashes["LICENSE"],
        },
        "verification": {
            "verified_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "checks_passed": [
                "archive_path_and_file_allowlist", "archive_crc",
                "bundle_metadata_matches_source", "resources_match_source_bytes",
                "license_matches_source_bytes",
                "thin_arm64_macho", "macos_14_0_deployment_target",
                "macos_26_sdk", "codesign_deep_strict",
                "ad_hoc_signature_identity", "hardened_runtime",
            ],
            "runtime_ui_acceptance": "not_tested",
            "binary_source_correspondence": "not_established_by_this_check",
        },
        "source_resource_sha256": dict(sorted(source_hashes.items())),
        "bundle_file_sha256": {
            name: sha256(extracted / name) for name in sorted(expected_files)
        },
    }

    # Nothing reaches dist until all checks pass. Prepare the complete set on
    # the destination filesystem, then replace each output; manifest goes last.
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".release-check-", dir=output) as publish:
        publish = Path(publish)
        shutil.copyfile(archive_path, publish / "TerminalSettings.zip")
        (publish / "SHA256SUMS").write_text(
            digest + "  TerminalSettings.zip\n", encoding="ascii")
        (publish / "release-manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8")
        for filename in ("TerminalSettings.zip", "SHA256SUMS", "release-manifest.json"):
            os.replace(publish / filename, output / filename)
    print("Release archive verified: version {} (build {}), arm64, macOS 14.0+.".format(
        info["CFBundleShortVersionString"], info["CFBundleVersion"]))
    print("Distribution: ad-hoc preview; no Developer ID or notarization claim.")
    print("Release files: " + str(output))


try:
    main()
except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile, RuntimeError) as error:
    print("Release verification FAILED: " + str(error), file=sys.stderr)
    sys.exit(1)
PY
