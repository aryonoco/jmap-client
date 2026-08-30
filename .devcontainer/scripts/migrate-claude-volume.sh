#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
#
# Carries /home/vscode/.claude across the rebuild that turns it into a
# volume mount.
#
# Docker populates a named volume from the image only while the volume is
# empty, and the image's /home/vscode/.claude is empty by construction. So
# adding the mount and rebuilding starts Claude Code from nothing: session
# transcripts, shell snapshots, the plugin cache and the stored credentials
# all live on the container's overlay filesystem and go with the old
# container.
#
# Pre-creating the destination is not an option. The devcontainer CLI
# routes its `mounts` entries through Compose, which stamps every volume it
# owns with a com.docker.compose.config-hash label and refuses one carrying
# the wrong hash — a value this script cannot compute. So the state is
# parked in a plain staging volume first, and copied into the real one
# after Compose has created it.
#
#   ./migrate-claude-volume.sh stage     # before "Rebuild Container"
#   ./migrate-claude-volume.sh restore   # after it comes back up
#   ./migrate-claude-volume.sh discard   # once you have verified it
#
# Run `stage` with Claude Code closed: the copy is not atomic, and
# history.jsonl is appended to continuously. Both steps are idempotent.
set -euo pipefail

CONTAINER="jmap-client"
STAGING="jmc-claude-migration"
CLAUDE_DIR="/home/vscode/.claude"
CLAUDE_FILE="/home/vscode/.claude.json"
HELPER_IMAGE="alpine:3"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_container() {
  docker inspect "$CONTAINER" >/dev/null 2>&1 ||
    die "container '$CONTAINER' is not running; start it first."
}

volume_empty() {
  [ -z "$(docker run --rm -v "$1":/v "$HELPER_IMAGE" ls -A /v)" ]
}

# The volume name embeds ${devcontainerId} and carries a Compose project
# prefix, so it is read back off the running container rather than spelled
# out. Matching on the mount point is what makes that safe.
target_volume() {
  docker inspect "$CONTAINER" --format \
    "{{range .Mounts}}{{if eq .Destination \"${CLAUDE_DIR}\"}}{{.Name}}{{end}}{{end}}"
}

cmd_stage() {
  require_container
  docker volume create "$STAGING" >/dev/null

  if ! volume_empty "$STAGING"; then
    echo "Staging volume '$STAGING' already holds content; leaving it alone."
    echo "Run 'discard' first if you meant to re-stage."
    return 0
  fi

  local helper="claude-stage-$$"
  # shellcheck disable=SC2064  # $helper is fixed at trap-installation time
  trap "docker rm -f '$helper' >/dev/null 2>&1 || true" RETURN
  docker run -d --name "$helper" -v "$STAGING":/stage "$HELPER_IMAGE" \
    sleep 900 >/dev/null

  echo "Staging ${CLAUDE_DIR} ..."
  docker cp "$CONTAINER:${CLAUDE_DIR}/." "$helper:/stage/"

  # Absent on a container that has never run Claude Code; not fatal.
  if docker exec "$CONTAINER" test -f "$CLAUDE_FILE" 2>/dev/null; then
    echo "Staging ${CLAUDE_FILE} ..."
    docker cp "$CONTAINER:$CLAUDE_FILE" "$helper:/stage/.claude.json"
  else
    echo "No ${CLAUDE_FILE} to stage; skipping."
  fi

  echo "Staged $(docker exec "$helper" du -sh /stage | cut -f1) into '$STAGING'."
  echo "Now rebuild the container, then run: $0 restore"
}

cmd_restore() {
  require_container
  docker volume inspect "$STAGING" >/dev/null 2>&1 ||
    die "staging volume '$STAGING' does not exist; was 'stage' run?"

  local target
  target="$(target_volume)"
  [ -n "$target" ] ||
    die "'$CONTAINER' has no volume mounted at ${CLAUDE_DIR}; rebuild first."

  if ! volume_empty "$target"; then
    echo "Target volume '$target' already holds content; nothing to do."
    return 0
  fi

  echo "Restoring into '$target' ..."
  docker run --rm -v "$STAGING":/src -v "$target":/dst "$HELPER_IMAGE" \
    sh -c 'cp -a /src/. /dst/ && chown -R 1000:1000 /dst && chmod 700 /dst'

  echo "Restored. Verify, then run: $0 discard"
}

cmd_discard() {
  docker volume rm "$STAGING" >/dev/null 2>&1 ||
    die "could not remove '$STAGING'; is a container still using it?"
  echo "Removed staging volume '$STAGING'."
}

case "${1:-}" in
  stage) cmd_stage ;;
  restore) cmd_restore ;;
  discard) cmd_discard ;;
  *)
    echo "usage: $0 {stage|restore|discard}" >&2
    exit 2
    ;;
esac
