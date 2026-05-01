#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
set -euo pipefail

ADMIN_AUTH="admin:jmapdev"
STALWART_URL="http://stalwart:8080"

# --- Wait for Stalwart readiness ---
echo "Waiting for Stalwart..."
for i in $(seq 1 60); do
  if curl -fsS "$STALWART_URL/healthz/live" >/dev/null 2>&1; then
    echo "Stalwart is ready (attempt $i)"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: Stalwart failed to start within 60s"
    exit 1
  fi
  sleep 1
done

# --- Create domain and users ---
# POST /api/principal returns 200 {"data": <id>} on success.
# Ignore errors for idempotency (re-running after already seeded).
echo "Creating domain test.local..."
curl -u "$ADMIN_AUTH" -X POST -H "Content-Type: application/json" \
  -d '{"type":"domain","name":"test.local"}' \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$STALWART_URL/api/principal" || true

echo "Creating user alice@test.local..."
curl -u "$ADMIN_AUTH" -X POST -H "Content-Type: application/json" \
  -d '{"type":"individual","name":"alice","secrets":["alice123"],"emails":["alice@test.local"],"roles":["user"]}' \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$STALWART_URL/api/principal" || true

echo "Creating user bob@test.local..."
curl -u "$ADMIN_AUTH" -X POST -H "Content-Type: application/json" \
  -d '{"type":"individual","name":"bob","secrets":["bob123"],"emails":["bob@test.local"],"roles":["user"]}' \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$STALWART_URL/api/principal" || true

# --- Write env file for integration tests ---
ALICE_B64=$(echo -n 'alice:alice123' | base64 -w0)
BOB_B64=$(echo -n 'bob:bob123' | base64 -w0)

cat > /tmp/stalwart-env.sh <<EOF
export JMAP_TEST_SESSION_URL="http://stalwart:8080/jmap/session"
export JMAP_TEST_AUTH_SCHEME="Basic"
export JMAP_TEST_ALICE_TOKEN="$ALICE_B64"
export JMAP_TEST_BOB_TOKEN="$BOB_B64"
EOF

echo ""
echo "=== Stalwart JMAP Test Server ==="
echo "Session URL:  http://stalwart:8080/jmap/session"
echo "Admin:        admin / jmapdev"
echo "Alice:        alice@test.local / alice123"
echo "Bob:          bob@test.local / bob123"
echo "Env file:     /tmp/stalwart-env.sh"
echo "================================="
