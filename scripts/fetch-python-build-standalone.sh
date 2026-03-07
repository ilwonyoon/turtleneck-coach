#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PYTHON_STANDALONE_TAG="${PYTHON_STANDALONE_TAG:-20260303}"
PYTHON_STANDALONE_VERSION="${PYTHON_STANDALONE_VERSION:-3.11.15}"
PYTHON_STANDALONE_ARTIFACT="${PYTHON_STANDALONE_ARTIFACT:-cpython-${PYTHON_STANDALONE_VERSION}+${PYTHON_STANDALONE_TAG}-aarch64-apple-darwin-install_only.tar.gz}"
PYTHON_STANDALONE_BASE_URL="${PYTHON_STANDALONE_BASE_URL:-https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_STANDALONE_TAG}}"
DOWNLOAD_URL="${PYTHON_STANDALONE_BASE_URL}/${PYTHON_STANDALONE_ARTIFACT}"
REQUESTED_CACHE_ROOT="${1:-}"
DEFAULT_CACHE_ROOT="${PROJECT_ROOT}/build/python-build-standalone"

if [[ "${REQUESTED_CACHE_ROOT}" == "-h" || "${REQUESTED_CACHE_ROOT}" == "--help" ]]; then
  cat <<USAGE
Usage: ./scripts/fetch-python-build-standalone.sh [CACHE_ROOT]

Defaults:
  tag:      ${PYTHON_STANDALONE_TAG}
  version:  ${PYTHON_STANDALONE_VERSION}
  artifact: ${PYTHON_STANDALONE_ARTIFACT}

Outputs:
  download: ${DEFAULT_CACHE_ROOT}/${PYTHON_STANDALONE_ARTIFACT}
  extract:  ${DEFAULT_CACHE_ROOT}/extracted
  link:     ${DEFAULT_CACHE_ROOT}/current

Override env vars:
  PYTHON_STANDALONE_TAG
  PYTHON_STANDALONE_VERSION
  PYTHON_STANDALONE_ARTIFACT
  PYTHON_STANDALONE_BASE_URL
USAGE
  exit 0
fi

CACHE_ROOT="${REQUESTED_CACHE_ROOT:-${DEFAULT_CACHE_ROOT}}"
DOWNLOAD_PATH="${CACHE_ROOT}/${PYTHON_STANDALONE_ARTIFACT}"
EXTRACT_ROOT="${CACHE_ROOT}/extracted"
SOURCE_LINK="${CACHE_ROOT}/current"

mkdir -p "${CACHE_ROOT}"

if [[ ! -f "${DOWNLOAD_PATH}" ]]; then
  echo "info: downloading ${DOWNLOAD_URL}"
  curl -fL --retry 3 --retry-delay 2 -o "${DOWNLOAD_PATH}" "${DOWNLOAD_URL}"
else
  echo "info: reusing cached archive ${DOWNLOAD_PATH}"
fi

rm -rf "${EXTRACT_ROOT}"
mkdir -p "${EXTRACT_ROOT}"

tar -xzf "${DOWNLOAD_PATH}" -C "${EXTRACT_ROOT}"

EXTRACTED_DIR="$(find "${EXTRACT_ROOT}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
if [[ -z "${EXTRACTED_DIR}" ]]; then
  echo "error: failed to locate extracted runtime root under ${EXTRACT_ROOT}" >&2
  exit 1
fi

ln -sfn "${EXTRACTED_DIR}" "${SOURCE_LINK}"

cat <<SUMMARY
fetched_tag=${PYTHON_STANDALONE_TAG}
fetched_version=${PYTHON_STANDALONE_VERSION}
archive=${DOWNLOAD_PATH}
runtime_root=${EXTRACTED_DIR}
current_link=${SOURCE_LINK}
SUMMARY
