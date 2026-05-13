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
    @echo "Running test: {{ file }}"
    testament pat {{ file }}

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

# Run every test including slow ones from tests/testament_skip.txt and
# the live integration suite, sharded by server for parallelism. Each
# shard logs to testresults/test-full/<shard>.log; live output is
# prefixed [stalwart] / [james] / [cyrus] / [joinable] per line for
# attribution. Fail-fast: first failing shard SIGTERMs siblings.
# Requires at least one of Stalwart, James, or Cyrus to be up.
test-full:
    #!/usr/bin/env bash
    set -m
    set -uo pipefail
    if [ ! -f /tmp/stalwart-env.sh ] && [ ! -f /tmp/james-env.sh ] && [ ! -f /tmp/cyrus-env.sh ]; then
        echo "ERROR: at least one of /tmp/stalwart-env.sh, /tmp/james-env.sh, or /tmp/cyrus-env.sh required" >&2
        echo "       run 'just jmap-up' (or 'just stalwart-up' / 'just james-up' / 'just cyrus-up') first" >&2
        exit 1
    fi
    declare -A shard_pids=()
    declare -A shard_logs=()
    cleanup() {
        for pid in "${shard_pids[@]:-}"; do
            kill -TERM -- "-${pid}" 2>/dev/null || true
        done
        rm -rf tests/integration/live-stalwart tests/integration/live-james tests/integration/live-cyrus
        find tests/ -name 'megatest' -type f -delete
        find tests/ -name 'megatest.nim' -type f -delete
    }
    trap cleanup EXIT
    mkdir -p testresults/test-full
    rm -f testresults/test-full/*.log

    # Pre-clean stale build artefacts that would defeat testament. A
    # tests/<cat>/ directory containing zero .nim files trips
    # categories.nim:752's "Invalid category" assertion in 'all' mode --
    # this is the failure mode after a branch switch where one branch
    # added a test category the other never had, but the compiled
    # binary lingers as an untracked file. Skip testdata which holds
    # captured JSON fixtures and is whitelisted by testament itself.
    for d in tests/*/; do
        name=$(basename "$d")
        [ "$name" = "testdata" ] && continue
        if [ -z "$(find "$d" -name '*.nim' -type f -print -quit 2>/dev/null)" ]; then
            echo "test-full: pruning stale category dir with no .nim sources: $d"
            rm -rf "$d"
        fi
    done

    # Phase 1 — every test except live execution. Live tests are in the
    # megatest binary but their bodies short-circuit via
    # loadLiveTestTargets().isOk when no JMAP_TEST_* env vars are sourced.
    run_joinable_shard() {
        local name="joinable"
        local log="testresults/test-full/${name}.log"
        shard_logs[$name]="$log"
        (
            stdbuf -oL -eL testament --backendLogging:off --colors:off all 2>&1 \
                | awk -v prefix="[${name}] " '{ gsub(/\033\[[0-9;]*m/, ""); print prefix $0; fflush(); }' \
                | tee "${log}"
            exit "${PIPESTATUS[0]}"
        ) &
        shard_pids[$name]=$!
    }

    # Phase 2 — one shard per server. Each shard hardlinks every .nim in
    # tests/integration/live/ into tests/integration/live-<name>/ so the
    # three concurrent compiles write their per-test binary outputs to
    # disjoint paths (Nim emits the binary next to the source file;
    # without per-shard source dirs we get "Text file busy" races on
    # the shared output path).
    run_live_shard() {
        local name="$1" envfile="$2"
        local log="testresults/test-full/${name}.log"
        local shard_dir="tests/integration/live-${name}"
        shard_logs[$name]="$log"
        rm -rf "$shard_dir"
        mkdir -p "$shard_dir"
        cp -al tests/integration/live/*.nim "$shard_dir/"
        (
            . "${envfile}"
            stdbuf -oL -eL testament --backendLogging:off --colors:off \
                pat "${shard_dir}/*_live.nim" -- -d:jmapLiveShard 2>&1 \
                | awk -v prefix="[${name}] " '{ gsub(/\033\[[0-9;]*m/, ""); print prefix $0; fflush(); }' \
                | tee "${log}"
            exit "${PIPESTATUS[0]}"
        ) &
        shard_pids[$name]=$!
    }

    echo "=== test-full: spawning shards ==="
    run_joinable_shard

    if [ -f /tmp/stalwart-env.sh ]; then
        run_live_shard stalwart /tmp/stalwart-env.sh
    fi
    if [ -f /tmp/james-env.sh ]; then
        run_live_shard james /tmp/james-env.sh
    fi
    if [ -f /tmp/cyrus-env.sh ]; then
        run_live_shard cyrus /tmp/cyrus-env.sh
    fi

    failed_shards=()
    remaining=${#shard_pids[@]}
    while [ "$remaining" -gt 0 ]; do
        finished_pid=""
        rc=0
        wait -n -p finished_pid || rc=$?
        if [ -z "$finished_pid" ] || [ "$rc" -eq 127 ]; then
            break
        fi
        for name in "${!shard_pids[@]}"; do
            if [ "${shard_pids[$name]}" = "$finished_pid" ]; then
                unset 'shard_pids[$name]'
                if [ "$rc" -ne 0 ]; then
                    failed_shards+=("$name")
                fi
                break
            fi
        done
        remaining=$((remaining - 1))
        if [ "$rc" -ne 0 ]; then
            for nm in "${!shard_pids[@]}"; do
                kill -TERM -- "-${shard_pids[$nm]}" 2>/dev/null || true
            done
            wait 2>/dev/null || true
            break
        fi
    done

    echo ""
    echo "=== test-full: summary ==="
    if [ ${#failed_shards[@]} -eq 0 ]; then
        echo "All shards passed. Logs in testresults/test-full/."
        exit 0
    fi
    echo "FAILED: ${failed_shards[*]}"
    for name in "${failed_shards[@]}"; do
        echo ""
        echo "================== [${name}] FAILURE LOG ================="
        cat "${shard_logs[$name]}" 2>/dev/null || echo "(no log captured)"
        echo "============== [${name}] END FAILURE LOG ================="
    done
    exit 1

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

# Enforce the public/internal boundary (A1, P5). Fails CI on any
# `import jmap_client/internal/...` outside src/jmap_client/** or
# tests/**.
lint-internal-boundary:
    @echo "Running H10 internal-boundary lint..."
    nim r --hints:off --warnings:off tests/lint/th10_internal_boundary.nim
    @echo "H10 internal-boundary lint passed"

# Enforce the typed-builder JsonNode prohibition (A5, P19). Fails CI
# on any `add<Entity><Method>*` proc that acquires a JsonNode
# parameter outside the documented allowlist (addEcho,
# addCapabilityInvocation, addInvocation).
lint-typed-builder-jsonnode:
    @echo "Running H11 typed-builder JsonNode lint..."
    nim r --hints:off --warnings:off tests/lint/h11_typed_builder_no_jsonnode.nim
    @echo "H11 typed-builder JsonNode lint passed"

# Enforce the post-A8 invariant: zero public `distinct` types under
# src/. Sealed Pattern-A objects are the only permitted value-carrier
# shape (P15). Catches regression on the seal that binds external
# consumers.
lint-sealed-distinct:
    @echo "Running H1 sealed-distinct lint..."
    nim r --hints:off --warnings:off tests/lint/h1_sealed_distinct_construction.nim
    @echo "H1 sealed-distinct lint passed"

# Static analysis with nimalyzer
analyse:
    @echo "Running static analysis..."
    nimalyzer nimalyzer.cfg
    @echo "Static analysis passed"

# Alias for analyse (American English spelling)
analyze: analyse

# Run all code quality checks
check: fmt-check lint lint-isolated lint-style lint-internal-boundary lint-typed-builder-jsonnode lint-sealed-distinct analyse
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
ci: reuse fmt-check lint lint-isolated lint-style lint-internal-boundary lint-typed-builder-jsonnode lint-sealed-distinct analyse test
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
# JMAP TEST SERVERS (Stalwart 0.15.5, Apache James 3.9, Cyrus IMAP 3.12.2)
# =============================================================================
# --- Stalwart -----------------------------------------------------------------

# Start Stalwart JMAP server and seed test accounts
stalwart-up:
    docker compose -f .devcontainer/docker-compose.yml --profile stalwart up stalwart -d
    .devcontainer/scripts/seed-stalwart.sh

# Stop Stalwart JMAP server (leaves the dev container untouched)
stalwart-down:
    docker compose -f .devcontainer/docker-compose.yml rm -fs stalwart
    rm -f /tmp/stalwart-env.sh

# Tear down and recreate Stalwart with fresh data (leaves the dev container untouched)
stalwart-reset:
    docker compose -f .devcontainer/docker-compose.yml rm -fsv stalwart
    -docker volume rm jmap-client_jmc-stalwart-data
    just stalwart-up

# Show Stalwart container status
stalwart-status:
    docker compose -f .devcontainer/docker-compose.yml --profile stalwart ps

# Follow Stalwart container logs
stalwart-logs:
    docker compose -f .devcontainer/docker-compose.yml --profile stalwart logs -f stalwart

# --- Apache James -------------------------------------------------------------

# Start James JMAP server (memory image) and seed test accounts
james-up:
    .devcontainer/scripts/ensure-james-keystore.sh
    docker compose -f .devcontainer/docker-compose.yml --profile james build james
    docker compose -f .devcontainer/docker-compose.yml --profile james up james -d
    .devcontainer/scripts/seed-james.sh

# Stop James (memory image is ephemeral; data dies with the container).
# Anonymous volumes from the parent image survive ``rm -fs`` and would
# carry leftover state across re-creates — ``-v`` removes them too, so

# every ``james-up`` starts on a guaranteed-clean slate.
james-down:
    docker compose -f .devcontainer/docker-compose.yml rm -fsv james
    rm -f /tmp/james-env.sh

# Tear down and recreate James with fresh data
james-reset: james-down james-up

# Show James container status
james-status:
    docker compose -f .devcontainer/docker-compose.yml --profile james ps

# Follow James container logs
james-logs:
    docker compose -f .devcontainer/docker-compose.yml --profile james logs -f james

# --- Cyrus IMAP ---------------------------------------------------------------

# Start Cyrus JMAP server and seed test accounts
cyrus-up:
    docker compose -f .devcontainer/docker-compose.yml --profile cyrus up cyrus -d
    .devcontainer/scripts/seed-cyrus.sh

# Stop Cyrus JMAP server. Anonymous volumes from the parent image
# survive ``rm -fs`` and would carry leftover state across re-creates;

# ``-v`` removes them so every ``cyrus-up`` starts on a clean slate.
cyrus-down:
    docker compose -f .devcontainer/docker-compose.yml rm -fsv cyrus
    rm -f /tmp/cyrus-env.sh

# Tear down and recreate Cyrus with fresh data
cyrus-reset: cyrus-down cyrus-up

# Show Cyrus container status
cyrus-status:
    docker compose -f .devcontainer/docker-compose.yml --profile cyrus ps

# Follow Cyrus container logs
cyrus-logs:
    docker compose -f .devcontainer/docker-compose.yml --profile cyrus logs -f cyrus

# --- Universal compositions (configured targets) ------------------------------

# Start every configured JMAP target (Stalwart, James, Cyrus)
jmap-up: stalwart-up james-up cyrus-up

# Stop every configured JMAP target
jmap-down: stalwart-down james-down cyrus-down

# Tear down and recreate every configured target with fresh data
jmap-reset: jmap-down jmap-up

# Show status of every configured target
jmap-status:
    docker compose -f .devcontainer/docker-compose.yml --profile stalwart --profile james --profile cyrus ps

# Follow logs from every configured target
jmap-logs:
    docker compose -f .devcontainer/docker-compose.yml --profile stalwart --profile james --profile cyrus logs -f

# --- Test recipes -------------------------------------------------------------
# Run live integration tests against every configured JMAP target
# (Stalwart, James, Cyrus). Requires 'just jmap-up' (or per-server
# variants). Each test iterates ``forEachLiveTarget(target):`` so a
# single testament invocation exercises every configured target;
# failures attribute to a specific server via the ``[stalwart]`` /
# ``[james]`` / ``[cyrus]`` suffix that ``mlive.assertOn`` injects

# into every assertion message.
test-integration:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f /tmp/stalwart-env.sh ] && [ ! -f /tmp/james-env.sh ] && [ ! -f /tmp/cyrus-env.sh ]; then
        echo "ERROR: at least one of /tmp/stalwart-env.sh, /tmp/james-env.sh, or /tmp/cyrus-env.sh required" >&2
        echo "       run 'just jmap-up' (or 'just stalwart-up' / 'just james-up' / 'just cyrus-up') first" >&2
        exit 1
    fi
    if [ -f /tmp/stalwart-env.sh ]; then . /tmp/stalwart-env.sh; fi
    if [ -f /tmp/james-env.sh ]; then . /tmp/james-env.sh; fi
    if [ -f /tmp/cyrus-env.sh ]; then . /tmp/cyrus-env.sh; fi
    testament pat "tests/integration/live/*_live.nim"

# Capture wire-payload fixtures from every configured JMAP target into
# ``tests/testdata/captured/``. Each test's ``captureIfRequested(client,
# "<name>-" & $target.kind)`` call writes
# ``<name>-stalwart.json`` / ``<name>-james.json`` / ``<name>-cyrus.json``
# depending on which targets are configured. Existing fixtures are
# preserved (``mcapture.nim``'s skip-if-exists guard); set

# ``JMAP_TEST_CAPTURE_FORCE=1`` to overwrite after a deliberate change.
capture-fixtures:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f /tmp/stalwart-env.sh ] && [ ! -f /tmp/james-env.sh ] && [ ! -f /tmp/cyrus-env.sh ]; then
        echo "ERROR: at least one of /tmp/stalwart-env.sh, /tmp/james-env.sh, or /tmp/cyrus-env.sh required" >&2
        echo "       run 'just jmap-up' (or 'just stalwart-up' / 'just james-up' / 'just cyrus-up') first" >&2
        exit 1
    fi
    if [ -f /tmp/stalwart-env.sh ]; then . /tmp/stalwart-env.sh; fi
    if [ -f /tmp/james-env.sh ]; then . /tmp/james-env.sh; fi
    if [ -f /tmp/cyrus-env.sh ]; then . /tmp/cyrus-env.sh; fi
    JMAP_TEST_CAPTURE=1 testament pat "tests/integration/live/*_live.nim"
    @echo "Captures written to tests/testdata/captured/"
    @echo "Review with 'git status' and stage with 'git add' before committing."

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
    readonly dest="{{ ref_dir }}"
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
    readonly dest="{{ ref_dir }}"
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
