# S4 — one-shots, easy-path, dissolve quarantine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use
> `superpowers:subagent-driven-development` to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax. **Design spec:**
> `docs/superpowers/specs/2026-06-16-s4-one-shots-easy-path-design.md` (gitignored).
> **Campaign brief:** `docs/superpowers/plans/2026-06-16-CAMPAIGN-HANDOFF-S4-AND-TRIAGE.md`.
> **The RFC text in `docs/rfcs/` is authoritative**; reviewers validate against it,
> not against this plan.

**Goal:** put the build-dispatch-extract one-shots first-class on the always-on
hub, dissolve the `convenience` quarantine, and root-fix the structured send path —
so a future email-client developer reaches for the library directly (P7); clears
root causes R1 + R4.

**Architecture:** a new additive `jeMethod` arm + a `fulfil` collapse helper let
single-purpose one-shots return flat `Result[T, JmapError]`; a new L4
`one_shot.nim` holds `connect` / the bare-gets / the query-then-gets /
`sendPlainText`; the eight pure combinators move to an internal L3 module
re-exported by root (the public `jmap_client/convenience` path is deleted); the
submission set path gains a typed `emailId` forward-reference and a
smart-constructed `EmailSubmissionSetSpec` feeding one total `addEmailSubmissionSet`.

**Tech stack:** Nim, `--mm:arc`, nim-results (`Result`/`Opt`/`?`/`valueOr`/`.lift`),
the L1–L3 `{.push raises: [], noSideEffect.}` + `strictCaseObjects` purity battery,
L4 `{.push raises: [].}`, nimalyzer (`complexity ≤ 10`, `hasdoc`,
`caseStatements min 2`), the H-lint battery + the oracle-frozen wire contract.

---

## STATE / HANDOFF BLOCK  ← flip this in the same commit as each task

- **Branch:** `api/s4-one-shots` (off `main`). NEVER implement on `main`.
- **Spec decisions (user-locked):** full dissolve; `jeMethod` arm + `fulfil`;
  one-shots flat `Result[T, JmapError]` (general `get`/`getBoth`/`getAll` keep
  `MethodOutcome`); `sendPlainText` explicit two mailboxes (Drafts→Sent +
  `onSuccessUpdateEmail`, RFC §7.5.1); extended scope (root-fix the structured
  send path).
- **Gates (run by the controller):** (1) `just ci`; (2) `just clean &&
  just jmap-reset && just test-full` until "All shards passed".

| Task | Title | Status | Commit |
|---|---|---|---|
| 0 | `jeMethod` arm + `fulfil` + H15 lockstep | ☐ NOT STARTED | — |
| 1 | typed `emailId` forward-reference | ☐ NOT STARTED | — |
| 2 | `EmailSubmissionSetSpec` + one total `addEmailSubmissionSet` | ☐ NOT STARTED | — |
| 3 | dissolve the `convenience` quarantine | ☐ NOT STARTED | — |
| 4 | the one-shot module (`connect`/gets/queries/`sendPlainText`) | ☐ NOT STARTED | — |
| 5 | re-bench `examples/jmap-cli` + reconcile AUDIT / design 16 | ☐ NOT STARTED | — |
| 6 | final snapshot reconciliation + BOTH gates | ☐ NOT STARTED | — |

**Dependency order:** 0 → (1, 2 may interleave; 2 depends on 1's `IdOrCreationRef`
emailId only inside `sendPlainText`, not in the builder) → 3 → 4 (needs 0's
`fulfil`, 2's total builder, 3's relocated combinators) → 5 (needs 4) → 6.

---

## RIPPLE-COMPLETENESS LEDGER  (fresh grep, 2026-06-16 — verify before each task)

**`jeMethod`/`fulfil` (Task 0):**
- `src/jmap_client/internal/protocol/jmap_error.nim` — add `MethodFault`,
  `methodFault`, `message(MethodFault)`, `$`, the `jeMethod` arm in `JmapErrorKind`
  + `JmapError` + `message(JmapError)`, `jmapMethod`, `fulfil`. Add `MethodName`
  import (currently absent — `../types/methods_enum`; verify it carries `MethodName`).
- `scripts/freeze_error_messages.nim` (je-block ~205-240, docstring count) **and**
  `tests/lint/h15_error_message_snapshot.nim` (je-block ~251-297, samples() doc
  ~34-38) — add a `je8` `jeMethod` sample **in lockstep**.
- `tests/wire_contract/error-messages.txt` (regen → 42 samples),
  `tests/wire_contract/type-shapes.txt` (the `JmapError` shape gains the arm),
  `tests/wire_contract/public-api.txt` (`MethodFault`, `methodFault`, `jmapMethod`,
  `fulfil`).

**Typed `emailId` (Task 1):**
- `src/jmap_client/internal/mail/email_submission.nim:138` (field `rawEmailId: Id`),
  `:153-164` (`parseEmailSubmissionBlueprint` `emailId: Id`), `:170` (accessor).
- `src/jmap_client/internal/mail/serde_email_submission.nim:156-171` (fromJson),
  `:208,216` (toJson `node["emailId"] = bp.emailId.toJson()`).
- Call sites → pass `directRef(id)`: `tests/mfixtures.nim:2402,2412`;
  `tests/mproperty.nim:3988,3995,4006`;
  `tests/unit/mail/temail_submission_blueprint.nim:27,41,75,84,91,138,164`;
  `tests/unit/mail/tsubmission_cid_invariant.nim:38`;
  integration `temail_bob_receives_alice_delivery_live.nim:62`,
  `temail_submission_changes_live.nim:141`,
  `temail_submission_full_lifecycle_live.nim:64`,
  `temail_submission_on_success_update_live.nim:90`,
  `temail_submission_set_baseline_live.nim:60`,
  `temail_submission_on_success_destroy_live.nim:72`,
  `temail_submission_multi_recipient_live.nim:73`,
  `temail_submission_cancel_pending_live.nim:65`,
  `temail_submission_get_delivery_status_live.nim:70`, `mlive.nim:1505`.
- Snapshots: `type-shapes.txt:560` (EmailSubmissionBlueprint shape),
  `public-api.txt` (`parseEmailSubmissionBlueprint` signature).

**`EmailSubmissionSetSpec` + total builder (Task 2):**
- `src/jmap_client/internal/mail/submission_builders.nim:116-134` (delete simple
  `addEmailSubmissionSet`), `:141-252` (delete `onSuccessRefs`,
  `validateOnSuccessCids`, `addEmailSubmissionAndEmailSet` — move the validation
  into `parseEmailSubmissionSet`).
- `src/jmap_client/internal/mail/email_submission.nim` — add `EmailSubmissionSetSpec`
  + `parseEmailSubmissionSet` (host the moved `validateOnSuccessCids` logic + the
  `onSuccessRefs` iterator).
- Call sites of `addEmailSubmissionSet` (→ `parseEmailSubmissionSet` + total builder
  + `getBoth`): `tests/protocol/tmail_builders.nim:1080`;
  integration `temail_bob_receives_alice_delivery_live.nim:70`,
  `temail_submission_changes_live.nim:148,264`,
  `temail_submission_full_lifecycle_live.nim:72,108,133`,
  `temail_submission_set_baseline_live.nim:68`,
  `temail_submission_cancel_pending_live.nim:73,109`,
  `temail_submission_filter_completeness_live.nim:256`,
  `temail_submission_multi_recipient_live.nim:81`,
  `temail_submission_get_delivery_status_live.nim:78`, `mlive.nim:1513`.
- Call sites of `addEmailSubmissionAndEmailSet`:
  `tests/unit/mail/tsubmission_cid_invariant.nim:53,72,88,102` (the cid-invariant
  unit test now targets `parseEmailSubmissionSet`),
  `tests/protocol/tmail_builders.nim:761`,
  integration `temail_submission_on_success_update_live.nim:98`,
  `temail_submission_on_success_destroy_live.nim:80`;
  example `examples/jmap-cli/commands/email_send.nim:156` (Task 5).
- Snapshots: `public-api.txt:661,666`, `type-shapes.txt` (new spec type shape).

**Dissolve convenience (Task 3):**
- Move `src/jmap_client/convenience.nim` → `src/jmap_client/internal/mail/combinators.nim`
  (flip `import jmap_client` → internal leaf imports); re-export from
  `src/jmap_client/internal/mail.nim` (the mail hub). Delete the public path.
- Importers → plain `import jmap_client`: `tests/protocol/tconvenience.nim:17`,
  `tests/compile/tcompile_a1d_mail_hub_surface.nim:27`,
  `examples/jmap-cli/commands/email_query.nim:13`,
  `examples/jmap-cli/commands/email_sync.nim:17` (Task 5 for the examples).
- Lints/snapshots: `tests/wire_contract/module-paths.txt:2` (remove the line);
  `tests/lint/h13_module_path_lock.nim` (snapshot lock); `public-api.txt:2,7,14-24`
  (remove the convenience section header; combinators reappear under root);
  `type-shapes.txt:3` (header); `tests/lint/h16_public_api_snapshot.nim:7`;
  `tests/lint/h11_typed_builder_no_jsonnode.nim:18,40` (the scan list names
  `convenience.nim` — repoint to `internal/mail/combinators.nim`);
  `tests/lint/th10_internal_boundary.nim:71` (the convenience message).

**One-shot module (Task 4):**
- New `src/jmap_client/internal/one_shot.nim`; `src/jmap_client.nim` (add
  `import …/internal/one_shot` + `export one_shot`).
- Snapshots: `public-api.txt`, `type-shapes.txt` (the one-shots, `QueryThenGet[T]`,
  `SentEmail`).

**Bench + docs (Task 5):** `examples/jmap-cli/commands/{email_send,email_query,
email_sync,session,cli_session,mailbox,email_read,thread,identity}.nim` (adopt the
one-shots + plain import + the new submission builder);
`examples/jmap-cli/AUDIT.md`; `docs/design/16-api-from-the-consumers-chair.md`;
`examples/jmap-cli/check-public-only.sh`.

---

## Task 0 — `jeMethod` arm + `fulfil` collapse helper + H15 lockstep

**Files:** Modify `src/jmap_client/internal/protocol/jmap_error.nim`,
`scripts/freeze_error_messages.nim`, `tests/lint/h15_error_message_snapshot.nim`;
regenerate `tests/wire_contract/{error-messages,type-shapes,public-api}.txt`.

- [ ] **Step 1 — confirm `MethodName` import.** In `jmap_error.nim`, verify whether
  `MethodName` is in scope (it is used in the new `MethodFault`). If not, add
  `import ../types/methods_enum` (it is L1 — no cycle). `MethodError` is already in
  scope via `../types/errors`.

- [ ] **Step 2 — add the sub-fault, arm, constructor, message, and collapse.** In
  `jmap_error.nim`, after the `ProtocolFault` block add `MethodFault`; extend
  `JmapErrorKind` with `jeMethod`; add the `JmapError` arm; add `jmapMethod`; add the
  `message` arm; and add `fulfil` near `MethodOutcome`:

```nim
type MethodFault* = object
  ## ``jeMethod`` payload (RFC 8620 §3.6.2). The single JMAP method whose
  ## server-side execution returned a method-level error. A one-shot, being
  ## single-purpose, lifts it onto the rail — there is no sibling method whose
  ## result it must preserve as data, so the data-not-rail rule (which protects a
  ## batch's other calls) does not apply.
  methodName*: MethodName
  error*: MethodError

func methodFault*(methodName: MethodName, error: MethodError): MethodFault =
  ## Constructs a ``MethodFault``.
  MethodFault(methodName: methodName, error: error)

func message*(mf: MethodFault): string =
  ## Human-readable diagnostic — reads "method Email/get failed: <error>".
  ## ``$mf.methodName`` is the wire method name (string-backed enum).
  "method " & $mf.methodName & " failed: " & mf.error.message

func `$`*(mf: MethodFault): string =
  ## Delegates to ``message`` for the single canonical projection.
  mf.message
```

- Extend `JmapErrorKind` (add as the final arm, additive):
  `jeMethod ## a single method returned a server method-level error (one-shot path)`.
- Extend `JmapError`: `of jeMethod:` `  method*: MethodFault` (field name `method` is
  fine as an object field; if `--styleCheck`/keyword issues arise, use `methodFault`).
- Add the constructor:

```nim
func jmapMethod*(fault: MethodFault): JmapError =
  ## Lifts a single method's server-level error onto the rail (the one-shot
  ## fail-fast path). The structured ``get`` / ``getBoth`` keep it as data.
  JmapError(kind: jeMethod, method: fault)
```

- Add the `message(JmapError)` arm: `of jeMethod: err.method.message`.
- Add `fulfil` after `methodFailure`:

```nim
func fulfil*[T](outcome: MethodOutcome[T], methodName: MethodName): Result[T, JmapError] =
  ## Collapses a single method's outcome onto the one rail: the value on
  ## ``mokValue``; a ``jeMethod`` fault on ``mokMethodError``. The fail-fast
  ## counterpart to reading ``MethodOutcome`` directly — for callers (and every
  ## one-shot) that issued a single method and want a flat result. ``get`` /
  ## ``getBoth`` / ``getAll`` are unchanged: a batch keeps method errors as data.
  case outcome.kind
  of mokValue: ok(outcome.value)
  of mokMethodError: err(jmapMethod(methodFault(methodName, outcome.error)))
```

- [ ] **Step 3 — build.** `just build` (then `nim c -r` a one-line driver if useful).
  Expect: clean. If the `method` field name trips `styleCheck`/keyword handling,
  rename the field to `methodFault*: MethodFault` and adjust `jmapMethod` + the
  message arm.

- [ ] **Step 4 — add the H15 `je8` sample IN LOCKSTEP.** Append after `je7` in BOTH
  `scripts/freeze_error_messages.nim` and `tests/lint/h15_error_message_snapshot.nim`
  (identical label + value):

```nim
let je8 = jmapMethod(methodFault(mnEmailGet, methodError("serverFail", Opt.some("internal error"))))
emit("jmapMethod(methodFault(mnEmailGet, methodError(\"serverFail\", Opt.some(\"internal error\"))))", je8.message)
```

  Update the docstring counts (`41` → `42`) in both files. Ensure `mnEmailGet` and
  `methodError` are importable in both (the freeze script imports `jmap_client` +
  leaves; add `methods_enum`/`errors` imports if needed).

- [ ] **Step 5 — regenerate the snapshots.** `just freeze-error-messages`,
  `just freeze-type-shapes`, `just freeze-api`. Review the diffs: `error-messages.txt`
  gains the `je8` block; `type-shapes.txt`'s `JmapError` gains the `jeMethod` arm;
  `public-api.txt` gains `MethodFault`, `methodFault`, `jmapMethod`, `fulfil`. No
  other churn.

- [ ] **Step 6 — fast suite.** `just test`. Expect green (H15 lint passes — the live
  sample list and the snapshot now agree).

- [ ] **Step 7 — controller commits** `protocol: add the jeMethod arm and fulfil
  one-shot collapse` and flips the STATE row.

## Task 1 — typed `emailId` forward-reference

**Files:** `src/jmap_client/internal/mail/email_submission.nim`,
`src/jmap_client/internal/mail/serde_email_submission.nim`; the call-site ledger
above; `tests/wire_contract/{type-shapes,public-api}.txt`.

- [ ] **Step 1 — change the type.** In `email_submission.nim`: field
  `rawEmailId: Id` → `rawEmailId: IdOrCreationRef`; `parseEmailSubmissionBlueprint`'s
  `emailId: Id` → `emailId: IdOrCreationRef`; the `emailId` accessor returns
  `IdOrCreationRef`. (`IdOrCreationRef`, `directRef`, `creationRef` already live in
  this module — no new import.)

- [ ] **Step 2 — serde.** In `serde_email_submission.nim`: `toJson` (line ~216)
  already calls `bp.emailId.toJson()` — confirm `IdOrCreationRef.toJson` exists
  (it is used for onSuccess keys; reuse it; it renders `#cid` / the bare id). For
  `fromJson` (lines ~156-171), parse the `emailId` node into an `IdOrCreationRef`:
  a value beginning `#` → `creationRef(parseCreationId(rest))`; otherwise
  `directRef(parseIdFromServer(value))`. (Match the existing onSuccess-key parse for
  `IdOrCreationRef` — reuse its helper if one exists.)

- [ ] **Step 3 — migrate call sites.** For every `parseEmailSubmissionBlueprint(...,
  emailId = <id>, ...)` in the ledger, wrap the existing id as `directRef(<id>)`
  (these are all existing-email references, not same-request creations). Transformation
  pattern (apply at each listed `file:line`):
  - before: `parseEmailSubmissionBlueprint(idn, emailId, envelope)`
  - after:  `parseEmailSubmissionBlueprint(idn, directRef(emailId), envelope)`
  Where a test reads back `.emailId` and asserts it equals an `Id`, update to assert
  the `IdOrCreationRef` (`directRef(expectedId)` or via `asDirectRef`).

- [ ] **Step 4 — build + sweep all tests/.** `just build`; then compile each touched
  test file standalone (`nim c -r tests/unit/mail/temail_submission_blueprint.nim`,
  etc.) — `UnusedImport`/`strictDefs` are hard errors, so a standalone compile catches
  breakage the fast suite's skip-list might hide.

- [ ] **Step 5 — regen `freeze-type-shapes` + `freeze-api`; `just test`.**

- [ ] **Step 6 — controller commits** `mail/submission: type emailId as a
  forward-reference` and flips STATE.

## Task 2 — `EmailSubmissionSetSpec` + one total `addEmailSubmissionSet`

**Files:** `src/jmap_client/internal/mail/email_submission.nim` (the spec + ctor),
`src/jmap_client/internal/mail/submission_builders.nim` (one total builder, delete
both old); the call-site ledger; snapshots.

- [ ] **Step 1 — the validated spec type.** In `email_submission.nim` add (Pattern-A
  sealed, `{.ruleOff: "objects".}`):

```nim
type EmailSubmissionSetSpec* {.ruleOff: "objects".} = object
  ## A validated EmailSubmission/set request body (RFC 8621 §7.5): create / update
  ## / destroy plus the onSuccessUpdateEmail / onSuccessDestroyEmail extensions,
  ## with the RFC 8620 §5.3 onSuccess↔create cross-reference invariant already
  ## proven. Copyable — composes with ``?`` — so the builder that consumes it is
  ## total (no uncopyable-RequestBuilder-in-Result).
  rawIfInState: Opt[JmapState]
  rawCreate: Opt[Table[CreationId, EmailSubmissionBlueprint]]
  rawUpdate: Opt[NonEmptyEmailSubmissionUpdates]
  rawDestroy: Opt[Referencable[seq[Id]]]
  rawOnSuccessUpdateEmail: Opt[NonEmptyOnSuccessUpdateEmail]
  rawOnSuccessDestroyEmail: Opt[NonEmptyOnSuccessDestroyEmail]
```

  with hub-private accessors (`ifInState`, `create`, `update`, `destroy`,
  `onSuccessUpdateEmail`, `onSuccessDestroyEmail`) the builder reads. Move the
  `onSuccessRefs` iterator and the `validateOnSuccessCids` body (from
  `submission_builders.nim:141-184`) into the smart constructor:

```nim
func parseEmailSubmissionSet*(
    create: Opt[Table[CreationId, EmailSubmissionBlueprint]] =
      Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    update: Opt[NonEmptyEmailSubmissionUpdates] =
      Opt.none(NonEmptyEmailSubmissionUpdates),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    onSuccessUpdateEmail: Opt[NonEmptyOnSuccessUpdateEmail] =
      Opt.none(NonEmptyOnSuccessUpdateEmail),
    onSuccessDestroyEmail: Opt[NonEmptyOnSuccessDestroyEmail] =
      Opt.none(NonEmptyOnSuccessDestroyEmail),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): Result[EmailSubmissionSetSpec, NonEmptySeq[ValidationError]] =
  ## Validates the RFC 8620 §5.3 cross-reference — every ``creationRef(cid)`` in
  ## either onSuccess* map MUST name a key in ``create`` — accumulating ALL bad
  ## references, then seals an ``EmailSubmissionSetSpec``. ``icrDirect`` refs are
  ## server-persisted ids, exempt.
  # accumulate violations (see email_update.nim pattern 7); err with
  # parseNonEmptySeq(violations).get() when non-empty, else ok(spec).
```

  Keep `complexity ≤ 10` (decompose the accumulation into a helper if needed). Note:
  the validation now produces a *seq* of violations (one per bad ref), matching the
  sibling `NonEmptySeq[ValidationError]` convention.

- [ ] **Step 2 — one total builder.** Replace the whole §"addEmailSubmissionSet …
  simple overload" + §"addEmailSubmissionAndEmailSet" region of
  `submission_builders.nim` with one total builder:

```nim
func addEmailSubmissionSet*(
    b: sink RequestBuilder, accountId: AccountId, spec: EmailSubmissionSetSpec
): (RequestBuilder, EmailSubmissionHandles) =
  ## EmailSubmission/set (RFC 8621 §7.5). The implicit Email/set the server runs
  ## (§7.5 ¶3) is surfaced through ``handles.implicit`` — present when the spec's
  ## onSuccess* drove a change, ``Opt.none`` at extraction otherwise. Total: the
  ## spec proved the §5.3 cross-reference at construction, so there is no Result
  ## and no uncopyable-builder move ceremony.
  # body: build SetRequest from spec.create/update/destroy + ifInState; splice
  # spec.onSuccessUpdateEmail/onSuccessDestroyEmail into args (as today, lines
  # 233-237); addInvocation(b, mnEmailSubmissionSet, ...); build EmailSubmissionHandles
  # exactly as today (lines 246-251). Return the bare tuple.
```

  Delete `onSuccessRefs` + `validateOnSuccessCids` from this file (moved to the spec).

- [ ] **Step 3 — migrate every call site.** Transformation patterns:
  - *Simple set* (was `addEmailSubmissionSet(b, acct, create=X, update=Y, ...)`
    returning `ResponseHandle`): now
    ```nim
    let spec = parseEmailSubmissionSet(create = X, update = Y, ...).get()  # invariant: literal/valid inputs
    let (b1, handles) = b.addEmailSubmissionSet(acct, spec)
    ```
    Extraction `dr.get(handle)` → `dr.getBoth(handles)` then read `.primary`
    (`MethodOutcome[EmailSubmissionSetResponse]`).
  - *Compound* (was the fallible `addEmailSubmissionAndEmailSet` with the
    `var r …; move(r.value)` ceremony): now
    ```nim
    let spec = ?parseEmailSubmissionSet(create = subCreate, onSuccessUpdateEmail = onSucc)
    let (b1, handles) = b.addEmailSubmissionSet(acct, spec)
    ```
    (the `var r`/`move` ceremony is deleted — the builder is total).
  Apply at every `file:line` in the Task-2 ledger. The cid-invariant unit test
  (`tsubmission_cid_invariant.nim`) now asserts on `parseEmailSubmissionSet`'s
  `Result` (the validation moved there), not on the builder.

- [ ] **Step 4 — build + sweep all tests/** (standalone-compile the touched files,
  incl. the live `temail_submission_*` set under `tests/integration/live/`).

- [ ] **Step 5 — regen `freeze-api` + `freeze-type-shapes`; `just test`.**

- [ ] **Step 6 — controller commits** `mail/submission: one total set builder via a
  validated spec` and flips STATE.

## Task 3 — dissolve the `convenience` quarantine

**Files:** move `src/jmap_client/convenience.nim` →
`src/jmap_client/internal/mail/combinators.nim`; `src/jmap_client/internal/mail.nim`;
the lint/snapshot ledger; the test importers.

- [ ] **Step 1 — relocate + reimport.** `git mv src/jmap_client/convenience.nim
  src/jmap_client/internal/mail/combinators.nim`. Replace its `import jmap_client`
  with the internal leaf imports it actually needs (the builders, dispatch, types,
  mail entities — model on `submission_builders.nim`'s import block). Drop the
  module-doc sentence about being opt-in / not re-exported.

- [ ] **Step 2 — re-export from the mail hub.** In `src/jmap_client/internal/mail.nim`
  add `import ./mail/combinators` + `export combinators` (so root's `export mail`
  surfaces it). Confirm `src/jmap_client.nim`'s doc comment (lines 16-18) no longer
  claims a separate `jmap_client/convenience` path — reword to "the combinators are
  part of the always-on hub".

- [ ] **Step 3 — migrate in-tree importers.** `tests/protocol/tconvenience.nim:17`
  and `tests/compile/tcompile_a1d_mail_hub_surface.nim:27`: drop
  `import jmap_client/convenience` (the symbols now arrive via `import jmap_client`).
  (Examples handled in Task 5.)

- [ ] **Step 4 — lints + snapshots.**
  - `tests/wire_contract/module-paths.txt`: remove the `jmap_client/convenience`
    line. Regenerate via the freeze recipe if one drives it; else hand-edit + re-lock.
  - `tests/lint/h11_typed_builder_no_jsonnode.nim:18,40`: repoint the scanned path
    from `convenience.nim` to `internal/mail/combinators.nim`.
  - `tests/lint/th10_internal_boundary.nim:71`: update the message/allowance that
    referenced the convenience public path.
  - `tests/lint/h13_module_path_lock.nim`: re-lock against the edited
    `module-paths.txt`.
  - `just freeze-api` + `freeze-type-shapes`: `public-api.txt` loses the
    `## jmap_client/convenience` section; the combinators reappear under the root
    section. Confirm no symbol is dropped (same public set, new grouping).

- [ ] **Step 5 — build + `just test`** (incl. standalone-compiling `tconvenience.nim`
  under its new import).

- [ ] **Step 6 — controller commits** `mail: fold the combinators onto the hub; drop
  the convenience path` and flips STATE.

## Task 4 — the one-shot module

**Files:** new `src/jmap_client/internal/one_shot.nim`; `src/jmap_client.nim`;
snapshots.

- [ ] **Step 1 — module skeleton.** Create `src/jmap_client/internal/one_shot.nim`
  with the SPDX header, `{.push raises: [].}` + `{.experimental: "strictCaseObjects".}`,
  a module docstring (British, why-focused, RFC refs), and imports: `./client`,
  `./transport`, `./types/*` (session_endpoint, credential, identifiers), the mail
  builders + `./mail` entities, `./mail/combinators`, `./protocol/dispatch`,
  `./protocol/jmap_error`, `./protocol/builder`, `std/tables`.

- [ ] **Step 2 — `connect`.**

```nim
proc connect*(url, username, password: string): Result[JmapClient, JmapError] =
  ## One-call client bootstrap (the on-ramp `docs/design/16` named): folds the
  ## endpoint + credential constructors and ``initJmapClient`` onto one rail. The
  ## session is fetched lazily on the first ``send`` (or ``fetchSession`` /
  ## ``requireMail``), matching the default backend.
  let endpoint = ?directEndpoint(url).lift
  let credential = ?basicCredential(username, password).lift
  initJmapClient(endpoint, credential)

proc connect*(url, username, password: string, transport: Transport): Result[JmapClient, JmapError] =
  ## As ``connect``, with a caller-supplied ``Transport`` (custom HTTP backend).
  let endpoint = ?directEndpoint(url).lift
  let credential = ?basicCredential(username, password).lift
  initJmapClient(endpoint, credential, transport)
```

- [ ] **Step 3 — a single private dispatch helper** to keep each one-shot a 1-liner
  and `complexity ≤ 10`:

```nim
proc runGet[T](client: JmapClient, name: MethodName,
    built: (RequestBuilder, ResponseHandle[GetResponse[T]])): Result[GetResponse[T], JmapError] =
  ## Internal: freeze → send → get → fulfil for a single Foo/get one-shot.
  let (b, handle) = built
  let dr = ?client.send(b.freeze())
  (?dr.get(handle)).fulfil(name)
```

  (and analogous internal helpers for the query-then-get and the submission compound,
  each reusing `fulfil`).

- [ ] **Step 4 — bare-get one-shots** (one per gettable entity):

```nim
proc getMailboxes*(client: JmapClient, accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]])): Result[GetResponse[Mailbox], JmapError] =
  ## Fetch mailboxes in one call (RFC 8621 §2.1). Returns the full GetResponse —
  ## ``.list`` plus ``.state`` (the sync cursor) and ``.notFound``.
  runGet[Mailbox](client, mnMailboxGet, client.newBuilder().addMailboxGet(accountId, ids))
```

  …and `getIdentities` (`mnIdentityGet`, `addIdentityGet`), `getEmails`
  (`mnEmailGet`, `addEmailGet`, extra `bodyFetchOptions` param), `getThreads`
  (`mnThreadGet`, `addThreadGet`), `getEmailSubmissions` (`mnEmailSubmissionGet`,
  `addEmailSubmissionGet`), `getVacationResponse` (`mnVacationResponseGet`,
  `addVacationResponseGet` — singleton). Verify each `mn*` enum + `add*Get` wrapper
  name against the source.

- [ ] **Step 5 — query-then-get one-shots + `QueryThenGet`.**

```nim
type QueryThenGet*[T] = object
  ## Off-rail result of a query-then-get one-shot (both method outcomes already
  ## collapsed onto the JmapError rail).
  query*: QueryResponse[T]
  get*: GetResponse[T]

proc queryEmails*(client: JmapClient, accountId: AccountId,
    filter = Opt.none(Filter[EmailFilterCondition]), sort = Opt.none(seq[EmailComparator]),
    queryParams = QueryParams(), collapseThreads = false,
    bodyFetchOptions = default(EmailBodyFetchOptions)): Result[QueryThenGet[Email], JmapError] =
  ## Email/query + Email/get in one call (RFC 8621 §4.4 + §4.2). A method error in
  ## either call surfaces on the rail (jeMethod).
  let (b, handles) = client.newBuilder().addEmailQueryThenGet(
    accountId, filter, sort, queryParams, collapseThreads, bodyFetchOptions)
  let dr = ?client.send(b.freeze())
  let both = ?dr.getBoth(handles)             # convenience getBoth → QueryGetResults
  ok(QueryThenGet[Email](query: ?both.query.fulfil(mnEmailQuery), get: ?both.get.fulfil(mnEmailGet)))
```

  …and `queryMailboxes` (`addMailboxQueryThenGet`, `mnMailboxQuery`/`mnMailboxGet`),
  `queryEmailSubmissions` (`addEmailSubmissionQueryThenGet`).

- [ ] **Step 6 — `sendPlainText`** (RFC 8621 §7.5.1, two-mailbox atomic flow). Use the
  spec §9 flow with the exact constructors from the recon: `plainTextBody`,
  `parseNonEmptyMailboxIdSet`, `initKeywordSet(@[kwDraft])`, `parseEmailBlueprint`,
  `addEmailSet`, `parseRFC5321Mailbox` + `SubmissionAddress` + `parseNonEmptyRcptList`
  + `reversePath`/`Envelope`, `parseEmailSubmissionBlueprint(identityId,
  creationRef(emailCid), Opt.some(env))`, `initEmailUpdateSet(@[moveToMailbox(
  sentMailbox), removeKeyword(kwDraft)])`, `parseNonEmptyOnSuccessUpdateEmail(@[(
  creationRef(subCid), updateSet)])`, `parseEmailSubmissionSet(create =
  {subCid: subBp}.toTable, onSuccessUpdateEmail = …)`, `addEmailSubmissionSet`. Mint
  `emailCid`/`subCid` via `parseCreationId("draft")`/`parseCreationId("sub")` (lift
  each fallible call with `?…​.lift`). Extract:

```nim
  let dr = ?client.send(b2.freeze())
  let emailOut = ?(?dr.get(emailHandle)).fulfil(mnEmailSet)        # SetResponse
  let subOut = ?dr.getBoth(subHandles)
  let subSet = ?subOut.primary.fulfil(mnEmailSubmissionSet)        # EmailSubmissionSetResponse
  # read emailCid → emailOut.created; subCid → subSet.created; return SentEmail.
  ok(SentEmail(emailId: createdEmailId, submissionId: createdSubmissionId))
```

  with `type SentEmail* = object` (`emailId*: Id`, `submissionId*: Id`). Reading the
  created id from a `SetResponse.created` table is `withValue`/`getOrDefault` keyed by
  the `CreationId` (never `Table.[]`); if the create is absent it is a `jeProtocol`
  or `jeValidation` shape — decide against the response type during implementation and
  document the invariant.

- [ ] **Step 7 — wire into the hub.** `src/jmap_client.nim`: add
  `import jmap_client/internal/one_shot` + `export one_shot` (after `client`).

- [ ] **Step 8 — build; regen `freeze-api` + `freeze-type-shapes`; `just test`.**
  Confirm `public-api.txt` gains the one-shots + `QueryThenGet` + `SentEmail`.

- [ ] **Step 9 — controller commits** `client: add the connect/get/query/sendPlainText
  one-shots` and flips STATE.

## Task 5 — re-bench `examples/jmap-cli` + reconcile the audit

**Files:** `examples/jmap-cli/commands/*.nim`; `examples/jmap-cli/AUDIT.md`;
`docs/design/16-api-from-the-consumers-chair.md`.

- [ ] **Step 1 — adopt the one-shots.** Rewrite the CLI command bodies onto the new
  surface: `cli_session.connect` → `connect`; the bare-get lifecycles (mailbox,
  email_read, thread, identity) → `getMailboxes`/`getEmails`/… ; `email_query` /
  `email_sync` → `queryEmails` / the combinators via plain `import jmap_client`
  (drop `import jmap_client/convenience`); `email_send` → `sendPlainText` (and/or the
  new total `addEmailSubmissionSet` where it builds manually). Keep the bench's
  purpose (exercise + document the public API), not prettiness.

- [ ] **Step 2 — public-only gate.** `bash examples/jmap-cli/check-public-only.sh`
  and `nim c examples/jmap-cli/jmap_cli.nim` — zero warnings, public-surface-only.

- [ ] **Step 3 — reconcile docs.** Add an S4 resolution section to
  `examples/jmap-cli/AUDIT.md` (map the connect-preamble / no-body-helper /
  builder-does-not-create / uncopyable-move / bare-get-combinator findings →
  RESOLVED, with how). Update `docs/design/16` send + first-fifteen-minutes +
  cross-cutting verdicts to reflect the one-shots. British, RFC-grounded.

- [ ] **Step 4 — controller commits** `examples/jmap-cli: adopt the S4 one-shots;
  reconcile the audit` and flips STATE.

## Task 6 — final snapshot reconciliation + BOTH gates

- [ ] **Step 1 — full snapshot regen + lint.** `just freeze-api`,
  `freeze-type-shapes`, `freeze-error-messages`; confirm no stragglers; `just ci`
  green (reuse, fmt-check, the H-lint battery, nimalyzer `complexity`/`hasdoc`/
  `caseStatements`, fast test).
- [ ] **Step 2 — adversarial Workflow** over the whole diff (RFC / 29-principles /
  purity / libcurl-SQLite-lens / completeness) before the live gate. Address any
  real finding (put contract-shaping surprises to the user).
- [ ] **Step 3 — live gate.** `just clean && just jmap-reset && just test-full` in the
  background; wait for "All shards passed" (Stalwart/James/Cyrus). On any failure,
  fix and re-run the WHOLE sequence. Confirm: the `sendPlainText` alice→bob delivery
  (verified at bob's inbox) AND a deliberately-failing submission leaving a draft,
  not a phantom-sent message.
- [ ] **Step 4 — controller** flips every STATE row to ✅ with its commit SHA;
  updates the `api-libcurl-sqlite-refactor` memory to "S4 both gates green, NOT
  merged — push/PR awaits user OK". **Confirm push/PR/merge with the user.**

---

## Self-review (against the spec)

- **Coverage:** spec §4 dissolve → Task 3; §5 jeMethod/fulfil → Task 0; §6 connect,
  §7 bare-gets, §8 query-then-get, §9 sendPlainText → Task 4; §10.1 typed emailId →
  Task 1; §10.2 spec+total builder → Task 2; §13 ripple → the ledger; §14 testing →
  woven through + Task 6. All covered.
- **Type consistency:** `EmailSubmissionSetSpec` / `parseEmailSubmissionSet` /
  `addEmailSubmissionSet(b, account, spec)` / `EmailSubmissionHandles` / `fulfil` /
  `MethodFault` / `QueryThenGet` / `SentEmail` used identically across tasks.
- **No placeholders:** new symbols carry full code; mechanical migrations carry an
  exact transformation pattern + the exhaustive `file:line` ledger (repeating 35
  near-identical blocks would be noise, not precision).
