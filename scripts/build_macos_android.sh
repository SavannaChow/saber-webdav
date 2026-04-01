#!/usr/bin/env bash
# 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  scripts/build_macos_android.sh [all|android|macos]

Examples:
  scripts/build_macos_android.sh
  scripts/build_macos_android.sh all
  scripts/build_macos_android.sh android
  scripts/build_macos_android.sh macos

Notes:
  - Android build outputs:
    build/app/outputs/flutter-apk/app-release.apk
  - macOS build outputs:
    build/macos_unsigned/Build/Products/Release/Saber.app
  - macOS build is unsigned on purpose, so it can build without provisioning.
EOF
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

build_android() {
  echo "==> Building Android APK"
  flutter build apk --target-platform android-arm64
  echo
  echo "Android artifact:"
  echo "  $REPO_ROOT/build/app/outputs/flutter-apk/app-release.apk"
}

build_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "macOS build requires macOS/Xcode." >&2
    exit 1
  fi

  echo "==> Preparing macOS build"
  flutter build macos --config-only

  echo "==> Building unsigned macOS app"
  xcodebuild \
    -quiet \
    -workspace "$REPO_ROOT/macos/Runner.xcworkspace" \
    -scheme Runner \
    -configuration Release \
    -derivedDataPath "$REPO_ROOT/build/macos_unsigned" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    build

  echo
  echo "macOS artifact:"
  echo "  $REPO_ROOT/build/macos_unsigned/Build/Products/Release/Saber.app"
}

target="${1:-all}"

case "$target" in
  all|android|macos) ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown target: $target" >&2
    usage >&2
    exit 1
    ;;
esac

cd "$REPO_ROOT"

# Use rustup-managed cargo/rustc first. Some plugins need rustup targets,
# and Homebrew rust ahead of rustup in PATH can break Flutter builds.
export PATH="$HOME/.cargo/bin:$PATH"

require_command flutter
require_command rustup

if [[ "$target" == "all" || "$target" == "macos" ]]; then
  require_command xcodebuild
fi

echo "==> Running flutter pub get"
flutter pub get
echo

case "$target" in
  all)
    build_android
    echo
    build_macos
    ;;
  android)
    build_android
    ;;
  macos)
    build_macos
    ;;
esac
