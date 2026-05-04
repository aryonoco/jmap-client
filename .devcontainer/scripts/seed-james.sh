#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
set -euo pipefail

WEBADMIN_URL="http://james:8000"

echo "Waiting for James..."
for i in $(seq 1 120); do
  if curl -fsS "$WEBADMIN_URL/healthcheck" >/dev/null 2>&1; then
    echo "James is ready (attempt $i)"
    break
  fi
  if [ "$i" -eq 120 ]; then
    echo "ERROR: James failed to start within 120s"
    exit 1
  fi
  sleep 1
done

# Domain creation is idempotent: PUT /domains/<name> returns 204 on
# success and 400 when already present; ?force lets the caller proceed
# regardless.
echo "Creating domain example.com..."
curl -X PUT -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$WEBADMIN_URL/domains/example.com"

echo "Creating user alice@example.com..."
curl -X PUT -H "Content-Type: application/json" \
  -d '{"password":"alice123"}' \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$WEBADMIN_URL/users/alice@example.com?force"

echo "Creating user bob@example.com..."
curl -X PUT -H "Content-Type: application/json" \
  -d '{"password":"bob123"}' \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$WEBADMIN_URL/users/bob@example.com?force"

# James Basic-auth uses the FULL email as username (enableVirtualHosting=true
# in usersrepository.xml). Stalwart uses the bare ``alice``/``bob``.
ALICE_B64=$(echo -n 'alice@example.com:alice123' | base64 -w0)
BOB_B64=$(echo -n 'bob@example.com:bob123' | base64 -w0)

cat > /tmp/james-env.sh <<EOF
export JMAP_TEST_JAMES_SESSION_URL="http://james:80/jmap/session"
export JMAP_TEST_JAMES_AUTH_SCHEME="Basic"
export JMAP_TEST_JAMES_ALICE_TOKEN="$ALICE_B64"
export JMAP_TEST_JAMES_BOB_TOKEN="$BOB_B64"
EOF

echo ""
echo "=== Apache James JMAP Test Server ==="
echo "Session URL:  http://james:80/jmap/session"
echo "WebAdmin:     http://james:8000 (no auth)"
echo "Alice:        alice@example.com / alice123"
echo "Bob:          bob@example.com / bob123"
echo "Env file:     /tmp/james-env.sh"
echo "======================================"
