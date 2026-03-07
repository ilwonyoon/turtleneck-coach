#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOURCE_CONTEXT="${1:-${PROJECT_ROOT}/python_server/.venv}"
OUTPUT_ROOT="${2:-${PROJECT_ROOT}/build/python_bundle_prep}"
RUNTIME_OUT="${OUTPUT_ROOT}/python_runtime"
PACKAGES_OUT="${OUTPUT_ROOT}/python_packages"
REQUIRE_COMPLETE_VENDORING="${REQUIRE_COMPLETE_VENDORING:-${REQUIRE_SELF_CONTAINED_INTERPRETER:-0}}"
RUNTIME_SOURCE_OVERRIDE="${PYTHON_RUNTIME_SOURCE_ROOT:-}"
SITE_PACKAGES_OVERRIDE="${PYTHON_SITE_PACKAGES_SOURCE:-}"

if [[ "${SOURCE_CONTEXT}" == "-h" || "${SOURCE_CONTEXT}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/prepare-python-runtime.sh [SOURCE_CONTEXT] [OUTPUT_ROOT]

Examples:
  ./scripts/prepare-python-runtime.sh
  ./scripts/prepare-python-runtime.sh ./python_server/.venv ./build/python_bundle_prep
  PYTHON_RUNTIME_SOURCE_ROOT=/tmp/python-build-standalone/current \
  PYTHON_SITE_PACKAGES_SOURCE=./python_server/.venv/lib/python3.9/site-packages \
  ./scripts/prepare-python-runtime.sh ./python_server/.venv

Optional env overrides:
  PYTHON_RUNTIME_SOURCE_ROOT   runtime root to vendor from directly
  PYTHON_SITE_PACKAGES_SOURCE  site-packages directory to bundle
  REQUIRE_COMPLETE_VENDORING=1 fail on incomplete vendoring
USAGE
  exit 0
fi

if [[ ! -d "${SOURCE_CONTEXT}" ]]; then
  echo "error: source context not found at ${SOURCE_CONTEXT}" >&2
  exit 1
fi

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

SOURCE_PYTHON="${SOURCE_CONTEXT}/bin/python3"
if [[ ! -e "${SOURCE_PYTHON}" ]]; then
  if [[ -x "${SOURCE_CONTEXT}/bin/python3" ]]; then
    SOURCE_PYTHON="${SOURCE_CONTEXT}/bin/python3"
  else
    echo "error: expected python3 at ${SOURCE_PYTHON}" >&2
    exit 1
  fi
fi

if [[ -n "${SITE_PACKAGES_OVERRIDE}" ]]; then
  SITE_PACKAGES_DIR="${SITE_PACKAGES_OVERRIDE}"
else
  SITE_PACKAGES_DIR="$(find "${SOURCE_CONTEXT}/lib" -type d -name site-packages | head -n1 || true)"
fi
if [[ -z "${SITE_PACKAGES_DIR}" || ! -d "${SITE_PACKAGES_DIR}" ]]; then
  echo "error: could not find site-packages. Set PYTHON_SITE_PACKAGES_SOURCE explicitly." >&2
  exit 1
fi

SOURCE_PYTHON_REAL="$(${SOURCE_PYTHON} - <<'PY' "${SOURCE_PYTHON}"
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"

if [[ -n "${RUNTIME_SOURCE_OVERRIDE}" ]]; then
  SOURCE_RUNTIME_ROOT="$(cd "${RUNTIME_SOURCE_OVERRIDE}" && pwd)"
  RUNTIME_SOURCE_KIND="explicit-runtime-root"
else
  SOURCE_RUNTIME_ROOT="$(${SOURCE_PYTHON} - <<'PY'
import sys
print(sys.base_prefix)
PY
)"
  RUNTIME_SOURCE_KIND="base-prefix-from-python"
fi

SOURCE_RUNTIME_BIN="${SOURCE_RUNTIME_ROOT}/bin"
RUNTIME_PYTHON="${SOURCE_RUNTIME_BIN}/python3"
if [[ ! -x "${RUNTIME_PYTHON}" ]]; then
  echo "error: runtime source is missing bin/python3 at ${RUNTIME_PYTHON}" >&2
  exit 1
fi
PYTHON_VERSION="$(${RUNTIME_PYTHON} - <<'PY'
import sys
print(f"python{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
PYTHON_VERSION_SHORT="${PYTHON_VERSION#python}"
SOURCE_RUNTIME_STDLIB="${SOURCE_RUNTIME_ROOT}/lib/${PYTHON_VERSION}"
SOURCE_RUNTIME_RESOURCES="${SOURCE_RUNTIME_ROOT}/Resources"
SOURCE_RUNTIME_FRAMEWORK_DYLIB="${SOURCE_RUNTIME_ROOT}/Python3"
SOURCE_RUNTIME_LIB_DIR="${SOURCE_RUNTIME_ROOT}/lib"

if [[ ! -d "${SOURCE_RUNTIME_STDLIB}" ]]; then
  echo "error: runtime source is missing stdlib at ${SOURCE_RUNTIME_STDLIB}" >&2
  exit 1
fi

rm -rf "${RUNTIME_OUT}" "${PACKAGES_OUT}"
mkdir -p "${RUNTIME_OUT}/bin" "${RUNTIME_OUT}/lib" "${PACKAGES_OUT}/lib/${PYTHON_VERSION}"

copy_tree "${SITE_PACKAGES_DIR}" "${PACKAGES_OUT}/lib/${PYTHON_VERSION}/site-packages"
copy_tree "${SOURCE_RUNTIME_STDLIB}" "${RUNTIME_OUT}/lib/${PYTHON_VERSION}"
copy_tree "${SOURCE_RUNTIME_BIN}" "${RUNTIME_OUT}/bin"

if [[ -d "${SOURCE_RUNTIME_RESOURCES}" ]]; then
  copy_tree "${SOURCE_RUNTIME_RESOURCES}" "${RUNTIME_OUT}/Resources"
fi
if [[ -d "${SOURCE_RUNTIME_ROOT}/share" ]]; then
  copy_tree "${SOURCE_RUNTIME_ROOT}/share" "${RUNTIME_OUT}/share"
fi
if [[ -d "${SOURCE_RUNTIME_LIB_DIR}/pkgconfig" ]]; then
  copy_tree "${SOURCE_RUNTIME_LIB_DIR}/pkgconfig" "${RUNTIME_OUT}/lib/pkgconfig"
fi
if [[ -f "${SOURCE_RUNTIME_FRAMEWORK_DYLIB}" ]]; then
  cp -f "${SOURCE_RUNTIME_FRAMEWORK_DYLIB}" "${RUNTIME_OUT}/Python3"
  chmod +x "${RUNTIME_OUT}/Python3"
fi
find "${SOURCE_RUNTIME_LIB_DIR}" -maxdepth 1 -type f -name 'libpython*.dylib' -print0 | while IFS= read -r -d '' dylib; do
  cp -f "${dylib}" "${RUNTIME_OUT}/lib/$(basename "${dylib}")"
done

chmod +x "${RUNTIME_OUT}/bin/python3" 2>/dev/null || true
chmod +x "${RUNTIME_OUT}/bin/python${PYTHON_VERSION_SHORT}" 2>/dev/null || true
ln -sfn python3 "${RUNTIME_OUT}/bin/python"
if [[ -f "${RUNTIME_OUT}/bin/python${PYTHON_VERSION_SHORT}" ]]; then
  :
else
  ln -sfn python3 "${RUNTIME_OUT}/bin/${PYTHON_VERSION}"
fi

cat > "${RUNTIME_OUT}/BUNDLE_MANIFEST.txt" <<MANIFEST
prepared_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
source_context=${SOURCE_CONTEXT}
source_python=${SOURCE_PYTHON}
source_python_real=${SOURCE_PYTHON_REAL}
source_runtime_root=${SOURCE_RUNTIME_ROOT}
runtime_source_kind=${RUNTIME_SOURCE_KIND}
source_site_packages=${SITE_PACKAGES_DIR}
python_version=${PYTHON_VERSION}
release_policy=apple_silicon_only_macos14_plus
MANIFEST

if [[ "${SOURCE_RUNTIME_ROOT}" == /Applications/Xcode.app/* ]]; then
  cat > "${RUNTIME_OUT}/XCODE_FRAMEWORK_SOURCE.txt" <<MARKER
This vendored Python runtime was materialized from the Xcode Python framework source.

source_python=${SOURCE_PYTHON}
source_python_real=${SOURCE_PYTHON_REAL}
source_runtime_root=${SOURCE_RUNTIME_ROOT}
MARKER
fi

VALIDATION_REPORT="${OUTPUT_ROOT}/VALIDATION.txt"
: > "${VALIDATION_REPORT}"
log_validation() { echo "$1" | tee -a "${VALIDATION_REPORT}"; }

log_validation "Prepared vendored Python layout:"
log_validation "  runtime:  ${RUNTIME_OUT}"
log_validation "  packages: ${PACKAGES_OUT}"
log_validation "  source interpreter realpath: ${SOURCE_PYTHON_REAL}"
log_validation "  runtime source root: ${SOURCE_RUNTIME_ROOT}"
log_validation "  runtime source kind: ${RUNTIME_SOURCE_KIND}"
log_validation "  site-packages source: ${SITE_PACKAGES_DIR}"

REQUIRED_FILES=(
  "${RUNTIME_OUT}/bin/python3"
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

HAS_FRAMEWORK_DYLIB=0
if [[ -f "${RUNTIME_OUT}/Python3" ]]; then
  HAS_FRAMEWORK_DYLIB=1
  log_validation "verified: ${RUNTIME_OUT}/Python3"
fi

LIBPYTHON_COUNT=$(find "${RUNTIME_OUT}/lib" -maxdepth 1 -type f -name 'libpython*.dylib' | wc -l | tr -d ' ')
if [[ "${LIBPYTHON_COUNT}" -gt 0 ]]; then
  log_validation "verified: bundled libpython dylib count=${LIBPYTHON_COUNT}"
fi

if [[ ${HAS_FRAMEWORK_DYLIB} -eq 0 && "${LIBPYTHON_COUNT}" -eq 0 ]]; then
  log_validation "error: no bundled Python runtime dylib found under ${RUNTIME_OUT}"
  exit 1
fi

OTOOl_REPORT="${OUTPUT_ROOT}/OTOOl.txt"
otool -L "${RUNTIME_OUT}/bin/python3" > "${OTOOl_REPORT}"
if grep -q '@executable_path/../Python3' "${OTOOl_REPORT}"; then
  log_validation "verified: python3 links against @executable_path/../Python3"
fi
if grep -q '@rpath/libpython' "${OTOOl_REPORT}"; then
  log_validation "verified: python3 links against @rpath/libpython*.dylib"
fi

ABSOLUTE_NON_SYSTEM_DEPS="$((grep '^[[:space:]]' "${OTOOl_REPORT}" | awk '{print $1}' | grep '^/' | grep -v '^/usr/lib/' | grep -v '^/System/' || true) | tr '\n' ' ')"
if [[ -n "${ABSOLUTE_NON_SYSTEM_DEPS}" ]]; then
  log_validation "warning: non-system absolute dylib dependencies detected: ${ABSOLUTE_NON_SYSTEM_DEPS}"
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
  if [[ ! -d "${RUNTIME_OUT}/lib/${PYTHON_VERSION}" ]]; then
    log_validation "error: REQUIRE_COMPLETE_VENDORING=1 and stdlib is missing."
    exit 1
  fi
  if [[ ${HAS_FRAMEWORK_DYLIB} -eq 0 && "${LIBPYTHON_COUNT}" -eq 0 ]]; then
    log_validation "error: REQUIRE_COMPLETE_VENDORING=1 and no runtime dylib was bundled."
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
DYLD_PATH_VALUE="${RUNTIME_OUT}/lib"
if [[ ${HAS_FRAMEWORK_DYLIB} -eq 1 ]]; then
  DYLD_PATH_VALUE="${RUNTIME_OUT}/lib"
fi

PYTHONHOME="${RUNTIME_OUT}" \
PYTHONPATH="${PREPARED_SITE_PACKAGES}" \
PYTHONNOUSERSITE=1 \
DYLD_LIBRARY_PATH="${DYLD_PATH_VALUE}" \
DYLD_FALLBACK_LIBRARY_PATH="${DYLD_PATH_VALUE}" \
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
