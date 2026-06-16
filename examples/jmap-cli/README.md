<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# jmap-cli — sample JMAP consumer (P29 ergonomics bench)

A deliberately thin CLI that drives the `jmap_client` **public API only**
to exercise every RFC 8621 entity area against a live JMAP server. Its
purpose is the audit in [`AUDIT.md`](AUDIT.md) and the critique in
[`docs/design/16-api-from-the-consumers-chair.md`](../../docs/design/16-api-from-the-consumers-chair.md),
not to be a usable mail client. It is the consumer mandated by principle
P29 and tracker item C1.

## Build

    nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap_cli.nim

The entry module is `jmap_cli.nim` (Nim module names cannot contain a
hyphen); the conventional run-name `jmap-cli` comes from `-o:`. The build
config (`nim.cfg`) pins the consumer contract: `--mm:arc --threads:on
--panics:on` and `--path` to `src/` and the vendored `nim-results`. It
deliberately does **not** enable the library's own warning-as-error
battery — and the sample compiles cleanly with or without it (a recorded
positive: the API leaks no strictness onto consumers).

> Built in-tree, the compiler still inherits the repo's `config.nims`
> (it walks up from the source dir), so the in-tree build runs under the
> library's full strict battery. To reproduce a *pristine* external
> consumer, copy the sources outside the repo and build with only the
> three flags above plus absolute `--path`s.

## Run against Stalwart

    just stalwart-up
    source /tmp/stalwart-env.sh
    /tmp/jmap-cli session
    /tmp/jmap-cli mailbox list
    /tmp/jmap-cli email query --unread
    /tmp/jmap-cli email read <emailId>
    /tmp/jmap-cli email flag <emailId>
    /tmp/jmap-cli email move <emailId> <mailboxId>
    /tmp/jmap-cli email send bob@example.com "hi" "body"
    /tmp/jmap-cli email sync                 # prints the current Email state
    /tmp/jmap-cli email sync <sinceState>    # incremental delta since that state
    /tmp/jmap-cli thread show <threadId>
    /tmp/jmap-cli identity list
    /tmp/jmap-cli vacation set "Away until Monday"
    /tmp/jmap-cli vacation get
    /tmp/jmap-cli search <text>
    /tmp/jmap-cli email query --one-shot          # the queryEmails one-shot path
    # run `jmap-cli` with no args for the full subcommand list

Connection is read from the environment (`source /tmp/stalwart-env.sh`
first): `JMAP_TEST_STALWART_SESSION_URL`, `_ALICE_USER`, `_ALICE_PASSWORD`.

## Public-surface guard

    examples/jmap-cli/check-public-only.sh

Fails if any module reaches past the public surface via `import`, `from`,
or `include` of `jmap_client/internal/*`. The CLI may import only
`jmap_client`, its own `./cli_session`, and `std/*`. (The former opt-in
`jmap_client/convenience` module no longer exists — its pipeline combinators
are now part of the always-on hub, reachable from the single `import
jmap_client`, so an import of it would simply fail to compile.) This is the
honesty mechanism for the bench (it mirrors what tracker H7 will later
mechanise in CI).

## Layout

| Path | Role |
|---|---|
| `jmap_cli.nim` | entry point; thin subcommand dispatch on argv |
| `commands/cli_session.nim` | shared connect+session+account helper (its existence is a finding) |
| `commands/*.nim` | one module per subcommand / entity area |
| `nim.cfg` | consumer build contract |
| `check-public-only.sh` | import-purity guard |
| `AUDIT.md` | the terse friction ledger (the deliverable) |

The narrative companion — what the API *feels* like, with the
per-area P7 verdict — lives in `docs/design/16-api-from-the-consumers-chair.md`.
