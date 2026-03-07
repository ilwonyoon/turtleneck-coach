#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOURCE_VENV="${1:-${PROJECT_ROOT}/python_server/.venv}"
OUTPUT_ROOT="${2:-${PROJECT_ROOT}/build/python_bundle_prep}"
RUNTIME_OUT="${OUTPUT_ROOT}/python_runtime"
PACKAGES_OUT="${OUTPUT_ROOT}/python_packages"
REQUIRE_COMPLETE_VENDORING="${REQUIRE_COMPLETE_VENDORING:-${REQUIRE_SELF_CONTAINED_INTERPRETER:-0}}"

if [[ "${SOURCE_VENV}" == "-h" || "${SOURCE_VENV}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/prepare-python-runtime.sh [SOURCE_VENV] [OUTPUT_ROOT]

Examples:
  ./scripts/prepare-python-runtime.sh
  ./scripts/prepare-python-runtime.sh ./python_server/.venv ./build/python_bundle_prep
  REQUIRE_COMPLETE_VENDORING=1 ./scripts/prepare-python-runtime.sh

Outputs:
  <OUTPUT_ROOT>/python_runtime
  <OUTPUT_ROOT>/python_packages

Purpose:
  - Materialize a vendored Python runtime/package layout from an existing local venv.
  - Vendor the interpreter, Python3 dylib, stdlib, and framework resources from the Xcode Python framework source that backs the venv.
  - Validate whether the vendored runtime layout is complete enough for release bundling.
USAGE
  exit 0
fi

if [[ ! -d "${SOURCE_VENV}" ]]; then
  echo "error: source venv not found at ${SOURCE_VENV}" >&2
  exit 1
fi

SOURCE_PYTHON="${SOURCE_VENV}/bin/python3"
if [[ ! -e "${SOURCE_PYTHON}" ]]; then
  echo "error: expected python3 at ${SOURCE_PYTHON}" >&2
  exit 1
fi

SITE_PACKAGES_DIR="$(find "${SOURCE_VENV}/lib" -type d -name site-packages | head -n1)"
if [[ -z "${SITE_PACKAGES_DIR}" ]]; then
  echo "error: could not find site-packages under ${SOURCE_VENV}/lib" >&2
  exit 1
fi

SOURCE_PYTHON_REAL="$("${SOURCE_PYTHON}" - <<'PY' "${SOURCE_PYTHON}"
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"
PYTHON_VERSION="$("${SOURCE_PYTHON}" - <<'PY'
import sys
print(f"python{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
PYTHON_VERSION_SHORT="${PYTHON_VERSION#python}"
SOURCE_BIN_DIR="$(dirname "${SOURCE_PYTHON_REAL}")"
FRAMEWORK_VERSION_DIR="$(cd "${SOURCE_BIN_DIR}/.." && pwd)"
FRAMEWORK_DYLIB_SOURCE="${FRAMEWORK_VERSION_DIR}/Python3"
FRAMEWORK_RESOURCES_SOURCE="${FRAMEWORK_VERSION_DIR}/Resources"
FRAMEWORK_STDLIB_SOURCE="${FRAMEWORK_VERSION_DIR}/lib/${PYTHON_VERSION}"

if [[ ! -f "${FRAMEWORK_DYLIB_SOURCE}" ]]; then
  echo "error: expected Python3 dylib at ${FRAMEWORK_DYLIB_SOURCE}" >&2
  exit 1
fi

if [[ ! -d "${FRAMEWORK_STDLIB_SOURCE}" ]]; then
  echo "error: expected stdlib at ${FRAMEWORK_STDLIB_SOURCE}" >&2
  exit 1
fi

rm -rf "${RUNTIME_OUT}" "${PACKAGES_OUT}"
mkdir -p "${RUNTIME_OUT}/bin" "${RUNTIME_OUT}/lib" "${PACKAGES_OUT}/lib/${PYTHON_VERSION}"

copy_tree() {
  local src="$1"
  local dst="$2"
  if command -v rsync >/dev/null 2>&1; then
    mkdir -p "${dst}"
    rsync -a --delete \
      --exclude '__pycache__' \
      --exclude '.DS_Store' \
      --exclude '*.pyc' \
      "${src}/" "${dst}/"
  else
    rm -rf "${dst}"
    mkdir -p "${dst}"
    ditto "${src}" "${dst}"
    find "${dst}" -name '__pycache__' -type d -prune -exec rm -rf {} +
    find "${dst}" -name '*.pyc' -type f -delete
  fi
}

copy_tree "${SITE_PACKAGES_DIR}" "${PACKAGES_OUT}/lib/${PYTHON_VERSION}/site-packages"
copy_tree "${FRAMEWORK_STDLIB_SOURCE}" "${RUNTIME_OUT}/lib/${PYTHON_VERSION}"

if [[ -d "${FRAMEWORK_RESOURCES_SOURCE}" ]]; then
  copy_tree "${FRAMEWORK_RESOURCES_SOURCE}" "${RUNTIME_OUT}/Resources"
fi

cp -f "${FRAMEWORK_DYLIB_SOURCE}" "${RUNTIME_OUT}/Python3"
chmod +x "${RUNTIME_OUT}/Python3"

cp -f "${SOURCE_PYTHON_REAL}" "${RUNTIME_OUT}/bin/python3"
chmod +x "${RUNTIME_OUT}/bin/python3"
ln -sf python3 "${RUNTIME_OUT}/bin/python"
ln -sf python3 "${RUNTIME_OUT}/bin/${PYTHON_VERSION}"
if [[ -f "${FRAMEWORK_VERSION_DIR}/bin/python${PYTHON_VERSION_SHORT}" ]]; then
  cp -f "${FRAMEWORK_VERSION_DIR}/bin/python${PYTHON_VERSION_SHORT}" "${RUNTIME_OUT}/bin/python${PYTHON_VERSION_SHORT}"
  chmod +x "${RUNTIME_OUT}/bin/python${PYTHON_VERSION_SHORT}"
fi
if [[ -f "${FRAMEWORK_VERSION_DIR}/bin/pydoc${PYTHON_VERSION_SHORT}" ]]; then
  cp -f "${FRAMEWORK_VERSION_DIR}/bin/pydoc${PYTHON_VERSION_SHORT}" "${RUNTIME_OUT}/bin/pydoc${PYTHON_VERSION_SHORT}"
  chmod +x "${RUNTIME_OUT}/bin/pydoc${PYTHON_VERSION_SHORT}"
fi
if [[ -f "${FRAMEWORK_VERSION_DIR}/bin/2to3-${PYTHON_VERSION_SHORT}" ]]; then
  cp -f "${FRAMEWORK_VERSION_DIR}/bin/2to3-${PYTHON_VERSION_SHORT}" "${RUNTIME_OUT}/bin/2to3-${PYTHON_VERSION_SHORT}"
  chmod +x "${RUNTIME_OUT}/bin/2to3-${PYTHON_VERSION_SHORT}"
fi

if [[ -f "${SOURCE_VENV}/pyvenv.cfg" ]]; then
  cp "${SOURCE_VENV}/pyvenv.cfg" "${RUNTIME_OUT}/pyvenv.cfg"
fi

cat > "${RUNTIME_OUT}/BUNDLE_MANIFEST.txt" <<MANIFEST
prepared_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
source_venv=${SOURCE_VENV}
source_python=${SOURCE_PYTHON}
source_python_real=${SOURCE_PYTHON_REAL}
framework_version_dir=${FRAMEWORK_VERSION_DIR}
framework_dylib_source=${FRAMEWORK_DYLIB_SOURCE}
framework_stdlib_source=${FRAMEWORK_STDLIB_SOURCE}
framework_resources_source=${FRAMEWORK_RESOURCES_SOURCE}
source_site_packages=${SITE_PACKAGES_DIR}
python_version=${PYTHON_VERSION}
release_policy=apple_silicon_only_macos14_plus
MANIFEST

SOURCE_MARKER="${RUNTIME_OUT}/XCODE_FRAMEWORK_SOURCE.txt"
cat > "${SOURCE_MARKER}" <<MARKER
This vendored Python runtime was materialized from the Xcode Python framework source.

source_python=${SOURCE_PYTHON}
source_python_real=${SOURCE_PYTHON_REAL}
framework_version_dir=${FRAMEWORK_VERSION_DIR}

This is an explicit vendoring path for release packaging. It removes the previous
"copied executable only" gap, but it still needs clean-machine validation and final
release signing/notarization work before it can be treated as production-complete.
MARKER

VALIDATION_REPORT="${OUTPUT_ROOT}/VALIDATION.txt"
: > "${VALIDATION_REPORT}"

log_validation() {
  echo "$1" | tee -a "${VALIDATION_REPORT}"
}

log_validation "Prepared vendored Python layout:"
log_validation "  runtime:  ${RUNTIME_OUT}"
log_validation "  packages: ${PACKAGES_OUT}"
log_validation "  source interpreter realpath: ${SOURCE_PYTHON_REAL}"
log_validation "  framework source: ${FRAMEWORK_VERSION_DIR}"
log_validation "  stdlib source: ${FRAMEWORK_STDLIB_SOURCE}"
log_validation "  site-packages source: ${SITE_PACKAGES_DIR}"

REQUIRED_FILES=(
  "${RUNTIME_OUT}/bin/python3"
  "${RUNTIME_OUT}/Python3"
  "${RUNTIME_OUT}/lib/${PYTHON_VERSION}/encodings/__init__.py"
  "${PACKAGES_OUT}/lib/${PYTHON_VERSION}/site-packages/mediapipe/__init__.py"
)

for required_path in "${REQUIRED_FILES[@]}"; do
  if [[ ! -e "${required_path}" ]]; then
    log_validation "error: missing required vendored path: ${required_path}"
    exit 1
  fi
  log_validation "verified: ${required_path}"
done

if [[ -d "${RUNTIME_OUT}/Resources" ]]; then
  log_validation "verified: ${RUNTIME_OUT}/Resources"
else
  log_validation "warning: framework Resources directory was not copied."
fi

if [[ ! -e "${PACKAGES_OUT}/lib/${PYTHON_VERSION}/site-packages/cv2" ]]; then
  log_validation "warning: cv2 package not found in prepared package layout."
fi

OTOOl_REPORT="${OUTPUT_ROOT}/OTOOl.txt"
otool -L "${RUNTIME_OUT}/bin/python3" > "${OTOOl_REPORT}"
if grep -q '@executable_path/../Python3' "${OTOOl_REPORT}"; then
  log_validation "verified: python3 links against @executable_path/../Python3"
else
  log_validation "warning: python3 no longer links against @executable_path/../Python3"
fi

ABSOLUTE_NON_SYSTEM_DEPS="$(
  grep '^[[:space:]]' "${OTOOl_REPORT}" | \
    awk '{print $1}' | \
    grep '^/' | \
    grep -v '^/usr/lib/' || true
)"
if [[ -n "${ABSOLUTE_NON_SYSTEM_DEPS}" ]]; then
  log_validation "warning: non-system absolute dylib dependencies detected:"
  while IFS= read -r dep; do
    [[ -n "${dep}" ]] && log_validation "  ${dep}"
  done <<< "${ABSOLUTE_NON_SYSTEM_DEPS}"
fi

if command -v lipo >/dev/null 2>&1; then
  PYTHON_ARCH_INFO="$(lipo -archs "${RUNTIME_OUT}/bin/python3")"
  log_validation "python3 archs: ${PYTHON_ARCH_INFO}"
  if [[ "${PYTHON_ARCH_INFO}" != *"arm64"* ]]; then
    log_validation "error: vendored python3 does not include arm64 support."
    exit 1
  fi
fi

if [[ "${REQUIRE_COMPLETE_VENDORING}" == "1" ]]; then
  if [[ ! -f "${RUNTIME_OUT}/Python3" ]]; then
    log_validation "error: REQUIRE_COMPLETE_VENDORING=1 and Python3 dylib is missing."
    exit 1
  fi
  if [[ ! -d "${RUNTIME_OUT}/lib/${PYTHON_VERSION}" ]]; then
    log_validation "error: REQUIRE_COMPLETE_VENDORING=1 and stdlib is missing."
    exit 1
  fi
  if [[ ! -d "${RUNTIME_OUT}/Resources" ]]; then
    log_validation "error: REQUIRE_COMPLETE_VENDORING=1 and framework Resources are missing."
    exit 1
  fi
  if [[ -n "${ABSOLUTE_NON_SYSTEM_DEPS}" ]]; then
    log_validation "error: REQUIRE_COMPLETE_VENDORING=1 and vendored python3 still references non-system absolute dylibs."
    exit 1
  fi
  log_validation "strict-mode check passed: vendored runtime layout is complete for bundle staging."
fi

PREPARED_PYTHON="${RUNTIME_OUT}/bin/python3"
PREPARED_SITE_PACKAGES="${PACKAGES_OUT}/lib/${PYTHON_VERSION}/site-packages"
SMOKE_REPORT="${OUTPUT_ROOT}/SMOKE_TEST.txt"

PYTHONHOME="${RUNTIME_OUT}" \
PYTHONPATH="${PREPARED_SITE_PACKAGES}" \
PYTHONNOUSERSITE=1 \
"${PREPARED_PYTHON}" - <<'PY' > "${SMOKE_REPORT}"
import cv2
import mediapipe
import sys

print(f"smoke_executable={sys.executable}")
print(f"smoke_prefix={sys.prefix}")
print(f"smoke_mediapipe={mediapipe.__file__}")
print(f"smoke_cv2={cv2.__file__}")
PY

while IFS= read -r line; do
  log_validation "${line}"
done < "${SMOKE_REPORT}"

log_validation "Validation complete."
log_validation "Next step: copy ${RUNTIME_OUT} and ${PACKAGES_OUT} into release bundle inputs if validation is acceptable."
