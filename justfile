# SPDX-License-Identifier: BSD-2-Clause
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
    @echo "  nimalyzer:     $(nimble dump nimalyzer 2>/dev/null | grep '^version:' | sed 's/version: *//;s/"//g' || echo 'not installed')"
    @echo "  just:          $(just --version)"
    @echo "  cspell:        $(cspell --version 2>/dev/null || echo 'not installed')"
    @echo "  reuse:         $(reuse --version 2>/dev/null || echo 'not installed')"
    @echo ""
    @echo "CLI utilities:"
    @echo "  ripgrep:       $(rg --version 2>/dev/null | head -1 || echo 'not installed')"
    @echo "  shellcheck:    $(shellcheck --version 2>/dev/null | sed -n '2p' || echo 'not installed')"
    @echo "  Python:        $(python3 --version 2>/dev/null || echo 'not installed')"
    @echo "  delta:         $(delta --version 2>/dev/null || echo 'not installed')"

# =============================================================================
# SETUP
# =============================================================================

# Install git hooks (safe to run repeatedly)
install-hooks:
    @git config core.hooksPath .githooks
    @echo "Git hooks installed (core.hooksPath → .githooks/)"

# Install project dependencies
setup: install-hooks
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

# Build shared library with release optimisations
build-release:
    @echo "Building shared library (release)..."
    nim c -d:release --app:lib --noMain -d:ssl -o:bin/libjmap_client.so src/jmap_client.nim
    @echo "Built: bin/libjmap_client.so (release)"

# =============================================================================
# TESTING
# =============================================================================

# Run all tests except those in tests/testament_skip.txt (see test-full for everything)
test:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s inherit_errexit
    cleanup() { find tests/ -name 'megatest' -type f -delete; find tests/ -name 'megatest.nim' -type f -delete; }
    trap cleanup EXIT
    echo "Running tests (excluding slow tests from tests/testament_skip.txt)..."
    testament --backendLogging:off --skipFrom:tests/testament_skip.txt all
    echo "All tests passed"

# Run tests with verbose output
test-verbose:
    @echo "Running tests (verbose)..."
    testament --verbose all
    @echo "All tests passed"

# Run specific test file
test-file file:
    @echo "Running test: {{file}}"
    testament {{file}}

# Run unit tests only
test-unit:
    @echo "Running unit tests..."
    testament cat unit

# Run serialisation tests only
test-serde:
    @echo "Running serde tests..."
    testament cat serde

# Run property-based tests only (excludes slow tests from tests/testament_skip.txt)
test-prop:
    @echo "Running property tests..."
    testament --skipFrom:tests/testament_skip.txt cat property

# Run RFC/scenario compliance tests only
test-rfc:
    @echo "Running compliance tests..."
    testament cat compliance

# Run stress and adversarial tests only
test-stress:
    @echo "Running stress tests..."
    testament cat stress

# Run test categories in parallel (faster CI)
test-parallel:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s inherit_errexit
    cleanup() { find tests/ -name 'megatest' -type f -delete; find tests/ -name 'megatest.nim' -type f -delete; }
    trap cleanup EXIT
    echo "Running tests in parallel by category (excluding tests/testament_skip.txt)..."
    testament --backendLogging:off --skipFrom:tests/testament_skip.txt cat unit &
    testament --backendLogging:off --skipFrom:tests/testament_skip.txt cat serde &
    testament --backendLogging:off --skipFrom:tests/testament_skip.txt cat property &
    testament --backendLogging:off --skipFrom:tests/testament_skip.txt cat compliance &
    testament --backendLogging:off --skipFrom:tests/testament_skip.txt cat stress &
    wait
    echo "All parallel tests passed"

# Run tests and generate HTML report
test-report:
    @echo "Running tests with report..."
    testament all
    testament html
    @echo "Test report: testresults.html"

# Run every test including slow ones from tests/testament_skip.txt. Use periodically.
test-full:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s inherit_errexit
    cleanup() { find tests/ -name 'megatest' -type f -delete; find tests/ -name 'megatest.nim' -type f -delete; }
    trap cleanup EXIT
    echo "Running FULL test suite (including slow tests)..."
    testament --backendLogging:off all
    echo "Full test suite passed"

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

# Lint every src/ module as its own entry point — catches effect-analysis
# failures in modules not yet transitively reachable from src/jmap_client.nim
# (e.g. a new module awaiting a re-export). Complements `lint`, which only
# sees the transitive closure from the library entry point.
lint-isolated:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s inherit_errexit
    echo "Running isolated nim check over every src/ module..."
    find src -name '*.nim' -type f -print0 | \
        xargs -0 -n1 -P"$(nproc)" bash -c '
            file="$1"
            if ! output=$(nim check --hints:off "$file" 2>&1); then
                printf "\n=== FAIL: %s ===\n%s\n" "$file" "$output"
                exit 1
            fi
        ' --
    echo "Isolated lint passed"

# Enforce --styleCheck:error + --hintAsError:Name over every src/ module.
# Per-file iteration (not a single transitive pass) so orphan modules — files
# not yet imported from the library entry point — are also covered; that
# matches lint-isolated's rationale. --errorMax:0 keeps the compiler going
# past vendored style noise (vendor/nim-results uses non-NEP1 casing we do
# not control); vendor/ diagnostics are filtered out and any src/-scoped
# style error fails the recipe. Tests are deliberately excluded — testament
# specs use underscored block names (rfc8620_S1_2_... / regression_2026_03_...)
# by convention.
lint-style:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s inherit_errexit
    echo "Running styleCheck:error + hintAsError:Name over every src/ module..."
    find src -name '*.nim' -type f -print0 | \
        xargs -0 -n1 -P"$(nproc)" bash -c '
            file="$1"
            output=$(nim check --errorMax:0 --hints:off --styleCheck:error --hintAsError:Name "$file" 2>&1 || true)
            src_errors=$(echo "$output" | grep -vE "vendor/.*Error: .* should be" | grep -E "Error: .* should be" || true)
            if [[ -n "$src_errors" ]]; then
                printf "\n=== FAIL: %s ===\n%s\n" "$file" "$src_errors"
                exit 1
            fi
        ' --
    echo "Style check passed (vendor/ diagnostics tolerated)"

# Static analysis with nimalyzer
analyse:
    @echo "Running static analysis..."
    nimalyzer nimalyzer.cfg
    @echo "Static analysis passed"

# Alias for analyse (American English spelling)
analyze: analyse

# Run all code quality checks
check: fmt-check lint lint-isolated lint-style analyse
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
ci: reuse fmt-check lint lint-isolated lint-style analyse test
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
    rm -rf bin/ nimcache/ htmldocs/ testresults/
    rm -f core.*
    rm -f testresults.html outputGotten.txt
    rm -f tests/megatest tests/megatest.nim
    find tests/ -name 'megatest' -type f -delete
    find tests/ -name 'megatest.nim' -type f -delete
    find tests/ -type f -executable -delete
    find src/ tests/ -name '*.out' -delete
    @echo "Clean complete"

# Deep clean (includes nimble cache)
clean-all: clean
    @echo "Deep cleaning..."
    rm -rf nimblecache/ nimbledeps/
    @echo "Deep clean complete"

# =============================================================================
# DEVELOPMENT HELPERS
# =============================================================================

# Watch for changes and rebuild
watch:
    @echo "Watching for changes... (Ctrl+C to stop)"
    @watchexec --exts nim --watch src/ -- just build

# Watch and run tests on change
watch-test:
    @echo "Watching for changes... (Ctrl+C to stop)"
    @watchexec --exts nim --watch src/ --watch tests/ -- just test

# =============================================================================
# STALWART (JMAP integration test server)
# =============================================================================

# Start Stalwart JMAP server and seed test accounts
stalwart-up:
    docker compose -f .devcontainer/docker-compose.yml --profile stalwart up stalwart -d
    .devcontainer/scripts/seed-stalwart.sh

# Stop Stalwart JMAP server
stalwart-down:
    docker compose -f .devcontainer/docker-compose.yml --profile stalwart down

# Tear down and recreate Stalwart with fresh data
stalwart-reset:
    docker compose -f .devcontainer/docker-compose.yml --profile stalwart down -v
    just stalwart-up

# Show Stalwart container status
stalwart-status:
    docker compose -f .devcontainer/docker-compose.yml --profile stalwart ps

# Follow Stalwart container logs
stalwart-logs:
    docker compose -f .devcontainer/docker-compose.yml --profile stalwart logs -f stalwart

# Run live integration tests (requires 'just stalwart-up')
test-integration:
    @if [ ! -f /tmp/stalwart-env.sh ]; then echo "ERROR: Run 'just stalwart-up' first"; exit 1; fi
    . /tmp/stalwart-env.sh && testament cat "integration/live"

# =============================================================================
# REFERENCE SOURCES (.nim-reference/, git-ignored, fetched on demand)
# =============================================================================

ref_dir := ".nim-reference"

# Fetch all reference sources
fetch-refs: fetch-nim-ref fetch-jmap-refs

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
clean-refs: clean-jmap-refs
    #!/usr/bin/env bash
    set -euo pipefail
    readonly dest="{{ref_dir}}"
    if [[ -d "${dest}" ]]; then
        rm -rf "${dest}"
        echo "Reference sources removed"
    else
        echo "Nothing to remove"
    fi

# Fetch or update JMAP client reference implementations for study
fetch-jmap-refs:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s inherit_errexit

    readonly dest="${HOME}/jmap-clients"
    mkdir -p "${dest}"

    declare -A repos=(
        [stalwartlabs-jmap-client]="https://github.com/stalwartlabs/jmap-client.git"
        [rockorager-go-jmap]="https://github.com/rockorager/go-jmap.git"
        [lachlanhunt-jmap-kit]="https://github.com/lachlanhunt/jmap-kit.git"
        [iNPUTmice-jmap]="https://codeberg.org/iNPUTmice/jmap.git"
        [linagora-jmap-dart-client]="https://github.com/linagora/jmap-dart-client.git"
        [htunnicliff-jmap-jam]="https://github.com/htunnicliff/jmap-jam.git"
        [meli-meli]="https://github.com/meli/meli.git"
        [bulwarkmail-webmail]="https://github.com/bulwarkmail/webmail.git"
        [smkent-jmapc]="https://github.com/smkent/jmapc.git"
        [fastmail-JMAP-Tester]="https://github.com/fastmail/JMAP-Tester.git"
    )

    for dirname in "${!repos[@]}"; do
        if [[ -d "${dest}/${dirname}/.git" ]]; then
            echo "  Updating ${dirname}..."
            if ! git -C "${dest}/${dirname}" pull --ff-only 2>/dev/null; then
                echo "    (pull failed — re-cloning)"
                rm -rf "${dest}/${dirname}"
                git clone --depth=1 -- "${repos[${dirname}]}" "${dest}/${dirname}"
            fi
        else
            echo "  Cloning ${dirname}..."
            rm -rf "${dest}/${dirname}"
            git clone --depth=1 -- "${repos[${dirname}]}" "${dest}/${dirname}"
        fi
    done

    echo "JMAP client references ready at ${dest}/"

# Remove fetched JMAP client references
clean-jmap-refs:
    #!/usr/bin/env bash
    set -euo pipefail
    readonly dest="${HOME}/jmap-clients"
    if [[ -d "${dest}" ]]; then
        rm -rf "${dest}"
        echo "JMAP client references removed"
    else
        echo "Nothing to remove"
    fi
