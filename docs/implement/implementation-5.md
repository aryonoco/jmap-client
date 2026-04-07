# Mail Part A Implementation Plan

Layers 1–4 of RFC 8620 core are complete. This plan adds the first vertical
slice of RFC 8621 (JMAP Mail): Thread, Identity, and VacationResponse entities
plus shared sub-types (addresses), mail capability parsing, and mail-specific
error classification. Each step cuts through L1 types + L2 serde together.
All code lives under `src/jmap_client/mail/`. Full specification:
`docs/design/06-mail-a-design.md`, building on cross-cutting design
`docs/design/05-mail-design.md`.

6 steps, one commit each, bottom-up through the dependency DAG. Every step
passes `just ci` before committing.

Cross-cutting requirements apply to all steps: all modules follow established
core patterns — SPDX header, `{.push raises: [].}`, `func` for pure
functions, `Result[T, ValidationError]` for smart constructors, `Opt[T]` for
optional fields, `checkJsonKind`/`optJsonField`/`parseError` for serde.
Design doc §8 (test specification, scenarios 1–75) and §9 (decision
traceability matrix, A1–A19) provide per-scenario coverage targets.

---

## Step 1: Shared sub-types — addresses.nim + serde_addresses.nim

**Create:** `src/jmap_client/mail/addresses.nim`,
`src/jmap_client/mail/serde_addresses.nim`,
`tests/unit/taddresses.nim`, `tests/serde/tserde_addresses.nim`

**Design doc:** §2 (shared sub-types), Decisions A1, A11.

Create the `src/jmap_client/mail/` directory. `addresses.nim` defines
`EmailAddress` (plain public fields: `name: Opt[string]`, `email: string`)
with `parseEmailAddress` smart constructor (validates non-empty `email`,
returns `Result[EmailAddress, ValidationError]`, post-construction `doAssert`).
`EmailAddressGroup` has plain public fields (`name: Opt[string]`,
`addresses: seq[EmailAddress]`), no smart constructor — all invariants
captured by field types.

`serde_addresses.nim` provides `toJson`/`fromJson` for both types following
core serde patterns. `EmailAddress.fromJson` extracts `email` (required
string) and `name` (absent/null → `Opt.none`), delegates to
`parseEmailAddress`. `EmailAddressGroup.fromJson` parses `addresses` JArray
with short-circuit on first element error via `?`.

Tests cover scenarios 1–12: smart constructor validation (empty email
rejection), `toJson` with/without name, `fromJson` with missing/null email,
`EmailAddressGroup` round-trip with named/unnamed groups and empty addresses.

---

## Step 2: Thread — thread.nim + serde_thread.nim

**Create:** `src/jmap_client/mail/thread.nim`,
`src/jmap_client/mail/serde_thread.nim`,
`tests/unit/tthread.nim`, `tests/serde/tserde_thread.nim`

**Design doc:** §3 (Thread entity), Decisions A4, A10, A14.

`thread.nim` defines `Thread` with Pattern A sealed fields (`rawId: Id`,
`rawEmailIds: seq[Id]`) and `parseThread` smart constructor (validates
`emailIds.len > 0`, post-construction `doAssert`). UFCS accessors `id`
and `emailIds`. Sealed fields prevent external construction with invalid
state (follows Session pattern).

`serde_thread.nim` provides `toJson` (uses accessor functions) and
`fromJson` (parses `id` via `Id.fromJson`, parses `emailIds` as JArray
with per-element `Id.fromJson`, delegates to `parseThread`).

Tests cover scenarios 13–21 plus sealed field safety: single/multiple/empty
`emailIds` construction, accessor correctness, `toJson` structure, `fromJson`
valid/invalid/empty array, sealed field protection from external modules
(named construction rejected, direct field access rejected), and `seq[Thread]`
collection operations.

---

## Step 3: Identity — identity.nim + serde_identity.nim

**Create:** `src/jmap_client/mail/identity.nim`,
`src/jmap_client/mail/serde_identity.nim`,
`tests/unit/tidentity.nim`, `tests/serde/tserde_identity.nim`

**Design doc:** §4 (Identity entity), Decisions A3, A5, A9, A18.

`identity.nim` defines `Identity` with plain public fields (`id: Id`,
`name: string`, `email: string`, `replyTo: Opt[seq[EmailAddress]]`,
`bcc: Opt[seq[EmailAddress]]`, `textSignature: string`,
`htmlSignature: string`, `mayDelete: bool`) — no smart constructor, all
invariants captured by field types. `IdentityCreate` has
`parseIdentityCreate` smart constructor (validates non-empty `email`,
default parameter values match RFC defaults for ergonomic construction).

`serde_identity.nim` imports `serde_addresses` for `EmailAddress` serde.
`Identity.fromJson` treats absent `name`/`textSignature`/`htmlSignature`
as `""` (RFC default), rejects empty/absent `email` (Decision A18).
`IdentityCreate.toJson` emits all fields (no `id`/`mayDelete`); no
`IdentityCreate.fromJson` (creation types are constructed by consumers).

Tests cover scenarios 24–37: full-field `fromJson`, absent-defaults-to-empty
for `name`/`textSignature`/`htmlSignature`, null `replyTo`/`bcc`, empty
`email` rejection, `toJson`/`fromJson` round-trip, `IdentityCreate`
construction with all defaults, `toJson` structure without `id`/`mayDelete`.

---

## Step 4: VacationResponse + capability types + mail errors

**Create:** `src/jmap_client/mail/vacation.nim`,
`src/jmap_client/mail/serde_vacation.nim`,
`src/jmap_client/mail/mail_capabilities.nim`,
`src/jmap_client/mail/serde_mail_capabilities.nim`,
`src/jmap_client/mail/mail_errors.nim`,
`tests/serde/tserde_vacation.nim`,
`tests/serde/tserde_mail_capabilities.nim`,
`tests/unit/tmail_errors.nim`

**Design doc:** §5 (VacationResponse), §6 (capabilities), §7 (mail errors),
Decisions A2, A6, A7, A8, A12, A13, A15, A16, A17, A19.

Five modules with no mail-internal dependencies, grouped for commit
efficiency.

`vacation.nim`: `VacationResponseSingletonId` const (`"singleton"`),
`VacationResponse` type (plain fields, no `id` field — Decision A6). No
smart constructor. `serde_vacation.nim`: `fromJson` validates
`id == VacationResponseSingletonId` then discards; `toJson` emits
`"id": VacationResponseSingletonId`.

`mail_capabilities.nim`: `MailCapabilities` (plain fields including
`emailQuerySortOptions: HashSet[string]` — Decision A13) and
`SubmissionCapabilities` (plain fields including
`submissionExtensions: OrderedTable[string, seq[string]]` — Decision A16).
`serde_mail_capabilities.nim`: `parseMailCapabilities` validates
`cap.kind == ckMail`, enforces `maxMailboxesPerEmail >= 1` and
`maxSizeMailboxName >= 100`. `parseSubmissionCapabilities` validates
`cap.kind == ckSubmission`, parses `submissionExtensions` JObject.

`mail_errors.nim`: `MailSetErrorType` string-backed enum (13 variants +
`msetUnknown`), `parseMailSetErrorType` via `strutils.parseEnum` with
fallback. Five typed accessor functions (`notFoundBlobIds`, `maxSize`,
`maxRecipients`, `invalidRecipientAddresses`, `invalidEmailProperties`)
extracting from `SetError.extras`, all returning `Opt[T]`.

Tests cover scenarios 38–69: VacationResponse serde round-trip, singleton
id validation/rejection, missing id rejection, compile-time `v.id`
rejection (scenario 44 — a type-level check, placed in
`tserde_vacation.nim` since VacationResponse has no smart constructor and
thus no dedicated unit test file); capability parsing with valid/invalid kinds and RFC constraint
boundary values (`maxMailboxesPerEmail = 0` rejected, `= 1` accepted;
`maxSizeMailboxName = 99` rejected, `= 100` accepted); error enum parsing
for all 13 known types plus unknown, typed accessor extraction from
valid/absent/malformed extras.

---

## Step 5: Entity registration + builder functions

**Create:** `src/jmap_client/mail/mail_entities.nim`,
`src/jmap_client/mail/mail_methods.nim`,
`tests/protocol/tmail_entities.nim`,
`tests/protocol/tmail_methods.nim`

**Design doc:** §3.5 (Thread registration), §4.4 (Identity registration),
§5.3 (VacationResponse builders), Decisions A7, A12.

`mail_entities.nim`: `methodNamespace` and `capabilityUri` overloads for
`Thread` (`"Thread"`, `"urn:ietf:params:jmap:mail"`) and `Identity`
(`"Identity"`, `"urn:ietf:params:jmap:submission"`). Calls
`registerJmapEntity` for both. VacationResponse is deliberately NOT
registered (Decision A7 — compile-time prevention of invalid methods).

`mail_methods.nim`: Two custom builder functions.
`addVacationResponseGet` adds `"urn:ietf:params:jmap:vacationresponse"`
capability, creates `"VacationResponse/get"` invocation, omits `ids`
parameter, returns `ResponseHandle[GetResponse[VacationResponse]]`.
`addVacationResponseSet` takes single `PatchObject` (not
`Table[Id, PatchObject]` — Decision A12), internally constructs update map
as `{VacationResponseSingletonId: update.toJson()}`, no create/destroy
parameters, returns `ResponseHandle[SetResponse[VacationResponse]]`.

Tests cover scenarios 70–75: entity registration compiles, invocation
name correctness, capability auto-collection, singleton id in update map,
absence of create/destroy in set invocation.

---

## Step 6: Re-export hubs + entry point

**Create:** `src/jmap_client/mail/types.nim`,
`src/jmap_client/mail/serialisation.nim`, `src/jmap_client/mail.nim`

**Update:** `src/jmap_client.nim`

**Design doc:** §1.5 (module summary), cross-cutting doc §3.3 (module
layout).

`mail/types.nim` imports and re-exports all Part A Layer 1 modules:
`addresses`, `thread`, `identity`, `vacation`, `mail_capabilities`,
`mail_errors`. `mail/serialisation.nim` imports and re-exports all Part A
Layer 2 modules: `serde_addresses`, `serde_thread`, `serde_identity`,
`serde_vacation`, `serde_mail_capabilities`. `mail.nim` (package-level hub)
imports and re-exports `mail/types`, `mail/serialisation`,
`mail/mail_entities`, `mail/mail_methods`.

Update `src/jmap_client.nim` to add `import jmap_client/mail` and
`export mail`. Verify all Part A public symbols are accessible through
`import jmap_client`. Run `just ci`.

---
