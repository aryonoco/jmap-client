#!/usr/bin/env bash
set -euo pipefail

# Docker named volumes default to root ownership regardless of Dockerfile
# directives. Correcting ownership here avoids permission-denied failures.
sudo chown -R vscode:vscode \
    /home/vscode/.nimble \
    /home/vscode/.config/gh \
    /home/vscode/.local/share/mise \
    2>/dev/null || true

# A freshly created named volume is empty; mise expects its state directory.
mkdir -p /home/vscode/.local/share/mise/state
mkdir -p /home/vscode/.nimble

# Restrict credential directories to owner-only access.
chmod 700 /home/vscode/.ssh 2>/dev/null || true
chmod 700 /home/vscode/.config/gh 2>/dev/null || true
