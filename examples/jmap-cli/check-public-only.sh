#!/usr/bin/env bash
# Fails if the sample reaches past the public surface into jmap_client/internal.
# This is the honesty mechanism for the P29 bench (mirrors tracker H7).
set -euo pipefail
cd "$(dirname "$0")"
if grep -rnE 'import[[:space:]]+[^#]*jmap_client/internal' --include='*.nim' .; then
  echo "FAIL: examples/jmap-cli imports jmap_client/internal (public surface only)" >&2
  exit 1
fi
echo "OK: jmap-cli imports only the public surface"
