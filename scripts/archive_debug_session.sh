#!/usr/bin/env bash
set -euo pipefail

# Archive current debug artifacts from /tmp into a repo-controlled folder.
#
# Usage:
#   ./scripts/archive_debug_session.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ARCHIVE_ROOT="${PROJECT_ROOT}/debug_data/sessions"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
SESSION_DIR="${ARCHIVE_ROOT}/${TIMESTAMP}"
METADATA_PATH="${SESSION_DIR}/metadata.txt"

LOG_SOURCE="/tmp/turtle_cvadebug.log"
DEBUG_SNAPSHOTS_SOURCE="/tmp/turtle_debug_snapshots"
MANUAL_SNAPSHOTS_SOURCE="/tmp/turtle_manual_snapshots"

mkdir -p "${SESSION_DIR}"

copy_if_present() {
  local source_path="$1"
  local dest_name="$2"

  if [[ -e "${source_path}" ]]; then
    cp -R "${source_path}" "${SESSION_DIR}/${dest_name}"
    printf 'copied\t%s\t%s\n' "${source_path}" "${SESSION_DIR}/${dest_name}" >> "${METADATA_PATH}"
  else
    printf 'missing\t%s\n' "${source_path}" >> "${METADATA_PATH}"
  fi
}

{
  printf 'timestamp=%s\n' "${TIMESTAMP}"
  printf 'created_at_iso=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'project_root=%s\n' "${PROJECT_ROOT}"
  printf 'archive_root=%s\n' "${ARCHIVE_ROOT}"
  printf '\n[sources]\n'
} > "${METADATA_PATH}"

copy_if_present "${LOG_SOURCE}" "turtle_cvadebug.log"
copy_if_present "${DEBUG_SNAPSHOTS_SOURCE}" "turtle_debug_snapshots"
copy_if_present "${MANUAL_SNAPSHOTS_SOURCE}" "turtle_manual_snapshots"

printf '\nArchived debug session to %s\n' "${SESSION_DIR}"
