#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RUNTIME_ROOT="${1:-${PROJECT_ROOT}/build/python-build-standalone/current}"
OUTPUT_ROOT="${2:-${PROJECT_ROOT}/build/python_packages_build}"
REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-${PROJECT_ROOT}/python_server/requirements.txt}"
PACKAGES_OUT="${OUTPUT_ROOT}/python_packages"

if [[ "${RUNTIME_ROOT}" == "-h" || "${RUNTIME_ROOT}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/prepare-python-packages.sh [RUNTIME_ROOT] [OUTPUT_ROOT]

Examples:
  ./scripts/prepare-python-packages.sh
  ./scripts/prepare-python-packages.sh /tmp/pt_python_standalone_cache/current ./build/python_packages_build

Override env vars:
  REQUIREMENTS_FILE
USAGE
  exit 0
fi

if [[ ! -x "${RUNTIME_ROOT}/bin/python3" ]]; then
  echo "error: runtime root missing bin/python3 at ${RUNTIME_ROOT}/bin/python3" >&2
  exit 1
fi

if [[ ! -f "${REQUIREMENTS_FILE}" ]]; then
  echo "error: requirements file not found at ${REQUIREMENTS_FILE}" >&2
  exit 1
fi

PYTHON_VERSION="$(${RUNTIME_ROOT}/bin/python3 - <<'PY'
import sys
print(f"python{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
SITE_PACKAGES_OUT="${PACKAGES_OUT}/lib/${PYTHON_VERSION}/site-packages"

rm -rf "${PACKAGES_OUT}"
mkdir -p "${SITE_PACKAGES_OUT}"

DYLD_LIBRARY_PATH="${RUNTIME_ROOT}/lib" \
DYLD_FALLBACK_LIBRARY_PATH="${RUNTIME_ROOT}/lib" \
PYTHONHOME="${RUNTIME_ROOT}" \
PYTHONNOUSERSITE=1 \
"${RUNTIME_ROOT}/bin/python3" -m pip install \
  --disable-pip-version-check \
  --only-binary=:all: \
  -r "${REQUIREMENTS_FILE}" \
  --target "${SITE_PACKAGES_OUT}"

VALIDATION_REPORT="${OUTPUT_ROOT}/VALIDATION.txt"
: > "${VALIDATION_REPORT}"
log_validation() { echo "$1" | tee -a "${VALIDATION_REPORT}"; }

log_validation "Prepared Python packages:"
log_validation "  runtime_root=${RUNTIME_ROOT}"
log_validation "  requirements=${REQUIREMENTS_FILE}"
log_validation "  packages_out=${SITE_PACKAGES_OUT}"

for required_pkg in mediapipe cv2 numpy; do
  if [[ ! -e "${SITE_PACKAGES_OUT}/${required_pkg}" ]]; then
    log_validation "error: missing ${required_pkg} in ${SITE_PACKAGES_OUT}"
    exit 1
  fi
  log_validation "verified: ${required_pkg}"
done

SMOKE_REPORT="${OUTPUT_ROOT}/SMOKE_TEST.txt"
DYLD_LIBRARY_PATH="${RUNTIME_ROOT}/lib" \
DYLD_FALLBACK_LIBRARY_PATH="${RUNTIME_ROOT}/lib" \
PYTHONHOME="${RUNTIME_ROOT}" \
PYTHONPATH="${SITE_PACKAGES_OUT}" \
PYTHONNOUSERSITE=1 \
"${RUNTIME_ROOT}/bin/python3" - <<'PY' > "${SMOKE_REPORT}"
import cv2
import mediapipe
import numpy
import sys
print(f"smoke_executable={sys.executable}")
print(f"smoke_prefix={sys.prefix}")
print(f"smoke_numpy={numpy.__file__}")
print(f"smoke_mediapipe={mediapipe.__file__}")
print(f"smoke_cv2={cv2.__file__}")
PY

while IFS= read -r line; do
  log_validation "${line}"
done < "${SMOKE_REPORT}"
