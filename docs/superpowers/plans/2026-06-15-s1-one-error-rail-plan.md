<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# S1 — One Error Rail (`JmapError`) — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans (or
> subagent-driven-development) to implement this task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking. This plan is **self-contained** (the
> companion spec `docs/superpowers/specs/2026-06-15-s1-one-error-rail-design.md`
> is gitignored). Campaign context:
> `docs/superpowers/plans/2026-06-15-CAMPAIGN-HANDOFF.md`.

**Goal:** Collapse the five public error rails into one `JmapError` sum so the
`freeze → send → get` pipeline composes with one `?`; keep `MethodError`/
`SetError` as response data.

**Architecture:** New L3 module `jmap_error.nim` defines `JmapError` (6 flat
arms) + `MethodOutcome[T]` + lifts + `.lift`; `JmapResult` relocates there;
`get` returns method-errors as data on the ok-branch; the five rails fold in;
two non-consumer leaf rails go internal.

**Tech stack:** Nim, `--mm:arc`, vendored nim-results, `func`-only L1–L3 under
`{.push raises: [], noSideEffect.}` + `strictCaseObjects`.

---

## STATE / HANDOFF  (update this block as each phase lands)

- **Branch:** `api/s1-one-error-rail` (off `main`, after S0 merge).
- **Current phase:** **S1 COMPLETE ✅** — both gates green on `4114cdd`
  (`just ci` "All CI checks passed!"; `just clean && just jmap-reset &&
  just test-full` "All shards passed" — Cyrus + Stalwart + James). Adversarial
  review of the keystone done (verdict: sound, no must-fix bugs; D2 fixed, D1
  documented, low nits accepted). 12 commits; 154 files, +3773/−2465. **Not
  pushed — awaiting user go-ahead for push/PR.** Next sub-project: **S2**
  (read-model uniformity).
- **Gate-2 / review fixes (all committed):** (a) compound `getBoth` §5.4
  conditional implicit — `CompoundResults.implicit` is `Opt[MethodOutcome[B]]`,
  extracted only on primary success (`155cd46`); (b) `ProtocolFault` call id
  moved into the variants — mandatory on `pfMissingCall`/`pfMalformedError`,
  `Opt` `decodeCallId` on `pfDecode` (D2, `4114cdd`); (c) REUSE-Ignore on the
  handoff prose + `MethodOutcomeKind` docstring (`70145c0`); (d) dead imports in
  `tadversarial_blueprint` (`f7eab8e`).
- **Phase 7 done (commit pending this turn):** Regenerated the wire-contract
  snapshots via the S0 oracle (`errorCounter=0`, 1661 rows) — diff is exactly as
  designed (ClientError/GetError/EmailBlueprintError(s)/TokenViolation/
  SmtpReplyViolation gone; JmapError + sub-types + MethodOutcome + jmap*/lift/
  toJmapError/requirePrimaryAccount + reshaped get/getBoth/getAll/initJmapClient
  added). Migrated ~110 test files to the new shapes (get→MethodOutcome, method
  errors as data, jeMisuse/jeProtocol, NonEmptySeq validation, JmapError arms);
  the surface-audit compile tests now actively assert the new surface present +
  retired rails ABSENT. Regenerated the h15 error-message snapshot (updated
  `scripts/freeze_error_messages.nim` — a necessary generator exception — to a
  JmapError sample set). Added an S1 resolution ledger to
  `examples/jmap-cli/AUDIT.md` mapping each error-rail finding to its fix (rail
  aspects resolved; ceremony/read-model aspects flagged for S2–S4).
  **`just test` → "All tests passed" (exit 0), independently re-run**; all 73
  live integration files compile; `just fmt-check` green. (Live suite itself runs
  in Phase 8.)
- **Phase 6 done (commit pending this turn):** `convenience.nim` needed no
  rewrite — Phases 3/4 already migrated its `getBoth` to `MethodOutcome`/
  `JmapError`; a rail-smell scan found no string rails or conversion shims.
  The CLI bench (13 `examples/jmap-cli/commands/*.nim`) was rewritten to thread
  `JmapError` end to end: `joinErrs` and every `Result[T, string]` collapse
  deleted; construction calls take one `.lift`, the pipeline a bare `?`; `get`
  sites `case` on `MethodOutcome`; `cli_session.connect` uses
  `?session.requirePrimaryAccount(ckMail)` for the preflight. `email_send.nim`
  is the headline single-`?` build→send→get pipeline (the P29 proof). One
  necessary exception: `addEmailSubmissionAndEmailSet` returns an *uncopyable*
  `RequestBuilder` in its Ok arm, so it uses an explicit `if r.isErr: return
  err(r.error.toJmapError)` + `move` (a separate uncopyable-builder friction =
  R4/S4, not an error-rail issue). Verified: `check-public-only.sh` OK, example
  builds 0 warnings, library still builds, no string rails remain in CLI code.
- **Phase 5 done (commit pending this turn):** New L3 module
  `protocol/preflight.nim` with `requirePrimaryAccount(session, kind):
  Result[AccountId, JmapError]` — the `jeSession` seed (sfCapabilityAbsent /
  sfPrimaryAccountAbsent), re-exported via the protocol hub. `TokenViolation`
  (+7 members +6 `detect*`) privatised from the L1 hub (`types.nim`);
  `SmtpReplyViolation` (+15 members +6 `detect*`) privatised from the mail hub
  (`mail/types.nim`) — both verified **gone** from the live S0-oracle api +
  type-shapes output (internal callers use direct `validation`/`submission_status`
  imports, so unaffected; tests reach them via direct import per H10).
  `just build` green; `JmapError`/`MethodOutcome`/`requirePrimaryAccount` present
  in the oracle. NOTE: the committed wire-contract snapshots are now stale across
  all of S1 — `lint-public-api`/`lint-type-shapes` (and H16/H17) fail until the
  Phase 7 regeneration; expected.
- **Phase 4 done (commit pending this turn):** `GetError` **retired**. New
  `classifyInvocation[T]` in `dispatch.nim` splits the located invocation into
  rail/data: missing→`jeProtocol pfMissingCall`, real `"error"` invocation→
  `ok(MethodOutcome mokMethodError)` (DATA), malformed `"error"`→`jeProtocol
  pfMalformedError`, decode-ok→`ok(mokValue)`, decode-fail→`jeProtocol pfDecode`.
  The synthetic `serverFail` MethodErrors (`extractInvocation`/
  `extractInvocationByName`) and `serdeToMethodError` are deleted — those library
  faults now ride the rail honestly. `get`×2 → `Result[MethodOutcome[T],
  JmapError]` (brand mismatch → `jeMisuse`); `getBoth` (dispatch) +
  `CompoundResults` carry `MethodOutcome`; `getAll` (mail_builders) + `getBoth`
  (mail_methods) + `getBoth`×3 (convenience) reshaped likewise (each result-record
  field is a `MethodOutcome`). Retired `GetError`/`GetErrorKind`/`getErrorMethod`/
  `getErrorHandleMismatch` from `errors.nim`; dropped from `types.nim` except-list.
  `just build` green; `convenience.nim` compiles.
- **Phase 3 done (commit pending in this turn):** `ClientError` **fully retired**
  — `classify.nim` is L4 (`transport/`, `{.push raises: [].}`) so it imports
  `jmap_error` and returns `JmapError` directly (`jeTransport`/`jeRequest`;
  envelope-decode → unlocalised `jeProtocol`). `JmapResult` relocated to
  `jmap_error.nim`; dropped from `types.nim` + the `export errors except` list
  (dropped `clientError`/`validationToClientError`/`validationToClientErrorCtx`).
  Retired `ClientError`/`ClientErrorKind`/`clientError`/`validationToClientError`/
  `validationToClientErrorCtx`/`classifyException` from `errors.nim` (kept
  `classifyTransportException` — the leaf). `client.nim` send path + the 4 L4
  ctors (`initJmapClient`×2, `newTransport`, `newHttpTransport`) now return
  `JmapError` (construction lifts via `.lift`/`jmapValidation`; transport faults
  via `jmapTransport`; session decode via `jmapProtocol(protocolDecode(sv))`).
  `protocol.nim` re-exports `jmap_error` **except** the internal-construction
  symbols (`jmapMisuse`/`jmapProtocol`/`misuse`/`protocolMissingCall`/
  `protocolMalformedError`/`protocolDecode`/`methodValue`/`methodFailure`).
  **Refinement:** `ProtocolFault.callId` is now `Opt[MethodCallId]` (envelope/
  session decode faults have no call id) with an unlocalised `protocolDecode`
  overload. `just build` green; `convenience.nim` compiles.
- **Done:** Recon; 4 forks approved; spec; **Phase 0** (commit `6712385`);
  **Phase 1** — `jmap_error.nim` (`JmapError` 6-arm sum + sub-types +
  `MethodOutcome[T]` + ctors + `toJmapError`/`lift` + `message`/`$` + relocated
  `JmapResult`); commit `33efadc`; additive, `nim check` clean. `==`/`hash`
  omitted (errors.nim convention; add reactively). **Phase 2** — added
  `hash(ValidationError)` (validation.nim) + `defineSealedNonEmptySeqOps(
  ValidationError)` (primitives.nim); the 14 accumulating validators now return
  `NonEmptySeq[ValidationError]` (wrapped via `parseNonEmptySeq(errs).get()`
  with invariant comments); `EmailBlueprintErrors` deleted and
  `EmailBlueprintConstraint`/`EmailBlueprintError` internalised, flattened to
  `ValidationError` via a faithful `toValidationError` (preserves
  `BodyPartLocation`); 12 files; `nim check src/jmap_client.nim` +
  `convenience.nim` = 0; `just fmt-check` green. (Note for Phase 7: tests
  referencing the retired `EmailBlueprintError*` types + the old `seq` rails
  will need updating; `BodyPartLocation`/`BodyPartPath` remain public — candidate
  for internalisation in S2.)
- **Next:** Phase 3 (`send`/transport/request → `JmapError`; relocate+re-point
  `JmapResult`; retire `ClientError`).
- **Green-checkpoint discipline:** **every phase leaves all of `src/` compiling**
  (root library *and* `convenience.nim`, kept minimally-compiling until its
  Phase-6 rewrite). `tests/` + `examples/` are swept in **Phases 6–7** — so
  `just test` is expected RED from Phase 2 until Phase 7; this is a deliberate,
  documented choice (update tests once against the final shape, not 5× as the
  API firms up), **not** a corner cut. Each phase = one green-`src/` commit.
- **Completion gates (BOTH must pass, in order):** `just ci`, then
  `just clean && just jmap-reset && just test-full`. If test-full fails, fix and
  re-run the whole `clean → jmap-reset → test-full` sequence until green.
- **Commit trailers (every commit body):**
  `Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>` /
  `Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>` /
  `Assisted-by: Claude:claude-4.8-opus`. Linux-kernel subject
  `subsystem: imperative summary` ≤75 cols. **Stage explicit paths; never
  `git add -A`.** Confirm push/PR with the user.

### Phase ledger
- [x] Phase 0 — spec + plan landed on branch; MEMORY.md repointed
- [x] Phase 1 — `JmapError` (L3) + sub-types + ctors + lifts + `.lift` (additive)
- [x] Phase 2 — validation rail → `NonEmptySeq[ValidationError]`; retire `EmailBlueprintErrors`
- [x] Phase 3 — `send`/transport/request → `JmapError`; relocate+re-point `JmapResult`; retire `ClientError`
- [x] Phase 4 — `get`/`getBoth`/`getAll` → `MethodOutcome`; retire `GetError`
- [x] Phase 5 — `jeSession` producer + privatise `TokenViolation`/`SmtpReplyViolation`
- [x] Phase 6 — fix consumers (`convenience.nim` clean; `examples/jmap-cli` rewritten)
- [x] Phase 7 — regenerate oracle contract + sweep tests + AUDIT triage
- [x] Phase 8 — both gates green + adversarial review + finalize

---

## Locked decisions (user-approved — do not relitigate)

1. **L1 purity → lift at the boundary.** L1 smart constructors stay
   `Result[T, ValidationError]`; `JmapError.jeValidation` wraps the validation
   rail; unify via `.lift`, never by retyping L1.
2. **get-side: method errors are data** on the ok-branch (`MethodOutcome[T]`);
   only library/dispatch faults ride the rail. Fail-fast convenience → S4.
3. **5th `jeSession` arm** for capability/primary-account misses.
4. **Dispatch arm split + keep JsonPath:** `jeMisuse` (consumer bug) ≠
   `jeProtocol` (server-response malformed, carries `SerdeViolation`). Because
   `jeProtocol` holds an L2 type, **`JmapError` lives in L3**.

## Design in brief (self-contained)

```nim
type JmapErrorKind* = enum
  jeValidation; jeTransport; jeRequest; jeSession; jeMisuse; jeProtocol

type JmapError* = object
  case kind*: JmapErrorKind
  of jeValidation: validation*: NonEmptySeq[ValidationError]
  of jeTransport:  transport*:  TransportError
  of jeRequest:    request*:    RequestError
  of jeSession:    session*:    SessionFault
  of jeMisuse:     misuse*:     Misuse
  of jeProtocol:   protocol*:   ProtocolFault

type SessionFaultKind* = enum sfCapabilityAbsent; sfPrimaryAccountAbsent
type SessionFault* = object
  kind*: SessionFaultKind
  capability*: Capability

type Misuse* = object            ## handle from a different builder (A6)
  expected*: BuilderId; actual*: BuilderId; callId*: MethodCallId

type ProtocolFaultKind* = enum pfMissingCall; pfMalformedError; pfDecode
type ProtocolFault* = object
  callId*: MethodCallId
  case kind*: ProtocolFaultKind
  of pfDecode: violation*: SerdeViolation
  of pfMissingCall, pfMalformedError: discard

type MethodOutcomeKind* = enum mokValue; mokMethodError
type MethodOutcome*[T] = object
  case kind*: MethodOutcomeKind
  of mokValue: value*: T
  of mokMethodError: error*: MethodError

type JmapResult*[T] = Result[T, JmapError]   ## relocated from types.nim:56
```

Lifts: `toJmapError*` overload per leaf (`ValidationError`,
`NonEmptySeq[ValidationError]`, `TransportError`, `RequestError`, `SessionFault`,
`SerdeViolation`); `func lift*[T,E](r): Result[T, JmapError] = (mixin
toJmapError; r.mapErr(toJmapError))`. Pipeline = bare `?`; construction =
`?ctor(x).lift`.

## Migration inventory (the 121, by current rail)

- **`ValidationError` ×74** → stay `ValidationError` (L1, pure). The 4 **L4**
  ctors (`initJmapClient`×2 client.nim, `newHttpTransport`/`newTransport`
  transport.nim) → `Result[T, JmapError]` via `.lift` (Phase 3).
- **`seq[ValidationError]` ×14** → `NonEmptySeq[ValidationError]` (Phase 2):
  `initEmailUpdateSet`, `parseNonEmptyEmailUpdates`, `initIdentityUpdateSet`,
  `parseNonEmptyIdentityUpdates`, `initMailboxUpdateSet`,
  `parseNonEmptyMailboxUpdates`, `initVacationResponseUpdateSet`,
  `initNonEmptyEmailImportMap`, `parseEmailSubmissionBlueprint`,
  `parseNonEmptyEmailSubmissionUpdates`, `parseNonEmptyOnSuccessDestroyEmail`,
  `parseNonEmptyOnSuccessUpdateEmail`, `parseNonEmptyRcptList`,
  `parseSubmissionParams`.
- **`EmailBlueprintErrors` ×1** → `parseEmailBlueprint` returns
  `NonEmptySeq[ValidationError]`; flatten `EmailBlueprintError` via a
  `toValidationError` translator; retire `EmailBlueprintErrors` +
  `EmailBlueprintError` (email_blueprint.nim) (Phase 2).
- **`GetError` ×8** → `Result[MethodOutcome[T], JmapError]` (Phase 4): dispatch
  `get`×2 + `getBoth`; convenience `getBoth`×3; `getAll` (mail_builders);
  `getBoth` (mail_methods). Retire `GetError` (errors.nim:599–650).
- **`ClientError` ×3** (`JmapResult`): `send` (client.nim:455), `fetchSession`
  (:365), `refreshSessionIfStale` (:447) → `JmapError` (Phase 3). Re-point
  `JmapResult`; retire `ClientError`/`clientError`/`validationToClientError`/
  `classifyException`.
- **`SerdeViolation` ×7** → stay (public decode leaf); dispatch lifts to
  `jeProtocol` (Phase 4).
- **`TransportError` ×2** → stay (transport plug-in leaf); `client.send` lifts
  to `jeTransport` (Phase 3).
- **`SmtpReplyViolation` ×6 + `TokenViolation` ×6** → internal (Phase 5).

---

## Phase 0 — spec + plan on branch

**Files:** Create `docs/superpowers/specs/2026-06-15-s1-one-error-rail-design.md`
(done, gitignored); create this plan (tracked); modify `MEMORY.md`.

- [ ] Write spec (done) and this plan.
- [ ] Repoint `MEMORY.md`: add a line for the S1 plan as the READ-FIRST pointer
      for the active sub-project.
- [ ] Commit: `git add docs/superpowers/plans/2026-06-15-s1-one-error-rail-plan.md
      <MEMORY paths>` then commit `errors: plan the one-error-rail refactor (S1)`.
      (The spec is gitignored, so it is not staged.)

## Phase 1 — define `JmapError` (L3) + lifts (purely additive)

**Files:** Create `src/jmap_client/internal/protocol/jmap_error.nim`; later
re-exported by `protocol.nim` (Phase 3, when `JmapResult` moves). Phase 1 adds
the module and compiles it in isolation — nothing imports it yet, so `src/`
stays green.

- [ ] **Boilerplate:** SPDX header; `{.push raises: [], noSideEffect.}`;
      `{.experimental: "strictCaseObjects".}`. Imports: `../types/validation`
      (`ValidationError`, `NonEmptySeq`-ops, `Idx`), `../types/primitives`
      (`NonEmptySeq`, `parseNonEmptySeq`), `../types/errors` (`TransportError`,
      `RequestError`, `message`), `../types/capabilities` (`Capability`),
      `../types/identifiers`/`framework` (`BuilderId`, `MethodCallId`),
      `../serialisation/serde` (`SerdeViolation`, its `message`), `results`.
- [ ] **Types:** `JmapErrorKind`, `JmapError`, `SessionFaultKind`,
      `SessionFault`, `Misuse`, `ProtocolFaultKind`, `ProtocolFault`,
      `MethodOutcomeKind`, `MethodOutcome[T]`, `JmapResult[T]` — exactly as the
      "Design in brief" block.
- [ ] **Per-arm smart ctors:** `jmapValidation`(scalar + seq), `jmapTransport`,
      `jmapRequest`, `jmapSession`, `jmapMisuse(expected, actual, callId)`,
      `jmapProtocol`. Sub-type ctors: `sessionFault(kind, capability)`,
      `misuse(...)`, `protocolMissingCall(callId)`,
      `protocolMalformedError(callId)`, `protocolDecode(callId, violation)`.
      `methodValue[T](v)`, `methodError[T](me)` (or reuse field construction).
- [ ] **Lifts:** `toJmapError*` overloads for `ValidationError`,
      `NonEmptySeq[ValidationError]`, `TransportError`, `RequestError`,
      `SessionFault`. For `SerdeViolation` provide an overload using a sentinel
      empty `MethodCallId` (documented: real call-id is supplied by `get` in
      Phase 4 — the generic `.lift` is not the SerdeViolation path).
      `func lift*[T, E](r: Result[T, E]): Result[T, JmapError] {.inline.} =
      (mixin toJmapError; r.mapErr(toJmapError))`.
- [ ] **Projections:** `message`/`$` exhaustive `case` over `JmapErrorKind`
      delegating to each payload's `message`; `==`/`hash` hand-written
      arm-dispatch. Same `==`/`$`/`hash`/`message` for `SessionFault`, `Misuse`,
      `ProtocolFault`, and `MethodOutcome[T]` (the last needs `T` to have `==`
      for its own `==` — gate behind the element ops the codebase already
      provides; if `==` on `MethodOutcome` proves unneeded, omit it).
- [ ] **Verify:** `nim check` the module compiles (write a tiny throwaway
      `import` in a scratch and remove, or rely on Phase 3's wiring). Ensure no
      `proc`, no raising calls, `strictCaseObjects`-clean (every variant read in
      a `case`; combined `of pfMissingCall, pfMalformedError` read via that
      combined arm).
- [ ] **Commit:** `errors: add JmapError sum type and boundary lifts (S1)`.

## Phase 2 — consolidate the validation rail

**Files:** `src/jmap_client/internal/types/validation.nim` (NonEmptySeq wrap
helper if needed); the 14 accumulating validators across `mail/email_update.nim`,
`mail/identity_update.nim`, `mail/mailbox.nim`/`mailbox_*`, `mail/vacation.nim`,
`mail/email.nim` (import map), `mail/email_blueprint.nim`,
`mail/email_submission.nim`, `mail/submission_*`; `mail/email_blueprint.nim`
(retire `EmailBlueprintErrors`/`EmailBlueprintError`); their internal callers +
serde modules.

- [ ] Add a helper to lift a non-empty accumulation buffer into
      `NonEmptySeq[ValidationError]` at the err point (the validators build a
      local `seq[ValidationError]`; on non-empty, `parseNonEmptySeq(errs).get`
      with an invariant comment, or a dedicated `func nonEmptyErrors`).
- [ ] Change each of the 14 signatures `Result[T, seq[ValidationError]]` →
      `Result[T, NonEmptySeq[ValidationError]]`; update their err arms.
- [ ] `email_blueprint.nim`: write `toValidationError(EmailBlueprintError):
      ValidationError` (flatten the typed `BodyPartLocation`/constraint to a
      structured reason); `parseEmailBlueprint` →
      `Result[EmailBlueprint, NonEmptySeq[ValidationError]]`; **retire**
      `EmailBlueprintErrors` + `EmailBlueprintError` + their ops.
- [ ] Fix every in-`src/` caller the compiler flags (chiefly the submission/
      email-set builders that consume `parseEmailBlueprint`). Keep
      `convenience.nim` compiling (mechanical only).
- [ ] **Verify:** full `src/` compiles. **Commit:** `errors: accumulate
      validation on NonEmptySeq, retire EmailBlueprintErrors (S1)`.

## Phase 3 — migrate the send / transport / request rail

**Files:** `src/jmap_client/internal/types.nim` (drop `JmapResult` alias),
`internal/protocol.nim` (re-export `jmap_error`), `internal/types/errors.nim`
(retire `ClientError` family), `internal/client.nim` (send/fetch/ensure/
refresh + `initJmapClient`), `internal/transport.nim` (`newHttpTransport`/
`newTransport` + the leaf `TransportError`), `convenience.nim` (keep compiling).

- [ ] `protocol.nim`: `import ./protocol/jmap_error; export jmap_error` so
      `JmapError`/`JmapResult`/`MethodOutcome` reach the L3 hub. Remove
      `JmapResult` from `types.nim:56`.
- [ ] `errors.nim`: delete `ClientError`/`ClientErrorKind`/`clientError`×2/
      `message(ClientError)`/`$`/`validationToClientError`/
      `validationToClientErrorCtx`/`classifyException`. **Keep**
      `classifyTransportException` (→ `TransportError`, the leaf).
- [ ] `client.nim`: `send`/`fetchSession`/`ensureSession`/
      `refreshSessionIfStale` now `JmapResult[T] = Result[T, JmapError]`. At the
      transport boundary, lift the `TransportError`/`RequestError` into
      `jeTransport`/`jeRequest` (replace the old `classifyException`/
      `clientError` calls with `toJmapError`/`.lift`). `initJmapClient`×2 →
      `Result[JmapClient, JmapError]` via `.lift` on the URL/credential
      construction.
- [ ] `transport.nim`: `newHttpTransport`/`newTransport` →
      `Result[…, JmapError]` via `.lift` on their `ValidationError`
      construction. The pluggable transport *callback contract* stays
      `Result[Response, TransportError]` (the leaf), lifted by `client.send`.
- [ ] Update `convenience.nim` minimally to compile against the new `send`.
- [ ] **Verify:** full `src/` compiles. **Commit:** `client: route transport and
      request failures onto JmapError (S1)`.

## Phase 4 — reshape `get` → `MethodOutcome`; retire `GetError`

**Files:** `internal/protocol/dispatch.nim` (the core), `internal/mail/
mail_methods.nim` + `mail/mail_builders.nim` (`getBoth`/`getAll`),
`internal/types/errors.nim` (retire `GetError`), `convenience.nim`
(`getBoth`×3, keep compiling).

- [ ] dispatch.nim: rewrite `extractInvocation`/`extractInvocationByName` to
      classify into the four rail/data outcomes (§ get-flow table in the spec):
      missing → `jeProtocol pfMissingCall`; `"error"` parses → real
      `MethodError` (data); `"error"` malformed → `jeProtocol pfMalformedError`;
      normal+decode-fail → `jeProtocol pfDecode(callId, sv)`. Delete
      `serdeToMethodError`.
- [ ] Rewrite both `get*[T]` overloads → `Result[MethodOutcome[T], JmapError]`:
      brand mismatch → `err(jmapMisuse(...))`; build `MethodOutcome` (mokValue /
      mokMethodError) on the ok-branch; protocol faults on the rail.
- [ ] `CompoundResults[A,B]` → holds `primary: MethodOutcome[A]`,
      `implicit: MethodOutcome[B]`; `getBoth` →
      `Result[CompoundResults[A,B], JmapError]`. `getAll` (mail_builders) →
      `Result[seq[MethodOutcome[T]], JmapError]`. `getBoth` (mail_methods) +
      convenience `getBoth`×3 → same shape.
- [ ] `errors.nim`: delete `GetError`/`GetErrorKind`/`getErrorMethod`/
      `getErrorHandleMismatch`/`message(GetError)`/`$`.
- [ ] Update `convenience.nim` minimally to compile.
- [ ] **Verify:** full `src/` compiles. **Commit:** `dispatch: surface method
      errors as data via MethodOutcome (S1)`.

## Phase 5 — `jeSession` producer + privatise leaf rails

**Files:** `internal/protocol/jmap_error.nim` or a small `session` helper
module (`requirePrimaryAccount`); `internal/types/validation.nim` +
`internal/mail/submission_status.nim` (the `detect*` leaf validators);
the re-export points (`types.nim`/`mail/types.nim`/`protocol.nim`).

- [ ] Implement `requirePrimaryAccount(session, capability):
      Result[AccountId, JmapError]` using the existing `Session`
      `primaryAccount`/capability `Opt` accessors → `err(jeSession …)` on a
      miss. (One thin, tested producer; the per-capability sugar is S3.)
- [ ] Privatise `TokenViolation`/`SmtpReplyViolation`: remove them and their
      `detect*`/`toValidationError` translators from the **public re-export**
      (use `export <module> except …`, or unexport where no cross-module caller
      exists). Verify the in-`src/` callers (`primitives`, `identifiers`,
      `mail/keyword`, `submission_status`) still resolve them via direct import.
- [ ] **Verify:** full `src/` compiles; (Phase 7 will confirm they vanish from
      the oracle). **Commit:** `errors: add session preflight, intern the
      validation leaf rails (S1)`.

## Phase 6 — fix consumers (convenience + CLI)

**Files:** `src/jmap_client/convenience.nim`;
`examples/jmap-cli/**` (`cli_session.nim`, `commands/*`).

- [ ] Rewrite `convenience.nim` to compose on `JmapError` end to end: delete any
      rail-conversion / stringify shims; the pipeline combinators thread one `?`;
      `getBoth` returns `MethodOutcome` pairs. Keep only honest multi-method
      compositions (the dissolve/fold decision itself is S4 — here just make it
      correct and rail-clean).
- [ ] CLI: replace the `Result[T, string]` collapse + hand-rolled `joinErrs`
      with the real `JmapError` rail; construction calls use `.lift`; `get`
      sites `case` on `MethodOutcome`. `cli_session.connect` uses
      `requirePrimaryAccount` for the mail-capability check (the `jeSession`
      payoff). Prove the single-`?` pipeline in `email_send.nim`.
- [ ] **Verify:** `bash examples/jmap-cli/check-public-only.sh` passes; the
      example builds. **Commit:** `examples: drive the JmapError rail from the
      consumer bench (S1)`.

## Phase 7 — regenerate contract + sweep tests + AUDIT triage

**Files:** `tests/wire_contract/{public-api.txt,type-shapes.txt}`;
`tests/**` referencing retired rails; `examples/jmap-cli/AUDIT.md`.

- [ ] `just freeze-api` + `just freeze-type-shapes` (the S0 oracle); **review the
      diff** — expect: `ClientError`/`GetError`/`EmailBlueprintErrors` gone;
      `JmapError`/`MethodOutcome`/sub-types added; `TokenViolation`/
      `SmtpReplyViolation` gone from the surface; 14 validators now `NonEmptySeq`;
      `send`/`get`/`fetch` E widened. Confirm nothing unexpected.
- [ ] Sweep `tests/` (unit/serde/property/compliance/stress) for the retired
      rails and the old `get` shape; update to `JmapError`/`MethodOutcome`. (This
      is the single test-update pass — see green-checkpoint note in STATE.)
- [ ] `AUDIT.md`: mark every R3 / error-rail finding `resolved` with its
      `JmapError` mapping; note method-error-as-data and the `.lift` idiom.
- [ ] **Verify:** `just test` (fast suite) green. **Commit:** `tests: refreeze
      the contract and migrate suites to JmapError (S1)`.

## Phase 8 — both gates green + adversarial review + finalize

- [ ] `just ci` green (resolve any nimalyzer complexity by decomposition, never
      by `ruleOff`).
- [ ] `just clean && just jmap-reset && just test-full` green (exact order;
      re-run the whole sequence on any failure until green).
- [ ] Dispatch an adversarial-review subagent on `jmap_error.nim` + the dispatch
      reshape (correctness, strictCaseObjects, FFI-enum readiness, RFC fidelity
      of the data/rail split). Address findings; re-run gates.
- [ ] Update this plan's STATE block → DONE; update memory
      (`api-libcurl-sqlite-refactor`) with S1 complete + S2 next.
- [ ] **Do not push/PR without the user's go-ahead.** Prepare the PR draft.

---

## Self-review notes (writing-plans gate)

- **Spec coverage:** every spec §5–§8 element maps to a phase (type→P1,
  validation→P2, send→P3, get→P4, session+intern→P5, consumers→P6,
  contract/tests/AUDIT→P7, gates→P8).
- **Type consistency:** `JmapError`/`MethodOutcome`/sub-type names and field
  names are identical across the brief, the inventory, and the phases.
- **No placeholders:** the one deferred mechanic (SerdeViolation→`pfDecode`
  call-id) is resolved in P4 with the real call-id; flagged, not hand-waved.
