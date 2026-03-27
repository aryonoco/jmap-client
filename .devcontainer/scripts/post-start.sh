#!/usr/bin/env bash
set -e
shopt -s inherit_errexit

get_version() {
    local output
    output=$("${@}" 2>/dev/null) || { echo "N/A"; return; }
    echo "${output%%$'\n'*}"
}

echo ""
echo "=== jmap-client Environment ==="
echo ""

ver_nim=$(get_version nim --version)
ver_nimble=$(get_version nimble --version)
ver_nph=$(get_version nph --version)
ver_nimlangserver=$(get_version nimlangserver --version)
ver_just=$(get_version just --version)
ver_cspell=$(get_version cspell --version)
ver_reuse=$(get_version reuse --version)
ver_ghcli=$(get_version gh --version)
ver_rg=$(get_version rg --version)
ver_python=$(get_version python3 --version)
ver_shellcheck=$(get_version shellcheck --version)
ver_delta=$(get_version delta --version)

echo "Tools:"
echo "  Nim:           ${ver_nim}"
echo "  Nimble:        ${ver_nimble}"
echo "  nph:           ${ver_nph}"
echo "  nimlangserver: ${ver_nimlangserver}"
echo "  just:          ${ver_just}"
echo "  cspell:        ${ver_cspell}"
echo "  reuse:         ${ver_reuse}"
echo "  GitHub CLI:    ${ver_ghcli}"
echo ""
echo "CLI utilities:"
echo "  ripgrep:       ${ver_rg}"
echo "  Python:        ${ver_python}"
echo "  shellcheck:    ${ver_shellcheck}"
echo "  delta:         ${ver_delta}"
echo ""

if gh auth status &>/dev/null 2>&1; then
    echo "GitHub CLI: Authenticated"
else
    echo "GitHub CLI: Not authenticated (run 'gh auth login')"
fi

echo ""
echo "=== Quick Commands ==="
echo "  just --list   - Show all available commands"
echo "  just ci       - Run full CI pipeline"
echo "  just build    - Build shared library"
echo "  just test     - Run tests"
echo ""
