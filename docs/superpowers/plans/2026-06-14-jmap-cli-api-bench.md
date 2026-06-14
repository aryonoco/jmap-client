# jmap-cli API Ergonomics Bench — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full-entity sample CLI (`examples/jmap-cli/`) that drives the jmap_client **public API only** against a live Stalwart server, and use it to produce two documents — a terse `AUDIT.md` friction ledger (freeze-gate C1 format) and a narrative consumer-perspective critique (`docs/design/16-api-from-the-consumers-chair.md`).

**Architecture:** The CLI is an *instrument*, not a product; the two documents are the deliverable. This is **Phase 1 — observe and document only. No library or API source is touched.** Findings are *catalogued* (status `[open]`), never resolved here — triage into resolve/accept/file-as-`Cn` is a separate later pass. Commands are written and audited in app-developer-encounter order (connect → read → mutate → send → search), each command audited immediately after it round-trips while the friction is fresh.

**Tech Stack:** Nim ≥ 2.2.0; the in-tree `jmap_client` library resolved via `--path`; vendored `nim-results`; `std/os` for env + argv; live Stalwart via `just stalwart-up` (Docker). No new third-party dependencies.

---

## How this plan differs from a normal feature plan (read first)

This is a **discovery bench**, so two conventions differ from standard TDD plans:

1. **The "test" for every command is: (a) it compiles against the public API only, and (b) it round-trips live against Stalwart.** There are no unit tests for the CLI — the compile + live round-trip *is* the verification. The import-purity guard (`check-public-only.sh`) is the mechanical gate that it touched no `jmap_client/internal/*` path.

2. **Command code in the tasks below is a *starting hypothesis*, not gospel.** The exact ergonomics of some call sites (e.g. constructing an inline `BlueprintBodyPart`, whether the helper is `directIds` vs `direct`, whether `Opt.some`/`?` resolve without an explicit `import results`) are precisely what the bench is testing. Where the provided code does not compile or read awkwardly, **that divergence is a finding to record in `AUDIT.md` — not a bug in this plan.** Adjust the code to whatever the hub-public surface actually supports, and log the adjustment. If a command genuinely *cannot* be expressed with hub-public symbols, that is the highest-severity finding: record it and move on (do not reach into `internal/`).

**The audit discipline (apply at every command task):** after the command round-trips, append to `AUDIT.md` one bullet per awkwardness in the form
`- <command>:<call-site>: <description> [open]`
Expected categories: UFCS chains >3 levels; manual `.get()`/`valueOr` chains over an `Opt` of a `Result`; sealed-type construction ceremony (`initX(...).get()` then `parseY(...).get()`); `FieldEcho[T]` three-state reads; back-reference `reference[T](h, mn…, rp…)` enum-discovery friction; any `JsonNode` at a call site; any concept you had to learn before the simple thing worked. Then add a short paragraph to the critique doc for that API area while the reaction is live.

---

## Decisions locked during brainstorming

- **Scope:** full-entity coverage — every public entity exercised at least once, including the `EmailSubmission` send path.
- **Transport:** live against **Stalwart first** (James added only once the command set is stable; out of scope for this plan).
- **Docs:** `AUDIT.md` (mandatory C1 ledger) **plus** a companion narrative critique at `docs/design/16-api-from-the-consumers-chair.md`.
- **Posture:** observe-only; status column is `[open]` throughout (a conscious divergence from C1's resolve/accept/file wording — noted in `AUDIT.md`'s preamble).
- **Tracker linkage:** this plan executes tracker items **C1, C1.1** and pre-stages **F4**. It does **not** implement H7 (the import-purity CI lint) or F4 (the CI smoke test) — those are library/CI infra, deferred.

---

## Ground truth captured (do not re-derive)

**Live Stalwart connection** (from `.devcontainer/scripts/seed-stalwart.sh` + `tests/integration/live/mconfig.nim`):

- Bring up: `just stalwart-up` (Docker compose + seed). Tear down: `just stalwart-down`.
- Env file written to `/tmp/stalwart-env.sh`, exporting:
  - `JMAP_TEST_STALWART_SESSION_URL="http://stalwart:8080/jmap/session"`
  - `JMAP_TEST_STALWART_ALICE_USER="alice"` / `JMAP_TEST_STALWART_ALICE_PASSWORD="alice123"`
  - `JMAP_TEST_STALWART_BOB_USER="bob"` / `JMAP_TEST_STALWART_BOB_PASSWORD="bob123"`
- Auth is HTTP **Basic** (`basicCredential`), endpoint is a **direct** session URL (`directEndpoint`), over plain `http://` (so `-d:ssl` is *not* required for Stalwart).
- Two principals: `alice@example.com` and `bob@example.com`. The CLI sends alice→bob to exercise real delivery.

**Consumer build config** (from `config.nims` + `nimble.paths`):

- The library lives at `src/jmap_client.nim`; vendored `nim-results` at `vendor/nim-results/results.nim`.
- A consumer must compile with `--mm:arc --threads:on` (whole-program memory model must match the library) and `--panics:on` (matches the library's defect model). It must add both `--path:src` and `--path:vendor/nim-results`.
- A consumer must **not** need the library's `warningAsError`/`styleCheck` battery. (If the sample compiles cleanly *without* them, that is a positive finding — the API leaks no strictness onto consumers. Record it.)

**Corrected lifecycle (authoritative — the public path):**

```
client.newBuilder()            # -> RequestBuilder         (newBuilder is the ONLY blessed entry)
  .addEntityMethod(...)        # -> (RequestBuilder, ResponseHandle[T])   (thread the builder)
b.freeze()                     # -> BuiltRequest           (sink; uncopyable)
client.send(builtReq)          # -> JmapResult[DispatchedResponse]   (= Result[_, ClientError])
dr.get(handle)                 # -> Result[T, GetError]
```

`initRequestBuilder` / `initBuilderId` are **hub-private** (do not use them — `client.newBuilder()` mints the brand). `freeze` **is** hub-public (`builder.nim:168`). Convenience combinators (`add*QueryThenGet`, `add*ChangesToGet`, `getBoth` for those) require `import jmap_client/convenience` and are **not** re-exported by the root.

---

## File structure

```
examples/jmap-cli/
├── jmap_cli.nimble            # nimble project (bin = jmap-cli)
├── nim.cfg                    # consumer build config: paths + mm:arc/threads/panics
├── check-public-only.sh       # import-purity guard (grep for jmap_client/internal)
├── README.md                  # build + run-against-Stalwart instructions
├── AUDIT.md                   # terse C1-format friction ledger (the deliverable)
├── jmap-cli.nim               # entry point: subcommand dispatch on argv
└── commands/
    ├── cli_session.nim        # shared connect+session+account helper (its existence IS a finding)
    ├── session.nim            # `session`        — RAW first-15-minutes path (no helper)
    ├── mailbox.nim            # `mailbox list`   — Mailbox/get + MailboxRights summary
    ├── email_query.nim        # `email query`    — Email/query -> reference -> Email/get
    ├── email_read.nim         # `email read`     — Email/get full record + text body
    ├── email_flag.nim         # `email flag`     — Email/set keywords ($seen)
    ├── email_move.nim         # `email move`     — Email/set mailboxIds (moveToMailbox)
    ├── email_send.nim         # `email send`     — EmailSubmission + on-success Email/set (HARD)
    ├── thread.nim             # `thread show`    — Thread/get
    ├── identity.nim           # `identity list`  — Identity/get
    ├── vacation.nim           # `vacation`       — VacationResponse get/set (NoCreate rail)
    └── search.nim             # `search`         — Email/query + SearchSnippet/get (back-ref)

docs/design/16-api-from-the-consumers-chair.md   # narrative consumer-perspective critique
```

The companion critique doc is created in Phase 0 (skeleton) and filled section-by-section as each command is audited.

---

## Execution branch

Do **not** execute on `main`. Create a feature branch first:

```bash
git checkout -b examples/jmap-cli-bench
```

All commit messages follow the project's Linux-kernel format (subject `examples/jmap-cli: …` ≤ 75 chars, imperative; body wrapped ~75) and **must** end with this trailer block (per `CLAUDE.md`):

```
Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
```

Every commit step below abbreviates this as `<TRAILERS>`. Paste the full block.

---

# Phase 0 — Scaffolding & build smoke

## Task 1: Create the project skeleton and prove `import jmap_client` compiles

**Files:**
- Create: `examples/jmap-cli/jmap_cli.nimble`
- Create: `examples/jmap-cli/nim.cfg`
- Create: `examples/jmap-cli/check-public-only.sh`
- Create: `examples/jmap-cli/jmap-cli.nim` (temporary smoke body, replaced in Task 3)

- [ ] **Step 1: Write the nimble project file**

`examples/jmap-cli/jmap_cli.nimble`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

version     = "0.1.0"
author      = "Aryan Ameri"
description = "Sample consumer CLI exercising the jmap_client public API (P29 bench)"
license     = "BSD-2-Clause"
srcDir      = "."
bin         = @["jmap-cli"]

requires "nim >= 2.2.0"
# jmap_client is resolved in-tree via nim.cfg --path (no published package yet).
```

- [ ] **Step 2: Write the consumer build config**

`examples/jmap-cli/nim.cfg` (paths are relative to this file):

```
--path:"../../src"
--path:"../../vendor/nim-results"
--mm:arc
--threads:on
--panics:on
```

Deliberately omit the library's `warningAsError`/`styleCheck` switches. Whether the sample still compiles cleanly is itself a finding (record in Task 17).

- [ ] **Step 3: Write the import-purity guard**

`examples/jmap-cli/check-public-only.sh`:

```bash
#!/usr/bin/env bash
# Fails if the sample reaches past the public surface into jmap_client/internal.
# This is the honesty mechanism for the P29 bench (mirrors tracker H7).
set -euo pipefail
cd "$(dirname "$0")"
if grep -rnE 'import[[:space:]]+[^#]*jmap_client/internal' --include='*.nim' .; then
  echo "FAIL: examples/jmap-cli imports jmap_client/internal (public surface only)" >&2
  exit 1
fi
echo "OK: jmap-cli imports only the public surface"
```

Then: `chmod +x examples/jmap-cli/check-public-only.sh`

- [ ] **Step 4: Write a temporary smoke entry point**

`examples/jmap-cli/jmap-cli.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

import jmap_client

when isMainModule:
  # Smoke: confirm the public surface imports and a smart constructor resolves.
  let ep = directEndpoint("http://stalwart:8080/jmap/session")
  if ep.isOk:
    echo "jmap-cli smoke: public API import OK"
  else:
    echo "jmap-cli smoke: endpoint rejected: ", ep.error.message
```

- [ ] **Step 5: Build the smoke binary**

Run: `nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim`
Expected: compiles to `/tmp/jmap-cli` with no errors.

If `directEndpoint`, `Opt`, or `.isOk`/`.error.message` do not resolve, this is the first finding: the root hub may not re-export the `results` Result vocabulary. Add `import results` to the smoke body, rebuild, and record `- session:imports: root import does not re-export Result/Opt vocabulary; consumer needs explicit 'import results' [open]` in `AUDIT.md` (created in Task 2). If `ValidationError.message`/`.error` shape differs, adjust to the actual accessor and note it.

- [ ] **Step 6: Run the import-purity guard**

Run: `examples/jmap-cli/check-public-only.sh`
Expected: `OK: jmap-cli imports only the public surface`

- [ ] **Step 7: Run the smoke binary**

Run: `/tmp/jmap-cli`
Expected: `jmap-cli smoke: public API import OK`

- [ ] **Step 8: Commit**

```bash
git add examples/jmap-cli/
git commit -m "examples/jmap-cli: scaffold sample consumer + build smoke

Stand up the P29 ergonomics bench: a sample CLI that links the
jmap_client public surface only. nim.cfg pins the consumer build
contract (mm:arc, threads, panics, src + vendored results on the
path) without the library's own warning-as-error battery, so the
sample exercises the API as an external developer would. A grep
guard (check-public-only.sh) enforces the no-internal-import rule
that tracker H7 will later mechanise.

<TRAILERS>"
```

## Task 2: Create the AUDIT.md ledger with its discipline preamble

**Files:**
- Create: `examples/jmap-cli/AUDIT.md`

- [ ] **Step 1: Write the ledger skeleton**

`examples/jmap-cli/AUDIT.md`:

```markdown
# jmap-cli API ergonomics audit (P29 / tracker C1)

This ledger is the deliverable of the sample-consumer bench. The CLI is
the instrument; this file is the product. Each line records one
awkwardness encountered while writing the CLI against the **public
API only** (`import jmap_client` [+ `jmap_client/convenience`]).

**Status convention (Phase 1, observe-only).** Every finding is logged
`[open]`. This is a deliberate divergence from tracker C1's
`[resolved | accepted | filed-as-Cn]` wording: this pass *catalogues*
friction without resolving it, so the API is felt as a newcomer would
feel it. Triage into resolve/accept/file is a separate later pass.

**Format.** `- <command>:<call-site>: <description> [open]`

**Expected categories.** UFCS chain >3 levels; `.get()`/`valueOr` chain
over an `Opt` of a `Result`; sealed-type construction ceremony; three-
state `FieldEcho[T]` reads; back-reference enum discovery
(`reference[T](h, mn…, rp…)`); raw `JsonNode` at a call site; concept
that must be learned before the simple thing works; a command that
cannot be expressed with hub-public symbols at all (highest severity).

## Positive findings (what is genuinely good)

<!-- record elegant call sites here as they are encountered -->

## Findings by command

### session
### mailbox
### email query
### email read
### email flag
### email move
### email send
### thread
### identity
### vacation
### search
### convenience

## Cross-cutting findings

<!-- friction that recurs across commands; promoted in Task 16 -->
```

- [ ] **Step 2: Commit**

```bash
git add examples/jmap-cli/AUDIT.md
git commit -m "examples/jmap-cli: add AUDIT ledger with observe-only preamble

<TRAILERS>"
```

## Task 3: Wire the subcommand dispatcher and the critique-doc skeleton

**Files:**
- Modify: `examples/jmap-cli/jmap-cli.nim` (replace smoke body)
- Create: `docs/design/16-api-from-the-consumers-chair.md`

- [ ] **Step 1: Replace the entry point with a thin subcommand dispatcher**

`examples/jmap-cli/jmap-cli.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## jmap-cli — a deliberately thin sample consumer of the jmap_client
## public API. Each subcommand lives in commands/ and exercises one
## RFC 8621 entity area. The CLI is an instrument for the P29 audit,
## not a polished product: argument handling is minimal on purpose.

import std/os

import commands/session as sessionCmd
import commands/mailbox as mailboxCmd
import commands/email_query as emailQueryCmd
import commands/email_read as emailReadCmd
import commands/email_flag as emailFlagCmd
import commands/email_move as emailMoveCmd
import commands/email_send as emailSendCmd
import commands/thread as threadCmd
import commands/identity as identityCmd
import commands/vacation as vacationCmd
import commands/search as searchCmd

proc usage() =
  stderr.writeLine """jmap-cli — sample JMAP consumer (P29 bench)
usage:
  jmap-cli session
  jmap-cli mailbox list
  jmap-cli email query [--unread]
  jmap-cli email read <emailId>
  jmap-cli email flag <emailId>
  jmap-cli email move <emailId> <mailboxId>
  jmap-cli email send <toAddress> <subject> <bodyText>
  jmap-cli thread show <threadId>
  jmap-cli identity list
  jmap-cli vacation get
  jmap-cli vacation set <bodyText>
  jmap-cli search <text>

Connection is read from env (source /tmp/stalwart-env.sh first):
  JMAP_TEST_STALWART_SESSION_URL, _ALICE_USER, _ALICE_PASSWORD"""

when isMainModule:
  let args = commandLineParams()
  if args.len == 0:
    usage()
    quit(2)
  # Dispatch returns an int exit code; commands print their own errors.
  let code =
    case args[0]
    of "session": sessionCmd.run(args[1 .. ^1])
    of "mailbox": mailboxCmd.run(args[1 .. ^1])
    of "email":
      if args.len >= 2 and args[1] == "query": emailQueryCmd.run(args[2 .. ^1])
      elif args.len >= 2 and args[1] == "read": emailReadCmd.run(args[2 .. ^1])
      elif args.len >= 2 and args[1] == "flag": emailFlagCmd.run(args[2 .. ^1])
      elif args.len >= 2 and args[1] == "move": emailMoveCmd.run(args[2 .. ^1])
      elif args.len >= 2 and args[1] == "send": emailSendCmd.run(args[2 .. ^1])
      else: (usage(); 2)
    of "thread": threadCmd.run(args[1 .. ^1])
    of "identity": identityCmd.run(args[1 .. ^1])
    of "vacation": vacationCmd.run(args[1 .. ^1])
    of "search": searchCmd.run(args[1 .. ^1])
    else: (usage(); 2)
  quit(code)
```

Note: this references command modules created in later tasks. It will not compile until at least the modules it imports exist. To keep the build green per task, **comment out the imports and case arms for not-yet-created commands**, uncommenting each as its task lands. (Record any friction this staging causes — it is incidental to the bench, not an API finding.)

- [ ] **Step 2: Write the critique-doc skeleton**

`docs/design/16-api-from-the-consumers-chair.md`:

```markdown
<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# 16. The API from the consumer's chair

A narrative companion to `14-Nim-API-Principles.md`, written from the
seat of an application developer building an email client against the
jmap_client public API via the `examples/jmap-cli/` bench (tracker
C1 / P29). Where `AUDIT.md` is the terse ledger of individual
awkwardnesses, this document records the *feel*: what is elegant, what
grates, what surprised, and the verdict on the make-or-break
first-fifteen-minutes path. Findings cross-reference principles
P1–P29 by number.

## The first fifteen minutes
<!-- filled in Task 4 -->

## Reading: mailboxes, queries, messages, threads, identities
<!-- filled in Tasks 5–9 -->

## Mutating: flags, moves, vacation
<!-- filled in Tasks 10–12 -->

## Sending: the EmailSubmission path
<!-- filled in Task 13 -->

## Search and the convenience layer
<!-- filled in Tasks 14–15 -->

## Cross-cutting verdict
<!-- filled in Task 17: would a competent developer reach for this
     directly, or wrap it? (P7) -->
```

- [ ] **Step 3: Commit**

```bash
git add examples/jmap-cli/jmap-cli.nim docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: add subcommand dispatcher + critique skeleton

<TRAILERS>"
```

---

# Phase 1 — Connect & session (the first fifteen minutes)

## Task 4: `session` command — the RAW first-run path, then extract the helper

This command is written **without** the `cli_session` helper on purpose: it documents the unhidden first-run experience. After auditing it, extract the repeated boilerplate into `cli_session.nim` for commands 5+ — the *existence* of that helper is a recorded finding (confirms the C5/C8 capability/connect wrapper triggers).

**Files:**
- Create: `examples/jmap-cli/commands/session.nim`
- Create: `examples/jmap-cli/commands/cli_session.nim`

- [ ] **Step 1: Write the raw session command**

`examples/jmap-cli/commands/session.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli session` — the unhidden first-run path: env -> credential
## -> endpoint -> client -> fetchSession -> capability check -> account.
## Written verbosely on purpose to document the first-fifteen-minutes
## experience (P29). Friction here goes straight to AUDIT.md.

import std/os
import jmap_client

proc run*(args: seq[string]): int =
  # 1. Read connection params (no config-file loader exists in the API).
  let sessionUrl = getEnv("JMAP_TEST_STALWART_SESSION_URL")
  let user = getEnv("JMAP_TEST_STALWART_ALICE_USER")
  let pass = getEnv("JMAP_TEST_STALWART_ALICE_PASSWORD")
  if sessionUrl.len == 0 or user.len == 0 or pass.len == 0:
    stderr.writeLine "missing env; source /tmp/stalwart-env.sh first"
    return 2

  # 2. Smart constructors (each fallible, each needs unwrapping).
  let endpoint = directEndpoint(sessionUrl).valueOr:
    stderr.writeLine "bad endpoint: " & error.message
    return 1
  let credential = basicCredential(user, pass).valueOr:
    stderr.writeLine "bad credential: " & error.message
    return 1

  # 3. Construct the client (convenience overload uses default HTTP transport).
  let client = initJmapClient(endpoint, credential).valueOr:
    stderr.writeLine "client init failed: " & error.message
    return 1

  # 4. Fetch the session (the first network call; ClientError on the rail).
  let session = client.fetchSession().valueOr:
    stderr.writeLine "fetchSession failed: " & error.message
    return 1

  echo "connected as: " & session.username
  echo "api url:      " & session.apiUrl

  # 5. Capability pre-flight + primary mail account in one shot.
  let mailAccount = session.primaryAccount(ckMail).valueOr:
    stderr.writeLine "server does not advertise JMAP Mail"
    return 1
  echo "mail account: " & $mailAccount

  # 6. Surface a few core limits (typed accessors).
  let core = session.coreCapabilities()
  echo "maxCallsInRequest: " & $core.maxCallsInRequest()
  echo "maxObjectsInGet:   " & $core.maxObjectsInGet()
  return 0
```

- [ ] **Step 2: Build**

Run: `nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim` (with only the `session` import/arm enabled)
Expected: compiles clean. If `session.username`/`apiUrl`/`primaryAccount(ckMail)`/`coreCapabilities()` differ from the mapped signatures, adjust and record.

- [ ] **Step 3: Run live against Stalwart**

```bash
just stalwart-up           # if not already up
source /tmp/stalwart-env.sh
/tmp/jmap-cli session
```
Expected: prints `connected as: …`, an api url, a mail account id, and two core limits. (Stalwart's `username` may be empty — note if so.)

- [ ] **Step 4: Record findings**

Append to `AUDIT.md` under `### session` (examples — log what you actually hit):
```
- session:connect: 4 fallible smart constructors (endpoint, credential, client, fetchSession) each need a valueOr block before the first useful call [open]
- session:capability: no client.requireMail()/supportsMail() one-liner; pre-flight goes through session.primaryAccount(ckMail) (confirms tracker C5/C8) [open]
- session:config: no config-file/loader in the API; consumer hand-reads 3 env vars [open]
```
Append to `docs/design/16-…md` `## The first fifteen minutes`: a paragraph on how many concepts a newcomer meets before `session` works (Result rail, `valueOr`, `Opt`, `SessionEndpoint`, `Credential`, `CapabilityKind`), whether the lifecycle is discoverable, and the verdict.

- [ ] **Step 5: Extract the shared connect helper**

`examples/jmap-cli/commands/cli_session.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared connect+session+account boilerplate for commands 5+. Its very
## existence is an AUDIT finding: every command needs this 4-call
## preamble, which is the C5/C8 "capability/connect wrapper trigger"
## made concrete. session.nim deliberately does NOT use it (it documents
## the raw path).

import std/os
import jmap_client

type CliContext* = object
  client*: JmapClient
  mailAccount*: AccountId

proc connect*(): Result[CliContext, string] =
  let sessionUrl = getEnv("JMAP_TEST_STALWART_SESSION_URL")
  let user = getEnv("JMAP_TEST_STALWART_ALICE_USER")
  let pass = getEnv("JMAP_TEST_STALWART_ALICE_PASSWORD")
  if sessionUrl.len == 0 or user.len == 0 or pass.len == 0:
    return err("missing env; source /tmp/stalwart-env.sh first")
  let endpoint = directEndpoint(sessionUrl).valueOr:
    return err("bad endpoint: " & error.message)
  let credential = basicCredential(user, pass).valueOr:
    return err("bad credential: " & error.message)
  let client = initJmapClient(endpoint, credential).valueOr:
    return err("client init failed: " & error.message)
  let session = client.fetchSession().valueOr:
    return err("fetchSession failed: " & error.message)
  let mailAccount = session.primaryAccount(ckMail).valueOr:
    return err("server does not advertise JMAP Mail")
  ok(CliContext(client: client, mailAccount: mailAccount))
```

Run: `nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim` — expected clean. Append to `AUDIT.md` under `## Cross-cutting findings`:
```
- *all commands*: required a 4-call connect+session+account preamble; extracted to cli_session.connect(); confirms C5/C8 connect-helper wrapper trigger [open]
```

- [ ] **Step 6: Commit**

```bash
git add examples/jmap-cli/commands/session.nim examples/jmap-cli/commands/cli_session.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement session command + connect helper

<TRAILERS>"
```

---

# Phase 2 — Read surfaces

> **Per-command rhythm for Tasks 5–9 (and all later command tasks):**
> 1. write the command module; 2. enable its import + dispatch arm in `jmap-cli.nim`;
> 3. `nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim`;
> 4. `examples/jmap-cli/check-public-only.sh`;
> 5. `source /tmp/stalwart-env.sh && /tmp/jmap-cli <subcommand …>`;
> 6. append `AUDIT.md` bullets + a critique paragraph; 7. commit.

## Task 5: `mailbox list` — Mailbox/get + rights summary

**Files:**
- Create: `examples/jmap-cli/commands/mailbox.nim`

- [ ] **Step 1: Write the command**

`examples/jmap-cli/commands/mailbox.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli mailbox list` — fetch all mailboxes (Mailbox/get with no
## id filter) and print name, unread count, and a hand-rolled rights
## summary (MailboxRights has no roll-up helpers yet — tracker C4).

import jmap_client
import ./cli_session

proc rightsSummary(r: MailboxRights): string =
  # No canRead/canMutate/canDelete roll-ups exist (C4); chain the flags.
  var parts: seq[string] = @[]
  if r.mayReadItems: parts.add "read"
  if r.mayAddItems or r.mayRemoveItems or r.mayRename or r.mayCreateChild:
    parts.add "mutate"
  if r.mayDelete: parts.add "delete"
  if parts.len == 0: "none" else: parts.join(",")

proc run*(args: seq[string]): int =
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  let (b, handle) = ctx.client.newBuilder().addMailboxGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let resp = dr.get(handle).valueOr:
    stderr.writeLine "Mailbox/get failed: " & error.message
    return 1
  for m in resp.list:
    echo m.name & "  [" & $m.id & "]  unread=" & $m.unreadEmails &
      "  total=" & $m.totalEmails & "  rights=" & rightsSummary(m.myRights)
  return 0
```

Note: `join` comes from `std/strutils` — add `import std/strutils` if the build complains. `$m.unreadEmails` relies on `UnsignedInt`'s `$`; if it fails, use the `toInt`/`toInt64` projection and record the friction.

- [ ] **Step 2: Build, guard, run**

```bash
nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim
examples/jmap-cli/check-public-only.sh
source /tmp/stalwart-env.sh && /tmp/jmap-cli mailbox list
```
Expected: one line per mailbox (Inbox, Sent, Drafts, etc.) with counts and a rights summary.

- [ ] **Step 3: Record findings + commit**

`AUDIT.md` under `### mailbox` (e.g. the C4 roll-up gap, the `$UnsignedInt` print path). Critique paragraph under `## Reading…`. Then:
```bash
git add examples/jmap-cli/commands/mailbox.nim examples/jmap-cli/jmap-cli.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement mailbox list command

<TRAILERS>"
```

## Task 6: `email query` — Email/query → back-reference → Email/get

**Files:**
- Create: `examples/jmap-cli/commands/email_query.nim`

- [ ] **Step 1: Write the command**

`examples/jmap-cli/commands/email_query.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email query [--unread]` — query Inbox (optionally unread
## only), sorted newest-first, then back-reference the matching ids
## into Email/get for subject/from/preview. Resolves Inbox by fetching
## mailboxes and matching role == inbox.

import jmap_client
import ./cli_session

proc resolveInbox(ctx: CliContext): Result[Id, string] =
  let (b, h) = ctx.client.newBuilder().addMailboxGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    return err("send failed: " & error.message)
  let resp = dr.get(h).valueOr:
    return err("Mailbox/get failed: " & error.message)
  for m in resp.list:
    for role in m.role:                      # Opt iteration
      if role == roleInbox:
        return ok(m.id)
  err("no Inbox mailbox found")

proc run*(args: seq[string]): int =
  let unreadOnly = "--unread" in args
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  let inboxId = resolveInbox(ctx).valueOr:
    stderr.writeLine error
    return 1

  # Build the filter: in Inbox, optionally lacking $seen.
  var cond = EmailFilterCondition(inMailbox: Opt.some(inboxId))
  if unreadOnly:
    cond.notKeyword = Opt.some(kwSeen)
  let filter = filterCondition(cond)
  let sort = @[plainComparator(pspReceivedAt, sdDescending)]

  var builder = ctx.client.newBuilder()
  let (b1, queryH) = builder.addEmailQuery(
    ctx.mailAccount,
    filter = Opt.some(filter),
    sort = Opt.some(sort),
    queryParams = QueryParams(limit: Opt.some(parseUnsignedInt(20).get())),
  )
  # Back-reference query result ids into Email/get (no second round-trip).
  let (b2, getH) = b1.addPartialEmailGet(
    ctx.mailAccount,
    ids = Opt.some(reference[seq[Id]](queryH, mnEmailQuery, rpIds)),
    properties = parseNonEmptySeq(@[egpId, egpFrom, egpSubject, egpReceivedAt, egpPreview]).get(),
  )
  let dr = ctx.client.send(b2.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let getResp = dr.get(getH).valueOr:
    stderr.writeLine "Email/get failed: " & error.message
    return 1

  for e in getResp.list:                      # e is PartialEmail
    let subj = e.subject.valueOr: "(no subject)"
    var from = "(unknown)"
    for addrs in e.fromAddr:                   # Opt[seq[EmailAddress]]
      if addrs.len > 0: from = addrs[0].email
    let id = e.id.valueOr: parseIdFromServer("?").get()
    echo $id & "  " & from & "  " & subj
  return 0
```

VERIFY points (record any divergence): the back-reference enum names (`mnEmailQuery`, `rpIds`); whether `PartialEmail.subject` is `Opt[string]` (mapped) or `FieldEcho[string]` (the slice-5 explorer hedged) — if `FieldEcho`, the read needs a three-state accessor and that is a notable finding; whether `parseNonEmptySeq` / `egp*` constants are hub-public.

- [ ] **Step 2: Build, guard, run**

```bash
nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim
examples/jmap-cli/check-public-only.sh
source /tmp/stalwart-env.sh && /tmp/jmap-cli email query --unread
```
Expected: lines of `id  from  subject`. (Empty inbox is fine — the seed delivers alice→bob, so query as bob, or send first via Task 13 and re-run. Note in AUDIT if the inbox is empty for alice.)

- [ ] **Step 3: Record findings + commit**

`AUDIT.md` under `### email query` (back-reference enum discovery, `FieldEcho` vs `Opt`, the resolve-inbox detour). Critique paragraph. Commit:
```bash
git add examples/jmap-cli/commands/email_query.nim examples/jmap-cli/jmap-cli.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement email query command

<TRAILERS>"
```

## Task 7: `email read` — full Email/get with decoded text body

**Files:**
- Create: `examples/jmap-cli/commands/email_read.nim`

- [ ] **Step 1: Write the command**

`examples/jmap-cli/commands/email_read.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email read <emailId>` — full-record Email/get with body
## values fetched, then print headers and the decoded text body.

import jmap_client
import ./cli_session

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli email read <emailId>"
    return 2
  let emailId = parseIdFromServer(args[0]).valueOr:
    stderr.writeLine "bad email id: " & error.message
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1

  let (b, handle) = ctx.client.newBuilder().addEmailGet(
    ctx.mailAccount,
    ids = Opt.some(directIds(@[emailId])),
    bodyFetchOptions = EmailBodyFetchOptions(
      fetchBodyValues: bvsText,
      maxBodyValueBytes: Opt.some(parseUnsignedInt(65536).get()),
    ),
  )
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let resp = dr.get(handle).valueOr:
    stderr.writeLine "Email/get failed: " & error.message
    return 1
  if resp.list.len == 0:
    stderr.writeLine "email not found"
    return 1
  let e = resp.list[0]                          # full Email
  echo "Subject: " & e.subject.valueOr("(none)")
  for addrs in e.fromAddr:
    if addrs.len > 0: echo "From: " & addrs[0].email
  echo "Preview: " & e.preview
  echo "----"
  # textBody lists the leaf parts; look each up in bodyValues by partId.
  for part in e.textBody:
    case part.isMultipart
    of false:
      e.bodyValues.withValue(part.partId, bv):
        echo bv[].value
    of true: discard
  return 0
```

VERIFY: `directIds(@[id])` vs `direct(@[id])` — confirm the hub-public direct-reference helper and its return type; `bvsText` enum name on `BodyValueScope`; that `EmailBodyPart.partId` is reachable on the `isMultipart == false` arm (strict case-object rules); `bodyValues.withValue` (Table accessor) vs `[]`.

- [ ] **Step 2: Build, guard, run**

```bash
nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim
examples/jmap-cli/check-public-only.sh
# get an id from `email query` first:
source /tmp/stalwart-env.sh && /tmp/jmap-cli email read <emailId>
```
Expected: subject, from, preview, decoded text body.

- [ ] **Step 3: Record findings + commit**

`AUDIT.md` under `### email read` (the `EmailBodyPart` case-object navigation to reach a leaf, the bodyValues table lookup ceremony, `directIds` shape). Critique paragraph. Commit:
```bash
git add examples/jmap-cli/commands/email_read.nim examples/jmap-cli/jmap-cli.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement email read command

<TRAILERS>"
```

## Task 8: `thread show` — Thread/get

**Files:**
- Create: `examples/jmap-cli/commands/thread.nim`

- [ ] **Step 1: Write the command**

`examples/jmap-cli/commands/thread.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli thread show <threadId>` — Thread/get; print the thread's
## email ids (the Thread read-model exposes id/emailIds accessors).

import jmap_client
import ./cli_session

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli thread show <threadId>"
    return 2
  let threadId = parseIdFromServer(args[0]).valueOr:
    stderr.writeLine "bad thread id: " & error.message
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  let (b, handle) = ctx.client.newBuilder().addThreadGet(
    ctx.mailAccount, ids = Opt.some(directIds(@[threadId])))
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let resp = dr.get(handle).valueOr:
    stderr.writeLine "Thread/get failed: " & error.message
    return 1
  if resp.list.len == 0:
    stderr.writeLine "thread not found"
    return 1
  let t = resp.list[0]
  echo "thread " & $t.id & " has " & $t.emailIds.len & " emails:"
  for eid in t.emailIds:
    echo "  " & $eid
  return 0
```

VERIFY: the dispatch shows two subcommand words (`thread show`); the entry-point arm currently passes `args[1..]` to `thread.run`, so `thread.run` receives `["show", "<id>"]`. Either strip the `show` token in `thread.nim` (`args[1..]`) or adjust the dispatcher. Record nothing API-related for this — it is CLI plumbing.

- [ ] **Step 2: Build, guard, run** (`/tmp/jmap-cli thread show <threadId>` — get a threadId from `email read`/`email query` by also fetching `egpThreadId`). Expected: the email ids in the thread.

- [ ] **Step 3: Record findings + commit**

`AUDIT.md` under a `### thread` heading (add it), critique paragraph, commit:
```bash
git add examples/jmap-cli/commands/thread.nim examples/jmap-cli/jmap-cli.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement thread show command

<TRAILERS>"
```

## Task 9: `identity list` — Identity/get

**Files:**
- Create: `examples/jmap-cli/commands/identity.nim`

- [ ] **Step 1: Write the command**

`examples/jmap-cli/commands/identity.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli identity list` — Identity/get; print each identity's
## display name and address (needed later to pick a From for sending).

import jmap_client
import ./cli_session

proc run*(args: seq[string]): int =
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  let (b, handle) = ctx.client.newBuilder().addIdentityGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let resp = dr.get(handle).valueOr:
    stderr.writeLine "Identity/get failed: " & error.message
    return 1
  for i in resp.list:
    echo $i.id & "  " & i.name & " <" & i.email & ">"
  return 0
```

- [ ] **Step 2: Build, guard, run** (`/tmp/jmap-cli identity list`). Expected: at least alice's identity with id, name, address. The `email send` task needs one of these ids.

- [ ] **Step 3: Record findings + commit** (`AUDIT.md` `### identity`, critique paragraph):
```bash
git add examples/jmap-cli/commands/identity.nim examples/jmap-cli/jmap-cli.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement identity list command

<TRAILERS>"
```

---

# Phase 3 — Write surfaces

## Task 10: `email flag` — Email/set keywords ($seen)

**Files:**
- Create: `examples/jmap-cli/commands/email_flag.nim`

- [ ] **Step 1: Write the command**

`examples/jmap-cli/commands/email_flag.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email flag <emailId>` — mark an email $seen via Email/set.
## Shows the EmailUpdate DSL -> EmailUpdateSet -> NonEmptyEmailUpdates
## sealing chain and the Table[Id, Result[Opt[PartialEmail], SetError]]
## update-result read-back.

import jmap_client
import ./cli_session

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli email flag <emailId>"
    return 2
  let emailId = parseIdFromServer(args[0]).valueOr:
    stderr.writeLine "bad email id: " & error.message
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1

  # DSL -> per-email update set -> keyed batch (each step fallible).
  let updateSet = initEmailUpdateSet(@[markRead()]).valueOr:
    stderr.writeLine "invalid update set"
    return 1
  let updates = parseNonEmptyEmailUpdates(@[(emailId, updateSet)]).valueOr:
    stderr.writeLine "invalid update batch"
    return 1

  let (b, handle) = ctx.client.newBuilder().addEmailSet(
    ctx.mailAccount, update = Opt.some(updates))
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let setResp = dr.get(handle).valueOr:
    stderr.writeLine "Email/set failed: " & error.message
    return 1

  # Read the per-item rail: ok(Opt[PartialEmail]) vs err(SetError).
  for id, res in setResp.updateResults:
    if res.isOk:
      echo "flagged " & $id & " $seen"
    else:
      stderr.writeLine "flag failed for " & $id & ": " & res.error.message
  return 0
```

VERIFY: `markRead()` returns an `EmailUpdate` (mapped); the smart constructors return `Result[_, seq[ValidationError]]` so `.valueOr:` binds `error` to a `seq` — adjust the message rendering accordingly (a finding: accumulating-error rail at a single-update call site); `res.error.message` read of a `SetError` (guard with `isOk` to stay strict-safe).

- [ ] **Step 2: Build, guard, run** (`/tmp/jmap-cli email flag <emailId>`). Expected: `flagged <id> $seen`. Re-run `email query --unread` to confirm it dropped off the unread list.

- [ ] **Step 3: Record findings + commit** (`AUDIT.md` `### email flag`: the triple-sealing chain, the `seq[ValidationError]` rail on a single update, the nested `Table[Id, Result[Opt[U], SetError]]` read). Commit:
```bash
git add examples/jmap-cli/commands/email_flag.nim examples/jmap-cli/jmap-cli.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement email flag command

<TRAILERS>"
```

## Task 11: `email move` — Email/set mailboxIds

**Files:**
- Create: `examples/jmap-cli/commands/email_move.nim`

- [ ] **Step 1: Write the command**

`examples/jmap-cli/commands/email_move.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email move <emailId> <mailboxId>` — replace an email's
## mailbox membership via the moveToMailbox convenience EmailUpdate.

import jmap_client
import ./cli_session

proc run*(args: seq[string]): int =
  if args.len < 2:
    stderr.writeLine "usage: jmap-cli email move <emailId> <mailboxId>"
    return 2
  let emailId = parseIdFromServer(args[0]).valueOr:
    stderr.writeLine "bad email id: " & error.message
    return 2
  let mailboxId = parseIdFromServer(args[1]).valueOr:
    stderr.writeLine "bad mailbox id: " & error.message
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1

  let updateSet = initEmailUpdateSet(@[moveToMailbox(mailboxId)]).valueOr:
    stderr.writeLine "invalid update set"
    return 1
  let updates = parseNonEmptyEmailUpdates(@[(emailId, updateSet)]).valueOr:
    stderr.writeLine "invalid update batch"
    return 1
  let (b, handle) = ctx.client.newBuilder().addEmailSet(
    ctx.mailAccount, update = Opt.some(updates))
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let setResp = dr.get(handle).valueOr:
    stderr.writeLine "Email/set failed: " & error.message
    return 1
  for id, res in setResp.updateResults:
    if res.isOk: echo "moved " & $id
    else: stderr.writeLine "move failed: " & res.error.message
  return 0
```

- [ ] **Step 2: Build, guard, run** (`/tmp/jmap-cli email move <emailId> <mailboxId>`, using ids from earlier commands). Expected: `moved <id>`; confirm with `email query` against the destination mailbox.

- [ ] **Step 3: Record findings + commit** (`AUDIT.md` `### email move`: same sealing-chain repetition as flag — note the recurring pattern; whether `moveToMailbox` reads cleanly). Commit:
```bash
git add examples/jmap-cli/commands/email_move.nim examples/jmap-cli/jmap-cli.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement email move command

<TRAILERS>"
```

## Task 12: `vacation get|set` — VacationResponse (NoCreate rail)

**Files:**
- Create: `examples/jmap-cli/commands/vacation.nim`

- [ ] **Step 1: Write the command**

`examples/jmap-cli/commands/vacation.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli vacation get` / `vacation set <bodyText>` — read or enable
## the singleton VacationResponse. /set has no create rail (NoCreate).

import jmap_client
import ./cli_session

proc doGet(ctx: CliContext): int =
  let (b, handle) = ctx.client.newBuilder().addVacationResponseGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let resp = dr.get(handle).valueOr:
    stderr.writeLine "VacationResponse/get failed: " & error.message
    return 1
  if resp.list.len == 0:
    echo "no vacation response configured"
    return 0
  let v = resp.list[0]
  echo "enabled: " & $v.isEnabled
  echo "subject: " & v.subject.valueOr("(none)")
  echo "body:    " & v.textBody.valueOr("(none)")
  return 0

proc doSet(ctx: CliContext, body: string): int =
  let updateSet = initVacationResponseUpdateSet(@[
    setIsEnabled(true),
    setSubject(Opt.some("Out of office")),
    setTextBody(Opt.some(body)),
  ]).valueOr:
    stderr.writeLine "invalid vacation update"
    return 1
  let (b, handle) = ctx.client.newBuilder().addVacationResponseSet(
    ctx.mailAccount, updateSet)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  discard dr.get(handle).valueOr:
    stderr.writeLine "VacationResponse/set failed: " & error.message
    return 1
  echo "vacation response enabled"
  return 0

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli vacation get | vacation set <bodyText>"
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  case args[0]
  of "get": doGet(ctx)
  of "set":
    if args.len < 2:
      stderr.writeLine "usage: jmap-cli vacation set <bodyText>"
      return 2
    doSet(ctx, args[1])
  else:
    stderr.writeLine "usage: jmap-cli vacation get | vacation set <bodyText>"
    2
```

VERIFY: `addVacationResponseSet` takes the `VacationResponseUpdateSet` by value (not `Opt`); `v.isEnabled` is a plain `bool` field; the `NoCreate` `T` slot needs no handling on the get path.

- [ ] **Step 2: Build, guard, run** (`/tmp/jmap-cli vacation set "Away until Monday"` then `/tmp/jmap-cli vacation get`). Expected: set confirms, get echoes enabled/subject/body.

- [ ] **Step 3: Record findings + commit** (`AUDIT.md` `### vacation`: the `NoCreate` marker visibility, set-takes-value-not-Opt asymmetry vs other `/set` builders). Commit:
```bash
git add examples/jmap-cli/commands/vacation.nim examples/jmap-cli/jmap-cli.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement vacation get/set command

<TRAILERS>"
```

---

# Phase 4 — Send (the make-or-break path)

## Task 13: `email send` — EmailSubmission + on-success Email/set

This is the hardest ergonomics in the API and the highest-value audit target. The slice-7 explorer flagged that there is **no plain-text-email shorthand** — the consumer hand-builds `BlueprintBodyPart → BlueprintLeafPart → BlueprintBodyValue → flatBody`, and constructs an RFC 5321 envelope. Treat every step as a finding. **If any step cannot be done with hub-public symbols (e.g. no public `PartId` constructor for an inline leaf), stop, record it as the top freeze-blocking finding, and leave the command returning a clear "blocked: <reason>" — do not import `internal/`.**

**Files:**
- Create: `examples/jmap-cli/commands/email_send.nim`

- [ ] **Step 1: Resolve the construction path before writing**

Read the hub-public surface of `src/jmap_client/internal/mail/email_blueprint.nim` and `body.nim` (via the *symbols*, not by importing them) to confirm: how to construct a `PartId` for an inline `BlueprintLeafPart` (look for `parsePartId`/`partId`), and whether a higher-level body helper exists. Record what you find in `AUDIT.md` `### email send` before coding — the discovery itself is the finding.

- [ ] **Step 2: Write the command (starting hypothesis — adjust to the real surface)**

`examples/jmap-cli/commands/email_send.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email send <toAddress> <subject> <bodyText>` — create a
## draft Email and submit it in one compound EmailSubmission/set +
## Email/set, moving the created email to Sent on success. Uses alice's
## first identity as the From. This is the gnarliest public path; every
## awkwardness is an AUDIT finding.

import std/tables
import jmap_client
import ./cli_session

proc firstIdentity(ctx: CliContext): Result[(Id, string), string] =
  let (b, h) = ctx.client.newBuilder().addIdentityGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    return err("send failed: " & error.message)
  let resp = dr.get(h).valueOr:
    return err("Identity/get failed: " & error.message)
  if resp.list.len == 0: return err("no identity to send from")
  ok((resp.list[0].id, resp.list[0].email))

proc resolveRole(ctx: CliContext, want: MailboxRole): Result[Id, string] =
  let (b, h) = ctx.client.newBuilder().addMailboxGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    return err("send failed: " & error.message)
  let resp = dr.get(h).valueOr:
    return err("Mailbox/get failed: " & error.message)
  for m in resp.list:
    for role in m.role:
      if role == want: return ok(m.id)
  err("mailbox role not found")

proc run*(args: seq[string]): int =
  if args.len < 3:
    stderr.writeLine "usage: jmap-cli email send <toAddress> <subject> <bodyText>"
    return 2
  let toAddress = args[0]
  let subject = args[1]
  let bodyText = args[2]
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1

  let (identityId, fromAddr) = firstIdentity(ctx).valueOr:
    stderr.writeLine error
    return 1
  let draftsId = resolveRole(ctx, roleDrafts).valueOr:
    stderr.writeLine error
    return 1
  let sentId = resolveRole(ctx, MailboxRole(rawKind: mrSent)).valueOr:
    # NOTE: if `roleSent` const exists, prefer it; otherwise parseMailboxRole("sent").
    stderr.writeLine error
    return 1

  # --- Build the draft email (no plain-text shorthand exists) ---
  let textPart = BlueprintBodyPart(
    contentType: "text/plain",
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartId("text").get(),     # VERIFY constructor name
      value: BlueprintBodyValue(value: bodyText),
    ),
  )
  let body = flatBody(textBody = Opt.some(textPart))
  let fromEa = parseEmailAddress(fromAddr).get()
  let toEa = parseEmailAddress(toAddress).get()
  let blueprint = parseEmailBlueprint(
    mailboxIds = parseNonEmptyMailboxIdSet(@[draftsId]).get(),
    body = body,
    fromAddr = Opt.some(@[fromEa]),
    to = Opt.some(@[toEa]),
    subject = Opt.some(subject),
  ).valueOr:
    stderr.writeLine "blueprint rejected"
    return 1

  # --- Build the submission referencing the not-yet-created email ---
  let mailFrom = parseRFC5321Mailbox(fromAddr).get()
  let rcptMb = parseRFC5321Mailbox(toAddress).get()
  let envelope = Envelope(
    mailFrom: reversePath(SubmissionAddress(
      mailbox: mailFrom, parameters: Opt.none(SubmissionParams))),
    rcptTo: parseNonEmptyRcptList(@[SubmissionAddress(
      mailbox: rcptMb, parameters: Opt.none(SubmissionParams))]).get(),
  )
  let subBlueprint = parseEmailSubmissionBlueprint(
    identityId = identityId,
    emailId = creationRef(CreationId("draft")).asCreationRef.get(),  # VERIFY: emailId type
    envelope = Opt.some(envelope),
  ).valueOr:
    stderr.writeLine "submission blueprint rejected"
    return 1

  # --- Compound: create email + submission, move to Sent on success ---
  var creates = initTable[CreationId, EmailSubmissionBlueprint]()
  creates[CreationId("sub")] = subBlueprint
  # On success, move the created email (#draft) to Sent.
  let onSuccess = parseNonEmptyOnSuccessUpdateEmail(@[(
    creationRef(CreationId("draft")),
    initEmailUpdateSet(@[setMailboxIds(parseNonEmptyMailboxIdSet(@[sentId]).get())]).get(),
  )]).get()

  let (b, handles) = ctx.client.newBuilder().addEmailSubmissionAndEmailSet(
    ctx.mailAccount,
    create = Opt.some(creates),
    onSuccessUpdateEmail = Opt.some(onSuccess),
  ).valueOr:
    stderr.writeLine "compound builder rejected: " & error.message
    return 1
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let results = dr.getBoth(handles).valueOr:
    stderr.writeLine "extraction failed: " & error.message
    return 1
  echo "submitted; submission createResults=" & $results.primary.createResults.len
  return 0
```

This task carries the most VERIFY uncertainty by design. Key things to resolve and record: (a) the `PartId` constructor for an inline leaf — **if none is hub-public, this command is blocked and that is the top finding**; (b) how the email creation key (`CreationId("draft")`) is wired so `addEmailSubmissionAndEmailSet`'s implicit Email/set sees it — the mapped signature shows `create` is only the *submission* blueprint table, so where does the **email** get created? Re-read `submission_builders.nim` hub-public surface: the compound builder likely needs the email `create` supplied too, or expects a separate `addEmailSet` create wired by creation id. **Resolve the actual two-creation wiring and record the exact mechanism** — this is the single most important ergonomic finding of the whole bench. (c) `mrSent`/`roleSent` availability; (d) `creationRef(...).asCreationRef` is almost certainly wrong for the `emailId` param (which wants an `Id` or an `IdOrCreationRef`) — fix to the real type and record the friction.

- [ ] **Step 3: Build, guard, run**

```bash
nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim
examples/jmap-cli/check-public-only.sh
source /tmp/stalwart-env.sh && /tmp/jmap-cli email send bob@example.com "hello from jmap-cli" "Sent by the P29 bench."
```
Expected: a success line. Verify delivery by querying **bob's** inbox (re-run with bob's credentials, or check the seed smoke). If the command is *blocked* by a missing public constructor, the expected outcome is a clear `blocked: <reason>` message and the finding logged.

- [ ] **Step 4: Record findings + commit**

`AUDIT.md` `### email send` will be the longest section. Capture: no plain-text body helper; manual MIME leaf construction; `PartId` constructor discoverability; the two-creation wiring; the RFC5321 envelope ceremony; the `IdOrCreationRef` forward-reference threading; the `Result[_, seq[ValidationError]]` rails. Critique paragraph under `## Sending…` with the blunt verdict (this is where P7 "would they wrap it?" is most likely to bite). Commit:
```bash
git add examples/jmap-cli/commands/email_send.nim examples/jmap-cli/jmap-cli.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement email send (submission) command

<TRAILERS>"
```

---

# Phase 5 — Search & the convenience layer

## Task 14: `search` — Email/query + SearchSnippet/get (back-reference)

**Files:**
- Create: `examples/jmap-cli/commands/search.nim`

- [ ] **Step 1: Write the command**

`examples/jmap-cli/commands/search.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli search <text>` — full-text Email/query plus SearchSnippet/get
## via the compound back-reference builder addEmailQueryWithSnippets.

import jmap_client
import ./cli_session

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli search <text>"
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  let filter = filterCondition(EmailFilterCondition(text: Opt.some(args[0])))
  let (b, chain) = ctx.client.newBuilder().addEmailQueryWithSnippets(
    ctx.mailAccount, filter)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let results = dr.getBoth(chain).valueOr:
    stderr.writeLine "extraction failed: " & error.message
    return 1
  echo "matched " & $results.query.ids.len & " emails"
  for s in results.snippets.list:
    echo $s.emailId & "  " & s.subject.valueOr("") & "  " & s.preview.valueOr("")
  return 0
```

VERIFY: `addEmailQueryWithSnippets` returns `(RequestBuilder, EmailQuerySnippetChain)` and there is a `getBoth` overload for that chain (mapped, `mail_methods.nim`). Confirm `SearchSnippet.subject`/`preview` are `Opt[string]`.

- [ ] **Step 2: Build, guard, run** (`/tmp/jmap-cli search hello`). Expected: a match count and snippet lines for the seeded mail.

- [ ] **Step 3: Record findings + commit** (`AUDIT.md` `### search`: the compound-chain ergonomics vs the manual back-reference in `email query`). Commit:
```bash
git add examples/jmap-cli/commands/search.nim examples/jmap-cli/jmap-cli.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: implement search command

<TRAILERS>"
```

## Task 15: Exercise the opt-in convenience layer (`jmap_client/convenience`)

This task adds a `--via-convenience` flag to `email query` that uses `addEmailQueryThenGet` + `getBoth` from the **opt-in** convenience module, proving the second public import path works and contrasting its ergonomics with the hand-wired back-reference in Task 6.

**Files:**
- Modify: `examples/jmap-cli/commands/email_query.nim`

- [ ] **Step 1: Add the convenience import and branch**

At the top of `email_query.nim`, add:
```nim
import jmap_client/convenience
```
Add near the start of `run`, after `connect`:
```nim
  if "--via-convenience" in args:
    let (b, handles) = ctx.client.newBuilder().addEmailQueryThenGet(ctx.mailAccount)
    let dr = ctx.client.send(b.freeze()).valueOr:
      stderr.writeLine "send failed: " & error.message
      return 1
    let both = dr.getBoth(handles).valueOr:
      stderr.writeLine "getBoth failed: " & error.message
      return 1
    echo "query matched " & $both.query.ids.len & ", got " & $both.get.list.len & " emails"
    for e in both.get.list:                     # full Email here
      echo e.subject.valueOr("(no subject)")
    return 0
```

VERIFY: `addEmailQueryThenGet` returns `QueryGetHandles[Email]` (full `Email`, not `PartialEmail`); the convenience `getBoth` overload resolves; `both.get.list` field name.

- [ ] **Step 2: Build, guard, run**

```bash
nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim
examples/jmap-cli/check-public-only.sh   # still OK: convenience is public, not internal
source /tmp/stalwart-env.sh && /tmp/jmap-cli email query --via-convenience
```
Expected: a match count + subjects. The guard must still pass (convenience is a public path).

- [ ] **Step 3: Record findings + commit** (`AUDIT.md` `### convenience`: discoverability cost of the separate `import jmap_client/convenience`; ergonomic delta vs the hand-wired chain — likely a *positive* finding). Commit:
```bash
git add examples/jmap-cli/commands/email_query.nim examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit -m "examples/jmap-cli: exercise opt-in convenience combinators

<TRAILERS>"
```

---

# Phase 6 — Synthesise the deliverables

## Task 16: Consolidate `AUDIT.md` (dedup, cross-cut, severity)

**Files:**
- Modify: `examples/jmap-cli/AUDIT.md`

- [ ] **Step 1: Promote recurring findings to the cross-cutting section**

Read the whole ledger. Any finding appearing under ≥2 commands (e.g. the `initX(...).get()` → `parseY(...).get()` sealing chain; the `Result[_, seq[ValidationError]]` rail on single updates; the nested `Table[Id, Result[Opt[U], SetError]]` read; the connect preamble) moves to `## Cross-cutting findings` with the command list. Leave per-command findings that are genuinely local in place.

- [ ] **Step 2: Add a severity tag to each cross-cutting finding**

Append ` {severity: high|medium|low}` before the `[open]` marker. `high` = a day-one wrapper trigger or a path that could not be completed with the public surface. Keep status `[open]` (no triage this pass).

- [ ] **Step 3: Add a summary count block at the top**

After the preamble, add:
```markdown
## Summary
- Commands exercised: 12 (session, mailbox, email query/read/flag/move/send, thread, identity, vacation, search, convenience)
- Findings: <N> total — <H> high, <M> medium, <L> low; positives: <P>
- Blocked commands (could not be expressed with hub-public symbols): <list or "none">
```
Fill `<…>` from the actual ledger.

- [ ] **Step 4: Commit**

```bash
git add examples/jmap-cli/AUDIT.md
git commit -m "examples/jmap-cli: consolidate audit ledger with severities

<TRAILERS>"
```

## Task 17: Complete the consumer-perspective critique

**Files:**
- Modify: `docs/design/16-api-from-the-consumers-chair.md`
- Modify: `examples/jmap-cli/README.md` (create)

- [ ] **Step 1: Write the cross-cutting verdict section**

Fill `## Cross-cutting verdict` in `docs/design/16-…md` answering, with evidence from the bench and principle cross-references:
- **P7 (wrap rate):** for each area (read / mutate / send / search), would a competent developer reach for jmap_client directly, or write a wrapper? The send path is the likely "wrap it" candidate — say so plainly.
- **P29 first-15-minutes:** the concept count before `mailbox list` works; lifecycle discoverability; the connect-preamble repetition (C5/C8).
- **What is genuinely excellent:** the typed phantom handles, the named-variant error rail (`ClientError`/`GetError`/`SetError` `.message`), the sealed smart constructors, the back-reference type safety. Be specific.
- **What grates:** sealing-chain ceremony, the no-plain-text-email gap, `FieldEcho` three-state reads, accumulating `seq[ValidationError]` on single updates.
- **The honest one-line verdict** per area.

- [ ] **Step 2: Write the README**

`examples/jmap-cli/README.md`:

```markdown
<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# jmap-cli — sample JMAP consumer (P29 ergonomics bench)

A deliberately thin CLI that drives the `jmap_client` **public API only**
to exercise every RFC 8621 entity area against a live JMAP server. Its
purpose is the audit in `AUDIT.md` and the critique in
`docs/design/16-api-from-the-consumers-chair.md`, not to be a usable
mail client.

## Build

    nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim

Build config (`nim.cfg`) pins the consumer contract: `--mm:arc
--threads:on --panics:on` and `--path` to `src/` and the vendored
`nim-results`. The sample deliberately does not enable the library's
own warning-as-error battery.

## Run against Stalwart

    just stalwart-up
    source /tmp/stalwart-env.sh
    /tmp/jmap-cli session
    /tmp/jmap-cli mailbox list
    /tmp/jmap-cli email query --unread
    /tmp/jmap-cli email send bob@example.com "hi" "body"
    # … see `jmap-cli` with no args for the full subcommand list

## Public-surface guard

    examples/jmap-cli/check-public-only.sh

Fails if any module imports `jmap_client/internal/*`. The CLI may import
only `jmap_client` and `jmap_client/convenience`.
```

- [ ] **Step 3: Final build + guard sweep**

```bash
nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap-cli.nim   # all commands enabled
examples/jmap-cli/check-public-only.sh
```
Expected: clean compile; guard passes.

- [ ] **Step 4: Commit**

```bash
git add docs/design/16-api-from-the-consumers-chair.md examples/jmap-cli/README.md
git commit -m "examples/jmap-cli: complete consumer critique + README

Close the P29 bench (tracker C1): the sample CLI exercises every
RFC 8621 entity area against live Stalwart through the public surface
only, AUDIT.md catalogues the ergonomic findings, and design doc 16
records the consumer-chair verdict per API area with P-number
cross-references. Observe-only pass: findings are [open]; triage is
deferred.

<TRAILERS>"
```

---

## Self-review checklist (run before declaring the plan done)

- [ ] **Spec coverage:** every brainstorming decision is realised — full-entity coverage (Tasks 5–15 hit Mailbox, Email, Thread, Identity, EmailSubmission, VacationResponse, SearchSnippet, convenience); live Stalwart (env wiring in Tasks 1/4); both docs (AUDIT.md Task 2/16, critique Task 3/17); observe-only `[open]` posture (Task 2 preamble); import purity (Task 1 guard).
- [ ] **Tracker linkage:** C1 (AUDIT.md exists, deliverable format), C1.1 (the scaffold tree), F4 noted as deferred.
- [ ] **No silent internal reach:** every command imports only `jmap_client`/`jmap_client/convenience`/`./cli_session`/`std/*`; the guard enforces it.
- [ ] **Discovery honesty:** every VERIFY note is a finding-to-record, not a hidden placeholder; the send task's blockers are explicitly allowed to terminate as `blocked: …`.
```
