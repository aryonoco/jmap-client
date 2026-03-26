# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri
#
# =============================================================================
# jmap-client — Cross-platform JMAP client library
# Task runner
# =============================================================================

set shell := ["bash", "-euo", "pipefail", "-c"]

# =============================================================================
# DEFAULT & HELP
# =============================================================================

# Show available commands
default:
    @just --list

# Show version information for all tools
versions:
    @echo "jmap-client Development Environment:"
    @echo "======================================"
    @echo "  Nim:           $(nim --version 2>/dev/null | head -1 | cut -d' ' -f4 || echo 'not installed')"
    @echo "  Nimble:        $(nimble --version 2>/dev/null | head -1 | cut -d' ' -f2 || echo 'not installed')"
    @echo "  nph:           $(nph --version 2>/dev/null | head -1 || echo 'not installed')"
    @echo "  nimlangserver: $(nimlangserver --version 2>/dev/null | head -1 || echo 'not installed')"
    @echo "  just:          $(just --version)"
    @echo "  cspell:        $(cspell --version 2>/dev/null || echo 'not installed')"
    @echo "  reuse:         $(reuse --version 2>/dev/null || echo 'not installed')"

# =============================================================================
# SETUP
# =============================================================================

# Install project dependencies
setup:
    @echo "Installing project dependencies..."
    nimble refresh
    nimble install -d --accept
    nimble setup
    @echo "Dependencies installed"

# Update all dependencies
update:
    nimble refresh
    nimble install -d --accept
    @echo "Dependencies updated"

# Generate nimble.lock for reproducible builds
lock:
    nimble lock
    @echo "nimble.lock generated"

# =============================================================================
# BUILDING
# =============================================================================

# Build shared library
build:
    @echo "Building shared library..."
    nim c --app:lib --noMain -d:ssl -o:bin/libjmap_client.so src/jmap_client.nim
    @echo "Built: bin/libjmap_client.so"

# =============================================================================
# TESTING
# =============================================================================

# Run all tests
test:
    @echo "Running tests..."
    nimble test
    @echo "All tests passed"

# Run tests with verbose output
test-verbose:
    @echo "Running tests (verbose)..."
    testament --verbose all
    @echo "All tests passed"

# Run specific test file
test-file file:
    @echo "Running test: {{file}}"
    testament {{file}}

# Run tests and generate HTML report
test-report:
    @echo "Running tests with report..."
    testament all
    testament html
    @echo "Test report: testresults.html"

# =============================================================================
# CODE QUALITY
# =============================================================================

# Format all source files with nph
fmt:
    @echo "Formatting source files..."
    nph src/ tests/
    @echo "Formatting complete"

# Check formatting without modifying (CI-friendly)
fmt-check:
    @echo "Checking formatting..."
    nph --check src/ tests/
    @echo "Formatting check passed"

# Show diff of formatting changes
fmt-diff:
    @echo "Showing formatting diff..."
    nph --diff src/ tests/

# Lint source files (Nim compile-time checks)
lint:
    @echo "Running lint checks..."
    nim check src/jmap_client.nim
    @echo "Lint checks passed"

# Run all code quality checks
check: fmt-check lint
    @echo "All quality checks passed"

# =============================================================================
# CI PIPELINE
# =============================================================================

# Check REUSE compliance (licensing)
reuse:
    @echo "Checking REUSE compliance..."
    reuse lint
    @echo "REUSE compliance check passed"

# Run full CI pipeline locally (mirrors .github/workflows/ci.yml)
ci: reuse fmt-check lint test
    @echo ""
    @echo "============================================"
    @echo "All CI checks passed!"
    @echo "============================================"

# =============================================================================
# DOCUMENTATION
# =============================================================================

# Generate HTML documentation
docs:
    @echo "Generating documentation..."
    nim doc --project --index:on --outdir:htmldocs src/jmap_client.nim
    @echo "Documentation generated: htmldocs/"

# =============================================================================
# CLEANUP
# =============================================================================

# Clean all build artifacts
clean:
    @echo "Cleaning build artifacts..."
    rm -rf bin/ nimcache/ htmldocs/
    rm -f testresults.html outputGotten.txt
    rm -f tests/megatest tests/megatest.nim
    @echo "Clean complete"

# Deep clean (includes nimble cache)
clean-all: clean
    @echo "Deep cleaning..."
    rm -rf nimblecache/ nimbledeps/
    @echo "Deep clean complete"

# =============================================================================
# DEVELOPMENT HELPERS
# =============================================================================

# Watch for changes and rebuild (requires entr)
watch:
    @echo "Watching for changes... (Ctrl+C to stop)"
    @find src/ -name '*.nim' | entr -c just build

# Watch and run tests on change
watch-test:
    @echo "Watching for changes... (Ctrl+C to stop)"
    @find src/ tests/ -name '*.nim' | entr -c just test

# =============================================================================
# REFERENCE SOURCES (.nim-reference/, git-ignored, fetched on demand)
# =============================================================================

ref_dir := ".nim-reference"

# Fetch all reference sources
fetch-refs: fetch-nim-ref

# Fetch Nim source (stdlib, compiler, docs) for read-only reference
fetch-nim-ref:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s inherit_errexit

    readonly version="${NIM_VERSION:?NIM_VERSION not set — check mise.toml}"
    readonly dest="{{ref_dir}}"
    readonly marker="${dest}/.version"
    readonly repo="https://github.com/nim-lang/Nim.git"

    if [[ -f "${marker}" && "$(<"${marker}")" == "${version}" ]]; then
        echo "Nim ${version} reference already present at ${dest}/"
        exit 0
    fi

    echo "Fetching Nim ${version} source..."
    rm -rf "${dest}"

    tmpdir="$(mktemp -d)"
    cleanup() { rm -rf "${tmpdir}"; }
    trap cleanup EXIT

    git clone --depth=1 --branch "v${version}" -- "${repo}" "${tmpdir}"
    rm -rf "${tmpdir}/.git"
    mv -- "${tmpdir}" "${dest}"

    echo "${version}" > "${marker}"
    echo "Nim reference source ready at ${dest}/"

# Remove all fetched reference sources
clean-refs:
    #!/usr/bin/env bash
    set -euo pipefail
    readonly dest="{{ref_dir}}"
    if [[ -d "${dest}" ]]; then
        rm -rf "${dest}"
        echo "Reference sources removed"
    else
        echo "Nothing to remove"
    fi
