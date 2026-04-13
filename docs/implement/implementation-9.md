# Mail Part E Implementation Plan

Layers 1–4 of RFC 8620 done; Mail Parts A–D done. This plan turns Mail
Part E (`docs/design/10-mail-e-design.md`) into ordered build steps.
Part E is L1 + L2 only — no L3 (deferred to Parts F–I per design §1.2).

7 phases, one commit each. Every phase passes `just ci` before
committing. Cross-cutting requirements (SPDX header, `{.push raises:
[], noSideEffect.}` for L1/L2, `func`-only, `Result` /
`ValidationError` / `Opt[T]`, fixture protocol) per design §1.4 apply
to every step.

---

## Phase 1: Foundational L1 extensions

Three independent additive changes. No Part C breakage.

- **Step 1:** Extend `src/jmap_client/primitives.nim` per design §4.6.
- **Step 2:** Extend `src/jmap_client/mail/mailbox.nim` per design §4.2,
  §5.5.
- **Step 3:** Extend `src/jmap_client/mail/headers.nim` per design §4.3,
  §4.4, §4.5, §5.3.
- **Step 4:** Extend `src/jmap_client/mail/serde_headers.nim` per design
  §4.3.3, §4.4.3.
- **Step 5:** Add scenarios 37i–37l to `tests/unit/tprimitives.nim` per
  design §6.1.5b.
- **Step 6:** Add scenarios 24–27a to `tests/unit/mail/tmailbox.nim`
  per design §6.1.3.
- **Step 7:** Create `tests/unit/mail/theaders_blueprint.nim` with
  scenarios 28a–37h per design §6.1.4, §6.1.5, §6.1.5a.

### CI gate

Run `just ci` before committing.

---

## Phase 2: Body modifications (Part C breakage)

Additive at type level; breaking at construction-site level.

- **Step 8:** Modify `src/jmap_client/mail/body.nim` per design §4.1, §5.1,
  §5.2.
- **Step 9:** Modify `src/jmap_client/mail/serde_body.nim` per design
  §4.1.3, §5.4.
- **Step 10:** Update Part C tests for the new field shape and retyped
  `extraHeaders` per the "Call-site impact" notes in design §5.1, §5.2.
  Two independent migrations, both required in the same commit:
  - **§5.1 (`value` field on `bpsInline`):** every
    `BlueprintBodyPart(..., source: bpsInline, partId: ...)` literal
    must gain `value: BlueprintBodyValue`. Enumerate sites with `rg -n
    'BlueprintBodyPart\(' tests/`; at time of writing, 22 sites in
    `tests/serde/mail/tserde_body.nim` (lines 454, 470, 484, 498, 512,
    519, 532, 540, 553, 570, 586, 599, 612, 623, 630, 636, 651, 658,
    667, 685, 697, 752) and 4 in `tests/unit/mail/tbody.nim` (lines
    101, 113, 125, 136).
  - **§5.2 (`extraHeaders` retype):** every
    `initTable[HeaderPropertyKey, HeaderValue]()` literal inside a
    Part C body-part construction becomes
    `initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()`;
    every `headers[key] = value` insert must use the new pair per the
    §5.2 migration example. Builders at time of writing: 4 in
    `tests/serde/mail/tserde_body.nim` (lines 568, 584, 683, 750).
    Also update `tests/mfixtures.nim` helpers (if any) that inline the
    old `Table[HeaderPropertyKey, HeaderValue]` shape.

### CI gate

Run `just ci` before committing.

---

## Phase 3: EmailBlueprint aggregate (L1)

- **Step 11:** Create `src/jmap_client/mail/email_blueprint.nim` per
  design §3.1, §3.2, §3.3, §3.4, §3.5.
- **Step 12:** Add factories I-1 through I-19 to `tests/mfixtures.nim`
  per design §6.5.2.
- **Step 13:** Add equality helpers K-1 through K-9 to
  `tests/mfixtures.nim` per design §6.5.4.
- **Step 14:** Add assertion templates L-1 through L-9 to
  `tests/massertions.nim` per design §6.5.5:
  - **L-1** `assertBlueprintErr(expr, variant)` — `Result` is `Err`
    AND contains at least one entry of `variant`. Delegates the
    `isErr` check to existing `assertErr` (massertions.nim:26); only
    the variant-search logic is new.
  - **L-2** `assertBlueprintErrContains(expr, variant, field, expected)`
    — L-1 plus field-level payload check (e.g., `dupName == "from"`).
  - **L-3** `assertBlueprintErrCount(expr, n)` — exact-N error
    accumulation.
  - **L-4** `assertBlueprintOkEq(expr, expected)` — variant of
    `assertCapOkEq` using `emailBlueprintEq` (K-7).
  - **L-5** `assertJsonKeyAbsent(node, key)` — symmetric complement to
    `assertJsonFieldEq`; replaces inlined `doAssert j{"x"}.isNil`.
  - **L-6** `assertJsonHasHeaderKey(node, name, form, isAll = false)`
    paired with `assertJsonMissingHeaderKey` — verify
    `"header:Name:asForm[:all]"` wire keys.
  - **L-7** `assertBlueprintErrAny(expr, variants: set[EmailBlueprintConstraint])`
    — `Err` AND contains at least one entry per variant in the set
    (for "multiple distinct variants, unknown exact count" cases).
  - **L-8** `assertBoundedRatio(slowExpr, fastExpr, maxRatio)` — times
    two expressions and asserts the slow/fast ratio is below a bound.
    Concrete HashDoS / Ω(n²) gate.
  - **L-9** `assertJsonStringEquals(node, key, exactBytes: string)` —
    byte-identical string-field check including escape sequences;
    catches silent `std/json` formatting drift.
- **Step 15:** Create `tests/unit/mail/temail_blueprint.nim` per design
  §6.5.1 row 1 (scenarios per §6.1.1, §6.1.2, §6.1.7, §6.4.4 rows
  102b/102d).
- **Step 16:** Create `tests/unit/mail/tblueprint_error_triad.nim` per
  design §6.5.1 row 5 (scenarios per §6.1.5c).
- **Step 17:** Create `tests/unit/mail/tblueprint_compile_time.nim` per
  design §6.5.1 row 6 (scenarios per §6.1.6).

### CI gate

Run `just ci` before committing.

---

## Phase 4: Serde (L2)

- **Step 18:** Create `src/jmap_client/mail/serde_email_blueprint.nim`
  per design §3.6, §4.5.3.
- **Step 19:** Create `tests/serde/mail/tserde_email_blueprint.nim` per
  design §6.5.1 row 7 (scenarios per §6.2.1, §6.2.2, §6.2.3).
- **Step 20:** Create `tests/serde/mail/tserde_email_blueprint_wire.nim`
  per design §6.5.1 row 8 (scenarios per §6.2.4).

### CI gate

Run `just ci` before committing.

---

## Phase 5: Adversarial, stress, FFI panic surface

- **Step 21:** Create
  `tests/serde/mail/tserde_email_blueprint_adversarial.nim` per design
  §6.5.1 row 9 (scenarios per §6.4.1, §6.4.5).
- **Step 22:** Create `tests/stress/tadversarial_blueprint.nim` per
  design §6.5.1 row 11 (scenarios per §6.4.2, §6.4.3, §6.4.4 rows
  102a/102c).
- **Step 23:** Create `tests/compliance/tffi_panic_surface.nim` per
  design §6.5.1 row 12 (scenario 102 — compile-time macro per §6.4.4).

### CI gate

Run `just ci` before committing.

---

## Phase 6: Property-based tests

- **Step 24:** Add generators J-1 through J-16 to `tests/mproperty.nim`
  per design §6.5.3.
- **Step 25:** Create `tests/property/tprop_mail_e.nim` per design
  §6.5.1 row 10 (eighteen properties per §6.3.1, §6.3.2, §6.3.3,
  §6.3.4).

### CI gate

Run `just ci` before committing.

---

## Phase 7: Re-export hub updates and final audit

- **Step 26:** Update `src/jmap_client/mail/types.nim` to re-export
  `email_blueprint` per design §1.5.
- **Step 27:** Update `src/jmap_client/mail/serialisation.nim` to
  re-export `serde_email_blueprint` per design §1.5.
- **Step 28:** Verify Part E public symbols are accessible via
  `import jmap_client` per design §1.5 module summary. The import
  must expose:
  - **From `email_blueprint.nim` (§3.1–§3.5):** `EmailBlueprint`,
    `EmailBlueprintBody`, `EmailBodyKind`, `EmailBlueprintConstraint`,
    `EmailBlueprintError`, `EmailBlueprintErrors`, `BodyPartPath`,
    `BodyPartLocation`, `BodyPartLocationKind`, `parseEmailBlueprint`,
    `flatBody`, `structuredBody`, and every §3.5 accessor
    (`mailboxIds`, `body`, `fromAddr`, `subject`, `to`, `cc`, `bcc`,
    `replyTo`, `sender`, `messageId`, `inReplyTo`, `references`,
    `receivedAt`, `keywords`, `headers`, `bodyValues`).
  - **From `serde_email_blueprint.nim`:** `toJson` for
    `EmailBlueprint`.
  - **From `mailbox.nim` (§4.2):** `NonEmptyMailboxIdSet`,
    `parseNonEmptyMailboxIdSet`.
  - **From `headers.nim` (§4.3–§4.5):** `BlueprintEmailHeaderName`,
    `BlueprintBodyHeaderName`, `BlueprintHeaderMultiValue`,
    `parseBlueprintEmailHeaderName`, `parseBlueprintBodyHeaderName`,
    and the seven form-specific helper constructors per §4.5.2
    (`rawMulti`, `textMulti`, `addressesMulti`, `groupedAddressesMulti`,
    `messageIdsMulti`, `datesMulti`, `urlsMulti`).
  - **From `primitives.nim` (§4.6):** `NonEmptySeq[T]`,
    `parseNonEmptySeq[T]`, `defineNonEmptySeqOps[T]` template.
  - **From `body.nim` (§4.1):** `BlueprintBodyValue`.

  A compile-time smoke test in Step 28 should reference each named
  symbol at least once; missing re-exports surface as compile errors
  in the Phase 7 CI gate.
- **Step 29:** Audit cross-cutting conventions per design §1.4 across
  every new and modified Part E source file (`email_blueprint.nim`,
  `serde_email_blueprint.nim`, and the extended regions of
  `primitives.nim`, `mailbox.nim`, `headers.nim`, `serde_headers.nim`,
  `body.nim`, `serde_body.nim`):
  - SPDX header at line 1.
  - `{.push raises: [], noSideEffect.}` at module top (all Part E
    modules are L1 or L2).
  - `func` only — no `proc` definitions
    (`rg -n '^proc ' src/jmap_client/mail/` should return nothing in
    Part E files).
  - Smart constructors return `Result[T, ValidationError]` or
    `Result[T, EmailBlueprintErrors]`; no `raise` statements on
    domain failure paths.
  - `Opt[T]` from nim-results, never `std/options`.
  - Pattern A sealing on `EmailBlueprint`: `raw*` fields
    module-private, same-name UFCS accessors public (§1.4 bullet 5).
  - `toJson`-only serde for creation types; no `fromJson` defined on
    Part E blueprint types (§1.4 bullet 7).
- **Step 30:** Spot-check §7 decision adherence for items that are
  NOT compiler-enforced (most decisions are — this list covers the
  few that aren't):
  - **E4** — `EmailBlueprint` private `raw*` fields (confirmed by
    Step 29 bullet 6; verify no public `raw*` escapes the module).
  - **E13 + E28** — header-key design: two distinct name types with
    form living on `BlueprintHeaderMultiValue`, not on the key.
    Confirm no vestigial `BlueprintEmailHeaderKey` or
    `BlueprintBodyHeaderKey` identifiers exist.
  - **E14 + E24** — `parseEmailBlueprint` takes
    `NonEmptyMailboxIdSet` and `EmailBlueprintBody` directly, not
    `openArray[Id]` or four independent body parameters.
  - **E27** — three `*HeaderDuplicate` variants present
    (`ebcEmailTopLevelHeaderDuplicate`,
    `ebcBodyStructureHeaderDuplicate`, `ebcBodyPartHeaderDuplicate`);
    Gap-1/Gap-2 variants carry `*DupName` (lowercase string), not
    `*DupKey` (`HeaderPropertyKey`).
  - **E18** — empty collections omitted from wire output (cross-link
    to serde scenarios 53, 57, 59, 77, 79).
  Where adherence is already covered by a runnable scenario,
  cross-link the scenario number. Where it isn't, add a one-line
  inline note to that module.

### CI gate

Run `just ci` before committing. Steps 29 and 30 are prerequisites
for the Phase 7 commit — failures there block the commit just like
test failures.
