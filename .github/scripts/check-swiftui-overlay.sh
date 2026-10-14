#!/usr/bin/env bash
# Diagnostic only: four independent tiny builds, never the enclosing DICOM package.
set -euo pipefail
: "${RUNNER_TEMP:?}"
: "${GITHUB_STEP_SUMMARY:?}"
probe_dir="$RUNNER_TEMP/swiftui-overlay-package"
log_dir="$RUNNER_TEMP/swiftui-overlay-logs"
mkdir -p "$probe_dir/Sources/OverlayProbe" "$log_dir"
cat > "$probe_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "OverlayProbe", platforms: [.macOS(.v15)],
    products: [.executable(name: "OverlayProbe", targets: ["OverlayProbe"])],
    targets: [.executableTarget(name: "OverlayProbe")])
SWIFT
cat > "$probe_dir/Sources/OverlayProbe/OverlayProbe.swift" <<'SWIFT'
import SwiftUI
import AVKit

@MainActor
func videoPlayerProbe() -> some View {
    VideoPlayer(player: AVPlayer())
}

@main
struct OverlayProbe {
    static func main() {}
}
SWIFT
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
probe_source="$probe_dir/Sources/OverlayProbe/OverlayProbe.swift"
{
  command -v swift
  command -v swiftc
  swift --version
  xcrun swiftc --version
  xcodebuild -version
  sw_vers
  printf 'SDK=%s\n' "$sdk_path"
  swift build --help | sed -n '/--build-system/,+4p'
} | tee "$log_dir/environment.log"
printf '| Probe | Exit status |\n|---|---:|\n' > "$log_dir/summary.md"
failed=0
run_probe() {
  local name="$1" status
  shift
  printf 'Running %s\n' "$name"
  if "$@" > "$log_dir/$name.log" 2>&1; then status=0; else status=$?; fi
  printf 'PROBE_RESULT %s %s\n' "$name" "$status"
  printf '| %s | %s |\n' "$name" "$status" >> "$log_dir/summary.md"
  if [[ "$status" -ne 0 ]]; then
    failed=1
    tail -n 45 "$log_dir/$name.log"
  else
    tail -n 4 "$log_dir/$name.log"
  fi
}
run_probe swiftc-baseline swiftc -typecheck -parse-as-library -swift-version 6 \
  -sdk "$sdk_path" -target arm64-apple-macosx15.0 "$probe_source"
run_probe swiftc-overlays swiftc -typecheck -parse-as-library -swift-version 6 \
  -sdk "$sdk_path" -target arm64-apple-macosx15.0 \
  -Xfrontend -enable-cross-import-overlays "$probe_source"
run_probe swiftbuild-baseline swift build --package-path "$probe_dir" \
  --scratch-path "$RUNNER_TEMP/overlay-build-baseline" --build-system swiftbuild -v
run_probe swiftbuild-overlays swift build --package-path "$probe_dir" \
  --scratch-path "$RUNNER_TEMP/overlay-build-enabled" --build-system swiftbuild -v \
  -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays
cat "$log_dir/summary.md"
cat "$log_dir/summary.md" >> "$GITHUB_STEP_SUMMARY"
# Every failure stays visible, including an expected baseline failure.
exit "$failed"
