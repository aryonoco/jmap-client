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
           yq sg watchexec; do
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
