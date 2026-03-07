#!/usr/bin/env bash
set -euo pipefail

# Create a distributable DMG containing:
# - TurtleneckCoach.app
# - Applications symlink
# - Custom volume name and volume icon
#
# Usage:
#   ./scripts/create-dmg.sh ./TurtleneckCoach.app [output_dir]
# Optional:
#   DMG_ICON_PATH=/path/to/icon.icns ./scripts/create-dmg.sh ./TurtleneckCoach.app
#   ALLOW_ADHOC_DMG=1 ./scripts/create-dmg.sh ./TurtleneckCoach.app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_PATH="${1:-${PROJECT_ROOT}/TurtleneckCoach.app}"
OUTPUT_DIR="${2:-${PROJECT_ROOT}}"

if [[ "${APP_PATH}" == "-h" || "${APP_PATH}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/create-dmg.sh [APP_PATH] [OUTPUT_DIR]

Examples:
  ./scripts/create-dmg.sh ./TurtleneckCoach.app
  ./scripts/create-dmg.sh ./TurtleneckCoach.app ./dist

Notes:
  - For public release, the app should already be Developer ID signed.
  - Ad-hoc signed apps are blocked by default; override only for local testing:
      ALLOW_ADHOC_DMG=1 ./scripts/create-dmg.sh ./TurtleneckCoach.app
USAGE
  exit 0
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: app bundle not found at ${APP_PATH}" >&2
  exit 1
fi

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
if [[ ! -f "${INFO_PLIST}" ]]; then
  echo "error: missing Info.plist at ${INFO_PLIST}" >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "error: hdiutil not found." >&2
  exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo "error: codesign not found." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

plist_get() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :${key}" "${INFO_PLIST}" 2>/dev/null || true
}

signature_summary="$(codesign -dv --verbose=4 "${APP_PATH}" 2>&1 || true)"
if grep -q "Signature=adhoc" <<<"${signature_summary}"; then
  if [[ "${ALLOW_ADHOC_DMG:-0}" != "1" ]]; then
    cat >&2 <<'ERR'
error: app bundle is ad-hoc signed.

For public DMG release, first run:
  ./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"

If you intentionally want a local test DMG, rerun with:
  ALLOW_ADHOC_DMG=1 ./scripts/create-dmg.sh ./TurtleneckCoach.app
ERR
    exit 1
  fi
  echo "warning: continuing with ad-hoc signed app because ALLOW_ADHOC_DMG=1 was set." >&2
fi

APP_NAME="$(basename "${APP_PATH}" .app)"
VERSION="$(plist_get CFBundleShortVersionString)"
if [[ -z "${VERSION}" ]]; then
  VERSION="$(plist_get CFBundleVersion)"
fi
if [[ -z "${VERSION}" ]]; then
  VERSION="0.0.0"
fi

SAFE_VERSION="${VERSION// /_}"
VOLUME_NAME="${APP_NAME} ${VERSION}"
OUTPUT_DMG="${OUTPUT_DIR}/${APP_NAME}-${SAFE_VERSION}.dmg"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.dmg.XXXXXX")"
STAGING_DIR="${WORK_DIR}/staging"
mkdir -p "${STAGING_DIR}"
trap 'rm -rf "${WORK_DIR}"' EXIT

echo "[1/4] Preparing DMG staging folder..."
ditto "${APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

ICON_PATH="${DMG_ICON_PATH:-}"
if [[ -z "${ICON_PATH}" ]]; then
  ICON_NAME="$(plist_get CFBundleIconFile)"
  if [[ -n "${ICON_NAME}" ]]; then
    if [[ "${ICON_NAME}" != *.icns ]]; then
      ICON_NAME="${ICON_NAME}.icns"
    fi
    CANDIDATE_ICON="${APP_PATH}/Contents/Resources/${ICON_NAME}"
    if [[ -f "${CANDIDATE_ICON}" ]]; then
      ICON_PATH="${CANDIDATE_ICON}"
    fi
  fi
fi

if [[ -z "${ICON_PATH}" ]]; then
  FALLBACK_ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"
  if [[ -f "${FALLBACK_ICON}" ]]; then
    ICON_PATH="${FALLBACK_ICON}"
  fi
fi

if [[ -n "${ICON_PATH}" && -f "${ICON_PATH}" ]]; then
  cp "${ICON_PATH}" "${STAGING_DIR}/.VolumeIcon.icns"
  chflags hidden "${STAGING_DIR}/.VolumeIcon.icns" || true

  SETFILE_BIN="$(xcrun --find SetFile 2>/dev/null || true)"
  if [[ -n "${SETFILE_BIN}" ]]; then
    "${SETFILE_BIN}" -a C "${STAGING_DIR}" || true
    "${SETFILE_BIN}" -a V "${STAGING_DIR}/.VolumeIcon.icns" || true
  else
    echo "warning: SetFile not found; volume custom icon flag may not be applied."
  fi
else
  echo "warning: no .icns file found for volume icon; creating DMG without custom icon."
fi

echo "[2/4] Creating DMG image..."
rm -f "${OUTPUT_DMG}"
if ! hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "${OUTPUT_DMG}"; then
  echo "error: failed to create DMG with hdiutil." >&2
  echo "hint: this can fail in restricted sandbox/CI environments that block disk image devices." >&2
  exit 1
fi

echo "[3/4] Verifying DMG integrity..."
if ! hdiutil verify "${OUTPUT_DMG}"; then
  echo "error: hdiutil verify failed for ${OUTPUT_DMG}" >&2
  exit 1
fi

echo "[4/4] Done."
echo "Created: ${OUTPUT_DMG}"
echo "Next step for public release: ./scripts/notarize.sh \"${OUTPUT_DMG}\" <keychain-profile>"
