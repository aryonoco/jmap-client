<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# E1 — Capability-resolution reconcile: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.
> **Design spec (authoritative for this change, gitignored — read from disk):**
> `docs/superpowers/specs/2026-06-16-s3-capability-resolution-reconcile-design.md`.
> **Zero-context brief:** `docs/superpowers/plans/2026-06-16-E1-RECONCILE-AND-S3-WRAPUP-HANDOFF.md`.
> **Authority rule:** the RFC text in `docs/rfcs/` governs every protocol question;
> the design docs are fallible (memory `rfc-is-authoritative`).
> **Design lens (overrides everything on conflict):** the only design input is the
> future email-client developer; model after libcurl/SQLite, avoid OpenSSL/libdbus;
> tests and incumbent callers are not inputs; 0 users, blast radius irrelevant;
> version-agnostic; exemplary, showcase quality, no corners cut.

**Goal:** Make the capability→account resolution surface coherent by **subtraction**:
remove the caller-less, general-strict `requirePrimaryAccount` and its now-dead
`sfPrimaryAccountAbsent` session fault, leaving one internally-consistent
named-soft resolver family (`requireMail` / `requireSubmission` / `requireVacation`).
Net public-surface change: **−1 public func, −1 error variant, no additions.**

**Architecture:** Purely subtractive edits to two L3 modules
(`protocol/preflight.nim`, `protocol/jmap_error.nim`), their test/script/lint
ripple, and the three regenerated wire-contract snapshots. The
"designated-primary-specifically" need is already served by the existing public
`session.primaryAccount(kind): Opt[AccountId]`. `SessionFaultKind` reduces to the
single meaningful variant `sfCapabilityAbsent`; `message()` stays an **exhaustive
single-arm `case`** so re-adding a variant fails to compile there (make illegal
states unrepresentable; never a catch-all `else`).

**Tech Stack:** Nim, nim-results (`Result`/`Opt`/`valueOr`), testament, nph,
nimalyzer, the compiler-as-library wire-contract oracle (`just freeze-*`).

---

## STATE / HANDOFF (update as each task lands — compaction-safe source of truth)

- **Branch:** `api/s3-complete-the-core` (off `main`), atop the 12 committed S3
  commits (top `7561f8b docs/s3: add zero-context handoff for the E1 reconcile`).
  S3 is fully implemented; both S3 gates were green at `f03193b`. E1 is the only
  remaining work on this branch before push/PR.
- **Per-task gate:** Task 1 must pass full `just ci` (it edits snapshots + the
  H15/H16/H17 lock lints). Task 2 is doc-only. Both full gates run once at the end
  (after Task 2): `just ci`, then `just clean && just jmap-reset && just test-full`.
- **Commits:** Linux-kernel style, subject ≤75 cols, why-focused body; end EVERY
  body with exactly the three trailers (see Conventions). Stage explicit paths;
  never `git add -A`. Flip this STATE block in the same commit as each task.
- **Status:** ⏳ IN PROGRESS — Tasks 1/2/1b committed + `just ci` green; both gates next.
  - [x] **Plan** — this file committed (`docs/s3: plan the E1 capability-resolution reconcile`).
  - [x] **Task 1** — subtractive code change + ripple + 3 snapshots regenerated; both
    reviewers ✅ (spec-compliant + quality-approved), `just ci` green (controller-run).
    Commit `protocol: retire requirePrimaryAccount and its dead session fault`.
    **Deviation accepted:** `message(SessionFault)` could not stay a single-arm
    `case` (nimalyzer `caseStatements min 2`; `tno_asserts_in_src` forbids a `static
    doAssert`); used the CI-blessed `when SessionFaultKind.low != .high: {.error.}`
    guard idiom from `serde_email_submission.nim` — preserves "new variant ⇒ compile
    error here". `je*` freeze-script locals renumbered contiguous (quality nit).
  - [x] **Task 2** — `examples/jmap-cli/AUDIT.md` session:capability finding → fully
    resolved (+ E1 reconcile note), history kept truthful; CLI rebuilds + public-only
    green. Commit `examples/jmap-cli: close the session:capability finding (E1)`.
  - [x] **Task 1b** — flatten `SessionFault` to `{ capability }` (drop `SessionFaultKind`,
    `sfCapabilityAbsent`, the Task-1 `when`-guard; plain `message()`), matching the flat
    single-reason sibling `Misuse`. Surfaced by the final 4-lens adversarial review (the
    post-Task-1 `kind` discriminator was single-valued + write-only) and **chosen by the
    user** over keeping+documenting the enum; deliberately overturns the approved design
    spec §3.2 "no further collapse" for the leaner, principle-aligned end-state. Ghost-grep
    empty; 3 snapshots regenerated (public-api loses the type + enumfield + the ctor `kind`
    param; type-shapes loses the `## SessionFaultKind` section + the `kind` field);
    `just ci` green (controller-run). Commit
    `protocol: flatten SessionFault to its single capability-absent reason`.
  - [ ] **Gates** — `just ci` ✅ (green at Task 1b); `just clean && just jmap-reset &&
    just test-full` "All shards passed" (Stalwart + James + Cyrus). Record SHAs here.
  - [ ] **Hand back** — confirm push/PR with the user (PR body: no Claude footer).

## Ripple-completeness ledger (every reference to the two removed names — nothing else may move)

Verified by `grep -rn "requirePrimaryAccount\|sfPrimaryAccountAbsent"` over `src/`,
`tests/`, `scripts/`, `examples/` (the `docs/superpowers/specs/*` hits are gitignored
historical design records — NOT edited; `docs/design/*` has zero hits).

| # | File | Reference | Action |
|---|---|---|---|
| 1 | `src/jmap_client/internal/protocol/preflight.nim` | module docstring "…or advertises it but has no primary account for it"; `func requirePrimaryAccount*` (def, lines ~25–38) | fix docstring; delete func |
| 2 | `src/jmap_client/internal/protocol/jmap_error.nim` | `sfPrimaryAccountAbsent` enum value; `of sfPrimaryAccountAbsent:` arm in `message()`; `jeSession` arm doc-comment | remove value; remove arm; truthful comment |
| 3 | `tests/compile/tcompile_a12_error_constructor_surface.nim` | `doAssert declared(requirePrimaryAccount)` | drop the line |
| 4 | `tests/lint/h15_error_message_snapshot.nim` | `sfPrimaryAccountAbsent` sample (in `samples()`); docstring count "42" | drop sample; count → 41 |
| 5 | `scripts/freeze_error_messages.nim` | `je5 = …sfPrimaryAccountAbsent…` sample; docstring count "38" (stale; really 42) | drop sample; count → 41 |
| 6 | `tests/wire_contract/public-api.txt` | `func requirePrimaryAccount …` AND `enumfield sfPrimaryAccountAbsent` | regenerate (`just freeze-api`) — loses **both** lines |
| 7 | `tests/wire_contract/type-shapes.txt` | `sfPrimaryAccountAbsent` enum member | regenerate (`just freeze-type-shapes`) |
| 8 | `tests/wire_contract/error-messages.txt` | `[jmapSession(sessionFault(sfPrimaryAccountAbsent, ckMail))]` + message | regenerate (`just freeze-error-messages`) |
| 9 | `examples/jmap-cli/AUDIT.md` | session:capability "PARTIALLY RESOLVED" + historical mentions | Task 2: mark fully resolved + E1 note |

Stay-green guards (must NOT need editing — confirm they still pass):
`tests/unit/tpreflight.nim` (the `require*` behaviour tests) and
`tests/unit/tmessages.nim:142` (`tSessionFaultMessage`, uses only the surviving
`sfCapabilityAbsent`). The only `case` over `SessionFaultKind` is `message()` in
`jmap_error.nim`; the compiler will surface any other site since catch-all `else`
on a finite enum is forbidden.

---

## Conventions (every task)

- **Layers:** both touched modules are L3 — `{.push raises: [], noSideEffect.}` +
  `{.experimental: "strictCaseObjects".}` already present; `func` only, pure/total.
- **`SessionFault` is a flat object** (not a case object): `case sf.kind` is a plain
  enum case, no strictCaseObjects obligation. Keep it an **exhaustive `case`**
  (single arm now) — do NOT collapse to a bare string; the case preserves the
  "new variant ⇒ compile error here" guarantee.
- **British-English** docstrings that explain *why*; **RFC-section refs only** in
  comments (no design-doc/campaign cross-refs, no "S1"/"E1"/"D5" in source). Every
  public `func` AND every test-helper `proc` needs a `##` docstring (nimalyzer
  `hasdoc` fires over `tests/` too, only in `just ci`).
- **No unused imports** — after deleting `requirePrimaryAccount`, confirm
  `preflight.nim`'s six imports all remain used (they do: `std/tables` for
  `session.accounts` iteration; `results`; `session`; `capabilities`;
  `identifiers`; `jmap_error`). `--warningAsError:UnusedImport` is fatal.
- **Commit format** (Linux-kernel), end EVERY body with exactly:
  ```
  Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
  Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
  Assisted-by: Claude:claude-4.8-opus
  ```
- **Stage explicit paths**; never `git add -A`. **Never** suppress a nimalyzer rule
  or loosen compiler settings. Confirm push/PR/merge with the user.

---

## Task 1 — Retire `requirePrimaryAccount` and `sfPrimaryAccountAbsent`

**Files:**
- Modify: `src/jmap_client/internal/protocol/preflight.nim`
- Modify: `src/jmap_client/internal/protocol/jmap_error.nim`
- Modify: `tests/compile/tcompile_a12_error_constructor_surface.nim`
- Modify: `tests/lint/h15_error_message_snapshot.nim`
- Modify: `scripts/freeze_error_messages.nim`
- Regenerate: `tests/wire_contract/{public-api,type-shapes,error-messages}.txt`

This is an **atomic** change: removing the enum value makes the lint + freeze
script + (transitively) the test surface fail to compile, so all edits land in one
green commit. "TDD red" = the failing build/lints pointing at every reference;
`tests/unit/tpreflight.nim` is the behavioural regression guard.

- [ ] **Step 1 — `jmap_error.nim`: remove the enum value.**
  Delete the `sfPrimaryAccountAbsent` line from `SessionFaultKind`:
  ```nim
  type SessionFaultKind* = enum
    ## Why a capability/account preflight failed against the live session.
    sfCapabilityAbsent ## the session does not advertise the required capability
  ```
  (Removed: `sfPrimaryAccountAbsent ## no primary account exists for the required capability`.)

- [ ] **Step 2 — `jmap_error.nim`: collapse `message()` to the exhaustive single arm.**
  ```nim
  func message*(sf: SessionFault): string =
    ## Human-readable diagnostic. Renders the registered URI when known, else
    ## the enum's symbolic name (``ckUnknown``).
    let uri = sf.capability.capabilityUri.valueOr:
      $sf.capability
    case sf.kind
    of sfCapabilityAbsent:
      "session does not advertise the " & uri & " capability"
  ```
  (Removed the `of sfPrimaryAccountAbsent: "no primary account for the " & uri & " capability"` arm.)

- [ ] **Step 3 — `jmap_error.nim`: make the `jeSession` arm comment truthful.**
  In `type JmapErrorKind* = enum`, change the `jeSession` line so it no longer
  claims a now-impossible "primary account absent" state:
  ```nim
    jeSession ## an expected session capability is absent
  ```
  (Was: `jeSession ## an expected capability or primary account is absent`.)

- [ ] **Step 4 — `preflight.nim`: fix the module docstring.** Replace the
  strict-failure clause (the orphan's behaviour) with the soft-resolution truth:
  ```nim
  ## Capability / primary-account preflight against a live ``Session``. Resolves
  ## and guards the account to use for a capability before dispatch, folding a
  ## failure onto the consumer error rail (``JmapError``, ``jeSession`` arm) when
  ## no account advertises the capability. Account resolution treats
  ## ``accountCapabilities`` as authoritative (RFC 8620 §2): it accepts the
  ## designated primary only when that account advertises the capability,
  ## otherwise the lowest-id advertising account.
  ```

- [ ] **Step 5 — `preflight.nim`: delete `func requirePrimaryAccount*`.** Remove the
  entire definition (the `func requirePrimaryAccount*(...)` … `ok(accountId)` block,
  ~14 lines). `lowestAdvertising`, `usableAccount`, and
  `requireMail`/`requireSubmission`/`requireVacation` stay byte-for-byte unchanged.

- [ ] **Step 6 — Build green.** `nim c src/jmap_client.nim` (or `just build`) — the
  library must compile. The lint/script/test files below will still be broken; fix
  them next.

- [ ] **Step 7 — `tcompile_a12_error_constructor_surface.nim`: drop the assertion.**
  Remove the line `doAssert declared(requirePrimaryAccount)` from the POSITIVE block
  (the public-api snapshot already locks the surface; no negative assertion needed).

- [ ] **Step 8 — `tests/lint/h15_error_message_snapshot.nim`: drop the sample + fix the count.**
  Remove the `result.add(("jmapSession(sessionFault(sfPrimaryAccountAbsent, ckMail))", …))`
  pair from `samples()`. Update the two docstring mentions of "42" → "41" (the
  `## Verifies that the canonical message() projection over the 42 …` line and the
  `## Inline declaration of the 42 (label, projected message) pairs …` line).

- [ ] **Step 9 — `scripts/freeze_error_messages.nim`: drop the sample + fix the count.**
  Remove the `je5` two lines (`let je5 = jmapSession(sessionFault(sfPrimaryAccountAbsent, ckMail))`
  and its `emit(...)`). Update the docstring "the 38 representative error values"
  → "the 41 representative error values" (the stored count was already stale — the
  true pre-change count is 42).

- [ ] **Step 10 — Regenerate the three snapshots, in any order:**
  ```bash
  just freeze-error-messages
  just freeze-api
  just freeze-type-shapes
  ```

- [ ] **Step 11 — Confirm ONLY the expected lines moved.**
  ```bash
  git diff -- tests/wire_contract/
  ```
  Expected, and nothing else: `public-api.txt` loses the `func requirePrimaryAccount …`
  line AND the `enumfield sfPrimaryAccountAbsent` line; `type-shapes.txt` loses the
  `sfPrimaryAccountAbsent` member under `## SessionFaultKind`; `error-messages.txt`
  loses the `[jmapSession(sessionFault(sfPrimaryAccountAbsent, ckMail))]` label +
  its message line. If anything else moved, STOP and investigate.

- [ ] **Step 12 — Full gate.** `just ci` must be green (REUSE, fmt-check, the H15/H16/H17
  lock lints now matching the regenerated snapshots, nimalyzer complexity+hasdoc,
  fast test). Fix any failure and re-run until green.

- [ ] **Step 13 — Commit** (stage explicit paths; flip STATE Task 1 ✅ in the same commit):
  ```bash
  git add src/jmap_client/internal/protocol/preflight.nim \
          src/jmap_client/internal/protocol/jmap_error.nim \
          tests/compile/tcompile_a12_error_constructor_surface.nim \
          tests/lint/h15_error_message_snapshot.nim \
          scripts/freeze_error_messages.nim \
          tests/wire_contract/public-api.txt \
          tests/wire_contract/type-shapes.txt \
          tests/wire_contract/error-messages.txt \
          docs/superpowers/plans/2026-06-16-s3-capability-resolution-reconcile-plan.md
  git commit -F - <<'EOF'
  protocol: retire requirePrimaryAccount and its dead session fault

  requireMail/requireSubmission/requireVacation already resolve a
  capability's account primary-preferred with a per-account fallback
  (RFC 8620 §2). The general-strict requirePrimaryAccount, merged before
  that family existed, now has zero production callers and silently
  disagrees with requireMail on the no-primary case -- two spellings of
  "get the mail account" that diverge. Its sfPrimaryAccountAbsent fault is
  produced only by it; the soft resolvers emit only sfCapabilityAbsent.

  Remove the orphan and the dead variant so one coherent named-soft family
  remains; the designated-primary-specific need is already served by the
  public session.primaryAccount(kind): Opt. SessionFaultKind reduces to the
  single meaningful sfCapabilityAbsent, and message() stays an exhaustive
  case so re-adding a variant fails to compile here. Regenerate the three
  wire-contract snapshots and the inlined error-message samples in lockstep.

  Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
  Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
  Assisted-by: Claude:claude-4.8-opus
  EOF
  ```

---

## Task 2 — Close the `session:capability` finding in the audit ledger

**Files:** Modify `examples/jmap-cli/AUDIT.md`.

The bench's session:capability finding is the last thing E1 closes. The S3
resolution section (≈lines 600–615) already marks the named-soft family RESOLVED;
the S1 resolution section (≈lines 386–390) still reads "PARTIALLY RESOLVED" and
presents the now-removed `requirePrimaryAccount` as the live resolution. Make the
net status unambiguous and record the reconcile, keeping the history truthful (do
not pretend S1 shipped `requireMail`).

- [ ] **Step 1 — S1 resolution section: retire the "PARTIALLY RESOLVED" line.**
  Replace the `primaryAccount(ckMail) … forcing an unwrap` bullet so it no longer
  presents the removed symbol as current — mark it fully resolved with a forward
  pointer (suggested text; the implementer may refine for flow, staying truthful):
  ```markdown
  - **"`primaryAccount(ckMail)` returns `Opt[AccountId]` forcing an unwrap"**
    (session:capability) → PARTIALLY RESOLVED at S1; **fully resolved in S3 + the
    capability-resolution reconcile.** S1 first put capability/account resolution
    on the rail (`jeSession`); S3 added the named-soft shorthand `requireMail`
    (+ `requireSubmission` / `requireVacation`), and the reconcile then retired the
    interim general-strict resolver, leaving one coherent named-soft family. See
    the S3 resolution section below.
  ```

- [ ] **Step 2 — S3 resolution section: append a one-line reconcile note** at the
  end of the session:capability bullet (after the existing "…close the identical
  finding for those two capabilities." sentence), recording the subtraction:
  ```markdown
  The capability-resolution reconcile then removed the interim general-strict
  resolver and its dead `sfPrimaryAccountAbsent` session fault, so the resolver
  family is uniformly named-soft with one session-fault reason
  (`sfCapabilityAbsent`); the designated-primary-specific need is served by the
  public `session.primaryAccount(kind): Opt`.
  ```

- [ ] **Step 3 — Sanity-check the example still builds** (AUDIT.md is prose only, but
  confirm nothing else regressed):
  ```bash
  nim c -o:/tmp/jmap_cli examples/jmap-cli/jmap_cli.nim && \
    bash examples/jmap-cli/check-public-only.sh
  ```

- [ ] **Step 4 — Commit** (flip STATE Task 2 ✅ + mark E1 ready-for-gates in the same commit):
  ```bash
  git add examples/jmap-cli/AUDIT.md \
          docs/superpowers/plans/2026-06-16-s3-capability-resolution-reconcile-plan.md
  git commit -F - <<'EOF'
  examples/jmap-cli: close the session:capability finding (E1)

  The capability/account-resolution friction the bench raised is now fully
  resolved: S1 first put resolution on the rail, S3 added the named-soft
  requireMail family, and the reconcile retired the interim general-strict
  resolver. Record the final state in the audit ledger.

  Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
  Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
  Assisted-by: Claude:claude-4.8-opus
  EOF
  ```

---

## Final verification (controller-run, after both task commits)

1. **Adversarial review of the whole E1 diff** (`git diff f03193b..HEAD` minus the
   handoff/plan docs) through independent lenses — RFC 8620 §2 / the 29 principles /
   L3 purity & strictCaseObjects / the libcurl-SQLite design lens / completeness
   (did every ledger row land; did anything unexpected move). Tell every reviewer
   the RFC is authoritative, not the design docs.
2. **Both gates, by the controller:**
   - `just ci`
   - `just clean && just jmap-reset && just test-full` (exact order; run in the
     background; wait for "All shards passed"; on any failure fix and re-run the
     WHOLE sequence). Record both outcomes + the final SHA range in STATE.
3. **Hand back to the user** for the push/PR decision — confirm before any
   push/PR/merge; the PR body carries no Claude Code footer.

## Self-review (writing-plans)

- **Spec coverage:** every line of spec §3 (the change) and §4 (ripple) maps to a
  Task-1 step or the ledger; §5 (gates) → Final verification; §6 (out of scope:
  findings #2 `EmailLeaf`, #3 naming/raw-`Blueprint*`) is explicitly NOT touched.
- **Ripple completeness:** the ledger was built from a fresh `grep` over
  `src/ tests/ scripts/ examples/`; it adds two references the spec under-named —
  the H15 lint's inlined sample and the second `public-api.txt` line
  (`enumfield sfPrimaryAccountAbsent`) — and confirms `type-shapes.txt` does move.
- **No placeholders:** every step carries exact code/commands; commit messages are
  pre-drafted with the three trailers.
- **Type/name consistency:** `sfCapabilityAbsent` (kept), `sfPrimaryAccountAbsent`
  (removed), `requirePrimaryAccount` (removed), `requireMail`/`requireSubmission`/
  `requireVacation` + `usableAccount`/`lowestAdvertising` (kept) — used consistently
  throughout.
