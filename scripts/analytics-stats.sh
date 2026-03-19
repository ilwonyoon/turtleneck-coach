#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage:
  ANALYTICS_BASE_URL=https://<worker-domain> \
  ANALYTICS_ADMIN_TOKEN=<token> \
  ./scripts/analytics-stats.sh [days]

Example:
  ANALYTICS_BASE_URL=https://turtleneck-analytics.example.workers.dev \
  ANALYTICS_ADMIN_TOKEN=super-secret-token \
  ./scripts/analytics-stats.sh 30
USAGE
  exit 0
fi

DAYS="${1:-30}"
BASE_URL="${ANALYTICS_BASE_URL:-}"
ADMIN_TOKEN="${ANALYTICS_ADMIN_TOKEN:-}"

if [[ -z "${BASE_URL}" ]]; then
  echo "error: ANALYTICS_BASE_URL is required, e.g. https://<worker-domain>" >&2
  exit 1
fi

if [[ -z "${ADMIN_TOKEN}" ]]; then
  echo "error: ANALYTICS_ADMIN_TOKEN is required." >&2
  exit 1
fi

URL="${BASE_URL%/}/v1/stats?days=${DAYS}"
RESPONSE="$(curl -fsSL \
  -H "User-Agent: TurtleneckCoachStats/1.0 CFNetwork Darwin" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "${URL}")"

if command -v jq >/dev/null 2>&1; then
  printf '%s\n' "${RESPONSE}" | jq
else
  printf '%s\n' "${RESPONSE}"
fi
