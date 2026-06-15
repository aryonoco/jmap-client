<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# S2 — Read-Model Uniformity: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans` to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every read off a returned value uniform — direct public fields for
data records, accessors only for stateful handles, one reader experience for
`Opt`/`FieldEcho` — clearing root cause R6.

**Architecture:** Two-bucket. Invariants move into field *types* (sealed newtypes)
or are parse-enforced with raw construction out-of-contract (Tier-C). See the
approved spec `docs/superpowers/specs/2026-06-15-s2-read-model-uniformity-design.md`
(read it first) and the survey `…/2026-06-15-s2-read-model-survey.md`.

**Tech stack:** Nim `--mm:arc --panics:on`, L1–L3 `{.push raises: [],
noSideEffect.}` + `{.experimental: "strictCaseObjects".}`, vendored `nim-results`.
No new deps, no `converter`s, no `requiresInit`.

---

## STATE / HANDOFF (update as each phase lands; survives compaction)

- **Branch:** `api/s2-read-model-uniformity` — **created off `main`**; never
  implement on `main`.
- **Phases:** 0 → 13. Each commit leaves `src/` building (`just build` green).
  Tests + `convenience.nim` are swept in Phase 11; the CLI re-bench in Phase 12;
  both gates in Phase 13. The wire contract is regenerated once in Phase 10 (the
  H16/H17 lints fail on the stale snapshot until then — so per-phase verification
  is `just build`, NOT `just ci`; `just ci` runs only at Phase 13).
- **Status:** 🟢 IN PROGRESS. (Mark each phase ✅ DONE with its commit SHA here.)
  - P0 FieldEcho reader ✅ `0d93a4a` · P1 NonEmptyIdSeq relocate ✅ `a4f5a44` · P2 newtypes ✅ `6c9a306` ·
    P3 ceremony flips ✅ `5785fa2` · P4 Thread ✅ `55042d8` · P5 capability arms ✅ `b83f091` · P6 Account ✅ `b2242fc` ·
    P7 Session ✅ `065eb6f` · P8 Email headers + MailboxChangesResponse ✅ `27443be` ·
    P9 SetResponse projections ✅ `759ab11` · P10 contract regen ✅ `c9f35ff` · P11 test sweep 🔜 ·
    P12 CLI re-bench ⬜ · P13 gates ⬜.

### RESUME PROTOCOL (for a zero-context successor after compaction)

If you are picking this up mid-flight, do EXACTLY this, in order:
1. Read, in full: `docs/superpowers/plans/2026-06-15-CAMPAIGN-HANDOFF.md` (§2 = the
   non-negotiable design lens; §8b = S2), then the approved spec
   `docs/superpowers/specs/2026-06-15-s2-read-model-uniformity-design.md`, then THIS
   plan top-to-bottom.
2. `git branch --show-current` → must be `api/s2-read-model-uniformity` (if on
   `main`, `git checkout api/s2-read-model-uniformity`). Then `git log --oneline -20`.
3. The **Status** line above + `git log` are the source of truth: the last phase
   marked ✅ with a SHA is done; resume at the next ⬜ phase from its Phase section.
4. Per-phase discipline (MANDATORY): a fresh subagent per phase → review its full
   diff against the spec → re-run `just build` YOURSELF → run `just fmt` so the
   touched files are nph-canonical (`fmt-check` is part of `just ci` at P13) →
   commit with explicit paths (NEVER `git add -A`) using the Linux-kernel trailer
   block below → mark the phase ✅ + SHA on the Status line. Verification is
   `just build`, NOT `just ci`, until Phase 13. (Substantive phases also get a
   two-stage subagent review — spec-compliance then code-quality — before commit.)
5. STOP and ask the user only for: a genuine plan↔code contradiction needing a
   design call; any push/PR/merge; Phase 13's live gate (needs `just jmap-up`).
6. Quality lens governs every call: future application developer only; libcurl/
   SQLite not OpenSSL/libdbus; tests + `convenience.nim` are findings to fix, never
   constraints; no loosened compiler/nimalyzer settings; no `converter`s, no
   `requiresInit`/Tier-B.

### FEASIBILITY VERIFICATION (done 2026-06-15, before Phase 0 — verdict: AMBER/GO)

An 8-cluster read-only verification confirmed the plan matches the current source
across all 14 phases (no blockers). Two scope-REDUCING adjustments are folded in
below; do not re-discover them:
- **Only 7 explicit-paren accessor call sites exist in `src/`** (the UFCS edit
  targets for the flips): `accountCapabilities()` ×3 (`session.nim:271`,
  `session.nim:280`, `serde_session.nim:377`), `coreCapabilities()` ×2
  (`client.nim:396`, `client.nim:465`), `collationAlgorithms()` ×2
  (`capabilities.nim:378`, `serde_session.nim:41`). The plan's other named
  accessors — `.emailIds()`, `.apiUrl()`, `.property()` — have **zero** call sites
  in `src/`; do not hunt for them. (Line numbers are pre-edit; the compiler is the
  real gate — `just build` finds any residual.)
- **Phase 8 step 5 is a no-op:** no external code reads `MailboxChangesResponse`
  via the forwarders, so flattening needs no caller migration.
- Minor drift only: `NonEmptySeq[T]` is at `primitives.nim:328` (plan said ~343);
  `Id` is local to `primitives.nim`, `Idx` is imported from `./validation`.

### RFC-AUDIT FINDINGS (2026-06-15, audited vs docs/rfcs/ — design docs are NOT authoritative)

A full RFC audit of the protocol claims S2 propagated from the agent-authored
spec/D-decisions. 6 confirmed CORRECT (headers-not-§4.2-default; the 6 bare
default fields; URL-template required vars §2; mayDelete always-present Boolean
§6; FieldEcho absent/null/value §5.1+§5.3). Actions:
- **🔴 B12 was a REAL RFC violation (committed P6) — ✅ FIXED `d062e04`.**
  `parseAccount` silently dropped write-implying capabilities from a read-only
  account's `accountCapabilities`. RFC 8620 §2: a capability MUST be listed "if the
  user may use those methods"; `isReadOnly` is a SEPARATE account-wide axis (a
  read-only mail account still supports `Email/get`/`query`), so `jmap:mail` MUST
  stay listed. The filter made `hasCapability(ckMail)`/`mailCapability()` falsely
  report no mail support. **Resolution (user-chosen): removed the filter entirely**
  — `parseAccount` now preserves the server's list verbatim; the
  `WriteImplyingAccountCapabilities` set is deleted; Account is now a clean record
  (no Tier-C cross-field invariant). **P11 must SEMANTICALLY update (not mechanically
  adapt) the tests asserting the old drop:** `tests/property/tprop_account.nim`
  (`propAccountB12SilentDropWriteImplying`), `tests/unit/tsession_account_convenience.nim`
  (section E `b12…`), `tests/compile/tcompile_a17_account_capability_surface.nim:21`
  (`declared(WriteImplyingAccountCapabilities)`). **P10** drops `public-api.txt:1354`
  (the removed const) in the regen.
- **Citation/wording fixes (no behaviour) — ✅ ALL DONE:** snippet.nim §4.8→§5 (P8
  `27443be`); thread.nim "implicitly non-empty per §3", session.nim DisplayName /
  ApiUrl / detectApiUrl citations softened, serde_session.nim B12 docstring (all
  `d062e04`).
- **Post-S2: a dedicated RFC-conformance audit of the WHOLE codebase** (every D/A/B
  decision + protocol claim, not just S2-touched) is a USER-APPROVED new sub-project
  to run AFTER S2 completes — record it in the campaign handoff at S2 wrap-up.

### P11 SWEEP INVENTORY (broken-test sites surfaced by P0-P9 reviews)

The src/ flips intentionally left tests red (per-phase gate is `just build`). P11
must migrate these (compiler is the gate; tests adapt to the API, never the reverse):
- **`tests/mfixtures.nim` is a FOUNDATIONAL shared helper — fix it FIRST.** Its
  `makeEmail` assigns `headers: @[]` to the now-`Opt[seq[EmailHeader]]` field
  (lines ~564/596/624) → `mfixtures` and `massertions` won't compile, cascading to
  most tests. Wrap with `Opt.some(@[...])` / `Opt.none(...)` as appropriate.
- **capability accessor calls** (`.maxSizeUpload()`/`.collationAlgorithms()`/
  `.maxDelayedSend()`/`.uri()`/etc. → drop parens; `coreCapabilities()`→`.core`):
  `tests/serde/tserde_capabilities.nim`, `tserde_session.nim`,
  `tserde/captured/tcaptured_session.nim`, `tests/serde/mail/tserde_mail_account_capabilities.nim`,
  `tests/property/tprop_capabilities.nim`/`tprop_session.nim`/`tprop_server_capability.nim`/
  `tprop_account_capability_entry.nim`/`tprop_serde.nim`, `tests/unit/tcapabilities.nim`/
  `tsession.nim`, `tests/compliance/trfc_8620.nim`/`tscenarios.nim`, `tests/stress/tadversarial.nim`,
  `tests/serde/tserde_account.nim`, `tests/mproperty.nim`.
- **`Session.apiUrl` is now `ApiUrl`** (use `$session.apiUrl` where a string/`.len`/`==`
  was used); **`Account.name` is `DisplayName`** (use `$`).
- **`Thread.emailIds` is `NonEmptyIdSeq`** (`.toSeq` where a `seq[Id]` is needed).
- **`Email.headers`/`requestedHeaders*` are `Opt`** (unwrap).
- **B12 behavioural tests must be SEMANTICALLY updated (not mechanically adapted)** —
  see the RFC-AUDIT FINDINGS B12 entry: the read-only-account-drops-caps assertions are
  now WRONG; invert/remove them. `tests/compile/tcompile_a17_account_capability_surface.nim:21`
  asserts `declared(WriteImplyingAccountCapabilities)` — that const is gone; remove the assert.

### DEFERRED FINDINGS (discovered during execution; OUT of S2 scope)

- **The D5 "always emit every field, `null` for `Opt.none`" toJson convention is
  NOT RFC-faithful** (RFC-verified during P8, citing RFC 8620 §5.1: a `/get`
  response returns only the requested properties, so an unrequested property is
  ABSENT, never present-as-`null`). The codebase's `toJson` (Email and others)
  emits `null` for every `none`, fabricating a response no compliant server would
  send. The two-state `Opt` also conflates "not requested" with "requested-and-
  null", which only `FieldEcho[T]`'s three states preserve. P8 makes the three
  Email header fields correctly OMIT-on-none (RFC-correct), but the broader
  convention is a serde-fidelity defect for a FUTURE sub-project — do NOT fix in
  S2. (The omit rule is correct ONLY for render-from-not-requested fields; a
  genuinely wire-nullable property that was requested-and-absent must serialise as
  `null`, so this must not be generalised to "omit all none fields".)

---

## Locked decisions (spec §2, §16) and plan refinements

- Keep `Opt` + `FieldEcho`; add `FieldEcho` reader (P0). Two-bucket access. Migrate
  capability arms to public (P5). `Account.name`→`DisplayName`,
  `Session.apiUrl`→`ApiUrl` newtypes. Cross-field residue (`Account` policy×caps,
  `Session` url-vars) → Tier-C (public fields, `parseX`-enforced, raw construction
  out-of-contract).
- **Refinements** (spec §16): `MailAccountCapabilities` bounds → Tier-C public
  `Opt[UnsignedInt]` (not new newtypes); `Session.accounts`/`primaryAccounts` →
  public `Table` fields (not lookup-only — `requiresInit`/Tier-B is rejected).

## Conventions (MANDATORY — from CLAUDE.md / handoff §10)

- **Per-phase verification:** `just build` (compiles `src/`). Commit only when green.
  Run `just fmt` before each commit so every phase commit is nph-canonical
  (`fmt-check` runs in `just ci` at P13). Phases that add a test also run that test.
- **Stage explicit paths; NEVER `git add -A`.**
- **Commit messages — Linux-kernel style.** Subject `subsystem: short imperative`
  ≤75 cols; body wrapped ~75 cols explaining *why*; end EVERY body with exactly:
  ```
  Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
  Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
  Assisted-by: Claude:claude-4.8-opus
  ```
- **UFCS invariant that makes most flips transparent:** for a private `rawX: T` +
  `func x*(o): T`, renaming to a public field `x*: T` and deleting the accessor
  keeps every paren-less call site `o.x` working unchanged (field access). Only
  **explicit-paren** calls `o.x()` break — after each flip, `grep -rn '\.x(' src/`
  and drop the parens. External call-site type breaks only when the field *type*
  changes (e.g. `seq[Id]`→`NonEmptyIdSeq`, `string`→`ApiUrl`, bare→`Opt`).
- **Never** loosen compiler/nimalyzer settings or add `converter`s. Flipped types
  keep/get `{.ruleOff: "objects".}` + a one-line justification (the 176-use
  established exemption).

## File-structure map (what each phase touches)

| Phase | Primary files |
|---|---|
| P0 | `types/field_echo.nim` (+ `tests/unit/tfield_echo_reader.nim`) |
| P1 | `mail/email_submission.nim` → `types/primitives.nim` |
| P2 | `types/session.nim` (add `DisplayName`, `ApiUrl`) |
| P3 | `types/framework.nim`, `types/capabilities.nim`, `types/account_capability_schemas.nim` |
| P4 | `mail/thread.nim`, `mail/serde_thread.nim` |
| P5 | `types/capabilities.nim`, `types/account_capability_schemas.nim` (+ their serde) |
| P6 | `types/session.nim` (Account) |
| P7 | `types/session.nim` (Session), `internal/client.nim`, `serialisation/serde_session.nim` |
| P8 | `mail/email.nim`, `mail/serde_email.nim`, `mail/mailbox_changes_response.nim`, `mail/snippet.nim` |
| P9 | `protocol/methods.nim` (+ `tests/unit/tset_response_projections.nim`) |
| P10 | `tests/wire_contract/*`, `tests/lint/*`, compile-time surface audits |
| P11 | `tests/**`, `src/jmap_client/convenience.nim` |
| P12 | `examples/jmap-cli/**`, `examples/jmap-cli/AUDIT.md`, `docs/design/16-…` |
| P13 | (gates only) |

---

## Phase 0 — `FieldEcho` reader (additive; zero breakage)

**Files:** Modify `src/jmap_client/internal/types/field_echo.nim`. Test:
`tests/unit/tfield_echo_reader.nim`.

- [ ] **Step 1 — add the reader funcs/templates.** In `field_echo.nim`, after the
  `fieldValue` template (line ~61) and before `==`, insert. Ensure `Opt` is in
  scope (`field_echo.nim` already imports `./validation`; if `Opt` is not visible,
  add `import results`). Verified strict-safe from an external module under the L1
  push pragma.

```nim
func isValue*[T](fe: FieldEcho[T]): bool =
  ## ``true`` iff the server echoed a non-null value (``fekValue``).
  fe.kind == fekValue

func isNull*[T](fe: FieldEcho[T]): bool =
  ## ``true`` iff the server echoed JSON ``null`` (``fekNull`` — the property
  ## was affirmatively cleared, RFC 8620 §5.3).
  fe.kind == fekNull

func isAbsent*[T](fe: FieldEcho[T]): bool =
  ## ``true`` iff the property was not echoed (``fekAbsent`` — unchanged / not
  ## requested; distinct from ``isNull`` for incremental ``/changes`` sync).
  fe.kind == fekAbsent

template valueOr*[T](fe: FieldEcho[T], def: untyped): T =
  ## Primary reader, mirroring ``nim-results`` ``Opt.valueOr``: the echoed value
  ## on ``fekValue``; the lazily-evaluated ``def`` on ``fekAbsent``/``fekNull``.
  ## Supersedes the consumer-hand-written ``fieldEchoOr``.
  case fe.kind
  of fekValue: fe.value
  of fekAbsent, fekNull: def

iterator items*[T](fe: FieldEcho[T]): T =
  ## Mirrors ``for v in opt:`` — yields once on ``fekValue``, never otherwise.
  case fe.kind
  of fekValue:
    yield fe.value
  of fekAbsent, fekNull:
    discard

func toOpt*[T](fe: FieldEcho[T]): Opt[T] =
  ## The everyday bridge for render-only callers: lets ``Email.subject`` (Opt)
  ## and ``PartialEmail.subject`` (FieldEcho) flow through one rendering
  ## function. DELIBERATELY collapses ``fekAbsent`` + ``fekNull`` → ``none`` —
  ## an opt-in lossy reader, NOT a converter, NOT erasure of the type (the
  ## ``isAbsent``/``isNull`` predicates remain for offline-sync callers).
  case fe.kind
  of fekValue: Opt.some(fe.value)
  of fekAbsent, fekNull: Opt.none(T)
```

- [ ] **Step 2 — verify the module compiles.** Run: `just build`. Expected: success.
- [ ] **Step 3 — write the reader unit test.** Create
  `tests/unit/tfield_echo_reader.nim` exercising all three states through
  `valueOr`, `isValue/isNull/isAbsent`, `items`, `toOpt` (use the project's
  `testCase`/`mtestblock` harness — copy the import block from a sibling
  `tests/unit/*.nim`). Assert: `fieldValue(5).valueOr(0) == 5`,
  `fieldAbsent(int).valueOr(0) == 0`, `fieldNull(int).valueOr(0) == 0`,
  `toString of items`, `toOpt` some/none per state.
- [ ] **Step 4 — run the test.** Run: `just test` (or `nim c -r tests/unit/tfield_echo_reader.nim`).
  Expected: pass.
- [ ] **Step 5 — commit.**
```bash
git add src/jmap_client/internal/types/field_echo.nim tests/unit/tfield_echo_reader.nim
git commit   # subject: "types/field_echo: add reader API (valueOr/predicates/items/toOpt)"
```

---

## Phase 1 — Relocate `NonEmptyIdSeq` to `primitives.nim`

**Why:** `Thread.emailIds: NonEmptyIdSeq` (P4) must not make `mail/thread.nim`
depend on `mail/email_submission.nim` (which imports `protocol/methods`+`dispatch`)
— a layering inversion. Move the primitive down to L1 `primitives.nim` beside
`NonEmptySeq[T]`.

**Files:** Modify `src/jmap_client/internal/types/primitives.nim` and
`src/jmap_client/internal/mail/email_submission.nim`.

- [ ] **Step 1 — cut the `NonEmptyIdSeq` block** (type + `==`/`$`/`len`/`[]`/`head`/
  `items`/`toSeq` + `parseNonEmptyIdSeq`, currently `email_submission.nim:277–320`)
  and paste it into `primitives.nim` after the `NonEmptySeq[T]` block (~line 343+).
  `Id`/`Idx` are already in scope in `primitives.nim` (verify the imports).
- [ ] **Step 2 — remove the moved block from `email_submission.nim`.** It re-exports
  primitives transitively via `import ../types/primitives`; confirm
  `email_submission.nim` still imports `primitives` (it does) so `NonEmptyIdSeq`
  resolves. Remove any now-duplicate import.
- [ ] **Step 3 — verify the L1 hub re-exports it.** `types.nim` re-exports
  `primitives`; confirm `NonEmptyIdSeq` is surfaced (no `except` hiding it).
- [ ] **Step 4 — build.** Run: `just build`. Expected: success.
- [ ] **Step 5 — commit.**
```bash
git add src/jmap_client/internal/types/primitives.nim src/jmap_client/internal/mail/email_submission.nim
git commit   # subject: "types/primitives: relocate NonEmptyIdSeq from mail layer"
```

---

## Phase 2 — Add the `DisplayName` and `ApiUrl` newtypes (additive)

**Files:** Modify `src/jmap_client/internal/types/session.nim` (define near the top,
above `Account`). The validation logic mirrors the existing `parseAccount`
name-check and `detectApiUrl`.

- [ ] **Step 1 — add `DisplayName`** (Account display name; no control chars,
  RFC 8620 §2 allows empty). Use the existing sealed-string-ops template (cf.
  `defineSealedStringOps(CapabilityUri)` in `capabilities.nim`):
```nim
type DisplayName* {.ruleOff: "objects".} = object
  ## RFC 8620 §2 account display name. Sealed value: no control characters;
  ## empty permitted. Read via ``$``/``string``.
  rawValue: string

defineSealedStringOps(DisplayName)

func parseDisplayName*(raw: string): Result[DisplayName, ValidationError] =
  ## Rejects control characters (RFC 8620 §2 "user-friendly string").
  for ch in raw:
    if ch < ' ' or ch == '\x7F':
      return err(validationError("DisplayName", "contains control characters", raw))
  ok(DisplayName(rawValue: raw))
```
- [ ] **Step 2 — add `ApiUrl`** (non-empty, no embedded newline — the existing
  `detectApiUrl` invariant):
```nim
type ApiUrl* {.ruleOff: "objects".} = object
  ## RFC 8620 §2 JMAP API endpoint URL. Sealed value: non-empty, no embedded
  ## CR/LF (which would break HTTP request-line framing). Read via ``$``/``string``.
  rawValue: string

defineSealedStringOps(ApiUrl)

func parseApiUrl*(raw: string): Result[ApiUrl, ValidationError] =
  if raw.len == 0:
    return err(validationError("ApiUrl", "must not be empty", raw))
  if raw.contains({'\c', '\L'}):
    return err(validationError("ApiUrl", "must not contain newline characters", raw))
  ok(ApiUrl(rawValue: raw))
```
- [ ] **Step 3** — confirm `defineSealedStringOps` and `validationError` are in scope
  in `session.nim` (it imports `./validation`; `defineSealedStringOps` lives in
  `primitives`/`validation` — verify and add the import if missing). Build:
  `just build`. Expected: success (types unused yet — exported, so no warning).
- [ ] **Step 4 — commit.**
```bash
git add src/jmap_client/internal/types/session.nim
git commit   # subject: "types/session: add DisplayName and ApiUrl sealed newtypes"
```

---

## Phase 3 — Pure-ceremony field flips (UFCS-transparent, type-unchanged)

Flip stored-fact-behind-accessor seals whose constructor is infallible and whose
field type is unchanged. Paren-less callers are unaffected (UFCS). Within each
defining module, rename `rawX`→`x*` and delete the accessor; drop `lent`.

**Files:** `types/framework.nim`, `types/capabilities.nim`,
`types/account_capability_schemas.nim`.

- [ ] **Step 1 — `framework.nim` `Comparator`.** `rawProperty: PropertyName` →
  `property*: PropertyName`; delete `func property*`; keep `parseComparator`
  (rename its constructor field). `direction*`/`collation*` already public.
- [ ] **Step 2 — `framework.nim` `AddedItem`.** `rawId: Id` → `id*: Id`; delete
  `func id*`; keep `initAddedItem`. `index*` already public.
- [ ] **Step 3 — `capabilities.nim` `CoreCapabilities`.** Rename the seven
  `rawMaxX: UnsignedInt` fields to `maxX*: UnsignedInt` and
  `rawCollationAlgorithms`→`collationAlgorithms*: HashSet[CollationAlgorithm]`
  (drop `lent`); delete the eight accessor funcs; update `parseCoreCapabilities`
  field names; update `hasCollation` (`c.collationAlgorithms()`→`c.collationAlgorithms`)
  and the `ServerCapability` `hash` site (`c.rawCore.maxSizeUpload.toInt64` →
  `c.rawCore.maxSizeUpload.toInt64`; `rawCore` is still the arm name until P5).
- [ ] **Step 4 — `account_capability_schemas.nim` `SubmissionAccountCapabilities`.**
  `rawMaxDelayedSend`→`maxDelayedSend*`, `rawSubmissionExtensions`→
  `submissionExtensions*`; delete the two accessors; update
  `parseSubmissionAccountCapabilities` + the `hash` site (`e.rawSubmission.maxDelayedSend`).
- [ ] **Step 5 — `account_capability_schemas.nim` `MailAccountCapabilities` (Tier-C
  bounds).** Rename all six `rawX` → public fields **keeping the same types**
  (`maxMailboxesPerEmail*: Opt[UnsignedInt]`, …, `emailQuerySortOptions*:
  HashSet[string]` dropping `lent`, `mayCreateTopLevelMailbox*: bool`); delete the
  six accessors; **keep `parseMailAccountCapabilities` and its `≥1`/`≥100`
  validation unchanged** (Tier-C: parse enforces, raw construction out-of-contract
  — add a one-line `## Tier-C:` comment on the type). Update the `hash` site
  (`e.rawMail.maxSizeAttachmentsPerEmail`).
- [ ] **Step 6 — drop explicit-paren calls in `src/`.** For each flipped accessor
  name, `grep -rn '\.<name>(' src/` and remove the parens where it was an accessor
  call (e.g. `collationAlgorithms()`, `maxSizeUpload()`, `maxDelayedSend()`). The
  internal `asCoreCapabilities`/`asMail…` etc. are unaffected (they read arm
  fields, untouched here).
- [ ] **Step 7 — build.** `just build`. Expected: success. Fix any residual
  `rawX`/paren references the compiler flags.
- [ ] **Step 8 — commit.**
```bash
git add src/jmap_client/internal/types/framework.nim \
        src/jmap_client/internal/types/capabilities.nim \
        src/jmap_client/internal/types/account_capability_schemas.nim
git commit   # subject: "types: flip infallible-ctor capability/comparator seals to fields"
```

---

## Phase 4 — `Thread` + `PartialThread`

**Files:** `mail/thread.nim`, `mail/serde_thread.nim`, plus any `src/` reader.

- [ ] **Step 1 — `Thread`.** Replace the sealed body:
```nim
type Thread* {.ruleOff: "objects".} = object
  ## A Thread groups related Emails (RFC 8621 §3). Non-empty ``emailIds`` is
  ## enforced by the field type ``NonEmptyIdSeq`` (Tier-A), so the read is a
  ## direct public field.
  id*: Id
  emailIds*: NonEmptyIdSeq
```
  Delete `func id*` and `func emailIds*`. Rewrite `parseThread`:
```nim
func parseThread*(id: Id, emailIds: seq[Id]): Result[Thread, ValidationError] =
  ## ``emailIds`` non-empty (RFC 8621 §3) is carried by ``NonEmptyIdSeq``;
  ## ``parseNonEmptyIdSeq`` rejects the empty list with a Thread-flavoured error.
  let ids = parseNonEmptyIdSeq(emailIds).valueOr:
    return err(validationError("Thread", "emailIds must contain at least one Id", ""))
  ok(Thread(id: id, emailIds: ids))
```
  Add `import ../types/primitives` if `NonEmptyIdSeq`/`parseNonEmptyIdSeq` not
  already visible (it imports `../types/primitives` already).
- [ ] **Step 2 — `PartialThread`.** Replace with public fields:
```nim
type PartialThread* {.ruleOff: "objects".} = object
  ## RFC 8621 §3 partial Thread (sparse ``/get``). No invariant — direct fields.
  id*: Opt[Id]
  emailIds*: Opt[seq[Id]]
```
  Delete `func id*`/`func emailIds*` and rewrite `initPartialThread` to set the
  public fields (keep it — serde uses it).
- [ ] **Step 3 — `serde_thread.nim`.** `parseThread(id, emailIds)` call is
  unchanged (still takes `seq[Id]`). The reader `for eid in t.emailIds` now
  iterates `NonEmptyIdSeq` via its `items` iterator — works. `toJson` reading
  `t.emailIds` → use `t.emailIds.toSeq` or iterate (it builds a JSON array).
  Verify and adjust.
- [ ] **Step 4 — sweep `src/` readers** that bound `t.emailIds` to `seq[Id]`:
  `grep -rn 'emailIds' src/` — anywhere it feeds a `seq[Id]`-typed slot, insert
  `.toSeq`. Iteration/`len` are unchanged.
- [ ] **Step 5 — build.** `just build`. Expected: success.
- [ ] **Step 6 — commit.**
```bash
git add src/jmap_client/internal/mail/thread.nim src/jmap_client/internal/mail/serde_thread.nim
git commit   # subject: "mail/thread: read id/emailIds as direct fields (NonEmptyIdSeq)"
```

---

## Phase 5 — Capability case-object arm migration (`ServerCapability`, `AccountCapabilityEntry`)

Expose the discriminator (`kind*` already public) + the typed/JsonNode arms as
public fields, and `uri` as a public field. Keep `asCoreCapabilities`/`asRawData`/
`asMail…`/`asSubmission…` as derived shortcuts reading the now-public arms.

**Files:** `types/capabilities.nim`, `types/account_capability_schemas.nim`, their
serde modules, and `types/session.nim` (`partitionCore` reads `cap.asCoreCapabilities`
— unaffected).

- [ ] **Step 1 — `ServerCapability`.** `rawUri: string` → `uri*: string` (delete
  `func uri*`). Rename each arm field public: `rawCore`→`core*`,
  `rawWebsocketData`→`websocketData*`, `rawMdnData`→`mdnData*`,
  `rawSmimeVerifyData`→`smimeVerifyData*`, `rawBlobData`→`blobData*`,
  `rawQuotaData`→`quotaData*`, `rawContactsData`→`contactsData*`,
  `rawCalendarsData`→`calendarsData*`, `rawSieveData`→`sieveData*`,
  `rawUnknownData`→`unknownData*`. Update `parseServerCapability`,
  `asCoreCapabilities`, `asRawData`, `==`, `$`, `hash` to the new field names
  (mechanical). Add a `## kind↔uri consistency is parseX-guaranteed (Tier-C)` note.
- [ ] **Step 2 — `AccountCapabilityEntry`.** Same: `rawUri`→`uri*`, `rawMail`→`mail*`,
  `rawSubmission`→`submission*`, `rawCoreData`→`coreData*`, `rawWebsocketData`→
  `websocketData*`, …, `rawUnknownData`→`unknownData*`. Update
  `parseAccountCapabilityEntry`, `asMailAccountCapabilities`,
  `asSubmissionAccountCapabilities`, `asRawData`, `==`, `$`, `hash`.
- [ ] **Step 3 — serde.** Find the capability serde (`grep -rln "ServerCapability\|AccountCapabilityEntry" src/jmap_client/internal/serialisation src/jmap_client/internal/mail`)
  and update any direct `raw*` field reads to the public names. (Most serde
  constructs via `parseX` and reads via `asX`, so churn is small.)
- [ ] **Step 4 — verify external bare-`case` compiles.** Add a throwaway check (or a
  temporary block in the P9/P0 test) that an external module can write
  `case cap.kind of ckCore: discard cap.core else: discard` under strict; remove
  it after confirming. (Belt-and-braces for the strict-Rule-3 migration.)
- [ ] **Step 5 — build.** `just build`. Expected: success.
- [ ] **Step 6 — commit.**
```bash
git add src/jmap_client/internal/types/capabilities.nim \
        src/jmap_client/internal/types/account_capability_schemas.nim \
        $(git diff --name-only src/jmap_client/internal/serialisation src/jmap_client/internal/mail)
git commit   # subject: "types: expose capability case-object arms as public fields"
```

---

## Phase 6 — `Account`

**Files:** `types/session.nim` (Account block, lines ~47–129).

- [ ] **Step 1 — flip the fields.** `rawName`→`name*: DisplayName`,
  `rawPolicy`→`policy*: AccountPolicy`, `rawAccountCapabilities`→
  `accountCapabilities*: seq[AccountCapabilityEntry]` (drop `lent`). Delete the
  `name`/`policy`/`accountCapabilities` accessors. Keep `isPersonal`/`isReadOnly`
  (derived funcs), `mailCapability`/`submissionCapability`/`supportsVacationResponse`
  (read `a.accountCapabilities` — now a field). Add a `## Tier-C: the read-only ⇒
  write-cap-filtering relationship is parseAccount-enforced` comment.
- [ ] **Step 2 — `parseAccount`.** Build `name` via `parseDisplayName` (replacing
  the inline control-char loop):
```nim
  let dn = ?parseDisplayName(name)
  ...
  ok(Account(name: dn, policy: policy, accountCapabilities: filtered))
```
  Keep the B12 `filtered` logic exactly. `parseAccount`'s `name: string` parameter
  stays (serde passes a string); it now returns the parse error from
  `parseDisplayName`.
- [ ] **Step 3 — `findCapability`/`hasCapability`/`findCapabilityByUri`** read
  `account.accountCapabilities` (was `accountCapabilities()`) — drop parens where
  explicit. `grep -rn '\.accountCapabilities(' src/` → fix.
- [ ] **Step 4 — sweep `src/`** for `account.name` typed as `string`: now
  `DisplayName`; wrap with `$`/`string()` at string-consuming sites. `grep -rn '\.name\b' src/jmap_client/internal/mail src/jmap_client/internal | …` (scope to Account uses).
- [ ] **Step 5 — build.** `just build`. Expected: success.
- [ ] **Step 6 — commit.**
```bash
git add src/jmap_client/internal/types/session.nim
git commit   # subject: "types/session: read Account fields directly (DisplayName, Tier-C caps)"
```

---

## Phase 7 — `Session` (highest-risk; serde round-trip guard)

**Files:** `types/session.nim` (Session block), `internal/client.nim`,
`serialisation/serde_session.nim` (locate via grep).

- [ ] **Step 1 — flip the fields.** Replace the private `rawX` set with public
  fields: `core*: CoreCapabilities`, `additional*: seq[ServerCapability]`,
  `accounts*: Table[AccountId, Account]`, `primaryAccounts*: Table[string, AccountId]`,
  `username*: string`, `apiUrl*: ApiUrl`, `downloadUrl*`/`uploadUrl*`/`eventSourceUrl*:
  UriTemplate`, `state*: JmapState`. Delete the scalar accessors
  (`capabilities` stays; `accounts`/`primaryAccounts`/`username`/`apiUrl`/`state`/
  the three url accessors are deleted — UFCS keeps paren-less callers working);
  delete `coreCapabilities` (callers move to `.core`). Add `## Tier-C: per-template
  required-variable rules are parseSession-enforced`.
- [ ] **Step 2 — `capabilities()` stays derived** from `core*` + `additional*`
  (rename `s.rawCore`→`s.core`, `s.rawAdditional`→`s.additional`). `findCapability`/
  `findCapabilityByUri`/`primaryAccount`/`findAccount` read the new public fields
  (rename `raw*`).
- [ ] **Step 3 — `parseSession`.** Build `apiUrl` via `parseApiUrl` (the
  `detectApiUrl` check becomes the `ApiUrl` smart constructor — either call
  `?parseApiUrl(apiUrl)` and drop `detectApiUrl`, or keep `detectApiUrl` for
  ordering and wrap the validated string as `ApiUrl(rawValue: apiUrl)` via a
  module-internal construction). Construct `Session(core: …, additional: …,
  accounts: …, apiUrl: apiUrlValue, …)` with the public field names.
- [ ] **Step 4 — `client.nim`.** It reads `client.session…apiUrl`/`state`. `apiUrl`
  is now `ApiUrl` — at the HTTP-request build site use `$session.apiUrl` /
  `string(session.apiUrl)`. `grep -rn 'apiUrl\|\.state\b' src/jmap_client/internal/client.nim`
  and adjust.
- [ ] **Step 5 — `serde_session.nim`.** Construction is via `parseSession`
  (unchanged signature: `apiUrl: string`) — fine. Any direct `raw*` reads → public
  names. `coreCapabilities()` reads → `.core`.
- [ ] **Step 6 — sweep `src/`** for `coreCapabilities`, `\.accounts(`,
  `\.primaryAccounts(`, `\.apiUrl(`, `\.state(`, the three url accessors with
  explicit parens; drop parens / rename `coreCapabilities`→`core`.
- [ ] **Step 7 — build.** `just build`. Expected: success.
- [ ] **Step 8 — round-trip guard.** Add `tests/serde/tsession_roundtrip_s2.nim`
  (or extend an existing session serde test) asserting a captured `/session`
  fixture parses and `toJson`-re-emits byte-identically. Run it.
- [ ] **Step 9 — commit.**
```bash
git add src/jmap_client/internal/types/session.nim src/jmap_client/internal/client.nim \
        src/jmap_client/internal/serialisation/serde_session.nim tests/serde/tsession_roundtrip_s2.nim
git commit   # subject: "types/session: read Session fields directly (ApiUrl, core, Tier-C urls)"
```

---

## Phase 8 — `Email` headers→`Opt`, `MailboxChangesResponse`, `SearchSnippet`

**Files:** `mail/email.nim`, `mail/serde_email.nim`,
`mail/mailbox_changes_response.nim`, `mail/snippet.nim`.

- [ ] **Step 1 — `Email` (full).** Change three non-default §4.2 fields to `Opt`
  (lines ~487/490/492): `headers*: Opt[seq[EmailHeader]]`,
  `requestedHeaders*: Opt[Table[HeaderPropertyKey, HeaderValue]]`,
  `requestedHeadersAll*: Opt[Table[HeaderPropertyKey, seq[HeaderValue]]]`. Update the
  docstrings (cite RFC 8621 §4.2 — not a default property, like `bodyStructure`).
  **Leave the six default fields bare** (`bodyValues`/`textBody`/`htmlBody`/
  `attachments`/`hasAttachment`/`preview`).
- [ ] **Step 2 — `ParsedEmail`.** Same three fields → `Opt` (lines ~603/606/608).
- [ ] **Step 3 — `serde_email.nim`.** For `headers`/`requestedHeaders`/
  `requestedHeadersAll`: absent → `Opt.none`, present → `Opt.some(parsed)`
  (mirror the existing `bodyStructure: Opt` deserialisation). Update `toJson` to
  emit only when `some`.
- [ ] **Step 4 — `MailboxChangesResponse`.** Delete the `forwardChangesFields`
  template (lines ~40–75) and its invocation (`forwardChangesFields(MailboxChangesResponse)`).
  `base*`/`updatedProperties*` stay public. Update the module docstring. `fromJson`
  is unchanged.
- [ ] **Step 5 — sweep `src/`** for `r.created`/`r.updated`/`r.destroyed`/
  `r.accountId`/`r.oldState`/`r.newState`/`r.hasMoreChanges` on a
  `MailboxChangesResponse` → `r.base.<field>`. (`grep -rn` scoped to mailbox-changes
  callers.) **Feasibility-confirmed NO-OP in `src/`:** no external code reads these
  forwarders (the only `r.base.<field>` reads are inside the template being
  deleted); the grep is a belt-and-braces confirmation, expect zero edits.
- [ ] **Step 6 — `snippet.nim`.** Add a one-line comment on `SearchSnippet`
  documenting the intentional always-present (`emailId: Id`) vs optional
  (`subject`/`preview: Opt[string]`) asymmetry (no code change).
- [ ] **Step 7 — build.** `just build`. Expected: success.
- [ ] **Step 8 — commit.**
```bash
git add src/jmap_client/internal/mail/email.nim src/jmap_client/internal/mail/serde_email.nim \
        src/jmap_client/internal/mail/mailbox_changes_response.nim src/jmap_client/internal/mail/snippet.nim
git commit   # subject: "mail: model non-default Email headers as Opt; flatten MailboxChanges"
```

---

## Phase 9 — `SetResponse` projections (additive)

**Files:** `protocol/methods.nim`. Test: `tests/unit/tset_response_projections.nim`.

- [ ] **Step 1 — add the six iterators** after the `SetResponse` definition
  (~line 280). Use strict-safe Result inspection (`case r.isOk of true:
  r.unsafeValue …`):
```nim
iterator created*[T, U](r: SetResponse[T, U]): tuple[id: CreationId, value: T] =
  ## Successful creates (CreationId → created entity). The typed
  ## ``createResults`` table remains for callers needing the SetError rail.
  for cid, res in r.createResults:
    case res.isOk
    of true: yield (cid, res.unsafeValue)
    of false: discard

iterator createFailures*[T, U](r: SetResponse[T, U]): tuple[id: CreationId, error: SetError] =
  for cid, res in r.createResults:
    case res.isOk
    of false: yield (cid, res.unsafeError)
    of true: discard

iterator updated*[T, U](r: SetResponse[T, U]): tuple[id: Id, serverEcho: Opt[U]] =
  ## Successful updates (Id → the RFC 8620 §5.3 server-changed-property echo,
  ## ``Opt.none`` when the server echoed nothing). The common "isOk, ignore the
  ## echo" path is one ``for``; the typed table remains for echo-consuming callers.
  for id, res in r.updateResults:
    case res.isOk
    of true: yield (id, res.unsafeValue)
    of false: discard

iterator updateFailures*[T, U](r: SetResponse[T, U]): tuple[id: Id, error: SetError] =
  for id, res in r.updateResults:
    case res.isOk
    of false: yield (id, res.unsafeError)
    of true: discard

iterator destroyed*[T, U](r: SetResponse[T, U]): Id =
  ## Successfully destroyed ids.
  for id, res in r.destroyResults:
    case res.isOk
    of true: yield id
    of false: discard

iterator destroyFailures*[T, U](r: SetResponse[T, U]): tuple[id: Id, error: SetError] =
  for id, res in r.destroyResults:
    case res.isOk
    of false: yield (id, res.unsafeError)
    of true: discard
```
  (`Table` iteration and `unsafeValue`/`unsafeError` are strict-safe + raises-free;
  confirm `unsafeError` exists in the vendored `nim-results` — it does. The
  generic `U` is unused in `created`/`destroyed`/`*Failures`; that is fine for an
  iterator on `SetResponse[T, U]`.)
- [ ] **Step 2 — build.** `just build`. Expected: success.
- [ ] **Step 3 — unit test.** `tests/unit/tset_response_projections.nim`: build a
  `SetResponse` with mixed ok/err entries; assert each iterator yields the right
  pairs/count. Run `just test`.
- [ ] **Step 4 — commit.**
```bash
git add src/jmap_client/internal/protocol/methods.nim tests/unit/tset_response_projections.nim
git commit   # subject: "protocol/methods: add SetResponse success/failure projections"
```

---

## Phase 10 — Regenerate the wire contract + update surface audits

**Files:** `tests/wire_contract/public-api.txt`, `…/type-shapes.txt`, the
compile-time surface-audit tests (`grep -rln "public-api\|type-shapes\|surface" tests/`).

- [ ] **Step 1 — regenerate.** Run `just freeze-api`, then `just freeze-type-shapes`,
  then **`just freeze-error-messages`** (the S0 oracle + H15 recipes). Inspect each
  diff: api/type-shapes should show the new public fields, the removed accessors,
  `headers→Opt`, the capability arms, the dropped `MailboxChangesResponse`
  forwarders, and the new `FieldEcho`/`SetResponse` symbols — and nothing
  unexpected. **error-messages.txt** changes because S2 adds `parseDisplayName`/
  `parseApiUrl` (new `DisplayName`/`ApiUrl` validation messages) and P6 replaces the
  inline `"Account"`/`"name contains control characters"` message with
  `parseDisplayName`'s `"DisplayName"`/`"contains control characters"` (and P7 may
  shift the `detectApiUrl` messages); `lint-error-messages` is part of `just ci`
  (justfile), so this MUST be regenerated or P13 fails H15.
- [ ] **Step 2 — update compile-time surface audits.** Any in-tree test asserting
  the *presence of the old accessors* or *absence of the new fields* updates to the
  new surface (assert new public fields present, retired accessors absent).
- [ ] **Step 3 — verify the lints pass.** Run `just lint-public-api` and
  `just lint-type-shapes`. Expected: pass (snapshot == oracle).
- [ ] **Step 4 — commit.**
```bash
git add tests/wire_contract/public-api.txt tests/wire_contract/type-shapes.txt tests/wire_contract/error-messages.txt $(git diff --name-only tests/lint tests/unit 2>/dev/null)
git commit   # subject: "tests/wire_contract: regenerate surface after read-model flip"
```

---

## Phase 11 — Test sweep + `convenience.nim` (subagent-driven, compiler-gated)

**Files:** `tests/**`, `src/jmap_client/convenience.nim`.

- [ ] **Step 1 — enumerate breakage.** Run `just test` and collect every compile
  error. Group by transformation: (a) `FieldEcho` reads → `valueOr`/predicates/
  `toOpt` (delete local `fieldEchoOr`); (b) `Thread.emailIds` `seq`→`NonEmptyIdSeq`
  (`.toSeq` where a `seq` is needed); (c) `Account.name`/`Session.apiUrl` newtype
  unwrap; (d) `coreCapabilities()`→`core`, dropped accessor parens; (e)
  `Email.headers`/`requestedHeaders*` now `Opt` (unwrap); (f)
  `MailboxChangesResponse` `r.created`→`r.base.created`; (g) capability arm reads.
- [ ] **Step 2 — sweep with subagents.** Dispatch one subagent per `tests/`
  subdirectory (`unit/`, `serde/`, `property/`, `compliance/`, `stress/`,
  `integration/`) with the transformation list and the rule "tests adapt to the
  API; never change `src/` to placate a test." Each returns its diff; review and
  re-run `nim c -r` on the touched files.
- [ ] **Step 3 — `convenience.nim`.** Apply the same transformations (it is a normal
  consumer; if a combinator no longer composes, fix it — a finding, not a
  constraint).
- [ ] **Step 4 — run the fast suite.** `just test`. Expected: all pass.
- [ ] **Step 5 — commit.**
```bash
git add tests/ src/jmap_client/convenience.nim
git commit   # subject: "tests, convenience: migrate read sites to uniform read model"
```

---

## Phase 12 — CLI re-bench + AUDIT + consumer narrative

**Files:** `examples/jmap-cli/**`, `examples/jmap-cli/AUDIT.md`, `docs/design/16-…`.

- [ ] **Step 1 — rewrite CLI reads** to the uniform idiom: delete
  `commands/email_query.nim` `func fieldEchoOr` (use hub `valueOr`); use direct
  fields for `Thread`/`Account`/`Session`/capabilities; `Email.headers` via `Opt`;
  capability bare-`case` where it reads cleaner. Keep the CLI public-API-only
  (`check-public-only.sh`).
- [ ] **Step 2 — build + run the bench** against a live server (`just stalwart-up`
  then the CLI's smoke commands) to confirm real reads work end-to-end.
- [ ] **Step 3 — update `AUDIT.md`.** Add an "S2 resolution" section mapping each
  R6 read-model finding to *resolved* (FieldEcho reader, same-field flip, accessor-
  vs-field, `lent`, `Thread`); mark the **deferred-to-S3** items explicitly
  (mailbox is-inbox three-idioms, `bodyValues` `import std/tables`,
  `decodedTextBody`). Do not claim findings S2 didn't touch.
- [ ] **Step 4 — update `docs/design/16-api-from-the-consumers-chair.md`** to reflect
  the now-uniform read model.
- [ ] **Step 5 — commit.**
```bash
git add examples/jmap-cli/ docs/design/16-api-from-the-consumers-chair.md
git commit   # subject: "examples/jmap-cli: re-bench against uniform read model; close R6"
```

---

## Phase 13 — Gates

- [ ] **Step 1 — `just ci`.** Expected: "All CI checks passed!" Fix any
  reuse/fmt/lint/analyse/test failure and re-run until green. (`just fmt` first if
  fmt-check fails.)
- [ ] **Step 2 — full live suite, exact order.** `just clean && just jmap-reset &&
  just test-full`. If `test-full` fails, fix, then re-run the **whole**
  `clean → jmap-reset → test-full` sequence until "All shards passed" against
  Cyrus + Stalwart + James.
- [ ] **Step 3 — final state.** Update this plan's STATE block (all phases ✅ with
  SHAs). Do **not** push/PR/merge without explicit user confirmation.

---

## Self-review (writing-plans)

- **Spec coverage:** every spec rule §4–§10 + decision §15/§16 maps to a phase
  (Rule 1→P3-P8; Rule 2 newtypes→P2,P4,P6,P7; Rule 3→P6,P7; Rule 4→P3,P4,P7,P8;
  Rule 5→P0,P8; Rule 6→P5; Rule 7→P8,P9). DP-by-DP: DP1→P3-P8, DP2/DP4→P0,
  DP3→P1+P4, DP5→P3, DP6→P8(doc), DP7→P5, DP8→P9, DP9→P8.
- **No placeholders:** new/additive code (P0 reader, P2 newtypes, P9 projections) is
  given in full; flips are exact old→new edits against the read source; sweeps give
  the grep + transformation rule (the compiler is the objective gate).
- **Type consistency:** field names are stable across phases (`core*`,
  `accountCapabilities*`, `emailIds*: NonEmptyIdSeq`, `apiUrl*: ApiUrl`,
  `name*: DisplayName`, `headers*: Opt[…]`); `serverEcho` (not `echo`) in P9.
- **Green-per-phase:** P0–P9 each end on `just build`; the surface lints are
  deferred to P10 (contract regen) by design; both gates at P13.
