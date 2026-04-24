#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  jmap-client DevContainer Setup"
echo "=========================================="
echo ""

# The docker-outside-of-docker feature creates a `docker` group inside the
# container with a GID it picks at install time. That GID may not match the
# GID that owns the host's docker socket (mounted at /var/run/docker-host.sock).
# When they diverge, `vscode` — though added to the container's docker group —
# cannot reach the socket. Reconcile by creating a supplementary group with
# the host socket's GID and adding vscode to it.
echo "Reconciling docker socket GID..."
if [[ -e /var/run/docker-host.sock ]]; then
    HOST_DOCKER_GID=$(stat -c '%g' /var/run/docker-host.sock)
    if [[ "${HOST_DOCKER_GID}" != "0" ]]; then
        if ! getent group "${HOST_DOCKER_GID}" >/dev/null; then
            sudo groupadd -g "${HOST_DOCKER_GID}" docker-host
        fi
        GROUP_NAME=$(getent group "${HOST_DOCKER_GID}" | cut -d: -f1)
        if ! id -nG vscode | grep -qw "${GROUP_NAME}"; then
            sudo usermod -aG "${GROUP_NAME}" vscode
        fi
        echo "  vscode has access via group ${GROUP_NAME} (GID ${HOST_DOCKER_GID})"
    else
        echo "  Host socket owned by gid 0; no reconciliation needed"
    fi
else
    echo "  /var/run/docker-host.sock not found; skipping"
fi
echo "  Done"

echo ""
echo "Configuring shell..."
DEVCONTAINER_DIR="/workspaces/jmap-client/.devcontainer"

cp "${DEVCONTAINER_DIR}/config/zshrc" /home/vscode/.zshrc
cp "${DEVCONTAINER_DIR}/config/zsh_plugins.txt" /home/vscode/.zsh_plugins.txt
cp "${DEVCONTAINER_DIR}/config/p10k.zsh" /home/vscode/.p10k.zsh
echo "  Done"

echo ""
echo "Installing tools via mise..."
cd /workspaces/jmap-client
mise install --yes
export PATH="/home/vscode/.local/share/mise/shims:${PATH}"
echo "  Done"

echo ""
echo "Installing Python tools via uv..."
uv tool install reuse==6.2.0
echo "  Done"

echo ""
echo "Installing nimalyzer via nimble..."
nimble install nimalyzer --accept
echo "  Done"

# Non-interactive shells (SSH, VS Code tasks) skip .zshrc, so mise shims
# must be injected into PATH via a profile.d script.
echo ""
echo "Configuring mise PATH for non-interactive shells..."
MISE_PROFILE_DIR="/home/vscode/.local/share/mise/profile.d"
mkdir -p "${MISE_PROFILE_DIR}"
cat > "${MISE_PROFILE_DIR}/mise-path.sh" << 'MISE_EOF'
# Sourced by ~/.profile to expose mise shims in non-interactive shells
export PATH="/home/vscode/.local/share/mise/shims:${PATH}"
MISE_EOF

if ! grep -q 'mise/profile.d/mise-path.sh' /home/vscode/.profile 2>/dev/null; then
    echo '[ -f /home/vscode/.local/share/mise/profile.d/mise-path.sh ] && . /home/vscode/.local/share/mise/profile.d/mise-path.sh' >> /home/vscode/.profile
    echo "  Added mise-path.sh sourcing to ~/.profile"
fi
echo "  Done"

echo ""
echo "Running project setup..."
just setup
echo "  Done"

echo ""
echo "Verifying CLI tool availability..."
failed=0
for cmd in nim nimble nph nimlangserver nimalyzer just cspell reuse \
           rg bat delta shellcheck shfmt sd python3 \
           eza dust hyperfine tokei bwrap socat \
           yq sg watchexec docker; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "  ERROR: ${cmd} not found after installation" >&2
        failed=1
    fi
done
if [[ "${failed}" -ne 0 ]]; then exit 1; fi
echo "  All CLI tools verified"

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "Available commands:"
echo "  just --list   - Show all available commands"
echo "  just ci       - Run full CI pipeline"
echo "  just build    - Build shared library"
echo "  just test     - Run tests"
echo ""
