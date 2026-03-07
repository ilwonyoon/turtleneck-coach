#!/usr/bin/env bash
set -euo pipefail

# Submit a DMG to Apple notarization, wait for result, staple ticket, and validate.
#
# Usage:
#   ./scripts/notarize.sh /path/to/TurtleneckCoach-1.0.0.dmg [keychain_profile]
#
# Auth options:
# 1) Recommended keychain profile:
#    xcrun notarytool store-credentials "turtle-notary" \
#      --apple-id "you@example.com" \
#      --team-id "TEAMID1234" \
#      --password "app-specific-password"
#
# 2) Environment variables (if no profile provided):
#    APPLE_ID, TEAM_ID, APP_SPECIFIC_PASSWORD

DMG_PATH="${1:-}"
KEYCHAIN_PROFILE="${2:-${NOTARYTOOL_PROFILE:-}}"

if [[ "${DMG_PATH}" == "-h" || "${DMG_PATH}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/notarize.sh <DMG_PATH> [KEYCHAIN_PROFILE]

Examples:
  ./scripts/notarize.sh ./TurtleneckCoach-1.0.0.dmg turtle-notary
  NOTARYTOOL_PROFILE=turtle-notary ./scripts/notarize.sh ./TurtleneckCoach-1.0.0.dmg

Expected input:
  - DMG created from a Developer ID signed app
  - app signed with hardened runtime and timestamp
USAGE
  exit 0
fi

if [[ -z "${DMG_PATH}" ]]; then
  echo "error: missing DMG path." >&2
  echo "Run './scripts/notarize.sh --help' for usage." >&2
  exit 1
fi

if [[ "${DMG_PATH}" == *.app ]] || [[ -d "${DMG_PATH}" && "${DMG_PATH}" == *.app/ ]]; then
  echo "error: expected a DMG path, not an app bundle." >&2
  echo "hint: run ./scripts/create-dmg.sh ./TurtleneckCoach.app first." >&2
  exit 1
fi

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "error: DMG not found at ${DMG_PATH}" >&2
  exit 1
fi

if ! xcrun --find notarytool >/dev/null 2>&1; then
  echo "error: notarytool not found. Install Xcode 13+ command line tools." >&2
  exit 1
fi

AUTH_ARGS=()
if [[ -n "${KEYCHAIN_PROFILE}" ]]; then
  AUTH_ARGS=(--keychain-profile "${KEYCHAIN_PROFILE}")
else
  if [[ -z "${APPLE_ID:-}" || -z "${TEAM_ID:-}" || -z "${APP_SPECIFIC_PASSWORD:-}" ]]; then
    cat >&2 <<'ERR'
error: notarization credentials not configured.

Provide either:
1) Keychain profile (recommended):
   xcrun notarytool store-credentials "turtle-notary" \
     --apple-id "you@example.com" \
     --team-id "TEAMID1234" \
     --password "app-specific-password"
   ./scripts/notarize.sh <dmg> turtle-notary

2) Environment variables:
   APPLE_ID=you@example.com
   TEAM_ID=TEAMID1234
   APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
   ./scripts/notarize.sh <dmg>
ERR
    exit 1
  fi
  AUTH_ARGS=(
    --apple-id "${APPLE_ID}"
    --team-id "${TEAM_ID}"
    --password "${APP_SPECIFIC_PASSWORD}"
  )
fi

RESULT_JSON="$(mktemp "${TMPDIR:-/tmp}/turtle-notary.XXXXXX.json")"
trap 'rm -f "${RESULT_JSON}"' EXIT

echo "[1/4] Submitting DMG to notarization service and waiting..."
if ! xcrun notarytool submit "${DMG_PATH}" --wait --output-format json "${AUTH_ARGS[@]}" > "${RESULT_JSON}"; then
  echo "error: notarization submission failed. Raw notarytool output:" >&2
  cat "${RESULT_JSON}" >&2
  exit 1
fi

echo "[2/4] Notary response:"
cat "${RESULT_JSON}"

NOTARY_STATUS=""
SUBMISSION_ID=""
if command -v python3 >/dev/null 2>&1; then
  PARSED_OUTPUT="$(python3 - "${RESULT_JSON}" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, "r", encoding="utf-8"))
print(data.get("status", ""))
print(data.get("id", ""))
PY
)"
  NOTARY_STATUS="$(echo "${PARSED_OUTPUT}" | sed -n '1p')"
  SUBMISSION_ID="$(echo "${PARSED_OUTPUT}" | sed -n '2p')"
else
  NOTARY_STATUS="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${RESULT_JSON}" | head -n1)"
  SUBMISSION_ID="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${RESULT_JSON}" | head -n1)"
fi

if [[ "${NOTARY_STATUS}" != "Accepted" ]]; then
  echo "error: notarization status is '${NOTARY_STATUS:-unknown}', expected 'Accepted'." >&2
  if [[ -n "${SUBMISSION_ID}" ]]; then
    echo "Fetching detailed notarization log for submission: ${SUBMISSION_ID}" >&2
    xcrun notarytool log "${SUBMISSION_ID}" "${AUTH_ARGS[@]}" || true
  fi
  exit 1
fi

echo "[3/4] Stapling notarization ticket..."
xcrun stapler staple -v "${DMG_PATH}"

echo "[4/4] Verifying stapled ticket..."
xcrun stapler validate -v "${DMG_PATH}"

if command -v spctl >/dev/null 2>&1; then
  echo "Running optional Gatekeeper assessment (informational)..."
  spctl --assess --type open --context context:primary-signature --verbose=4 "${DMG_PATH}" || true
fi

echo "Notarization, stapling, and validation complete for:"
echo "  ${DMG_PATH}"
