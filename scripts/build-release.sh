#!/usr/bin/env bash
set -euo pipefail

# Build and sign TurtleneckCoach for distribution.
# - Default signing is ad-hoc (-) so the script works immediately.
# - Pass a Developer ID identity to enable hardened runtime automatically.
# - This is the only supported app build entrypoint for DMG release.
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
PYTHON_RUNTIME_SOURCE="${PROJECT_ROOT}/python_runtime"
PYTHON_RUNTIME_DEST="${RESOURCES_DIR}/python_runtime"
PYTHON_PACKAGES_SOURCE="${PROJECT_ROOT}/python_packages"
PYTHON_PACKAGES_DEST="${RESOURCES_DIR}/python_packages"
PYTHON_VENV_SOURCE="${PROJECT_ROOT}/python_server/.venv"
PREPARE_PYTHON_RUNTIME_SCRIPT="${PROJECT_ROOT}/scripts/prepare-python-runtime.sh"
PREPARE_PYTHON_PACKAGES_SCRIPT="${PROJECT_ROOT}/scripts/prepare-python-packages.sh"
FETCH_PYTHON_STANDALONE_SCRIPT="${PROJECT_ROOT}/scripts/fetch-python-build-standalone.sh"
PREPARED_PYTHON_ROOT="${BUILD_DIR}/prepared_python_bundle"
PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE="${PYTHON_RUNTIME_SOURCE_ROOT:-}"
PYTHON_SITE_PACKAGES_SOURCE_OVERRIDE="${PYTHON_SITE_PACKAGES_SOURCE:-}"
PYTHON_STANDALONE_CACHE_ROOT="${PYTHON_STANDALONE_CACHE_ROOT:-${PROJECT_ROOT}/build/python-build-standalone/current}"
AUTO_FETCH_PYTHON_STANDALONE="${AUTO_FETCH_PYTHON_STANDALONE:-1}"

STRICT_SELF_CONTAINED_MEDIAPIPE="${STRICT_SELF_CONTAINED_MEDIAPIPE:-0}"
REQUIRE_COMPLETE_VENDORING="${REQUIRE_COMPLETE_VENDORING:-${STRICT_SELF_CONTAINED_MEDIAPIPE}}"

SIGNING_IDENTITY="${1:-${SIGNING_IDENTITY:--}}"
ANALYTICS_ENDPOINT_URL="${ANALYTICS_ENDPOINT_URL:-}"
ANALYTICS_ENABLED_BY_DEFAULT="${ANALYTICS_ENABLED_BY_DEFAULT:-1}"

if [[ "${SIGNING_IDENTITY}" == "-h" || "${SIGNING_IDENTITY}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/build-release.sh [SIGNING_IDENTITY]

Examples:
  ./scripts/build-release.sh
  ./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"

Release DMG flow:
  1) ./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"
  2) ./scripts/create-dmg.sh ./TurtleneckCoach.app
  3) ./scripts/notarize.sh ./TurtleneckCoach-<version>.dmg <keychain-profile>
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

echo "info: release build entrypoint selected."
echo "info: use ./build.sh only for local DEBUG development builds."

if [[ "${REQUIRE_COMPLETE_VENDORING}" == "1" ]]; then
  echo "info: strict MediaPipe vendoring enabled (release build will fail if vendored runtime layout is incomplete)."
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
  <key>TurtleneckAnalyticsEndpointURL</key>
  <string></string>
  <key>TurtleneckAnalyticsEnabledByDefault</key>
  <true/>
</dict>
</plist>
PLIST
fi

if command -v plutil >/dev/null 2>&1; then
  plutil -replace TurtleneckAnalyticsEndpointURL -string "${ANALYTICS_ENDPOINT_URL}" "${INFO_PLIST_DEST}"
  if [[ "${ANALYTICS_ENABLED_BY_DEFAULT}" == "0" ]]; then
    plutil -replace TurtleneckAnalyticsEnabledByDefault -bool NO "${INFO_PLIST_DEST}"
  else
    plutil -replace TurtleneckAnalyticsEnabledByDefault -bool YES "${INFO_PLIST_DEST}"
  fi
else
  echo "warning: plutil not found; analytics Info.plist keys were not updated." >&2
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

if [[ -z "${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}" && -d "${PYTHON_STANDALONE_CACHE_ROOT}" ]]; then
  PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE="${PYTHON_STANDALONE_CACHE_ROOT}"
  echo "info: using standalone runtime source from ${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}"
fi

if [[ -z "${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}" && "${AUTO_FETCH_PYTHON_STANDALONE}" == "1" && -x "${FETCH_PYTHON_STANDALONE_SCRIPT}" ]]; then
  echo "info: standalone runtime cache not found; fetching pinned python-build-standalone runtime..."
  "${FETCH_PYTHON_STANDALONE_SCRIPT}" "$(dirname "${PYTHON_STANDALONE_CACHE_ROOT}")"
  if [[ -d "${PYTHON_STANDALONE_CACHE_ROOT}" ]]; then
    PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE="${PYTHON_STANDALONE_CACHE_ROOT}"
    echo "info: fetched standalone runtime source from ${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}"
  fi
fi

if [[ ! -d "${PYTHON_RUNTIME_SOURCE}" && -n "${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}" && -d "${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}" ]]; then
  echo "info: using standalone runtime root directly from ${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}"
  PYTHON_RUNTIME_SOURCE="${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}"
fi

if [[ ! -d "${PYTHON_PACKAGES_SOURCE}" && -n "${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}" && -x "${PREPARE_PYTHON_PACKAGES_SCRIPT}" ]]; then
  echo "info: rebuilding Python packages against standalone runtime ${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}"
  "${PREPARE_PYTHON_PACKAGES_SCRIPT}" "${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}" "${PREPARED_PYTHON_ROOT}"
  PYTHON_PACKAGES_SOURCE="${PREPARED_PYTHON_ROOT}/python_packages"
fi

if [[ ( ! -d "${PYTHON_RUNTIME_SOURCE}" || ! -d "${PYTHON_PACKAGES_SOURCE}" ) && -d "${PYTHON_VENV_SOURCE}" && -x "${PREPARE_PYTHON_RUNTIME_SCRIPT}" ]]; then
  echo "info: materializing bundled Python runtime/package layout from ${PYTHON_VENV_SOURCE}"
  REQUIRE_COMPLETE_VENDORING="${REQUIRE_COMPLETE_VENDORING}" \
  PYTHON_RUNTIME_SOURCE_ROOT="${PYTHON_RUNTIME_SOURCE_ROOT_OVERRIDE}" \
  PYTHON_SITE_PACKAGES_SOURCE="${PYTHON_SITE_PACKAGES_SOURCE_OVERRIDE}" \
    "${PREPARE_PYTHON_RUNTIME_SCRIPT}" "${PYTHON_VENV_SOURCE}" "${PREPARED_PYTHON_ROOT}"
  PYTHON_RUNTIME_SOURCE="${PREPARED_PYTHON_ROOT}/python_runtime"
  PYTHON_PACKAGES_SOURCE="${PREPARED_PYTHON_ROOT}/python_packages"
fi

if [[ -d "${PYTHON_RUNTIME_SOURCE}" ]]; then
  echo "info: bundling python runtime from ${PYTHON_RUNTIME_SOURCE}"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude '__pycache__' \
      --exclude '.DS_Store' \
      "${PYTHON_RUNTIME_SOURCE}/" "${PYTHON_RUNTIME_DEST}/"
  else
    rm -rf "${PYTHON_RUNTIME_DEST}"
    mkdir -p "${PYTHON_RUNTIME_DEST}"
    ditto "${PYTHON_RUNTIME_SOURCE}" "${PYTHON_RUNTIME_DEST}"
  fi
else
  echo "warning: ${PYTHON_RUNTIME_SOURCE} not found; release build is not yet MediaPipe self-contained." >&2
fi

if [[ -d "${PYTHON_PACKAGES_SOURCE}" ]]; then
  echo "info: bundling python packages from ${PYTHON_PACKAGES_SOURCE}"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude '__pycache__' \
      --exclude '.DS_Store' \
      "${PYTHON_PACKAGES_SOURCE}/" "${PYTHON_PACKAGES_DEST}/"
  else
    rm -rf "${PYTHON_PACKAGES_DEST}"
    mkdir -p "${PYTHON_PACKAGES_DEST}"
    ditto "${PYTHON_PACKAGES_SOURCE}" "${PYTHON_PACKAGES_DEST}"
  fi
else
  echo "warning: ${PYTHON_PACKAGES_SOURCE} not found; release build is not yet MediaPipe self-contained." >&2
fi

if [[ -f "${PYTHON_RUNTIME_SOURCE}/XCODE_FRAMEWORK_SOURCE.txt" ]]; then
  echo "info: prepared Python runtime was vendored from the local Xcode Python framework source."
  echo "info: see ${PYTHON_RUNTIME_SOURCE}/XCODE_FRAMEWORK_SOURCE.txt for provenance details."
fi

if [[ "${REQUIRE_COMPLETE_VENDORING}" == "1" ]]; then
  if [[ ! -f "${PYTHON_RUNTIME_SOURCE}/Python3" ]] && ! find "${PYTHON_RUNTIME_SOURCE}/lib" -maxdepth 1 -type f -name 'libpython*.dylib' | grep -q .; then
    echo "error: strict MediaPipe vendoring requested, but no bundled runtime dylib was found under ${PYTHON_RUNTIME_SOURCE}." >&2
    exit 1
  fi
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
  -framework Charts \
  -framework ServiceManagement

chmod +x "${EXECUTABLE_PATH}"

echo "[4/6] Signing nested frameworks/bundles and Python binaries..."
USE_HARDENED_RUNTIME=0
if [[ "${SIGNING_IDENTITY}" != "-" ]]; then
  USE_HARDENED_RUNTIME=1
  echo "info: using Developer ID signing identity; hardened runtime enabled."
else
  echo "info: using ad-hoc signing identity (-)."
fi

CODESIGN_BASE_ARGS=(--force --sign "${SIGNING_IDENTITY}" --entitlements "${ENTITLEMENTS_PATH}")

# Sign all nested binaries in Frameworks and Resources (including Python .so/.dylib and executables)
NESTED_SIGN_COUNT=0

# Sign Mach-O executables in python_runtime/bin/
while IFS= read -r -d '' nested_exec; do
  if file "${nested_exec}" | grep -q "Mach-O"; then
    if [[ "${USE_HARDENED_RUNTIME}" -eq 1 ]]; then
      codesign "${CODESIGN_BASE_ARGS[@]}" --options runtime --timestamp "${nested_exec}"
    else
      codesign "${CODESIGN_BASE_ARGS[@]}" "${nested_exec}"
    fi
    NESTED_SIGN_COUNT=$((NESTED_SIGN_COUNT + 1))
  fi
done < <(find "${RESOURCES_DIR}/python_runtime/bin" -type f -perm +111 -print0 2>/dev/null || true)

# Sign .so, .dylib, .framework in all of Contents/
while IFS= read -r -d '' nested_code; do
  if [[ "${USE_HARDENED_RUNTIME}" -eq 1 ]]; then
    codesign "${CODESIGN_BASE_ARGS[@]}" --options runtime --timestamp "${nested_code}"
  else
    codesign "${CODESIGN_BASE_ARGS[@]}" "${nested_code}"
  fi
  NESTED_SIGN_COUNT=$((NESTED_SIGN_COUNT + 1))
done < <(find "${CONTENTS_DIR}" -mindepth 2 \
  \( -name "*.framework" -o -name "*.dylib" -o -name "*.so" \) \
  -print0 2>/dev/null || true)
echo "  signed ${NESTED_SIGN_COUNT} nested binaries."

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
if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  echo
  echo "warning: app is ad-hoc signed and is NOT ready for public DMG distribution."
  echo "warning: rerun with a Developer ID Application identity before notarization."
fi
