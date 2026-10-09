#!/usr/bin/env bash

# Select an installed Xcode that can build this package and fail early when
# the runner's Swift toolchain is older than the package's tools version.
set -euo pipefail

requested_version="${1:-}"
package_version="$(sed -nE '1s/.*swift-tools-version: *([0-9]+\.[0-9]+).*/\1/p' Package.swift)"
required_version="${SWIFT_VERSION:-$package_version}"

select_developer_dir() {
  local candidate

  if [[ -n "$requested_version" ]]; then
    candidate="/Applications/Xcode_${requested_version}.app/Contents/Developer"
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    echo "::warning::Xcode ${requested_version} is not installed on this runner; selecting the newest installed Xcode instead." >&2
  fi

  # macOS runner images may rename or remove point-release Xcode bundles.
  # Prefer the default Xcode when present, then fall back to the newest bundle.
  if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    printf '%s\n' "/Applications/Xcode.app/Contents/Developer"
    return 0
  fi

  candidate="$(find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print 2>/dev/null | sort | tail -n 1 || true)"
  if [[ -n "$candidate" && -d "$candidate/Contents/Developer" ]]; then
    printf '%s\n' "$candidate/Contents/Developer"
    return 0
  fi

  echo "::error::No Xcode installation was found under /Applications." >&2
  return 1
}

developer_dir="$(select_developer_dir)"
sudo xcode-select -s "$developer_dir"

echo "Selected developer directory: $(xcode-select -p)"
xcodebuild -version
swift --version

# Swift tools versions are compared numerically (6.0 must not silently run a
# package that declares swift-tools-version: 6.4).
actual_version="$(swift --version | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -n 1)"
if [[ -z "$actual_version" ]]; then
  echo "::error::Unable to determine the selected Swift version." >&2
  exit 1
fi

if ! awk -v actual="$actual_version" -v required="$required_version" 'BEGIN { exit !(actual + 0 >= required + 0) }'; then
  echo "::error::Swift ${actual_version} is older than the required Swift ${required_version}." >&2
  exit 1
fi

echo "Swift ${actual_version} satisfies the package requirement (${required_version}+)."
