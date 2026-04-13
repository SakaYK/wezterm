#!/usr/bin/env bash
set -euo pipefail

# Auto-detect package format from environment or distro
if [ -z "${PKG_FORMAT:-}" ]; then
  if command -v dpkg >/dev/null 2>&1; then
    PKG_FORMAT=deb
  elif command -v rpm >/dev/null 2>&1; then
    PKG_FORMAT=rpm
  else
    echo "ERROR: Cannot detect package format. Set PKG_FORMAT=deb|rpm" >&2
    exit 1
  fi
fi

echo "=== Package format: ${PKG_FORMAT} ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${PKG_FORMAT}" in
  deb) exec bash "${SCRIPT_DIR}/build-deb.sh" ;;
  rpm) exec bash "${SCRIPT_DIR}/build-rpm.sh" ;;
  *)
    echo "ERROR: Unknown PKG_FORMAT '${PKG_FORMAT}'. Use deb or rpm." >&2
    exit 1
    ;;
esac
