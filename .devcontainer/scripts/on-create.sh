#!/usr/bin/env bash
set -euo pipefail

# Docker named volumes default to root ownership regardless of Dockerfile
# directives. Correcting ownership here avoids permission-denied failures.
sudo chown -R vscode:vscode \
    /home/vscode/.nimble \
    /home/vscode/.config/gh \
    /home/vscode/.local/share/mise \
    2>/dev/null || true

# Deliberately not in the recursive chown above: the Claude volume carries
# hundreds of megabytes of session transcripts, and recursing it on every
# container create costs seconds for nothing. Only the mount point can be
# wrongly owned — the Dockerfile seeds ownership when Docker populates an
# empty volume from the image, and the migration chowns the contents when
# the volume is pre-seeded instead.
sudo chown vscode:vscode /home/vscode/.claude 2>/dev/null || true

# A freshly created named volume is empty; mise expects its state directory.
mkdir -p /home/vscode/.local/share/mise/state
mkdir -p /home/vscode/.nimble

# Restrict credential directories to owner-only access.
chmod 700 /home/vscode/.ssh 2>/dev/null || true
chmod 700 /home/vscode/.config/gh 2>/dev/null || true
chmod 700 /home/vscode/.claude 2>/dev/null || true
