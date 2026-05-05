#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
set -euo pipefail

ADMIN_URL="http://cyrus:8001"
JMAP_URL="http://cyrus:8080"

echo "Waiting for Cyrus..."
# Cyrus boots in ~30–60 s on amd64; under arm64 QEMU the budget is
# correspondingly larger. The healthcheck on the docker-compose
# service polls every 5 s with start_period 30 s + 24 retries × 5 s
# = 150 s headroom. The seed script polls the admin homepage up to
# 240 s for safety on slower hosts.
for i in $(seq 1 240); do
  if curl -fsS "$ADMIN_URL/" >/dev/null 2>&1; then
    echo "Cyrus admin server is ready (attempt $i)"
    break
  fi
  if [ "$i" -eq 240 ]; then
    echo "ERROR: Cyrus failed to start within 240s"
    exit 1
  fi
  sleep 1
done

# The cyrus-docker-test-server image (FastMail) exposes an
# administrative Mojolicious surface on port 8001 with three routes:
# ``GET /api/<username>``, ``PUT /api/<username>``, ``DELETE
# /api/<username>``. The PUT body is the JSON dump produced by
# ``Cyrus::AccountSync::dump_user``; the canonical empty-mailbox
# template ships in the image at ``/srv/testserver/examples/empty.json``
# (INBOX / Archive / Drafts / Sent / Spam / Trash with the standard
# specialUse markers). Provision Alice and Bob with that template.
EMPTY_JSON='{"mailboxes":[{"name":"INBOX","subscribed":true},{"name":"Archive","subscribed":true,"specialUse":"\\Archive"},{"name":"Drafts","subscribed":true,"specialUse":"\\Drafts"},{"name":"Sent","subscribed":true,"specialUse":"\\Sent"},{"name":"Spam","subscribed":true,"specialUse":"\\Junk"},{"name":"Trash","subscribed":true,"specialUse":"\\Trash"}]}'

echo "Creating user alice..."
curl -X PUT -H "Content-Type: application/json" \
  -d "$EMPTY_JSON" \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$ADMIN_URL/api/alice"

echo "Creating user bob..."
curl -X PUT -H "Content-Type: application/json" \
  -d "$EMPTY_JSON" \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$ADMIN_URL/api/bob"

# Cyrus's JMAP authenticates Basic with the bare username (no
# domain part) — matching the Stalwart convention. James uses the
# full email. The library's ``initJmapClient`` accepts whatever
# ``authScheme`` / token pair the env vars supply. Cyrus's test
# image accepts any password for any user (per the admin homepage).
ALICE_B64=$(echo -n 'alice:any' | base64 -w0)
BOB_B64=$(echo -n 'bob:any' | base64 -w0)

cat > /tmp/cyrus-env.sh <<EOF
export JMAP_TEST_CYRUS_SESSION_URL="$JMAP_URL/jmap"
export JMAP_TEST_CYRUS_AUTH_SCHEME="Basic"
export JMAP_TEST_CYRUS_ALICE_TOKEN="$ALICE_B64"
export JMAP_TEST_CYRUS_BOB_TOKEN="$BOB_B64"
EOF

echo ""
echo "=== Cyrus IMAP 3.12.2 JMAP Test Server ==="
echo "Session URL:  $JMAP_URL/jmap"
echo "Admin API:    $ADMIN_URL/api/<username>"
echo "Alice:        alice / any"
echo "Bob:          bob / any"
echo "Env file:     /tmp/cyrus-env.sh"
echo "==========================================="
