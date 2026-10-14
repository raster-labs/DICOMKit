#!/usr/bin/env bash

# Select official Swift 6.4.0 with the hosted runner's existing default Xcode/SDK.
# Runtime qualification remains a required workflow gate.
set -euo pipefail

fail() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

[[ "${GITHUB_ACTIONS:-}" == 'true' ]] || fail 'This setup helper is for GitHub Actions runners only.'
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

selector="$GITHUB_WORKSPACE/.github/scripts/select-swift-toolchain.sh"
[[ -f "$selector" ]] || fail "Missing existing toolchain selector: $selector"

package_url='https://download.swift.org/swift-6.4.0-release/xcode/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-osx.pkg'
download_dir=''
cleanup() {
  if [[ -n "$download_dir" ]]; then
    rm -rf -- "$download_dir"
  fi
}
trap cleanup EXIT

is_swift_640() {
  # Some release binaries print 6.4 while others include the trailing .0.
  printf '%s\n' "$1" | head -n 1 | grep -Eq '(^| )Swift version 6\.4(\.0)?([[:space:]]|$)'
}

find_release_toolchain() {
  local candidate basename version
  local -a matches=()
  shopt -s nullglob
  for candidate in /Library/Developer/Toolchains/swift-6.4*.xctoolchain \
      "$HOME"/Library/Developer/Toolchains/swift-6.4*.xctoolchain; do
    [[ -d "$candidate" ]] || continue
    basename="${candidate##*/}"
    # Exclude snapshots, previews and later patch releases.
    [[ "$basename" =~ ^swift-6\.4(\.0)?-RELEASE\.xctoolchain$ ]] || continue
    if [[ ! -x "$candidate/usr/bin/swift" || ! -r "$candidate/Info.plist" ]]; then
      printf '::error::Incomplete existing release toolchain: %s\n' "$candidate" >&2
      return 2
    fi
    if ! version="$("$candidate/usr/bin/swift" --version 2>&1)"; then
      printf '::error::Existing release compiler cannot run: %s\n%s\n' "$candidate" "$version" >&2
      return 2
    fi
    if ! is_swift_640 "$version"; then
      printf '::error::Unexpected compiler in release toolchain: %s\n%s\n' "$candidate" "$version" >&2
      return 2
    fi
    matches+=("$candidate")
  done
  if [[ "${#matches[@]}" -eq 0 ]]; then
    return 1
  fi
  if [[ "${#matches[@]}" -ne 1 ]]; then
    printf '::error::Multiple exact Swift 6.4 release toolchains are installed; selection is ambiguous.\n' >&2
    return 2
  fi
  printf '%s\n' "${matches[0]}"
}

if toolchain_dir="$(find_release_toolchain)"; then
  printf 'Reusing installed release toolchain: %s\n' "$toolchain_dir"
else
  discovery_status=$?
  [[ "$discovery_status" -eq 1 ]] || fail 'Existing toolchain validation failed.'
  download_dir="$(mktemp -d "$RUNNER_TEMP/dicomkit-swift64.XXXXXX")"
  package_path="$download_dir/swift-6.4.0-RELEASE-osx.pkg"
  printf 'Official toolchain package: %s\n' "$package_url"
  curl --fail --location --show-error --silent \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 20 --max-time 600 \
    --retry 2 --retry-delay 2 --retry-max-time 900 \
    --output "$package_path" "$package_url"
  # Record package provenance; the digest is a receipt, not a pinned checksum.
  shasum -a 256 "$package_path"
  pkgutil --check-signature "$package_path"
  sudo installer -pkg "$package_path" -target /
  toolchain_dir="$(find_release_toolchain)" || fail 'Installed package did not provide one exact Swift 6.4 release toolchain.'
fi

toolchain_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$toolchain_dir/Info.plist")"
[[ "$toolchain_id" =~ ^[A-Za-z0-9.-]+$ ]] || fail 'Toolchain CFBundleIdentifier is missing or invalid.'
toolchain_bin="$toolchain_dir/usr/bin"
export TOOLCHAINS="$toolchain_id"
export PATH="$toolchain_bin:$PATH"
hash -r

# The existing selector checks the package's Swift requirement. Run it only
# after the custom compiler is active, retaining its default-Xcode selection.
cd "$GITHUB_WORKSPACE"
bash "$selector"

swift_version="$(swift --version)"
is_swift_640 "$swift_version" || fail 'The active compiler is not Swift 6.4.0.'
xcrun_swift="$(xcrun --find swift)"
expected_bin_dir="$(cd "$toolchain_bin" && pwd -P)"
actual_bin_dir="$(cd "$(dirname "$xcrun_swift")" && pwd -P)"
[[ "$actual_bin_dir" == "$expected_bin_dir" ]] || fail "xcrun selected a different toolchain: $xcrun_swift"
xcrun_version="$(xcrun swift --version)"
[[ "$xcrun_version" == "$swift_version" ]] || fail 'Direct Swift and xcrun Swift disagree.'

runtime_version="$(sw_vers -productVersion)"
runtime_build="$(sw_vers -buildVersion)"
runner_arch="$(uname -m)"
swift_path="$(command -v swift)"
developer_dir="$(xcode-select -p)"
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
xcode_version="$(xcodebuild -version)"
source_sha="$(git rev-parse --verify HEAD)"
# Isolate cached build products from other OS/compiler/SDK combinations. Include
# full versions so runner image updates cannot reuse an incompatible namespace.
cache_fingerprint="$(printf '%s\n' "$runtime_version" "$runtime_build" "$runner_arch" \
  "$toolchain_id" "$swift_version" "$developer_dir" "$xcode_version" \
  "$sdk_version" "$sdk_path" | shasum -a 256 | awk '{print $1}')"
cache_prefix="spm-v2-macos${runtime_version%%.*}-${runner_arch}-swift6.4.0-${cache_fingerprint}"
printf 'Runner runtime: %s (%s)\n' "$runtime_version" "$runtime_build"
printf 'Runner architecture: %s\n' "$runner_arch"
printf 'Toolchain directory: %s\nToolchain identifier: %s\n' "$toolchain_dir" "$toolchain_id"
printf 'Swift executable: %s\nxcrun Swift executable: %s\n' "$swift_path" "$xcrun_swift"
printf '%s\n' "$swift_version"
printf 'Selected developer directory: %s\n' "$developer_dir"
printf '%s\n' "$xcode_version"
printf 'macOS SDK version: %s\n' "$sdk_version"
printf 'macOS SDK path: %s\n' "$sdk_path"

# Persist only after every setup/selection check succeeds. GitHub applies these
# files to subsequent steps; the exports above cover this invocation itself.
printf 'TOOLCHAINS=%s\n' "$toolchain_id" >> "$GITHUB_ENV"
printf '%s\n' "$toolchain_bin" >> "$GITHUB_PATH"
printf 'cache-prefix=%s\n' "$cache_prefix" >> "$GITHUB_OUTPUT"
printf 'source-sha=%s\n' "$source_sha" >> "$GITHUB_OUTPUT"
