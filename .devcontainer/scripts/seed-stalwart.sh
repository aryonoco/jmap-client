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
echo "Creating domain example.com..."
curl -u "$ADMIN_AUTH" -X POST -H "Content-Type: application/json" \
  -d '{"type":"domain","name":"example.com"}' \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$STALWART_URL/api/principal" || true

echo "Creating user alice@example.com..."
curl -u "$ADMIN_AUTH" -X POST -H "Content-Type: application/json" \
  -d '{"type":"individual","name":"alice","secrets":["alice123"],"emails":["alice@example.com"],"roles":["user"]}' \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$STALWART_URL/api/principal" || true

echo "Creating user bob@example.com..."
curl -u "$ADMIN_AUTH" -X POST -H "Content-Type: application/json" \
  -d '{"type":"individual","name":"bob","secrets":["bob123"],"emails":["bob@example.com"],"roles":["user"]}' \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$STALWART_URL/api/principal" || true

# --- Disable Stalwart inbound SMTP rate limiters for test traffic ---
# Stalwart 0.15.5 ships queue.limiter.inbound.sender enabled at
# 25 messages/hour per (sender_domain, rcpt) and queue.limiter.inbound.ip
# at 5/sec per remote_ip. The 26th alice→bob submission would defer with
# SMTP 452, leaving the EmailSubmission stuck at 'pending' indefinitely
# and breaking sequential test runs. The dev container topology (private
# Docker network, two test users) has no abuse vector, so disable both.
echo "Disabling SMTP rate limiters for test traffic..."
curl -u "$ADMIN_AUTH" -X POST -H "Content-Type: application/json" \
  -d '[{"type":"insert","prefix":null,"values":[["queue.limiter.inbound.sender.enable","false"],["queue.limiter.inbound.ip.enable","false"]],"assert_empty":false}]' \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$STALWART_URL/api/settings" || true

# Stalwart caches the rate-limiter config at startup; the admin-API
# override above only takes effect after GET /api/reload re-evaluates
# the queue layer.
echo "Reloading Stalwart config..."
curl -u "$ADMIN_AUTH" \
  -o /dev/null -s -w "  HTTP %{http_code}\n" \
  "$STALWART_URL/api/reload" || true

# --- Write env file for integration tests ---
ALICE_B64=$(echo -n 'alice:alice123' | base64 -w0)
BOB_B64=$(echo -n 'bob:bob123' | base64 -w0)
ADMIN_B64=$(echo -n "$ADMIN_AUTH" | base64 -w0)

cat > /tmp/stalwart-env.sh <<EOF
export JMAP_TEST_SESSION_URL="http://stalwart:8080/jmap/session"
export JMAP_TEST_AUTH_SCHEME="Basic"
export JMAP_TEST_ALICE_TOKEN="$ALICE_B64"
export JMAP_TEST_BOB_TOKEN="$BOB_B64"
export JMAP_TEST_ADMIN_BASIC="$ADMIN_B64"
EOF

# --- JMAP-level SMTP smoke check ---
# Issues a real submission alice -> bob via the JMAP API and polls
# EmailSubmission/get until undoStatus == "final". Fails fast (non-zero
# exit) on HTTP error, setError in createResults, or 10 s timeout. The
# check serves as a regression detector: future Stalwart upgrades that
# alter SMTP listener defaults, route.local, or submission capability
# trip the gate before any test runs.
echo ""
echo "Running JMAP-level SMTP smoke check (alice -> bob)..."
SMOKE_START=$(date +%s%3N)

# 1. Resolve account id and inbox mailbox id from the session + Mailbox/get.
SESSION_JSON=$(curl -fsS -u alice:alice123 "$STALWART_URL/jmap/session")
MAIL_ACCT=$(printf '%s' "$SESSION_JSON" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["primaryAccounts"]["urn:ietf:params:jmap:mail"])')
SUB_ACCT=$(printf '%s' "$SESSION_JSON" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["primaryAccounts"]["urn:ietf:params:jmap:submission"])')

MAILBOX_REQ=$(python3 -c '
import json, sys
print(json.dumps({
  "using": ["urn:ietf:params:jmap:core","urn:ietf:params:jmap:mail"],
  "methodCalls": [["Mailbox/get", {"accountId": sys.argv[1]}, "c0"]]
}))
' "$MAIL_ACCT")
MAILBOX_RESP=$(curl -fsS -u alice:alice123 -H 'Content-Type: application/json' \
  --data "$MAILBOX_REQ" "$STALWART_URL/jmap/")
INBOX_ID=$(printf '%s' "$MAILBOX_RESP" \
  | python3 -c '
import json, sys
d = json.load(sys.stdin)
inv = d["methodResponses"][0]
for mb in inv[1]["list"]:
  if mb.get("role") == "inbox":
    print(mb["id"]); break
')
if [ -z "$INBOX_ID" ]; then
  echo "ERROR: smoke check could not resolve inbox mailbox id"
  exit 1
fi

# 2. Seed a draft email alice -> bob.
EMAIL_REQ=$(python3 -c '
import json, sys
acct, inbox = sys.argv[1], sys.argv[2]
print(json.dumps({
  "using": ["urn:ietf:params:jmap:core","urn:ietf:params:jmap:mail"],
  "methodCalls": [["Email/set", {
    "accountId": acct,
    "create": {"smoke": {
      "mailboxIds": {inbox: True},
      "from": [{"email": "alice@example.com", "name": "Alice"}],
      "to":   [{"email": "bob@example.com",   "name": "Bob"}],
      "subject": "smoke-check",
      "bodyValues": {"1": {"value": "smoke", "isEncodingProblem": False, "isTruncated": False}},
      "textBody": [{"partId": "1", "type": "text/plain"}]
    }}
  }, "c0"]]
}))
' "$MAIL_ACCT" "$INBOX_ID")
EMAIL_RESP=$(curl -fsS -u alice:alice123 -H 'Content-Type: application/json' \
  --data "$EMAIL_REQ" "$STALWART_URL/jmap/")
EMAIL_ID=$(printf '%s' "$EMAIL_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
inv = d["methodResponses"][0]
created = inv[1].get("created") or {}
nc = inv[1].get("notCreated") or {}
if "smoke" in nc:
  print("ERR:" + json.dumps(nc["smoke"]))
elif "smoke" in created:
  print(created["smoke"]["id"])
')
case "$EMAIL_ID" in
  ERR:*) echo "ERROR: smoke check Email/set failed: ${EMAIL_ID#ERR:}"; exit 1 ;;
  "")    echo "ERROR: smoke check Email/set produced no result"; exit 1 ;;
esac

# 3. Resolve alice's identity (or create one if absent), then submit.
IDENTITY_REQ=$(python3 -c '
import json, sys
print(json.dumps({
  "using": ["urn:ietf:params:jmap:core","urn:ietf:params:jmap:submission"],
  "methodCalls": [["Identity/get", {"accountId": sys.argv[1]}, "c0"]]
}))
' "$SUB_ACCT")
IDENTITY_RESP=$(curl -fsS -u alice:alice123 -H 'Content-Type: application/json' \
  --data "$IDENTITY_REQ" "$STALWART_URL/jmap/")
IDENTITY_ID=$(printf '%s' "$IDENTITY_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
items = d["methodResponses"][0][1].get("list") or []
for it in items:
  if it.get("email") == "alice@example.com":
    print(it["id"]); break
')
if [ -z "$IDENTITY_ID" ]; then
  IDENTITY_CREATE=$(python3 -c '
import json, sys
print(json.dumps({
  "using": ["urn:ietf:params:jmap:core","urn:ietf:params:jmap:submission"],
  "methodCalls": [["Identity/set", {
    "accountId": sys.argv[1],
    "create": {"alice": {"email": "alice@example.com", "name": "Alice"}}
  }, "c0"]]
}))
' "$SUB_ACCT")
  IDENTITY_CREATED=$(curl -fsS -u alice:alice123 -H 'Content-Type: application/json' \
    --data "$IDENTITY_CREATE" "$STALWART_URL/jmap/")
  IDENTITY_ID=$(printf '%s' "$IDENTITY_CREATED" | python3 -c '
import json, sys
d = json.load(sys.stdin)
created = d["methodResponses"][0][1].get("created") or {}
if "alice" in created:
  print(created["alice"]["id"])
')
fi
if [ -z "$IDENTITY_ID" ]; then
  echo "ERROR: smoke check could not resolve or create alice's Identity"
  exit 1
fi

SUB_REQ=$(python3 -c '
import json, sys
acct, ident, eid = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
  "using": ["urn:ietf:params:jmap:core","urn:ietf:params:jmap:submission"],
  "methodCalls": [["EmailSubmission/set", {
    "accountId": acct,
    "create": {"sub": {
      "identityId": ident,
      "emailId": eid,
      "envelope": {
        "mailFrom": {"email": "alice@example.com"},
        "rcptTo":   [{"email": "bob@example.com"}]
      }
    }}
  }, "c0"]]
}))
' "$SUB_ACCT" "$IDENTITY_ID" "$EMAIL_ID")
SUB_RESP=$(curl -fsS -u alice:alice123 -H 'Content-Type: application/json' \
  --data "$SUB_REQ" "$STALWART_URL/jmap/")
SUB_ID=$(printf '%s' "$SUB_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
inv = d["methodResponses"][0][1]
created = inv.get("created") or {}
nc = inv.get("notCreated") or {}
if "sub" in nc:
  print("ERR:" + json.dumps(nc["sub"]))
elif "sub" in created:
  print(created["sub"]["id"])
')
case "$SUB_ID" in
  ERR:*) echo "ERROR: smoke check EmailSubmission/set failed: ${SUB_ID#ERR:}"; exit 1 ;;
  "")    echo "ERROR: smoke check EmailSubmission/set produced no result"; exit 1 ;;
esac

# 4. Poll EmailSubmission/get every 500 ms until undoStatus == final or 10 s.
FINAL_REACHED=0
for i in $(seq 1 20); do
  POLL_REQ=$(python3 -c '
import json, sys
print(json.dumps({
  "using": ["urn:ietf:params:jmap:core","urn:ietf:params:jmap:submission"],
  "methodCalls": [["EmailSubmission/get", {
    "accountId": sys.argv[1],
    "ids": [sys.argv[2]]
  }, "c0"]]
}))
' "$SUB_ACCT" "$SUB_ID")
  POLL_RESP=$(curl -fsS -u alice:alice123 -H 'Content-Type: application/json' \
    --data "$POLL_REQ" "$STALWART_URL/jmap/")
  STATUS=$(printf '%s' "$POLL_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
items = d["methodResponses"][0][1].get("list") or []
print(items[0]["undoStatus"] if items else "")
')
  if [ "$STATUS" = "final" ]; then
    FINAL_REACHED=1
    break
  fi
  sleep 0.5
done

if [ "$FINAL_REACHED" -ne 1 ]; then
  SMOKE_END=$(date +%s%3N)
  echo "ERROR: smoke check timed out waiting for undoStatus=final after $((SMOKE_END - SMOKE_START))ms"
  exit 1
fi

# Drain the outgoing SMTP queue before declaring smoke-check success.
# Mirrors mlive.awaitSmtpQueueDrain so the env file is written only
# after Stalwart has genuinely delivered the smoke message — the very
# first integration test then starts with an empty queue.
DRAIN_REACHED=0
TOTAL=-1
for i in $(seq 1 60); do
  TOTAL=$(curl -fsS -u "$ADMIN_AUTH" \
    "$STALWART_URL/api/queue/messages?values=true" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("data",{}).get("total",-1))')
  if [ "$TOTAL" = "0" ]; then DRAIN_REACHED=1; break; fi
  sleep 0.5
done
if [ "$DRAIN_REACHED" -ne 1 ]; then
  echo "ERROR: smoke check SMTP queue did not drain (total=$TOTAL)"
  exit 1
fi

SMOKE_END=$(date +%s%3N)
SMOKE_MS=$((SMOKE_END - SMOKE_START))
echo "alice->bob delivery confirmed in ${SMOKE_MS}ms"

echo ""
echo "=== Stalwart JMAP Test Server ==="
echo "Session URL:  http://stalwart:8080/jmap/session"
echo "Admin:        admin / jmapdev"
echo "Alice:        alice@example.com / alice123"
echo "Bob:          bob@example.com / bob123"
echo "Env file:     /tmp/stalwart-env.sh"
echo "================================="
