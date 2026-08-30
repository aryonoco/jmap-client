#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
set -uo pipefail

# Precondition gate for the live-integration recipes (`just test-full`,
# `just test-integration`, `just capture-fixtures`).
#
# The /tmp env files outlive the containers that wrote them: the dev
# container survives a `docker stop` of the servers, and its /tmp is
# persistent, so a file written weeks ago still names a host that no
# longer resolves. File existence is therefore no evidence a target is
# answering, and an unprobed dead target surfaces as one DNS failure per
# live test — 73 of them, none naming the actual cause — instead of the
# single actionable line printed here.
#
# The probe authenticates as Alice against the session endpoint, so it
# also rejects a target whose container is up but whose accounts were
# never seeded.

PROBE_TIMEOUT="${JMAP_LIVE_PROBE_TIMEOUT:-10}"

configured=()
unreachable=()

probe_target() {
    local name="$1" envfile="$2"
    [ -f "$envfile" ] || return 0
    configured+=("$name")

    local prefix urlvar uservar passvar url user password
    prefix="JMAP_TEST_$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
    # shellcheck source=/dev/null
    . "$envfile"
    urlvar="${prefix}_SESSION_URL"
    uservar="${prefix}_ALICE_USER"
    passvar="${prefix}_ALICE_PASSWORD"
    url="${!urlvar:-}"
    user="${!uservar:-}"
    password="${!passvar:-}"

    if [ -z "$url" ] || [ -z "$user" ] || [ -z "$password" ]; then
        unreachable+=("${name}"$'\t'"${envfile} is missing session URL or credentials")
        return 0
    fi

    if ! curl -fsS -m "$PROBE_TIMEOUT" -u "${user}:${password}" -o /dev/null "$url" \
        2>/dev/null; then
        unreachable+=("${name}"$'\t'"no session response from ${url}")
    fi
}

probe_target stalwart /tmp/stalwart-env.sh
probe_target james /tmp/james-env.sh
probe_target cyrus /tmp/cyrus-env.sh

if [ "${#configured[@]}" -eq 0 ]; then
    echo "ERROR: at least one of /tmp/stalwart-env.sh, /tmp/james-env.sh, or /tmp/cyrus-env.sh required" >&2
    echo "       run 'just jmap-up' (or 'just stalwart-up' / 'just james-up' / 'just cyrus-up') first" >&2
    exit 1
fi

if [ "${#unreachable[@]}" -gt 0 ]; then
    echo "ERROR: configured JMAP target(s) not answering:" >&2
    for entry in "${unreachable[@]}"; do
        name="${entry%%$'\t'*}"
        reason="${entry#*$'\t'}"
        echo "       ${name}: ${reason}" >&2
        echo "              restart with 'just ${name}-up', or 'just ${name}-reset' for a clean slate" >&2
    done
    echo "       (a /tmp env file outlives the container that wrote it, so its" >&2
    echo "       presence alone does not mean the server is up)" >&2
    exit 1
fi
