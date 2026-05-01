#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  jmap-client DevContainer Setup"
echo "=========================================="
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

# nph is built from source rather than fetched from GitHub releases:
# upstream's "nph-linux_arm64.tar.gz" actually contains the x86_64 binary
# (verified across v0.5–v0.7), so mise's GitHub-asset backend installs an
# x86 binary on aarch64 hosts that fails with "Dynamic loader not found:
# /lib64/ld-linux-x86-64.so.2" the first time `just fmt-check` runs.
# Building via nimble against the in-image Nim produces a host-native
# binary on both amd64 and arm64. Version pinned to match what mise.toml
# previously selected.
echo ""
echo "Installing nph via nimble (host-native build)..."
nimble install nph@0.7.0 --accept
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
