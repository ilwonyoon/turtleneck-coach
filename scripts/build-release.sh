#!/usr/bin/env bash
set -euo pipefail

# Build and sign TurtleneckCoach for distribution.
# - Default signing is ad-hoc (-) so the script works immediately.
# - Pass a Developer ID identity to enable hardened runtime automatically.
#
# Usage:
#   ./scripts/build-release.sh
#   ./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="TurtleneckCoach"
APP_BUNDLE="${PROJECT_ROOT}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
EXECUTABLE_PATH="${MACOS_DIR}/${APP_NAME}"
BUILD_DIR="${PROJECT_ROOT}/build/release"
MODULE_CACHE_DIR="${BUILD_DIR}/ModuleCache.noindex"

INFO_PLIST_SOURCE="${PROJECT_ROOT}/TurtleneckCoach/Resources/Info.plist"
INFO_PLIST_DEST="${CONTENTS_DIR}/Info.plist"
ENTITLEMENTS_PATH="${PROJECT_ROOT}/TurtleneckCoach/Resources/TurtleneckCoach.entitlements"
PYTHON_SERVER_SOURCE="${PROJECT_ROOT}/python_server"
PYTHON_SERVER_DEST="${RESOURCES_DIR}/python_server"

SIGNING_IDENTITY="${1:-${SIGNING_IDENTITY:--}}"

if [[ "${SIGNING_IDENTITY}" == "-h" || "${SIGNING_IDENTITY}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/build-release.sh [SIGNING_IDENTITY]

Examples:
  ./scripts/build-release.sh
  ./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"
USAGE
  exit 0
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc not found. Install Xcode Command Line Tools." >&2
  exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo "error: codesign not found." >&2
  exit 1
fi

if [[ ! -f "${ENTITLEMENTS_PATH}" ]]; then
  echo "error: entitlements file not found at ${ENTITLEMENTS_PATH}" >&2
  exit 1
fi

echo "[1/6] Preparing clean app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

if [[ -f "${INFO_PLIST_SOURCE}" ]]; then
  cp "${INFO_PLIST_SOURCE}" "${INFO_PLIST_DEST}"
else
  cat > "${INFO_PLIST_DEST}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.turtleneck.detector</string>
  <key>CFBundleName</key>
  <string>Turtleneck Coach</string>
  <key>CFBundleExecutable</key>
  <string>TurtleneckCoach</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSCameraUsageDescription</key>
  <string>Turtleneck Coach uses the camera to analyze your posture. Images are processed on-device and never stored.</string>
</dict>
</plist>
PLIST
fi

ICON_SOURCE="${PROJECT_ROOT}/TurtleneckCoach/Resources/AppIcon.icns"
if [[ -f "${ICON_SOURCE}" ]]; then
  cp "${ICON_SOURCE}" "${RESOURCES_DIR}/AppIcon.icns"
else
  echo "warning: AppIcon.icns not found at ${ICON_SOURCE}" >&2
fi

echo "[2/6] Bundling runtime resources..."
if [[ -d "${PYTHON_SERVER_SOURCE}" ]]; then
  mkdir -p "${PYTHON_SERVER_DEST}"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude '__pycache__' \
      --exclude '.DS_Store' \
      --exclude '.venv' \
      "${PYTHON_SERVER_SOURCE}/" "${PYTHON_SERVER_DEST}/"
  else
    rm -rf "${PYTHON_SERVER_DEST}"
    mkdir -p "${PYTHON_SERVER_DEST}"
    ditto "${PYTHON_SERVER_SOURCE}" "${PYTHON_SERVER_DEST}"
    find "${PYTHON_SERVER_DEST}" -name "__pycache__" -type d -prune -exec rm -rf {} +
  fi
else
  echo "warning: ${PYTHON_SERVER_SOURCE} not found; continuing without bundled python_server."
fi

echo "[3/6] Compiling Swift sources (release optimization)..."
SWIFT_SOURCES=()
while IFS= read -r source_file; do
  SWIFT_SOURCES+=("${source_file}")
done < <(find "${PROJECT_ROOT}/TurtleneckCoach" -type f -name '*.swift' | sort)

if [[ "${#SWIFT_SOURCES[@]}" -eq 0 ]]; then
  echo "error: no Swift sources found under ${PROJECT_ROOT}/TurtleneckCoach" >&2
  exit 1
fi

swiftc \
  "${SWIFT_SOURCES[@]}" \
  -o "${EXECUTABLE_PATH}" \
  -target arm64-apple-macos14 \
  -module-cache-path "${MODULE_CACHE_DIR}" \
  -O \
  -whole-module-optimization \
  -gnone \
  -parse-as-library \
  -framework SwiftUI \
  -framework Vision \
  -framework AVFoundation \
  -framework UserNotifications \
  -framework AppKit \
  -framework Network \
  -framework Charts

chmod +x "${EXECUTABLE_PATH}"

echo "[4/6] Signing nested frameworks/bundles (if present)..."
USE_HARDENED_RUNTIME=0
if [[ "${SIGNING_IDENTITY}" != "-" ]]; then
  USE_HARDENED_RUNTIME=1
  echo "info: using Developer ID signing identity; hardened runtime enabled."
else
  echo "info: using ad-hoc signing identity (-)."
fi

CODESIGN_BASE_ARGS=(--force --sign "${SIGNING_IDENTITY}" --entitlements "${ENTITLEMENTS_PATH}")

while IFS= read -r -d '' nested_code; do
  echo "  signing: ${nested_code}"
  if [[ "${USE_HARDENED_RUNTIME}" -eq 1 ]]; then
    codesign "${CODESIGN_BASE_ARGS[@]}" --options runtime --timestamp "${nested_code}"
  else
    codesign "${CODESIGN_BASE_ARGS[@]}" "${nested_code}"
  fi
done < <(find "${FRAMEWORKS_DIR}" -mindepth 1 \
  \( -name "*.framework" -o -name "*.dylib" -o -name "*.so" -o -name "*.bundle" -o -name "*.xpc" \) \
  -print0 2>/dev/null || true)

echo "[5/6] Signing app bundle..."
if [[ "${USE_HARDENED_RUNTIME}" -eq 1 ]]; then
  codesign "${CODESIGN_BASE_ARGS[@]}" --options runtime --timestamp --deep "${APP_BUNDLE}"
else
  codesign "${CODESIGN_BASE_ARGS[@]}" --deep "${APP_BUNDLE}"
fi

echo "[6/6] Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
codesign --display --verbose=4 "${APP_BUNDLE}" | sed -n '1,12p'

if [[ "${SIGNING_IDENTITY}" != "-" ]]; then
  if spctl --assess --type execute --verbose=4 "${APP_BUNDLE}"; then
    echo "Gatekeeper assessment passed for signed app."
  else
    echo "warning: spctl assessment did not pass yet (this can happen before notarization)." >&2
  fi
else
  echo "info: skipping Gatekeeper assessment for ad-hoc signature."
fi

echo
echo "Build complete:"
echo "  ${APP_BUNDLE}"
