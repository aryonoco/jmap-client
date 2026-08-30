# Pre-1.0 API alignment with `docs/design/14-Nim-API-Principles.md`

This is the consolidated punch list of changes required to bring `src/`
into full alignment with the 29 principles of the Nim API design rubric
before 1.0 lands. 

Each item names the principle(s) it serves (e.g. `(P19)`) and points at
the file:line where the gap lives so review and execution have a fixed
referent.

## How this list is verified

This document is a contract. Every item below has, or must acquire,
a **verification gate** — a mechanism that fails CI on regression
once the item is executed. Items without a gate are advisory and
flagged as such. The three permissible gate types:

- **Mechanical gate** (preferred). A CI lint, property test, or
  unit test fails on regression. H1–H13 are mechanical gates.
- **Snapshot gate**. A frozen file under `tests/wire_contract/`
  whose diff requires explicit `[API-CHANGE]`, `[WIRE-CHANGE]`,
  `[TYPE-SHAPE-CHANGE]`, or `[MODULE-PATH-CHANGE]` PR labelling.
  A10a, A25, A26, F6 are snapshot gates.
- **Existence gate**. A file must exist at a stated path before
  the 1.0 release tag. C1, D1.5, D9, D10, D11.5, D13.5, D16, D17
  are existence gates. (D15 is dropped; A10c covers the push /
  websocket stubs.)

A separate pre-1.0 freeze checklist tracking gate status per item
(D18, at `docs/TODO/pre-1.0-freeze-checklist.md`) is deferred by user
decision 2026-08-04. Until it lands, the per-item markers below carry
that status.

The principle of this section: **alignment is upheld by policy + CI,
not by accident.** A new contributor opening a PR cannot violate a
principle without CI catching it.

## Status legend

Each item's heading carries a status marker reflecting current
codebase state, verified against `src/` and `tests/`. The doc is
a living artefact — markers and bodies update as items land.

- **✅ DONE** — fully implemented and backed by its verification
  gate.
- **🟡 PARTIAL** — partly implemented; the item body names what
  is done and what remains.
- **⬜ TODO** — not yet implemented.
- **🟦 DEFERRED** — explicitly deferred to a post-1.0 release, or
  deferred by an explicit dated user decision.
- **❌ DROPPED** — superseded or rejected; the body explains why.
- **❌ MOOT** — the item's premise was dissolved by later work, so
  there is nothing left to do; the body explains what dissolved it.
- **RESOLVED** — a design-decision item rather than an
  implementation task; the body records the decision reached.
- **(FREEZE-BLOCKING)** — appended where the gap blocks the 1.0
  tag.

Where an item has no marker, treat it as ⬜ TODO until verified.

## Status dashboard

This dashboard is regenerated mechanically from the per-item status
markers below. Re-derive the counts with
`grep -cE "^### .*— ✅ DONE" docs/TODO/pre-1.0-api-alignment.md` (and
the sibling marker forms) — anchoring on `^### ` excludes this
dashboard's own legend text from the tally. F7 (Coverage-trace
consistency check) will be the freeze-time gate that mechanically
catches dashboard drift; until it lands, the counts are maintained by
hand.

Last reconciled 2026-08-30 against branch `api/l5-c-abi`. The four
deltas the previous reconciliation carried ahead of `main` — C15, C17,
C21 and C23 — reached `main` with PR #19. One delta is folded into the
counts below and is not yet on `main`: C24, opened and closed on this
branch as the Layer-5 C ABI that doc 17 designed.

| Status | Count | What it means |
|---|---|---|
| ✅ DONE | 83 | Implemented and verified against source / tests. |
| ⬜ TODO | 32 | Not yet implemented. |
| 🟦 DEFERRED | 5 | Post-1.0, or deferred by user decision (E1; D1, D1.5, D9, D18). |
| ❌ MOOT | 5 | Premise dissolved by later work (C7, C9, D16, F3, H7). |
| 🟡 PARTIAL | 4 | Some parts implemented; gaps named in the item body. |
| ❌ DROPPED | 2 | Superseded or rejected (D15, B11). |
| **RESOLVED** | 2 | Design decision made (A3.5, C4). |

**Freeze-blocking gaps**: no item carries the (FREEZE-BLOCKING) tag, and
C1 (sample CLI consumer) with its scaffold C1.1 (`examples/jmap-cli/`)
are both ✅ DONE. C12 (privatise the raw `BlueprintLeafPart` /
`BlueprintBodyPart` constructors — a decided non-additive removal) is
closed, merged to `main` as PR #17 (`3a04b66`). One item remains
that has to close before the 1.0 tag, because it cannot ride a 1.x
additive window: the B6/P18 ship-or-affirm question on the public
`bool` parameter family (affirming it as a documented exception is
free; retyping it is a breaking parameter change). The re-export-hub
snapshot gate (A26), the type-shape gate (A25/A25b), and their CI
wiring (F6) have landed — `lint-public-api` (H16) and
`lint-type-shapes` (H17) are wired into the local `check` and `ci`
recipes, alongside `lint-error-messages` (H15). Wiring those snapshot
lints into hosted CI is F2's remaining scope. The outstanding lint
backstops (H2–H6, H8, H9, H14) can ship in the same window or shortly
after; H1, H1b, H10–H13, H15–H17, and the three C-header gates
H18–H20 (C24, and the only ones of the set hosted CI runs today) are
already in place.

**Deferred by user decision (2026-08-04)**: D18 (the pre-1.0 freeze
checklist tracker), D1 and D1.5 (the SemVer / deprecation policy), and D9
(the long-form guide). No freeze-checklist file exists; until D18 lands,
this dashboard plus the per-item markers below are the single view of
gate status.

## Documented exceptions to the principles

Four patterns in `src/` are intentional violations of P18
("sum types over flag soup") or P19 ("schema-driven types"),
justified by the RFC or by Postel's law. Reviewers must not
re-litigate these — the exception is permanent and recorded
here so future contributors do not waste cycles attempting to
retype them.

- **`MailboxRights` 9 independent boolean fields**
  (`src/jmap_client/internal/mail/mailbox.nim`). RFC 8621 §2.4 defines nine
  independent ACL flags whose every combination is legal. A
  sum-typed alternative would forbid combinations the RFC permits.
  See Decision B6 documented on the type. **Exception scope.** P18
  ("sum types over flag soup") explicitly carves this out.
- **`addEcho(args: JsonNode)`**
  (`src/jmap_client/internal/protocol/builder.nim`). RFC 8620 §4
  makes `Core/echo` return its input verbatim — the method is
  structurally JSON-typed. A22 documents this as the explicit
  exception to P19.
- **`addCapabilityInvocation(b, capability, methodName, args:
  JsonNode)`**
  (`src/jmap_client/internal/protocol/builder.nim`). RFC 8620 §2.5
  reserves vendor URN namespaces (`urn:com:vendor:*`,
  `urn:io:vendor:*`) for capabilities the library cannot enumerate;
  their method args are structurally vendor-defined. Standard IETF
  capabilities (`urn:ietf:params:jmap:*`) MUST go through the typed
  `add<Entity><Method>` family — H11 lint enforces this. The
  `capability: CapabilityUri` and `methodName: MethodNameLiteral`
  parameters are typed; only `args` is the JsonNode escape.
- **Per-arm `rawXxxData: JsonNode` payloads on capability case
  objects, plus `*.extras` fields for unknown server fields.** A22b
  pins these as the four legitimate `JsonNode` patterns in the
  library:
  - `ServerCapability` — 9 `rawXxxData` arms (ckWebsocket, ckMdn,
    ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve,
    ckUnknown). The remaining arms are typed: ckCore carries
    `CoreCapabilities`; ckMail / ckSubmission / ckVacationResponse are
    discard arms (RFC 8621 §1.3 declares them empty at session scope).
  - `AccountCapabilityEntry` — 10 `rawXxxData` arms (ckCore,
    ckWebsocket, ckMdn, ckSmimeVerify, ckBlob, ckQuota, ckContacts,
    ckCalendars, ckSieve, ckUnknown). The typed arms are ckMail
    (`MailAccountCapabilities`, RFC 8621 §1.3.1), ckSubmission
    (`SubmissionAccountCapabilities`, RFC 8621 §1.3.2), and
    ckVacationResponse (discard, presence-only per RFC 8621 §1.3.3).
  - `MethodError.extras` — non-standard server fields.
  - `SetError.extras` — non-standard server fields.

  These exist for forward compatibility (Postel's law: lenient on
  receive). Future RFCs lift fields off a `rawXxxData` arm or out of
  `extras` by typing the arm additively (P20): the arm acquires a
  typed payload; the URI dispatches to the new typed variant. Inline
  docstrings at each `JsonNode` declaration cite this exception
  (A22b).

Any new public `JsonNode` field, parameter, or return type added
after 1.0 is a P19 violation unless it falls under one of the four
patterns above. Reviewers can grep for `JsonNode` under `src/` to
spot new occurrences; the typed-builder family is additionally
guarded by the H11 lint.

## Section A — Must FREEZE before 1.0

These items become unfixable after 1.0 ships. Anything load-bearing on
the public surface (exported types, fields, function signatures, module
paths) cannot be retracted in 1.x without a major bump.

### A1. Headline public layer; alternatives stay internal *(P5, P7)* — ✅ DONE

L3 builder + dispatch is the headline API. The closed public-path
set is exactly one path: the root (`import jmap_client`). S4
dissolved the P6 convenience quarantine — `convenience.nim` is
deleted, its pipeline combinators now live in
`src/jmap_client/internal/mail/combinators.nim` and the one-shots in
`src/jmap_client/internal/one_shot.nim`, both first-class on the
always-on hub rather than behind an opt-in import. All modules —
types, serialisation, protocol, transport, client, mail entities,
combinators, one-shots, `PushChannel` / `WebSocketChannel`
reservation types — live under `jmap_client/internal/` and reach
consumers exclusively through the root re-export. A10 locks this
layout (`tests/wire_contract/module-paths.txt` holds the single row
`jmap_client`); H13 (A10b) enforces it.

The per-hub per-symbol audits are tracked separately: A1b
(protocol hub), A1c (serialisation hub) and A1d (mail hub) are
all done.

### A1b. Per-symbol audit of `protocol.nim` re-exports *(P5)* — ✅ DONE

`protocol.nim` re-exports the user-facing surface using Nim's
`export module except sym1, sym2, …` form. Registration plumbing,
pre-serialisation helpers, internal merge functions, and the
stringly-typed `addInvocation` escape hatch (P19) are hub-private
through the `except` filter. Selective filtering (rather than
blanket `export module`) is structurally required: the
`envelope` identifier collides with the
`EmailSubmissionBlueprint.envelope*` UFCS accessor, and
Nim's symbol-resolution outcome at qualified call sites such as
`envelope.Response.fromJson(j)` is sensitive to the export form.

**Final public surface per module**:

- `entity.nim` — `registerJmapEntity`, `registerQueryableEntity`,
  `registerSettableEntity` (3 templates). The per-entity overloads
  (`methodEntity`, `getMethodName`, `setMethodName`, `capabilityUri`,
  `filterType`, etc.) live in `internal/mail/mail_entities.nim` —
  hub-private intra-`internal/mail/` `mixin` scaffolding, out of
  scope for A1b's protocol-hub audit and not public surface (A1d).
- `methods.nim` — request types `GetRequest`, `ChangesRequest`,
  `SetRequest`, `CopyRequest`; response types `GetResponse`,
  `ChangesResponse`, `SetResponse`, `CopyResponse`, `QueryResponse`,
  `QueryChangesResponse`; copy disposition `CopyDestroyModeKind`,
  `CopyDestroyMode`, `keepOriginals`, `destroyAfterSuccess`; serde
  `toJson`, `fromJson`. Module-private (no `*` qualifier):
  `optState`, `optUnsignedInt`, `mergeCreateResults`. Hub-private
  (`*` retained for cross-internal use, filtered via `except`):
  `SerializedSort`, `SerializedFilter`, `toJsonNode`,
  `serializeOptSort`, `serializeOptFilter`, `serializeFilter`,
  `assembleQueryArgs`, `assembleQueryChangesArgs`.
- `dispatch.nim` — sealed handle types `ResponseHandle[T]`,
  `NameBoundHandle[T]`, `CompoundHandles[A, B]`,
  `CompoundResults[A, B]`, `ChainedHandles[A, B]`,
  `ChainedResults[A, B]`; sealed dispatch artifact
  `DispatchedResponse`; extraction `get`, `getBoth`; handle
  accessors `callId`, `methodName`; `DispatchedResponse`
  convenience accessors `sessionState`, `createdIds`; back-reference
  primitive `reference` (the sole non-`mixin` back-reference path);
  registration templates `registerCompoundMethod`,
  `registerChainableMethod`; operators `==`, `$`, `hash`.
  Module-private (no `*` qualifier): `serdeToMethodError`,
  `findInvocation`, `extractInvocation`, `findInvocationByName`,
  `extractInvocationByName`. Hub-private (`*` retained for
  cross-internal callers, filtered via `except`):
  `initResponseHandle`, `initNameBoundHandle`,
  `initDispatchedResponse`, `response` (on `DispatchedResponse`),
  `builderId` (handle + `DispatchedResponse` accessors carrying the
  A6 brand — diagnostic-internal, never read by application code).
- `builder.nim` — sealed lifecycle types `RequestBuilder`,
  `BuiltRequest`; `RequestBuilder` accessors `methodCallCount`,
  `isEmpty`, `capabilities`; transition `freeze`; the sealed-
  handle wire-shape diagnostic `toJson(br: BuiltRequest):
  JsonNode` (A16; modelled on SQLite's
  `sqlite3_expanded_sql(stmt)`); the two RFC-mandated JsonNode
  escapes `addEcho` and `addCapabilityInvocation` (both documented
  exceptions to P19); argument-construction helper `directIds`.
  Hub-private (`*` retained for cross-internal callers —
  `mail_builders.nim`, `identity_builders.nim`,
  `submission_builders.nim`, `mail_methods.nim`,
  `combinators.nim`, `one_shot.nim`, `client.nim`, and tests under
  H10's allowlist — filtered via `except`):
  `addInvocation` (the typed-invocation chokepoint; surfaces would
  re-introduce the P19 stringly-typed escape hatch),
  `initRequestBuilder` (factories live behind
  `JmapClient.newBuilder`), the generic four-param `addGet`,
  `addChanges`, `addSet`, `addCopy`, `addQuery`, `addQueryChanges`
  (consumers reach the typed per-entity wrappers under
  `internal/mail/`), the `BuiltRequest` accessors `request`,
  `builderId`, `callLimits` (internal lifecycle bookkeeping), the
  internal escape `builtRequestFromParts` (whitebox fixture
  scaffolding only, no production caller).

**Audit mechanism** — three layers of enforcement:

1. **File-private symbols** — symbols with no cross-module callers
   carry no `*` qualifier. Whitebox test files use Nim's `include`
   directive to reach them (`tests/protocol/tmethods_whitebox.nim`,
   `tests/protocol/tdispatch_whitebox.nim`). Tests are not a design
   input — they follow the public/private boundary, they don't shape it.
2. **`export module except sym, …`** — for symbols that retain `*`
   because sibling `internal/...` modules need them, the hub
   `protocol.nim` filters them out with `except`. Cross-internal
   callers reach the symbol through direct internal imports;
   `import jmap_client` does not.
3. **Compile-time audit test** — `tests/compile/tcompile_a1b_protocol_hub_surface.nim`
   asserts both presence and absence of every symbol via
   `static: doAssert declared(...)` and `static: doAssert not
   declared(...)`. Compilation success is the canonical signal that
   the hub matches the agreed contract per P2.

A1c (serialisation hub) and A1d (mail hub) audit the remaining
hubs independently. The two hubs use different mechanisms because
the principled cuts produce different shapes: A1c's L2 surface is
fully internal, so no L2 hub aggregator exists (`export … except`
filtering is not needed); A1d's mail surface includes types app
developers do touch (`Email`, `Mailbox`, `Identity`, etc.), so it
uses A1b's selective-export pattern.

### A1c. Per-symbol audit of `serialisation.nim` re-exports *(P5, P19)* — ✅ DONE

Every L2 serialisation symbol is hub-private. The decisive anchor:
`SerdeViolation` is not carried on any `ClientError` variant. The
library projects `SerdeViolation` → `ValidationError` →
`TransportError(tekNetwork, message: string)` at four boundary
sites (`internal/client.nim` Session parse path,
`internal/transport/classify.nim` Response parse path, and two
sites inside `internal/protocol/dispatch.nim`). The projection
collapses every L2 type to a string message inside `TransportError`
before an error reaches application code. The same P19 logic governs
envelope `fromJson` — typed envelope parsing is library plumbing,
never application code — and envelope `toJson` emission: the
application-facing send-side diagnostic seam is `BuiltRequest.toJson`
on the sealed handle (in `internal/protocol/builder.nim`), not on
bare wire types.

**Module layout.**

- `src/jmap_client/internal/serialisation.nim` does not exist. No
  L2 hub aggregator is needed because no L2 symbol is hub-public.
  `src/jmap_client.nim` neither imports nor exports it.
- `serde.nim` carries the diagnostic ADTs only: `SerdeViolation`,
  `SerdeViolationKind` + 9 ordinals, `JsonPath`, `JsonPathElement`,
  `JsonPathElementKind` + 2 ordinals, the `/` and `$` operators
  on `JsonPath`.
- `serde_diagnostics.nim` carries the diagnostic helpers
  consumed by every `fromJson` site: `emptyJsonPath`,
  `jsonPointerEscape`, and the `SerdeViolation` → `ValidationError`
  translator `toValidationError`.
- `serde_helpers.nim` carries the 20 scaffolding helpers
  (`expectKind`, `fieldJ*` family, optional-field extractors,
  ID-array parsers, `parseKeyedTable`, `optToJsonOrNull`, etc.).
- `serde_primitives.nim` carries the primitive
  `string`/`bool`/`seq[T]`/`Table[K,V]` overloads, the
  `defineDistinct*` templates, the 11 instantiations for L1
  distinct types (`Id`, `AccountId`, `JmapState`, `MethodCallId`,
  `CreationId`, `BlobId`, `PropertyName`, `Date`, `UTCDate`,
  `UnsignedInt`, `JmapInt`), and the `MaxChanges` ser/de.
- `serde_session.nim` carries the Session-context ser/de plus
  `UriTemplate.toJson` / `fromJson`.
- `serde_framework.nim` carries `Filter[C]`, `FilterOperator`,
  `Comparator`, `AddedItem`. `MaxFilterDepth` is module-private
  (no `*`).
- `serde_errors.nim` carries `RequestError`, `MethodError`,
  `SetError` ser/de.
- `serde_field_echo.nim` carries `NoCreate` ser/de plus the
  `parsePartialOptField` / `parsePartialFieldEcho` /
  `emitPartialFieldEcho` templates used by every `Partial*`
  parser.
- `serde_envelope.nim` is the consolidated envelope SerDe module.
  Emit half: `Invocation.toJson`, `Request.toJson`,
  `ResultReference.toJson` (all carry `*` for cross-internal use;
  `Response.toJson` is intentionally absent — A16). Parse half:
  `Invocation.fromJson`, `Request.fromJson`, `Response.fromJson`,
  `ResultReference.fromJson`, plus the internal helpers
  `parseCreatedIds`, `referencableKey`, and `fromJsonField`. The
  smart-constructor seam routes through L1: `Request.fromJson`
  delegates final construction to `parseRequest` via
  `wrapInner` (bridging `ValidationError` → `SerdeViolation`);
  `Response.fromJson` delegates to `initResponse` directly (A30).

**Dispatch resolves typed responses without user-scope mixin.**
`ResponseHandle[T]` and `NameBoundHandle[T]` carry a
`rawParseProc: ParseProc[T]` field. The proc is bound at handle
construction time inside the builder where `T.fromJson` is in
scope (`initResponseHandle` and `initNameBoundHandle` are
templates that capture `T.fromJson` via `mixin` at the builder's
call site). `dispatch.get[T]` invokes `handle.rawParseProc(args)`
directly — no `mixin` at the extraction site. The same shape
covers `NameBoundHandle`, `CompoundHandles`, and `ChainedHandles`.
`convenience.getBoth[T]` likewise delegates to `dr.get(handles.*)`
without `mixin`. The library never requires the L2 surface to be
visible at the application's call site to make `dispatched.get(h)`
compile.

The single application-code path that still touches a wire
JsonNode is `Core/echo`: `JsonNode.fromJson` is a pass-through
identity defined in `internal/protocol/methods.nim`, so
`initResponseHandle[JsonNode]` resolves through the same mixin
chain as every typed handle.

**No re-export from the protocol hub.** `internal/protocol.nim`
neither imports nor re-exports `serde_envelope`. Application-facing
wire-shape diagnostics flow through two surfaces, both at L3 / L4
respectively: `BuiltRequest.toJson` (the sealed-handle diagnostic
seam — A16) and `JmapClient.setDebugCallback` (the receive-side
per-handle callback — A31). Bare envelope `toJson` and `fromJson`
are hub-invisible.

**Mail-serde leaves and builders import what they need; nothing
from L2 reaches the hub through them.** Each mail-serde leaf
(`serde_addresses`, `serde_body`, `serde_email`,
`serde_email_submission`, the 14 others) is itself hub-private. A
leaf imports the L2 modules its body references and re-exports the
sibling serde of any entity it nests — `serde_email` and
`serde_identity` re-export `serde_addresses`, `serde_email_submission`
re-exports `serde_email` — so a builder importing the top-level
entity serde resolves the full `mixin`-driven `T.fromJson` chain.
The chain for `SetResponse[Mailbox, PartialMailbox].fromJson` etc.
resolves at each builder file's instantiation site
(`mail_builders.nim`, `identity_builders.nim`,
`submission_builders.nim`, `mail_methods.nim`), where the
necessary L2 modules are imported directly. None of these
re-exports reaches `import jmap_client`: the mail-serde leaves are
not on the hub. Tests reach the L2 surface via the H10-permitted
test-side aggregator `tests/m_l2_serde.nim`.

**Audit gate.**
`tests/compile/tcompile_a1c_serialisation_hub_surface.nim`
asserts absence at compile time via `when declared(X):
{.error.}` and `when compiles(<typed-expression>): {.error.}`.
Runtime anchors on `Mailbox` and `Session` satisfy
`UnusedImport`. The audit covers the diagnostic ADTs, the three
scaffolding modules, every primitive distinct ser/de, the
`MaxChanges` and `UriTemplate` ser/de, the envelope `fromJson`
overloads, and the field-echo and framework helpers. The envelope
`toJson` hub-invisibility is asserted at
`tests/compile/tcompile_a1b_protocol_hub_surface.nim` (the
protocol-hub audit) since the filter mechanism is `protocol.nim`'s
absent re-export rather than an L2-module-level seal.
The `when declared` check is **not** applied to
`toValidationError`: the name is also a public L1 helper
(`validation.nim` for `TokenViolation`, `session.nim` for
`UriTemplateViolation`, `primitives.nim` for `DateViolation`,
`collation.nim` for `CollationViolation`), and the L1 overload
is legitimately surfaced. The L2 overload over `SerdeViolation`
is hub-private; absence of the other L2 symbols is the
indirect proof.

**Pattern relationship to A1b.** A1b's `protocol.nim` mixes
hub-public and hub-private symbols, so it uses `export module
except sym, …` to filter per symbol. A1c's L2 modules have zero
hub-public symbols; protocol.nim has no `export serde_envelope`
line at all, and the L2 hub aggregator file is structurally
absent rather than filtered.

### A1d. Per-symbol audit of `mail.nim` re-exports *(P5)* — ✅ DONE

`internal/mail.nim` re-exports exactly the RFC 8621 (JMAP Mail)
public surface — mail entity types, smart constructors, and the
typed per-entity method builders — through five sub-modules
(`types`, `mail_methods`, `mail_builders`, `identity_builders`,
`submission_builders`). Wire serialisation and the
entity-registration scaffolding are hub-private. Three classes of
symbol an application developer has no call site for stay off the
`import jmap_client` surface:

1. **Mail-entity ser/de (P5, P19).** No mail-entity `fromJson` /
   `toJson` is reachable through the hub. There is no mail serde
   aggregator module; the builder modules import the L2 `serde_*`
   leaves directly without re-exporting them; the Email/parse and
   SearchSnippet/get response-serde funcs in `mail_methods.nim` are
   module-private; and `mail.nim`'s `export types except fromJson`
   filters `MailboxChangesResponse.fromJson`. Typed entities arrive
   through `dr.get(handle)` — the parser closure is captured inside
   the handle at builder-definition scope (A1c).

2. **Entity-registration overloads (P5).** The `typedesc`-keyed
   overloads in `mail_entities.nim` (`methodEntity`,
   `queryMethodName`, `filterType`, `createType`, `setResponseType`,
   …) are L3 `mixin` scaffolding. `mail_entities.nim` is hub-private
   — `mail.nim` neither imports nor re-exports it; the
   intra-`internal/mail/` builder modules import it directly for
   `mixin` resolution.

3. **Back-reference construction (P5, P7, P19).** The sole
   back-reference primitive on the public surface is the explicit
   `reference[U](handle, name, path): Referencable[U]` — non-`mixin`,
   dragging no registration scaffolding into the caller's scope. There
   is one way in: the base get-builders accept
   `ids = Opt.some(reference[seq[Id]](h, name, path))`, so no `*ByRef`
   get-builders exist (P7 minimum surface, A30b). The one back-reference
   builder with no base equivalent — `addSearchSnippetGetByRef`, whose
   base builder takes a literal cons-cell and has no `Referencable`
   path — takes `Referencable[seq[Id]]`. Common chains are expressed
   through the per-entity wrappers in `internal/mail/combinators.nim`
   (and the one-shots in `internal/one_shot.nim` above them) and the
   per-entity compound builders; no generic `mixin`-based reference
   helper is public.

4. **`parseFromString` adapters (P5).** The three typedesc adapters
   `parseFromString*(typedesc[Id|PartId|HeaderPropertyKey], string)`
   that feed the generic `Table[K, V].fromJson` mixin are filtered off
   the hub (A30b): `internal/types.nim` (`export primitives except
   parseFromString`) and `internal/mail/types.nim` (`export headers /
   body except parseFromString`). Serde leaves import them by direct
   leaf import, so the mixin chain is unaffected.

`tests/compile/tcompile_a1d_mail_hub_surface.nim` pins this surface
— positive `doAssert declared` for the entity records, typed
builders, and convenience wrappers; negative `when compiles` /
`when declared` probes for the entity-registration overloads and
mail serde — mirroring A1b/A1c. `tcompile_mail_f_public_surface.nim`
and `tcompile_mail_g_public_surface.nim` cover specific RFC-feature
slices; A1d covers the mail hub as a whole.

### A2. Privatise `Invocation.arguments*` *(P19, P5, P8, P25)* — ✅ DONE

`src/jmap_client/internal/types/envelope.nim` (`Invocation.arguments`
field). Mirrors the module-private `rawName` / `rawMethodCallId`
siblings: the `arguments` field is module-private, with a
`func arguments*(inv: Invocation): JsonNode` accessor exported from
envelope.nim for internal consumers
(`internal/serialisation/serde_envelope.nim`,
`internal/protocol/dispatch.nim`, `internal/protocol/builder.nim`).
The hub re-export (`src/jmap_client/internal/types.nim`) demotes the
**whole `Invocation` type** and all its accessors/constructors (A30b),
so `import jmap_client` exposes neither `Invocation` nor `arguments` /
`name` / `methodCallId` / `initInvocation` / `parseInvocation`. The
accessors remain `*`-exported from `envelope.nim` for internal
consumers reaching them by direct leaf import. `Invocation.toJson` is
L2-internal (A16) — the application-facing wire-shape diagnostic is
`BuiltRequest.toJson` on the sealed handle. No JsonNode-shaped
mutation API exists on `Invocation`: replay flows through
`parseInvocation` from captured wire bytes; construction flows
through `RequestBuilder`. A `withArguments` setter would
re-introduce the libdbus stringly-typed back door (P19). The
seal is verified in both directions by
`tests/compile/tcompile_a2_invocation_hub_surface.nim` (sealed
from `import jmap_client`, including `inv.toJson`) and
`tests/compile/tcompile_a2_invocation_internal_access.nim`
(reachable via direct internal import).

**Adjacent invariants the seal depends on.**

- *CLAUDE.md L1 paths.* The "Important Directories" section in
  `CLAUDE.md` lists the L1 modules under `internal/types/`,
  matching the directory layout the seal assumes.
- *Typed limit metadata.* `validateLimits` enforces
  `maxObjectsInGet` and `maxObjectsInSet` from typed `CallLimitMeta`
  on `RequestBuilder`, not by walking `inv.arguments` JsonNode keys.
  `CallLimitMeta` lives in `internal/protocol/call_meta.nim`; each
  `add*` builder constructs the typed metadata from its typed
  inputs. The four `NonEmpty*Updates` wrappers
  (`NonEmptyIdentityUpdates`, `NonEmptyEmailUpdates`,
  `NonEmptyEmailSubmissionUpdates`, `NonEmptyMailboxUpdates`)
  borrow `len*` so the generic `addSet[T, C, U, R]` resolves
  `u.len` at instantiation via `mixin len`. Post-condition: no
  routine walks `inv.arguments` for type-derivable information. The
  only `inv.arguments` key-reading call sites are the two wire
  boundaries — `internal/serialisation/serde_envelope.nim` (L2 wire
  boundary) and `internal/protocol/dispatch.nim` (L3 typed-decoding
  boundary); the remaining references are benign — the `arguments*`
  accessor definition itself in `internal/types/envelope.nim` and a
  docstring mention in `internal/protocol/builder.nim`.

`validateLimits` in `client.nim` operates on the typed
`CallLimitMeta` a `BuiltRequest` already carries (max-calls +
per-call /get + per-call /set), never by walking wire shape for
type-derivable information; `send` invokes it once before consuming
the `BuiltRequest`. There is a single typed dispatch path —
`send(client, req: sink BuiltRequest)` — so no raw-`Request` sender
or wire-walking limit check exists alongside it.

### A3. Type `GetResponse[T].list` *(P19)* — ✅ DONE

`GetResponse[T].list` is `seq[T]`, parsed per-entry via `mixin
T.fromJson` inside `GetResponse[T].fromJson`
(`src/jmap_client/internal/protocol/methods.nim`). Consumers read
`getResp.list[i]` as a typed `T`; the wrapper-trigger pattern
`Entity.fromJson(getResp.list[0]).expect(...)` has no place in the
public API. Implementation mirrors `mergeCreateResults[T]` and
`QueryChangesResponse[T].added`.

Scope:
- Receive path only. Serialisation direction stays governed by
  D3.7 — A3 does NOT add `GetResponse[T].toJson`. Future need for
  typed emission can land additively (P20) without breaking A3's
  contract.
- Full-record receive path. `GetResponse[T].list` is `seq[T]`, parsed
  by the full-record-strict `T.fromJson`. Sparse-property `/get` is a
  separate typed path (A3.6): the full-record wrappers take no
  `properties` filter, and the typed `addPartial<E>Get` wrappers return
  `GetResponse[Partial<E>]` whose lenient parser tolerates elided
  fields. A property filter therefore cannot reach a strict full-record
  parser, so a sparse fetch cannot drive the five strict-parser
  entities to `MethodError(metServerFail)`. A2's seal on
  `Invocation.arguments` holds; `internal/` access stays
  library-internal-only.

Related items: A3.6 (partial-entity types for sparse `/get`),
A4 + A3.5 (`updateResults` typing + decision), A29
(`list ∩ notFound` coherence invariant), F1 (property test
wiring), D10 (L5 FFI design).

Doc references: `03-layer-3-design.md`, `00-architecture.md`,
`07-mail-b-design.md` (D3.6 narrative spans three halves: get-side
full-record under A3; update-side under A4; sparse-property under
A3.6).

### A4. Type `SetResponse[T].updateResults` *(P19)* — ✅ DONE

`SetResponse[T, U]` widens the response type with a `U`
parameter — the per-entity `PartialT` (D1). `updateResults` is
typed `Table[Id, Result[Opt[U], SetError]]` (D2): wire
`updated[id] = null` → `ok(Opt.none(U))` (server confirmed without
echo); wire `updated[id] = {...}` → `ok(Opt.some(partial))`
(server echoed partial state); wire `notUpdated[id]` →
`err(setError)`. Every non-trivial mutation flow sees typed
`PartialT` echoes on the consumer rail, symmetric with the typed
`createResults` rail.

`PartialT` family (six types): `PartialEmail`, `PartialMailbox`,
`PartialIdentity`, `PartialEmailSubmission`, `PartialVacationResponse`,
`PartialThread`. Each mirrors the full read model with wire-nullable
fields typed as `FieldEcho[T]` (three states: absent / null / value)
and wire-non-nullable fields typed as `Opt[T]` (two states: absent /
value). Receive-side parsers lenient on missing, strict on
wrong-kind-present (D4).

`NoCreate` marker fills the `T` slot for entities whose `/set` has no
create rail — currently `VacationResponse` only (D6).

### A5. Typed extension wrappers; one JsonNode escape for vendor URNs *(P19)* — ✅ DONE

The public typed-builder family carries no `extras: seq[(string,
JsonNode)]` parameter. Locked structure:

- The five generic builders (`addGet[T]`, `addSet[T, …]`,
  `addCopy[T, …]`, `addQuery[T, …]`, `addQueryChanges[T, …]`), their
  single-type-parameter templates, and the two-parameter
  `addChanges[T, RespT]` are hub-private. They retain `*` in
  `src/jmap_client/internal/protocol/builder.nim` so in-tree
  per-entity wrappers, `internal/mail/combinators.nim` and
  `internal/one_shot.nim` reach them via direct
  internal import, but are filtered from `protocol.nim`'s
  `export builder except …` clause — `import jmap_client` does not
  see them.

- Per-IETF-method, the user-facing surface is a typed wrapper:
  `addMailboxGet`, `addMailboxChanges`, `addMailboxQuery`,
  `addMailboxQueryChanges`, `addMailboxSet`; `addEmailGet`,
  `addPartialEmailGet`, `addEmailChanges`, `addEmailQuery`,
  `addEmailQueryChanges`, `addEmailSet`, `addEmailCopy`,
  `addEmailCopyAndDestroy`, `addEmailParse`, `addEmailImport`;
  `addThreadGet`, `addThreadChanges`; `addEmailSubmissionGet`,
  `addEmailSubmissionChanges`, `addEmailSubmissionQuery`,
  `addEmailSubmissionQueryChanges`, `addEmailSubmissionSet`,
  `addEmailSubmissionAndEmailSet`; `addVacationResponseGet`,
  `addVacationResponseSet`; `addSearchSnippetGet`,
  `addSearchSnippetGetByRef`. Entity-specific extension keys are
  typed parameters (e.g. `EmailBodyFetchOptions` on `addEmailGet` /
  `addPartialEmailGet` / `addEmailParse`). Back-references are supplied
  to any base get-builder via `ids = Opt.some(reference[seq[Id]](…))`;
  `addSearchSnippetGetByRef` is the sole dedicated back-reference
  builder (its base builder has no `Referencable` path).

- **Typed sparse-`/get` family (A3.6).** Alongside each full-record
  wrapper sits a typed projection wrapper returning `GetResponse[
  Partial<E>]`: `addPartialMailboxGet`, `addPartialThreadGet`,
  `addPartialIdentityGet`, `addPartialEmailSubmissionGet`,
  `addPartialVacationResponseGet`, `addPartialEmailGet`. Each takes a
  required `properties: NonEmptySeq[<E>GetProperty]`. The seven
  selectors (`MailboxGetProperty`, `ThreadGetProperty`,
  `IdentityGetProperty`, `EmailSubmissionGetProperty`,
  `VacationResponseGetProperty`, `EmailGetProperty`,
  `EmailBodyProperty`) are sealed Pattern-A case objects with named
  `…p` constants, a classifying `parse…`, and a `…Other` escape arm
  (private `rawIdentifier`) — a controlled typed escape for
  capability-extension property names, analogous to the
  `addCapabilityInvocation` vendor-URN escape below. The full-record
  wrappers carry no `properties` parameter, so a property filter can
  never reach a strict full-record parser (P16). The shared engine
  `addGetSelected[T, P]` is hub-private.

- For vendor URN capabilities the library cannot enumerate, the
  sole typed escape is
  `addCapabilityInvocation(b: RequestBuilder, capability:
  CapabilityUri, methodName: MethodNameLiteral, args: JsonNode):
  Result[(RequestBuilder, ResponseHandle[JsonNode]),
  ValidationError]`. Vendor URN namespaces (`urn:com:vendor:*`,
  `urn:io:vendor:*`) are the only legitimate values for
  `capability`; standard IETF capabilities (`urn:ietf:params:jmap:*`)
  flow through the typed wrapper family.

- `CapabilityUri` (sealed Pattern-A object in
  `src/jmap_client/internal/types/capabilities.nim`, A8) carries
  RFC 8620 §2 capability URIs end-to-end. `rawValue` is
  module-private; `parseCapabilityUri` validates the RFC 8141 URN
  envelope. `RequestBuilder.capabilityUris` holds
  `seq[CapabilityUri]`; `build()` / `capabilities()` unwrap to
  `seq[string]` for the RFC 8620 §3.3 wire shape.

- `MethodNameLiteral` (sealed Pattern-A object in
  `src/jmap_client/internal/types/methods_enum.nim`, A8) is the
  validated wire-name carrier for `addCapabilityInvocation`.
  Separate from the `MethodName` enum because vendor methods
  cannot be enumerated; `parseMethodNameLiteral` enforces 1..255
  octets, no control chars, contains `/`.

- Per-call typed metadata lives in
  `src/jmap_client/internal/protocol/call_meta.nim` — `setMeta` /
  `getMeta` helpers fold typed create/update/destroy/ids inputs into
  `CallLimitMeta` once; the hub-private generic builders delegate.

- `EmailBodyFetchOptions` is consumed via
  `emitBodyFetchOptions(node, opts)`
  (`src/jmap_client/internal/mail/serde_email.nim:933`). Three
  Email body-fetching wrappers consume it: `addEmailGet`,
  `addPartialEmailGet`, `addEmailParse`.

**Mechanical gate.** H11 typed-builder JsonNode lint
(`tests/lint/h11_typed_builder_no_jsonnode.nim`) walks
`src/jmap_client/internal/{protocol,mail}/` and `src/jmap_client.nim`;
CI fails on any exported
`add<Entity><Method>*` declaration whose parameter list contains
`JsonNode`. Allowlist: `addEcho`, `addCapabilityInvocation`,
`addInvocation` (the latter is hub-private; the lint exempts it so
it remains internally callable for the typed wrappers). Wired into
`just check`, `just ci`, and `just lint-typed-builder-jsonnode`.

### A6. Phantom-tag handles to a `BuiltRequest` *(P16, P21)* — ✅ DONE

Every `ResponseHandle[T]`, `NameBoundHandle[T]`, `BuiltRequest`,
and `DispatchedResponse` carries a `BuilderId` brand.
`dispatch.get(handle)` compares the brands and returns
`err(gekHandleMismatch)` on mismatch with diagnostic payload
`(expected, actual, callId)`. The brand catches cross-builder
reuse within one client and cross-client reuse across `JmapClient`
instances (multi-account scenarios).

`BuilderId` is composite: `clientBrand: uint64` drawn via
`std/sysrand.urandom` once per `JmapClient` (entropy failure
surfaces as a `ValidationError`) plus
`serial: uint64` monotonic per client.

`ResponseHandle[T]` and `NameBoundHandle[T]` additionally carry a
`rawParseProc: ParseProc[T]` field captured at handle construction
(A1c). `dispatch.get` invokes that closure directly — no
user-scope `mixin fromJson` chain — so the brand check is the only
concern at the extraction site.

**Pointers.**
- `src/jmap_client/internal/types/identifiers.nim` — `BuilderId`
  + `initBuilderId` + `clientBrand` / `serial` accessors.
- `src/jmap_client/internal/protocol/dispatch.nim` — sealed
  handle shape (including `rawParseProc`) + brand-check at
  `get` / `getBoth`.
- `src/jmap_client/internal/protocol/builder.nim` — `BuilderId`
  threading through every `add*` via the chokepoint
  `addInvocation`.
- `src/jmap_client/internal/client.nim` — brand draw via
  `drawClientBrand` + `newBuilder`.
- `tests/protocol/tdispatch.nim` — cross-builder and
  cross-client mismatch blocks exercise the brand check.

### A7. Lifecycle types *(P21, P16, P22, P23)* — ✅ DONE

The synchronous dispatch chain is the entire 1.0 lifecycle: each
phase is a distinct sealed type and transitions are functions
returning the next type.

`RequestBuilder` (immutable value-accumulator) → `BuiltRequest`
(frozen, branded, dispatch-ready) → `DispatchedResponse` (received,
branded, handle-extractable).

Three types, three phase invariants, two transitions (`freeze` /
`send`). Both transitions consume their input (`sink`). Wire-data
carriers `Request` and `Response` sit off the dispatch chain —
they belong to the fixture/replay path (A28), not the live
dispatch path.

A6 carries the `BuilderId` brand through every transition so
cross-builder / cross-client misuse fails at handle extraction with
`gekHandleMismatch`. The brand is the type-level encoding of
"handle was issued by this dispatch's builder" (P16). The
`sink`-on-`send` signature on `BuiltRequest` (uncopyable via
`{.error.}` `=copy` / `=dup` hooks) closes the brand-aliasing
hazard the runtime check could not detect: two
`DispatchedResponse`s from one `BuiltRequest` would share a
`BuilderId`, and a single handle set would validate against either.

The asynchronous chain extends the same `BuiltRequest` additively
through `DispatchedRequest` and `sendAsync` (A7e — reserved by policy in
`docs/policy/03-rfc-extension-policy.md`; never stubbed onto the sync surface;
P23 — async is a different type with a different lifecycle, not a flag on the
existing one).

**Sub-items.** All done: A6.5 (sealed `BuiltRequest` + `DispatchedResponse`),
A7b (`freeze` and `send(BuiltRequest)` wired), A7c (`BuiltRequest` uncopyable,
structurally consumed by `send`), A7d (`RequestBuilder` structurally uncopyable
— the whole lifecycle is now single-use), and A7e (async-surface name
reservation in the RFC-extension policy file).

**Pointers.**
- `src/jmap_client/internal/protocol/builder.nim` — `RequestBuilder`,
  `BuiltRequest`, `freeze` (`sink RequestBuilder`).
- `src/jmap_client/internal/protocol/dispatch.nim` —
  `DispatchedResponse`.
- `src/jmap_client/internal/client.nim` `send` — `send(sink BuiltRequest)`.
- `tests/compile/treject_a7c_send_consumes_builtrequest.nim` —
  testament `action: reject` anchor for double-`send`;
  `treject_a7d_freeze_consumes_builder.nim` and
  `treject_a7d_post_freeze_add.nim` — the matching anchors for the
  now-uncopyable `RequestBuilder` (see A7d).

### A8. Privatise raw distinct-type constructors *(P15)* — ✅ DONE

Every public value-carrying type in the library is a sealed
Pattern-A object: a single module-private field named `rawValue`
holds the underlying representation; the type's smart constructor
is the only path that yields a value. Direct field-init from
outside the defining module fails at compile time with *"the field
'rawValue' is not accessible."*. The seal binds external library
consumers, not just internal call sites, so the P15 contract is
enforced at the type level rather than via a CI grep.

**Sealed-object op templates** live in
`src/jmap_client/internal/types/validation.nim` and supply the
operation surface each type opts into:

- `defineSealedStringOps` — `==`, `$`, `hash`, `len` for
  string-backed values whose length is a domain quantity.
- `defineSealedOpaqueStringOps` — `==`, `$`, `hash` for
  opaque-token strings (no `len`): `JmapState`, `MethodCallId`,
  `CreationId`, `BlobId`.
- `defineSealedIntOps` — `==`, `<`, `<=`, `$`, `hash` for orderable
  numerics.
- `defineSealedTagIntOps` — `==`, `$`, `hash` (no ordering) for
  categorical numerics (`ReplyCode`, `SubjectCode`, `DetailCode`).
- `defineSealedHashSetOps` / `defineSealedNonEmptyHashSetOps` —
  read-model and creation-context HashSet operations.
- `defineSealedNonEmptySeqOps[T]` — `NonEmptySeq[T]` operations,
  generic over the element type.

**Single-value sealed types** — `Id`, `UnsignedInt`, `JmapInt`,
`Date`, `UTCDate`, `MaxChanges`, `Idx` (`primitives.nim`,
`validation.nim`); `AccountId`, `JmapState`, `MethodCallId`,
`CreationId`, `BlobId` (`identifiers.nim`); `PropertyName`
(`framework.nim`); `CapabilityUri` (`capabilities.nim`);
`MethodNameLiteral` (`methods_enum.nim`); `Keyword`
(`mail/keyword.nim`); `PartId` (`mail/body.nim`);
`BlueprintEmailHeaderName`, `BlueprintBodyHeaderName`
(`mail/headers.nim`); `BodyPartPath` (`mail/email_blueprint.nim`);
`RFC5321Keyword`, `OrcptAddrType`
(`internal/types/submission_atoms.nim`); `RFC5321Mailbox`
(`mail/submission_mailbox.nim`); `HoldForSeconds`,
`MtPriority`, `NotifySet` (`mail/submission_param.nim` — `NotifySet`
holds the RFC 3461 §4.1 NOTIFY flag set; sole constructor
`parseNotifySet`); `ReplyCode`, `SubjectCode`, `DetailCode`
(`mail/submission_status.nim`).

**Collection-backed sealed types** — `KeywordSet`
(`mail/keyword.nim`); `MailboxIdSet`, `NonEmptyMailboxIdSet`,
`MailboxUpdateSet`, `NonEmptyMailboxUpdates` (`mail/mailbox.nim`);
`NonEmptyEmailImportMap` (`mail/email.nim`); `EmailUpdateSet`,
`NonEmptyEmailUpdates` (`mail/email_update.nim`);
`NonEmptyEmailSubmissionUpdates`, `NonEmptyIdSeq`,
`NonEmptyOnSuccessUpdateEmail`, `NonEmptyOnSuccessDestroyEmail`
(`mail/email_submission.nim`); `IdentityUpdateSet`,
`NonEmptyIdentityUpdates` (`mail/identity.nim`);
`VacationResponseUpdateSet` (`mail/vacation.nim`);
`DeliveryStatusMap` (`mail/submission_status.nim`);
`SubmissionParams` (`mail/submission_param.nim`);
`NonEmptyRcptList` (`mail/submission_envelope.nim` — enforces the
RFC 8621 §7 1..N `rcptTo` cardinality);
`SubmissionExtensionMap` (`internal/types/submission_atoms.nim`).

**Multi-field flat sealed records** — multi-field Pattern-A objects
where each field is module-private and only the smart constructor
admits external construction: `Session` (`internal/types/session.nim`),
`Account` (`internal/types/session.nim`), `CoreCapabilities`
(`internal/types/capabilities.nim`), `MailAccountCapabilities`,
`SubmissionAccountCapabilities`
(`internal/types/account_capability_schemas.nim`).

**Generic sealed type** — `NonEmptySeq[T]` (`primitives.nim`),
plus the standalone `head*[T]` accessor and `asSeq*[T]`
borrow-projection consumed by `defineSealedNonEmptySeqOps`.

**Case-object sealing** — every public discriminated union with a
construction invariant has its discriminator and arm payloads
private to its defining module: `IdOrCreationRef`
(`mail/email_submission.nim`) exposes `kind*`, `asDirectRef*`,
`asCreationRef*` accessors plus `directRef` / `creationRef` smart
constructors; `ServerCapability` (`internal/types/capabilities.nim`)
and `AccountCapabilityEntry`
(`internal/types/account_capability_schemas.nim`) carry per-arm
payloads and expose `uri*`, `kind*`, and the typed projection
accessors (`asCoreCapabilities`, `asMailAccountCapabilities`,
`asSubmissionAccountCapabilities`, `asRawData`); `SessionEndpoint`
(`internal/types/session_endpoint.nim`, A20/A8b) exposes a `kind` accessor over
the private `rawKind` discriminator plus the `directEndpoint` /
`discoveryEndpoint` smart constructors; `Credential`
(`internal/types/credential.nim`, A21/A8b) exposes a `scheme` accessor over the
private `rawScheme` discriminator plus the
`bearerCredential` / `basicCredential` smart constructors; `MailboxRole`
(`mail/mailbox.nim`), `ContentDisposition` (`mail/body.nim`),
`CollationAlgorithm` (`internal/types/collation.nim`),
`Comparator`, `AddedItem` (`framework.nim`), and `Thread`,
`PartialThread` (`mail/thread.nim`) are likewise sealed.

**Internal-only sealed types** — `JsonPath` (`serialisation/serde.nim`),
`SerializedSort`, `SerializedFilter` (`protocol/methods.nim`).

**Projection accessors** (`§7` of the implementation plan) — each
sealed collection-backed type exposes a value-projection accessor
(`toSeq`, `toTable`, `toHashSet`, `toOrderedTable`) returning a
copy of the underlying collection; mutation through the projection
cannot reach the sealed value. Numeric-backed types expose
`toInt64` / `toInt` / `toUint16` projections. Two collection types
(`DeliveryStatusMap`, `SubmissionExtensionMap`) carry no
invariant beyond type identity and expose `initDeliveryStatusMap*`
/ `initSubmissionExtensionMap*` wrap constructors so serde can
construct them from a validated `Table` / `OrderedTable`.

**`SubmissionParam` sealed.** `SubmissionParam`
(`mail/submission_param.nim`) is a sealed case object: a private
`rawKind` discriminator, private `raw*` arms, a public `kind`
accessor, and eleven `asX` `Opt`-accessors. Its `spkNotify` payload is
a sealed `NotifySet` newtype whose sole constructor `parseNotifySet`
enforces the RFC 3461 §4.1 non-empty + `NEVER`-exclusivity invariant;
`notifyParam` delegates to it. The seal makes that invariant
unbypassable: without it, a raw `SubmissionParam(kind: spkNotify,
notifyFlags: {})` would put an empty `NOTIFY=` on the wire. Reject
test: `tests/compile/treject_submissionparam_notify_construction.nim`.

**Transparent ADTs intentionally not sealed** — variant types whose
payloads ARE the data and carry no bypassable construction invariant:
`SubmissionParamKey` (internal identity key; its public `extName*`
arm carries an already-validated `RFC5321Keyword`), `JsonPathElement`,
`BodyPartLocation`, `EmailBodyPart`, `SerdeViolation`, `Filter[C]`,
every `*Update` case object, `HeaderValue`, and
`BlueprintHeaderMultiValue`. The last is the instructive boundary
case: its arms ARE public (`rawValues*: NonEmptySeq[string]`, …) and
its constructors ARE fallible (`rawMulti*: Result[…]`), yet it is *not*
a hole — every arm payload is a sealed `NonEmptySeq[T]` that cannot be
constructed empty, so the non-empty invariant lives in the payload
type, not in a discriminator the public arm could bypass. P15 applies
where a smart constructor enforces an invariant a *raw-payload* arm
would bypass; these unions have no such arm.

**Mechanical enforcement of the closed claim.** Two CI lints make the
A8 universal claim ("every hub-reachable public value type is sealed
or has no bypassable invariant") mechanically checkable: H1 (no public
`distinct` under `src/`) covers the newtype surface, and **H1b**
(fallible-ctor ∩ public-arm-over-raw-payload) covers the sum-type
surface. Both report zero — `SubmissionParam` is sealed and
`BlueprintHeaderMultiValue`'s arms carry sealed payloads.

**Reject test.**
`tests/compile/treject_a8_sealed_external_construction.nim` is a
testament `action: reject` test that imports `jmap_client` and
attempts `AccountId(rawValue: "foo")` from an external module. CI
verifies the Nim 2.2.8 diagnostic *"the field 'rawValue' is not
accessible."* on every run.

**Pointers.**
- `src/jmap_client/internal/types/validation.nim` — sealed-object
  templates + `Idx`.
- `src/jmap_client/internal/types/primitives.nim` — single-value
  numeric and string sealed types, `NonEmptySeq[T]`, `asSeq[T]`.
- `src/jmap_client/internal/types/identifiers.nim` — identifier
  sealed types.
- `src/jmap_client/internal/mail/*.nim` — mail-domain sealed types
  and projection accessors.
- `src/jmap_client/internal/mail/email_submission.nim` —
  `IdOrCreationRef` sealed surface (`kind`, `asDirectRef`,
  `asCreationRef`, `directRef`, `creationRef`).
- `tests/compile/treject_a8_sealed_external_construction.nim` —
  testament reject anchor.

### A9. No test backdoors on the public surface *(P5, P8, P14)* — ✅ DONE

`src/jmap_client/internal/client.nim` exports only the JMAP-shaped
operational surface: `initJmapClient`, `newBuilder`, `setCredential`,
`setDebugCallback`, `fetchSession`, `isSessionStale`,
`refreshSessionIfStale`, `send`. No accessor, `close`, or
`*ForTest*` / `*ForTesting*` / `setSessionFor*` / `lastRaw*` /
`last*Response*` / `last*Request*` symbol exists anywhere under
`src/jmap_client/**`. Tests obtain what they need through the
public API and the H10-permitted internal seams:

- **Priming a cached session** — tests issue a real `fetchSession`
  against a canned Transport
  (`tests/mtransport.nim:newClientWithSessionCaps`).
- **Inspecting raw response bytes** — a `RecordingTransport`
  wrapper exposes `RecordingTransportState.lastResponseBody`
  (`tests/mtransport.nim:newRecordingTransport`).
- **Adversarial raw POSTs** — composed from the public
  `newHttpTransport` plus the tests-permitted internal classify
  helper (`tests/integration/live/mlive.nim:postRawJmap`,
  `postRawSingleInvocation`).
- **Limit enforcement** — `validateLimits` is module-private
  inside `client.nim`; its sole caller is `send`, and tests drive
  limit checks through `client.send()` against a canned-session
  Transport.
- **Credential** — `setCredential` is a write-only mutator; the
  credential is read per-call when the client builds each request's
  `Authorization` header. No credential getter exists.

**Verification gate.** `tests/lint/h12_no_test_backdoor_symbols.nim`
(H12) — a mechanical lint, run in `just ci`, fails on any exported
symbol under `src/jmap_client/**` matching the forbidden naming
shapes. Zero violations.

### A10. Module-path lock *(P1, P5, P6, P20, P23)* — ✅ DONE

Module paths are part of the contract: every importable path under
`jmap_client/...` is a public commitment the moment 1.0 ships. The
closed set is the SQLite/libcurl minimum-surface model: one headline
entry, nothing beside it.

**Closed set of public module paths.** One path total, since S4
dissolved the P6 quarantine and deleted `jmap_client/convenience`. The
filesystem-derived snapshot at
`tests/wire_contract/module-paths.txt` is the contract; the H13
lint (A10b) verifies snapshot vs filesystem bidirectionally on
every CI run.

```
jmap_client                  — the headline API (everything)
```

**Reservation types named, not module paths.** RFC 8620 §7 Push
and RFC 8887 WebSocket each get a type stub (`PushChannel`,
`WebSocketChannel`) re-exported from root. P23 names the *type*;
P5 keeps the *module path* out of the public contract. Future
implementation lands additively on those types (P20). If a
separate module path earns its keep later
(`jmap_client/push`, `jmap_client/websocket`), that is a minor
bump per P20; locking the path pre-1.0 would commit a surface
that cannot be removed (P1).

**Sub-items.**

- **A10a. Filesystem-derived module-path snapshot — DONE.**
  `tests/wire_contract/module-paths.txt`; regenerable via
  `just freeze-module-paths`.
- **A10b. H13 anti-bypass lint — DONE.**
  `tests/lint/h13_module_path_lock.nim`; bidirectional; sibling
  to H10. Wired to `just check` and `just ci` via
  `just lint-module-paths`.
- **A10c. Reservation type stubs — DONE.**
  `src/jmap_client/internal/push.nim` (`PushChannel*`),
  `src/jmap_client/internal/websocket.nim`
  (`WebSocketChannel*`); types re-exported from root, no
  separate module paths.
- **A10d. Cross-references — DONE.** A1, A1b, A23, A24, and
  A26 cite the locked module-path layout; the CLAUDE.md
  "Important Directories" section and the D1.5 / D18 outlines
  match it; the H10 lint message names the layout. The
  `convenience.nim` internal-access cleanup is tracked as its
  own item, C10.

**Anti-bypass.** Adding a new public module path requires
either (a) the H13 lint failing because the filesystem adds a
`.nim` directly under `src/jmap_client/` and the snapshot has
not been updated — caught at CI; or (b) explicitly regenerating
the snapshot, tagging the PR `[MODULE-PATH-CHANGE]`, and landing
the rationale. Removing or renaming a public path post-1.0 is a
2.0 break per P1.

**Verification gate.** H13 mechanical lint (A10b);
`tests/wire_contract/module-paths.txt` snapshot (A10a); eight
testament reject tests `tests/compile/treject_a10_path_<X>.nim`
enforce that each non-closed-set path FAILS to compile.

### A11. Forward-compat enum audit *(P1, P19, P20)* — ✅ DONE

Every **open-world** enum that crosses the JMAP wire carries a
catch-all variant AND a `raw…` field on its carrier type, plus a
publicly-reachable parser. Closed-world wire enums (RFC fully
enumerates; no extensibility) are documented exemptions.

**Compliance matrix — open-world wire enums (11/11 compliant):**

| # | Enum | Catch-all | Carrier `raw…` | Parser | Family |
|---|---|---|---|---|---|
| 1 | `MethodName` | `mnUnknown` | `Invocation.rawName` | `parseMethodName` | Total |
| 2 | `CapabilityKind` | `ckUnknown` | `ServerCapability.rawUri` | `parseCapabilityKind` | Total |
| 3 | `RequestErrorKind` | `retUnknown` | `RequestError.rawType` | `parseRequestErrorKind` | Total |
| 4 | `MethodErrorKind` | `metUnknown` | `MethodError.rawType` | `parseMethodErrorKind` | Total |
| 5 | `SetErrorKind` | `setUnknown` | `SetError.rawType` | `parseSetErrorKind` | Total |
| 6 | `CollationAlgorithmKind` | `caOther` | `CollationAlgorithm.rawIdentifier` | `parseCollationAlgorithm` | Fallible |
| 7 | `MailboxRoleKind` | `mrOther` | `MailboxRole.rawIdentifier` | `parseMailboxRole` | Fallible |
| 8 | `ContentDispositionKind` | `cdExtension` | `ContentDisposition.rawIdentifier` | `parseContentDisposition` | Fallible |
| 9 | `DeliveredState` | `dsOther` | `ParsedDeliveredState.rawBacking` | `parseDeliveredState` | Total |
| 10 | `DisplayedState` | `dpOther` | `ParsedDisplayedState.rawBacking` | `parseDisplayedState` | Total |
| 11 | `RefPath` | `rpUnknown` | `ResultReference.rawPath` | `parseRefPath` | Total |

**Parse-function families.** Per P15, Result-returning constructors
exist where there is a real invariant to fail against; forward-compat
tolerance is not a failure mode. **Total** (8/11): `func parseT(raw:
string): T` — catch-all IS the answer for non-matching wire strings.
**Fallible** (3/11): `func parseT(raw: string): Result[T,
ValidationError]` — RFC structural constraints validated before
classification; catch-all is for structurally-valid-but-unknown
tokens.

**Documented closed-world wire enums** (intentionally without
catch-all; out of scope by RFC stipulation):
`UndoStatus` (RFC 8621 §7 ¶7),
`FilterOperator` (RFC 8620 §5.5),
`HeaderForm` (RFC 8621 §4.1.2),
`BodyValueScope` (client-only; replaces three RFC booleans per D9),
`PlainSortProperty`, `KeywordSortProperty`, `EmailComparatorKind`
(RFC 8621 §4.4.2),
`EmailSubmissionSortProperty` (RFC 8621 §7.4),
`BodyEncoding` (RFC 6531),
`DsnRetType` (RFC 3461),
`DsnNotifyFlag` (RFC 3461),
`DeliveryByMode` (RFC 2852).

**Request-side (toJson-only) open-world family (A3.6).** The seven
get-property selectors — `MailboxGetProperty`, `ThreadGetProperty`,
`IdentityGetProperty`, `EmailSubmissionGetProperty`,
`VacationResponseGetProperty`, `EmailGetProperty`, `EmailBodyProperty`
— are open-world by the same discipline as the Fallible rows above
(catch-all `…Other` arm + private `rawIdentifier` + a fallible
`parse…` validating only non-control-string structure before
classification). They sit *outside* the receive-side matrix because
they never round-trip from server JSON: selectors flow client→server
only (no `fromJson`), emitted via `wireName`. A capability-extension
gettable property a future server defines is expressible through the
`…Other` escape (forward-compat, P20) without a library change.

**Source locations.**

- `RefPath.rpUnknown` sits at ordinal 0 in
  `src/jmap_client/internal/types/methods_enum.nim`; `parseRefPath`
  in the same module mirrors `parseMethodName`. `ResultReference.path`
  in `src/jmap_client/internal/types/envelope.nim` delegates to
  `parseRefPath(rr.rawPath)`. Wire emission and wire parsing in
  `internal/serialisation/serde_envelope.nim` both route through
  the verbatim `rawPath` string.
- `RequestContext` (`rcSession` / `rcApi`) lives in
  `src/jmap_client/internal/transport/classify.nim` alongside its
  sole L4 consumers. No hub aggregates `transport/classify`, so the
  symbol is structurally hub-invisible — mirrors the A1c shape where
  the L2 cut also produces no hub.

**Verification gates.**

- `tests/compile/tcompile_a11_refpath_unknown.nim` — positive
  audit: `parseRefPath` resolves through `import jmap_client`;
  vendor paths land on `rpUnknown` while `rawPath` preserves the
  bytes.
- `tests/compile/tcompile_a11_request_context_hub_surface.nim` —
  negative audit: `import jmap_client` does not surface
  `RequestContext`, `rcSession`, or `rcApi`.
- `tests/compile/tcompile_a11_request_context_internal_access.nim`
  — positive internal-access audit: direct import of
  `jmap_client/internal/transport/classify` resolves the symbol.
- `tests/compile/tcompile_a11_wire_enum_invariant.nim` —
  named-list regression defence: every catch-all variant in the
  matrix above plus the typed parser families resolve through the
  hub. Removing any catch-all variant fails CI with an exact-string
  error.

Addition of a new non-compliant open-world wire enum is undetected
by the named-list gate; the comprehensive AST-walking defence is
tracked at H14.

### A12. Error surface *(P1, P5, P7, P13, P15, P18, P20, P28)* — ✅ DONE

Every error type — `ValidationError`, `TransportError`,
`RequestError`, `ClientError`, `MethodError`, `SetError`,
`GetError` — exposes a canonical `message(): string` projection
and a `$` overload delegating to it. The discriminator is `kind`
on every type; every classification enum carries the `*Kind`
suffix (`TransportErrorKind`, `RequestErrorKind`,
`ClientErrorKind`, `MethodErrorKind`, `SetErrorKind`,
`GetErrorKind`); the total parsers follow the same suffix
(`parseRequestErrorKind`, `parseMethodErrorKind`,
`parseSetErrorKind`). The shape an application developer sees is
the same across all seven types — `case err.kind of …` with the
`message()` projection composed deterministically per variant.

`ValidationError.reason` carries the raw failure reason;
`TransportError.detail` carries the wire/exception text. Naming
each field for its semantic role keeps the canonical `message()`
projection structurally non-collidable — the libcurl trap where
"the same thing" returns two different strings depending on
parenthesisation cannot arise.

Library-internal error constructors (`validationError`,
`toValidationError`, `requestError`, `methodError`, `setError`,
the seven `setErrorXxx` smart constructors, both `clientError`
overloads, `validationToClientError`,
`validationToClientErrorCtx`, `getErrorMethod`,
`getErrorHandleMismatch`) are filtered off the hub at
`src/jmap_client/internal/types.nim` via `export … except …` —
the same mechanism A14 uses for `addInvocation`. Application
developers receive error values; they do not construct them.
Custom `Transport` implementations are an exception: the
Transport-contract producers (`transportError`,
`httpStatusError`, `sizeLimitExceeded`,
`classifyTransportException`, `classifyException`,
`enforceBodySizeLimit`) remain public by A19 because a custom
`Transport` MUST return a `TransportError` on failure.

Format stability is locked by
`tests/wire_contract/error-messages.txt` (38 representative
samples), enforced by `tests/lint/h15_error_message_snapshot.nim`
(see Section H, H15), and regenerated by
`scripts/freeze_error_messages.nim` /
`just freeze-error-messages`. Any format change requires the
`[ERR-MSG-CHANGE]` PR label (D17 reviewer checklist).

The five mail-specific extractors at
`src/jmap_client/internal/mail/mail_errors.nim` (`notFoundBlobIds`,
`maxSize`, `maxRecipients`, `invalidRecipientAddresses`,
`invalidEmailProperties`) are exhaustive `case se.kind`
statements with no `else:` arm — adding a `SetErrorKind` variant
forces a compile error at every mail-specific accessor.
`SetError.message` and `TransportError.message` are likewise
exhaustive. The catch-all-`else` anti-pattern lockout matrix
lists A12 alongside A11 / H9.

`tests/unit/tmessages.nim` pins the per-variant format strings;
`tests/property/tprop_errors.nim` carries five property
invariants (determinism, no control bytes, bounded length ≤
4096, classification token in the message, no
`ValidationError.value` leak). The narrative contract lives at
`docs/design/15-error-surface.md`.

### A13. JmapClient destruction semantics *(P8, P12, P24)* — ✅ DONE

`JmapClient` is a ref-object handle
(`src/jmap_client/internal/client.nim` `type JmapClient* = ref
JmapClientObj`); ARC tears down its fields when the last reference
drops. The `JmapClient` itself carries no `=destroy` hook — when
ARC drops the contained `Transport` ref, the Transport's
`=destroy` cascade (A19) invokes the user-supplied `closeImpl`
callback. There is no public `close()` proc on `JmapClient`.

**P24 implication — documented.** `Transport`'s `=destroy` hook at
`src/jmap_client/internal/transport.nim` `=destroy` runs `closeImpl` inside a
`{.cast(gcsafe).}` block because user-supplied closures cannot be
proved gcsafe by ARC; the library's threading invariant (P24) keeps
the destructor on the owning thread, so the cast is structural and
does not represent a real escape. The threading invariant is
restated in both `Transport`'s and `JmapClient`'s type docstrings.

### A14. Demote `addInvocation*` *(P5, P19)* — ✅ DONE

`addInvocation` lives in
`src/jmap_client/internal/protocol/builder.nim` and retains `*`
because sibling internal modules (`mail_methods.nim` etc.) need
to call it as the typed-invocation chokepoint. It is filtered
out of the public surface via the `except` clause in
`internal/protocol.nim`'s `export builder except ...,
addInvocation, ...` clause. Public consumers cannot reach
`addInvocation` through `import jmap_client`; the typed `add*`
family is the user surface.

### A15. Demote remaining JsonNode-typed escape hatches *(P19)* — ✅ DONE

`SerializedSort` / `SerializedFilter` in
`src/jmap_client/internal/protocol/methods.nim` are sealed
Pattern-A objects (A8). `serializeOptSort[S]`,
`serializeOptFilter[C]`, `serializeFilter[C]` are the only
producers; external `SerializedSort(...)` /
`SerializedFilter(...)` field-init from outside `methods.nim`
fails to compile via the `rawValue`-private mechanism that binds
A8. The three serialize helpers are hub-private (filtered via
`except` in `internal/protocol.nim`).

`internal/protocol/builder.nim` exposes a single
argument-construction helper, `directIds(openArray[Id]):
Opt[Referencable[seq[Id]]]`. It absorbs the `Referencable`
sum-type's `direct(...)` arm — a library-specific construction —
so the call site reads `directIds(@[id1, id2])` instead of
`Opt.some(direct(@[id1, id2]))`.

No JsonNode-keyed create-table shim exists. Per-entity create
payloads are typed (`MailboxCreate`, `EmailBlueprint`,
`IdentityCreate`, `EmailSubmissionBlueprint`); the hub-private
generic `addSet[T, C, U, R]` and the five per-entity wrappers
(`addEmailSet`, `addMailboxSet`, `addIdentitySet`,
`addEmailSubmissionSet`, `addVacationResponseSet`) take
`Opt[Table[CreationId, C]]` directly. Consumer call sites
construct creates through the natural Nim idiom
`Opt.some({cid: c}.toTable)`. A typed `initCreates[C]` shim
would shave only stdlib operations (`Opt.some` + `.toTable`)
without absorbing any library-specific construction — P7's
wrap-rate threshold is not met — so the surface stays minimum
(P5). P20 covers future additive recovery if a real consumer
call site emerges where the idiom is awkward.

`tests/compile/tcompile_a1b_protocol_hub_surface.nim` carries a
`doAssert not declared(initCreates)` lock alongside the matching
positive assertion for `directIds`; re-introducing a
JsonNode-keyed create-table helper on the public hub fails at
audit-compile time.

**Documented exception — `addEcho(args: JsonNode)`.** Echo is the
RFC-mandated input-echoes-output method; documented as an
exception in the "Documented exceptions to the principles" section
of this doc.

### A16. Envelope `toJson` publicness *(P5, P7, P8, P19, P1)* — ✅ DONE

The single application-facing send-side wire-shape diagnostic is
`func toJson*(br: BuiltRequest): JsonNode` on the sealed handle the
developer already holds. Modelled after SQLite's
`sqlite3_expanded_sql(stmt)`: render the prepared thing before I/O.
The receive-side / post-transport diagnostic is `setDebugCallback`
(see A31).

Envelope-level emitters are hub-private:

- `Request.toJson` carries `*` inside the consolidated
  `serde_envelope.nim` for cross-internal use (HTTP-body
  construction at `client.performSend` and delegation from
  `BuiltRequest.toJson` in `builder.nim`). Hub-invisible because
  `internal/protocol.nim` does not import `serde_envelope`.
- `Invocation.toJson` carries `*` inside the consolidated
  `serde_envelope.nim` for cross-internal use (called by
  `Request.toJson` in the same module). Same hub-invisibility
  mechanism as `Request.toJson`.
- `ResultReference.toJson` carries `*` inside the consolidated
  `serde_envelope.nim` for cross-internal use (called by
  `methods.nim`'s back-reference encoding for the `rkReference`
  arms of `GetRequest.ids` and `SetRequest.destroy`). Same hub-
  invisibility mechanism.
- `Response.toJson` is intentionally absent. Receive-side
  rendering has no application-code path; the receive-side
  diagnostic is `setDebugCallback` (A31). The parser
  `Response.fromJson` is the only direction L2 carries for the
  Response shape.

Wire-byte order of `BuiltRequest.toJson` is locked by A28b
(`tests/property/twire_determinism.nim`).

**Pointers.**
- `src/jmap_client/internal/protocol/builder.nim` —
  `func toJson*(br: BuiltRequest): JsonNode`.
- `src/jmap_client/internal/serialisation/serde_envelope.nim` —
  consolidated envelope SerDe; `Request.toJson`,
  `Invocation.toJson`, and `ResultReference.toJson` carry `*` for
  cross-internal use; `Response.toJson` is absent.
- `src/jmap_client/internal/protocol.nim` — does not import or
  export `serde_envelope`.
- `tests/compile/tcompile_a1b_protocol_hub_surface.nim` — positive
  audit for `BuiltRequest.toJson` and the A30 accessors;
  `doAssert not compiles(...)` audit for envelope-level
  `toJson` symbols.
- `tests/compile/tcompile_a2_invocation_hub_surface.nim` —
  `doAssert not compiles(inv.toJson)` audit.
- `tests/property/twire_determinism.nim` — A28b byte determinism,
  key order, and round-trip identity properties.

### A17. Typed account-capability surface *(P19)* — ✅ DONE

`src/jmap_client/internal/types/account_capability_schemas.nim`
defines `AccountCapabilityEntry` as a sealed Pattern-A case object
with per-arm payloads: `ckMail` carries `MailAccountCapabilities`
(RFC 8621 §1.3.1), `ckSubmission` carries
`SubmissionAccountCapabilities` (RFC 8621 §1.3.2),
`ckVacationResponse` is discard (RFC 8621 §1.3.3, presence-only).
Per-arm `rawXxxData: JsonNode` (10 arms) covers the unimplemented
named RFCs and vendor URNs, each with inline A22b docstring footer.
`Account` (in `src/jmap_client/internal/types/session.nim`) is sealed
Pattern-A; `parseAccount` carries the B12 silent-drop. Three
convenience accessors live on `Account`: `mailCapability`,
`submissionCapability`, `supportsVacationResponse`.
`parseAccountCapabilityEntry`, `parseMailAccountCapabilities`, and
`parseSubmissionAccountCapabilities` are hub-private; the only
application-visible construction path is `Session.fromJson`.

### A18. `ServerCapability` typed arms *(P19)* — ✅ DONE

`src/jmap_client/internal/types/capabilities.nim` defines
`ServerCapability` as a sealed Pattern-A case object with per-arm
payloads: `ckCore` is typed as `CoreCapabilities`; `ckMail`,
`ckSubmission`, and `ckVacationResponse` are discard arms (RFC 8621
§1.3 declares them empty at session scope); the remaining 9 arms
carry `rawXxxData: JsonNode` with inline A22b docstring footers.
`CoreCapabilities` is sealed Pattern-A. `parseServerCapability` and
`parseCoreCapabilities` are hub-private; construction flows through
`Session.fromJson`.

### A19. `Transport` interface *(P11, P12, P15, P22, P24)* — ✅ DONE

`src/jmap_client/internal/transport.nim` is the public Layer 4 module for
the pluggable HTTP transport. The shape is a two-closure vtable
carried by a private value-object (`TransportObj`) wrapped in a
public ref alias (`Transport*`):

- `SendProc* = proc(req: HttpRequest): Result[HttpResponse,
  TransportError] {.closure, raises: [].}`.
- `CloseProc* = proc() {.closure, raises: [].}`.
- `newTransport*(sendImpl, closeImpl): Result[Transport,
  ValidationError]`. Smart constructor; rejects nil closures.
- `newHttpTransport*(timeout, maxRedirects, maxResponseBytes,
  userAgent): Result[Transport, ValidationError]`. Default
  backend built on `std/httpclient`. All HTTP-level configuration
  lives here, not on `initJmapClient` (P17).
- `send*(t: Transport, req: HttpRequest)`. Public vtable
  dispatcher; the JMAP layer calls this once per `fetchSession`
  / `send`.
- `=destroy` on `TransportObj`. ARC hook; invokes the
  closure-vtable's `closeImpl` exactly once when the last
  `Transport` reference drops.

`JmapClient` carries a `Transport` field; the typed JMAP layer is
oblivious to which HTTP backend is in use. Application developers
plug in libcurl, puppy, chronos, recording proxies, or in-process
mocks by composing the public `newTransport(send, close)` API.

**Two-overload constructor surface** (P3 additive). The endpoint and
credential are sealed Layer-1 sum types (`SessionEndpoint`, `Credential`;
A20/A21), so the construction surface is exactly two overloads:

- `initJmapClient(endpoint, credential, transport)` — primary;
  application developer supplies the transport.
- `initJmapClient(endpoint, credential)` — convenience; delegates to
  `newHttpTransport()`.

A discovery domain is a `SessionEndpoint` variant (`discoveryEndpoint`);
there is no separate discovery constructor.

**C-FFI alignment.** The closure-vtable shape projects directly to
a single C function-pointer-plus-userdata pair at L5. Future C
consumers bring their own HTTP library via callback (the libcurl
`CURLOPT_WRITEFUNCTION` / SQLite-VFS model). See D10's forward
pointer.

### A20. Collapse session entry points *(P3, P5, P19, P20)* — ✅ DONE

The session locator is one sealed Layer-1 sum type, not a spread of
stringly-typed constructor channels.
`src/jmap_client/internal/types/session_endpoint.nim` defines it:

```nim
type SessionEndpointKind* = enum
  sekDirectUrl
  sekDiscoveryDomain
  # sekSrvDomain — reserved; future DNS-SRV autodiscovery (P20/P23)

type SessionEndpoint* {.ruleOff: "objects".} = object
  case rawKind: SessionEndpointKind      # private discriminator (A8b)
  of sekDirectUrl: directUrl: string     # private payload
  of sekDiscoveryDomain: domain: string  # private payload

func kind*(e: SessionEndpoint): SessionEndpointKind  # read-only accessor
func directEndpoint*(url: string): Result[SessionEndpoint, ValidationError]
func discoveryEndpoint*(domain: string): Result[SessionEndpoint, ValidationError]
```

`directEndpoint` and `discoveryEndpoint` are the only producers; the
payload is module-private (A8). A precomputed session URL and a
discovery domain are two variants of one type, so `initJmapClient` takes
a single `SessionEndpoint` (A19); discovery needs no separate
constructor. Resolution to a concrete URL is a Layer-4 concern — `resolveEndpoint` (in `client.nim`) maps the endpoint
to a URL, which `fetchSession` caches in `resolvedSessionUrl`. The
reserved `sekSrvDomain` arm is the single additive seam where DNS-SRV
autodiscovery lands (P20/P23) without a constructor change.

Audits: `tests/compile/treject_a20_sealed_endpoint_construction.nim`
and `tests/compile/tcompile_a20a21_hub_surface.nim`; L1 unit coverage in
`tests/unit/tsession_endpoint.nim`.

### A21. Type the auth scheme *(P17, P18, P19)* — ✅ DONE

The authentication scheme and its secret are one sealed Layer-1 sum
type whose discriminator is the scheme, so a scheme and a mismatched
secret cannot coexist.
`src/jmap_client/internal/types/credential.nim` defines it:

```nim
type AuthScheme* = enum
  asBearer = "Bearer"
  asBasic = "Basic"

type Credential* {.ruleOff: "objects".} = object
  case rawScheme: AuthScheme          # private discriminator (A8b)
  of asBearer: bearerTok: string     # private payload
  of asBasic: basicUser, basicPass: string

func scheme*(c: Credential): AuthScheme  # read-only accessor
func bearerCredential*(token: string): Result[Credential, ValidationError]
func basicCredential*(username, password: string): Result[Credential, ValidationError]
```

- **No `parseAuthScheme`.** Authentication is client→server, so there
  is no "unknown scheme off the wire" to tolerate — no lenient parser,
  no `asUnknown` arm. New schemes are additive `AuthScheme` variants
  (P20).
- **Library owns RFC 7617 encoding.** `base64(user:pass)` is
  materialised at exactly one hub-private site
  (`authorizationHeaderValue`). The encoder is inlined because
  `std/base64.encode` is a side-effecting `proc` that would break the
  module's `{.push raises: [], noSideEffect.}`.
- **Secret never printed.** `$` renders scheme + Basic username only
  (`Credential(Bearer)` / `Credential(Basic, username: alice)`); the
  token and password reach neither `$`, nor `ValidationError.value`
  (every credential violation carries `value = ""`), nor a
  `DebugCallback`.
- **Bearer hardening.** `bearerCredential` rejects an empty token or any
  control char (`{'\0'..'\x1F','\x7F'}`, incl. CR/LF) — the token goes
  verbatim into the `Authorization` header, so control bytes would
  enable header injection. `directEndpoint` applies the same guard to
  URLs.

`setCredential` (on `JmapClient`) rotates the credential; subsequent
requests build the `Authorization` header from the new value.

Audits: `tests/compile/treject_a21_sealed_credential_construction.nim`,
`tests/compile/tcompile_a20a21_hub_surface.nim`; L1 unit coverage in
`tests/unit/tcredential.nim`.

### A22. `addEcho` JsonNode argument policy *(P19)* — ✅ DONE

`src/jmap_client/internal/protocol/builder.nim` exposes
`addEcho(b, args: JsonNode)` returning `ResponseHandle[JsonNode]`.
RFC 8620 §4 makes Core/echo "server returns input verbatim",
which is structurally JsonNode-shaped — typing the args would be
fictional precision.

The decision: `args: JsonNode` for `addEcho` is the explicit
RFC-mandated exception to P19. It is enumerated in the
"Documented exceptions to the principles" section of this
document and allowlisted in the H11 lint
(`tests/lint/h11_typed_builder_no_jsonnode.nim`). Any other
JsonNode-typed public proc requires a similar written exception
in the same section, plus the A22b docstring footer at the
declaration site.

### A23. `PushChannel` type reservation *(P20, P23)* — ✅ DONE

P23 says "the type they will inhabit is named in the public design
now". A name reservation without a type stub means any future 1.x can
land *any shape* of `PushChannel` — including a shape that puts it on
`JmapClient` as a method (the libdbus retrofit P23 exists to prevent).

The type stub lives at `src/jmap_client/internal/push.nim`:

```nim
type PushChannel* = ref object
  ## Reserved handle for HTTP push notifications (RFC 8620 §7).
```

Re-exported from `src/jmap_client.nim` via
`import jmap_client/internal/push; export push`. P23 names the
*type*; the type declaration alone fulfils it. Future Push lands by
adding methods to `PushChannel`, never to `JmapClient`. The module
path `jmap_client/push` is NOT reserved (P5 minimum surface); if
Push earns its own path later, that is a minor bump per P20. The
closed-set lock at A10 prevents the path from sneaking in pre-1.0.
A dedicated positive surface gate,
`tests/compile/tcompile_a23a24_push_websocket_surface.nim`, asserts
`declared(PushChannel)` / `declared(WebSocketChannel)` over
`import jmap_client`.

### A24. `WebSocketChannel` type reservation *(P20, P23)* — ✅ DONE

Same shape as A23 but for RFC 8887 (WebSocket). Distinct type
from `PushChannel` — WebSocket is a different transport (a
bidirectional connection upgraded from HTTPS), not a Push
variant; conflating them is the libdbus-style retrofit failure
mode.

The type stub lives at `src/jmap_client/internal/websocket.nim`:

```nim
type WebSocketChannel* = ref object
  ## Reserved handle for RFC 8887 JMAP-over-WebSocket.
```

Re-exported from `src/jmap_client.nim`. The module path
`jmap_client/websocket` is NOT reserved (A10 / P5); if
WebSocket earns its own path later, that is a minor bump per P20.

### A25. Type-shape snapshot in CI *(P1, P2)* — ✅ DONE

A26's `public-api.txt` snapshot catches symbol-set drift but not
field-set drift. A `Request` whose `using*: seq[string]` field is
silently changed to `seq[CapabilityUri]` would break consumers; the
symbol-set snapshot would not flag it.

**Implementation.** `tests/wire_contract/type-shapes.txt` records the
public-field signature of every public type reachable through the hub —
object fields, case discriminator and variants, and enum members — with
private `raw*` fields excluded so internal sealing refactors do not churn
the snapshot (a sealed Pattern-A type therefore shows an empty shape; its
accessors are tracked as `func`s by A26). The H17 lint recomputes the
shapes and fails CI bidirectionally on any un-frozen drift; a deliberate
change regenerates via `just freeze-type-shapes` and carries the
`[TYPE-SHAPE-CHANGE]` PR label. Wired into `check` and `ci`. The
mechanical generator is A25b.

**Pointers.**
- `scripts/api_oracle.nim` (`API_ORACLE_MODE=type-shapes`) — the
  compiler-as-library oracle, invoked identically by generator and lint
  so the two cannot drift.
- `scripts/api_probe.nim` — the in-repo compile target the oracle reads,
  so the surface is computed under the project's own `config.nims` flags.
- `justfile` — `_api-oracle` (builds it), `freeze-type-shapes` (generator).
- `tests/lint/h17_type_shape_snapshot.nim` — H17 lint.
- `tests/wire_contract/type-shapes.txt` — frozen snapshot.

### A26. Re-export hub snapshot *(P1)* — ✅ DONE

The set of symbols reachable through `import jmap_client` — the single
public entry point (A1, A10) — is a public commitment once 1.0 ships:
adding or removing a re-exported symbol changes the import graph
consumers observe.

**Implementation.** `tests/wire_contract/public-api.txt` snapshots that
surface — one `<kind> <name> <signature>` line per `*`-exported
declaration, grouped by owning module. The surface is enumerated by a
compiler-as-library oracle (`scripts/api_oracle.nim`) that reads the
post-sem interface table of `scripts/api_probe.nim`, an in-repo module
whose sole content is `import jmap_client` / `export jmap_client`. That
table is the compiler's own answer to "what does `import jmap_client`
expose", so own symbols, re-exports and `except` filters need no
re-derivation; compiling in-repo also means the project's `config.nims`
flags apply, and no text scraper has to model Nim's export rules. The
earlier `nim jsondoc` routes were rejected first: over the hub it yields
zero entries (it does not follow re-exports), and `--project`
over-captures. The H16 lint recomputes the surface and fails CI
bidirectionally on any add or remove; a deliberate change regenerates via
`just freeze-api` and carries the `[API-CHANGE]` PR label. F6 is the
CI-wiring side of the same gate.

**Pointers.**
- `scripts/api_oracle.nim` (`API_ORACLE_MODE=api`) — the oracle.
- `scripts/api_probe.nim` — the compile target it enumerates.
- `justfile` — `_api-oracle` (builds it), `freeze-api` (generator).
- `tests/lint/h16_public_api_snapshot.nim` — H16 lint.
- `tests/wire_contract/public-api.txt` — frozen snapshot.

### A27. Seal the handle types *(P8)* — ✅ DONE

All handle types are sealed Pattern-A objects with private `raw*`
fields and explicit accessors:
`ResponseHandle[T]`, `NameBoundHandle[T]`, `CompoundHandles[A, B]`,
plus `DispatchedResponse` (the sealed wrapper that pairs the wire
`Response` with a `BuilderId`). The generic `ChainedHandles[A, B]`
was removed in B9 (it reduced to two `dr.get` calls); the one chain
that needed a heterogeneous pair — `Email/query` → `SearchSnippet/get`
— is now the bespoke sealed handle record `EmailQuerySnippetChain`.
The two single-call handles additionally carry a `rawParseProc:
ParseProc[T]` field — the captured resolver bound at handle
construction time (A6, A1c).

**Pointer.** `src/jmap_client/internal/protocol/dispatch.nim`.

### A28. `Request` and `Response` opacity decision *(P8, P19)* — ✅ DONE

`Request` and `Response` are pure wire-data carriers. Dispatch
metadata lives on sealed wrappers: `BuiltRequest` on the request
side, `DispatchedResponse` on the response side. SQLite-style
opacity (compiled dispatch artifact vs row data); libcurl-style
ownership (easy handle vs response bytes).

`Request` and `Response` are themselves sealed Pattern-A objects
(A30): private `raw*` fields, hub-private smart constructors. The
types are hub-internal in full (A30b) — `import jmap_client` exposes
neither the types nor their accessors. The app-facing wire surface is
the `BuiltRequest` / `DispatchedResponse` handles plus `Referencable[T]`.
The wire-emit surface is hub-private (A16) — the application-facing
diagnostic seams are `BuiltRequest.toJson` (send-side) and
`setDebugCallback` (receive-side). The SQLite/libcurl opacity is
complete: the app holds easy handles, never raw wire records.

**Pointers.**
- `src/jmap_client/internal/protocol/builder.nim` —
  `BuiltRequest` sealed; `request` / `builderId` / `callLimits`
  accessors hub-private.
- `src/jmap_client/internal/protocol/dispatch.nim` —
  `DispatchedResponse` sealed; `response` / `builderId`
  hub-private; `sessionState` / `createdIds` hub-public.

### A29. `GetResponse[T]` `list ∩ notFound = ∅` disjointness *(P16)* — ✅ DONE

`internal/protocol/methods.nim` `GetResponse[T]` carries `list` and
`notFound` as two independent seqs, so the same id could structurally
appear in both. RFC 8620 §5.1 defines an id as *either* a found object
*or* a missing id; the only explicit MUST is the duplicate-request-id
case (rfc8620 lines 1648-1651), so full distinct-id disjointness is the
**inferred** invariant P16 closes here.

`GetResponse[T]` is server-emitted and no caller constructs it, so the
project's lenient-ingress / strict-egress rule lands A29 on the lenient
arm (Postel; cf. receive-side B12, the opposite of send-side A6.6).
`GetResponse[T].fromJson` folds in the **total** helper
`reconcileNotFound` (`serialisation/serde_helpers.nim`): on overlap it
drops the id from `notFound` and keeps the `list` entry (the wire `id`
is positive existence evidence). It is silent — L1–L3 are `{.push
raises: [], noSideEffect.}`, so logging is impossible; the raw bytes
stay inspectable via the A31 `setDebugCallback` seam. Being total, it is
a `fromJson` fold, not a fallible `parse*`/`parseGetResponse` constructor
(A30 naming).

`ChangesResponse` and `QueryChangesResponse` are deliberately untouched:
their cross-set overlaps are RFC-legal (§5.2 created/updated/destroyed
MAY repeat) or RFC-required (§5.6 an id in both `removed` and `added` on
a mutable-property re-index), not illegal states. A one-line comment at
each sibling's `fromJson` records this so A29 is not mistakenly extended.

Rejected: an A4-style `Table[Id, …]` model (the `ids: null` fetch-all
mode has no key set, and the dominant pattern iterates `list` as a
`seq` — a P7 cost to prevent a spec-violating-server-only bug); sealing
the response generics (A8 keeps them transparent; out of scope);
reject-as-`MethodError` (wrong layer + contradicts lenient ingress);
do-nothing (P16).

**Pointers.**
- `src/jmap_client/internal/serialisation/serde_helpers.nim` —
  `reconcileNotFound` (total; drops `list`-present ids from `notFound`).
- `src/jmap_client/internal/protocol/methods.nim` —
  `GetResponse[T].fromJson` folds it in; sibling `fromJson`s carry the
  RFC-legal-overlap comments.
- `tests/protocol/tmethods.nim` — six deterministic cases plus the
  `propGetResponseNotFoundDisjoint` property guard the invariant.

### A2b. Property test: `Invocation` round-trip *(P19, P2)* — ✅ DONE

`tests/property/tprop_envelope.nim` gains `propInvocationRoundTrip`:
`Invocation.fromJson(toJson(inv)).get() == inv` for **every** `MethodName`
variant — the 27 named ones (via `initInvocation`, which stores the wire name)
plus the `mnUnknown` catch-all exercised through a synthesised vendor wire name
(via `parseInvocation`, which preserves the raw bytes — A11 forward-compat).
`Invocation` is a flat object, so its auto-generated structural `==` compares
all three fields including the `JsonNode` arguments (std/json structural `==`).
The envelope SerDe is reached through the H10-permitted direct leaf import of
`internal/serialisation/serde_envelope` (the SerDe is hub-internal — A16/A30b).

The wire-byte determinism slice for `BuiltRequest.toJson` (which embeds the
Invocation array) remains owned by A28b. `Response.toJson` is intentionally
absent (A16); the receive-side wire-shape contract is exercised by the
captured-fixture two-parse identity in
`tests/serde/captured/tcaptured_round_trip_integrity.nim` and the parser
totality property in `tests/property/tprop_serde.nim`.

### A3.5. Decide `SetResponse[T].updateResults` payload shape *(P19)* — **RESOLVED**

Resolved by A4 D2 — `updateResults` carries typed `Opt[U]`, with
`U` the per-entity `PartialT`. No semver-upgrade path is required:
the `PartialT` family is part of A4's surface.

### A3.6. Partial-entity types for sparse `/get` responses *(P5, P7, P16, P19)* — ✅ DONE

Six `PartialT` types are in place: `PartialEmail`, `PartialMailbox`,
`PartialIdentity`, `PartialEmailSubmission`, `PartialVacationResponse`,
`PartialThread`. Each mirrors the full read model — wire-nullable
fields typed as `FieldEcho[T]` (three-state: absent / null / value);
wire-non-nullable fields typed as `Opt[T]` (two-state: absent /
value). Receive-side parsers are lenient on missing, strict on
wrong-kind-present (D4). Closed-enum wire tokens
(`PartialEmailSubmission.undoStatus: Opt[UndoStatus]`) stay typed —
unknown tokens surface as `SerdeViolation`.

Each `PartialT` registers as a getter-only JMAP entity (D7) — same
`MethodEntity` tag, capability URI, and `getMethodName` as the full
record; no setter / queryer / changes / copy / import overloads.
Each is also the typed `U` slot of `SetResponse[T, U].updateResults`
(A4), so every `/set` echo path is `PartialT`-typed.

**The invariant.** A get builder that can emit a property filter
returns a filter-tolerant `PartialT`; a strict full-record type is
unreachable through a property filter; and property selection is a
typed per-entity value, never a string list. Two illegal states are
unrepresentable by construction:

- *A property filter reaching a strict parser (P16).* The full-record
  wrappers take no `properties` parameter, so a property filter has no
  path to a strict `GetResponse[T]`. Were one to reach it, the five
  strict-parser entities would yield a record missing required fields
  → `SerdeViolation` → `MethodError(metServerFail)` (a sparse Mailbox
  badge-count fetch `@["unreadEmails", "totalEmails"]` is the canonical
  case). The typed `addPartial<E>Get` wrappers are the sole
  property-filter path, and they return a lenient `Partial<E>`.
- *Stringly-typed property selection (P19).* Get-property selection is
  a typed per-entity value (the selectors below), not a `seq[string]`.

**Public surface.**

- **Seven typed selectors**, each a sealed Pattern-A case object whose
  backing strings are the exact RFC 8621 wire names, with named `…p`
  constants, `kind` / `wireName` / `$` / `==` / `hash`, a classifying
  `parse…` smart constructor, and a `…Other` forward-compat escape arm
  (private `rawIdentifier`): `MailboxGetProperty`, `ThreadGetProperty`,
  `IdentityGetProperty`, `EmailSubmissionGetProperty`,
  `VacationResponseGetProperty`, `EmailGetProperty`, `EmailBodyProperty`.
  The two Email selectors additionally carry a typed `…Header` arm
  (`HeaderPropertyKey` payload) for the dynamic
  `header:Name[:form][:all]` form. Selectors flow client→server only —
  no `fromJson`. `EmailGetProperty` is reused for `Email/parse` (RFC
  8621 §4.9 shares the Email/get property set — P3/P5).
- **Six partial-get wrappers**: `addPartialMailboxGet`,
  `addPartialThreadGet`, `addPartialIdentityGet`,
  `addPartialEmailSubmissionGet`, `addPartialVacationResponseGet`,
  `addPartialEmailGet`. Each takes a **required** `properties:
  NonEmptySeq[<E>GetProperty]` — an empty selection is meaningless
  (`id` is always returned), so `NonEmptySeq` makes the empty case
  unrepresentable (P16). A back-reference is supplied through the
  shared `ids: Opt[Referencable[seq[Id]]]` parameter (`ids =
  Opt.some(reference[seq[Id]](h, name, path))`), so there are no
  `*ByRef` variants. They share the hub-private generic engine
  `addGetSelected[T, P]` in `builder.nim` (VacationResponse is
  hand-rolled for its `idCount: 1` singleton meta).
- **`bodyProperties` is typed**:
  `EmailBodyFetchOptions.bodyProperties: Opt[NonEmptySeq[EmailBodyProperty]]`.
- **`addEmailQueryWithThreads`** (the RFC 8621 §4.10 first-login
  display pipeline) emits a property filter, so by the invariant its
  `threadIdFetch` / `display` handles are `GetResponse[PartialEmail]`;
  `DefaultDisplayProperties` is a typed
  `NonEmptySeq[EmailGetProperty]`.

**Full vs sparse are distinctly named, not overloaded.** `add<E>Get`
returns `GetResponse[<E>]`; `addPartial<E>Get` returns
`GetResponse[Partial<E>]`. The two entry points return structurally
different types (full record vs all-`Opt`/`FieldEcho` projection), so
distinct names keep the projection a call-site-visible choice rather
than a return type that silently depends on whether `properties` was
passed (P16/P19). This is the conscious trade-off against P3's
overloading example.

**`Email` parser is lenient, by design.** `addEmailGet` is the
full-record contract; `addPartialEmailGet` is the projection contract.
`emailFromJson` reads every field through `parseOpt*` helpers and never
fails on absence — all-`Opt` by Postel's law (real servers omit
fields; strictness would regress robustness, P7/P29). The five
strict-parser entities are strict-on-presence. This lenient-Email /
strict-five asymmetry is intentional and structural, not a gap to
close.

**Pointers.**
- Selectors: `mailbox.nim`, `thread.nim`, `identity.nim`,
  `email_submission.nim`, `vacation.nim`, `email.nim` (the two Email
  selectors).
- Generic engine: `addGetSelected` in `internal/protocol/builder.nim`
  (hub-private via the `protocol.nim` `except` list).
- Wrappers: `mail_builders.nim`, `identity_builders.nim`,
  `submission_builders.nim`, `mail_methods.nim`.
- Coverage: `tests/unit/mail/tget_property_selectors.nim`, plus
  per-wrapper emit assertions in `tmail_builders.nim` /
  `tmail_methods.nim` and the hub audits
  `tcompile_a1d_mail_hub_surface.nim` /
  `tcompile_a1b_protocol_hub_surface.nim`.

### A6.5. Sealed `BuiltRequest` and `DispatchedResponse` types *(P8, P21)* — ✅ DONE

`BuiltRequest` is the sealed, branded carrier produced by
`RequestBuilder.freeze()` and consumed by `JmapClient.send`.
`DispatchedResponse` is the sibling sealed type returned by
`send`, carrying the wire `Response` plus the brand. Both have
private fields; the only public producers are the lifecycle
transitions (`freeze`, `send`) plus the hub-private internal
escapes (`builtRequestFromParts`, `initDispatchedResponse`)
filtered from `internal/protocol.nim`'s re-export and reached
only via direct internal import (H10-permitted in `tests/`).

The asynchronous-path `DispatchedRequest` is reserved by name in
`docs/policy/03-rfc-extension-policy.md` (A7e ✅), not by stub. Its shape
depends on the `Transport` interface and lands once async arrives as additive
surface (P20).

**Pointers.**
- `src/jmap_client/internal/protocol/builder.nim` —
  `BuiltRequest` declaration plus `builtRequestFromParts`
  internal escape.
- `src/jmap_client/internal/protocol/dispatch.nim` —
  `DispatchedResponse` declaration and `initDispatchedResponse`
  escape.

### A6.6. Sibling-creation cid invariant on `addEmailSubmissionAndEmailSet` *(P16)* — ✅ DONE

RFC 8620 §5.3 ties every `icrCreation(cid)` reference in
`onSuccessUpdateEmail` and `onSuccessDestroyEmail` to a
`CreationId` appearing as a key in `create` on the same call.
`addEmailSubmissionAndEmailSet` enforces this at the builder
boundary via the per-call smart constructor `validateOnSuccessCids`;
failure surfaces as `ValidationError` before any wire
serialisation, not as a server-side `SetError(setNotFound)`
round-trip. `icrDirect` references are exempt (server-persisted
ids are validated separately by the server).

**Why a smart constructor and not a phantom type.** A phantom-typed
`OnSuccessUpdateEmail[CreateScope]` would force every consumer to
thread the scope marker through the call site, multiplying the
public surface for marginal benefit. The validation is concentrated
at one boundary (`addEmailSubmissionAndEmailSet`) and the failure
mode is rare; an informative `ValidationError` is the right
ergonomic tradeoff.

**Pointers.**
- `src/jmap_client/internal/mail/submission_builders.nim` —
  `validateOnSuccessCids` + `addEmailSubmissionAndEmailSet` return
  type `Result[(RequestBuilder, EmailSubmissionHandles), ValidationError]`.
- `tests/unit/mail/tsubmission_cid_invariant.nim` — exercises the
  three branches: mismatch returns `ValidationError`; matching
  `create` returns `ok`; `icrDirect` exempt returns `ok`.

### A7b. Lifecycle: `RequestBuilder.freeze()` and `JmapClient.send(BuiltRequest)` *(P21, P16)* — ✅ DONE

`RequestBuilder.freeze() → BuiltRequest` produces the frozen,
branded carrier. `JmapClient.send(BuiltRequest) →
JmapResult[DispatchedResponse]` is the sole blessed send path —
neither raw `Request` nor unfrozen `RequestBuilder` is accepted.
Future async-path overload (A19 + E1) extends the chain
additively per A7e.

**Pointers.**
- `src/jmap_client/internal/protocol/builder.nim` — `freeze`,
  `BuiltRequest`.
- `src/jmap_client/internal/client.nim` `send` — `send(BuiltRequest)`;
  `validateLimits` (`client.nim`) operates on `BuiltRequest`.

### A7c. Consume `BuiltRequest` on `send` *(P16, P21)* — ✅ DONE

`src/jmap_client/internal/client.nim` — `proc send*(client: JmapClient,
req: sink BuiltRequest): JmapResult[DispatchedResponse]`.
`BuiltRequest` is uncopyable: its `=copy` and `=dup` hooks
(`src/jmap_client/internal/protocol/builder.nim`, just after the
type definitions) are declared with `{.error: "BuiltRequest is
uncopyable; transfer ownership via `sink`".}`. The canonical Nim
idiom — used verbatim in `lib/std/tasks.nim`, `lib/std/isolation.nim`,
`lib/std/private/threadtypes.nim`, and `lib/std/widestrs.nim` —
converts `sink` from an optimisation hint into a structural
single-use contract.

Without the hooks, `sink` only requests a move at the last use and
silently inserts a copy at any non-last use (Nim `destructors.md`
§"Sink parameters"). With them, every non-last use of a
`BuiltRequest` is a compile error of the form *"requires a copy
because it's not the last read of '<name>'"*. A re-dispatch of the
same value cannot compile; the brand-alias hazard between two
`DispatchedResponse`s from one `BuiltRequest` is closed at the
type level. A retry replays `freeze` from a freshly constructed
builder.

Read-only accessors on `BuiltRequest` (`request`, `builderId`,
`callLimits`) take a plain `BuiltRequest` object parameter — passed
by hidden reference, so an accessor read does not trigger the
`{.error.}` copy machinery; the same applies to
`validateLimits(req: BuiltRequest, …)`, which `send` invokes once
before consuming `req`.

The hub-private internal escape `builtRequestFromParts`
(`builder.nim`) is filtered out of `internal/protocol.nim`'s
re-export and reached only via direct internal import; tests
under H10's `tests/` allowlist use it for whitebox fixture
scaffolding. Production code routes through
`RequestBuilder.freeze()`.

**Compile-reject anchor.**
`tests/compile/treject_a7c_send_consumes_builtrequest.nim` is a
testament `action: "reject"` file: it asserts the compiler emits
*"requires a copy because it's not the last read of"* against a
double-`send`. The substring is sourced from
`compiler/injectdestructors.nim:207` and stable across Nim 2.2.x.

### A7d. Consume `RequestBuilder` on `freeze` *(P16, P21)* — ✅ DONE

`RequestBuilder` is now **structurally uncopyable** — `=copy` / `=dup`
`{.error.}` hooks alongside `BuiltRequest`'s (`builder.nim`). Freezing the same
builder twice, or calling any `add*` on it after `freeze`, is a compile error
(*"requires a copy because it's not the last read"*), closing the brand-alias
hazard at the type level rather than merely advising it with `sink`. The whole
lifecycle is now uncopyable: `newBuilder` → `add*` chain → `freeze` → `send`,
each phase consuming its input.

**The documented friction did not materialise** (the escalation predated the
A1c/A30b refactors that reshaped dispatch/handles):

- *Module-top-level test friction* — a non-issue. `tests/mtestblock.testCase`
  wraps every test body in a `proc`, so builder chains run in normal-function
  move-analysis scope, not at module top-level. A full sweep of all 319 test
  files surfaced only **3** real copy-failures (not ~80).
- *`Result[(RequestBuilder, …)]` extraction* — production compiles unchanged;
  `addCapabilityInvocation` / `addEmailSubmissionAndEmailSet` and `?`-propagation
  through them are fine. Only **callers** that extract the uncopyable Ok tuple
  via `.get()` / `.expect()` needed the move idiom `var r = …; doAssert r.isOk;
  let (b, h) = move(r.value)` — documented on the builders and the module
  comment for application developers.

**Production change:** one site, `addPartialEmailGet` (`mail_builders.nim`),
read `b1.builderId` in the same expression that moved `b1` into the return
tuple; fixed by binding `let brand = b1.builderId` first (the pattern every
other builder already uses). **Test changes:** `massertions.assertOk`/`assertErr`
now *borrow* their argument (`doAssert (expr).isOk`) instead of `let res = expr`
(which copied the uncopyable Result); a `moveExpect` helper plus an inline
`move(r.value)` in the two on-success submission live tests.

**Compile-reject anchors.** `tests/compile/treject_a7d_freeze_consumes_builder.nim`
(double `freeze`) and `tests/compile/treject_a7d_post_freeze_add.nim` (`add*`
after `freeze`) both `action: "reject"` on *"requires a copy because it's not
the last read of"*, and both pass. Full fast suite green.

### A7e. Async surface name reservation *(P20, P22, P23)* — ✅ DONE

The asynchronous chain extends the sync chain additively:

`RequestBuilder` → `BuiltRequest` → `DispatchedRequest` (in-flight
token) → `DispatchedResponse` (received).

`DispatchedRequest` and its companion procedure `sendAsync` are
reserved **by policy, not by type stub**, in
`docs/policy/03-rfc-extension-policy.md` (now written; it also carries the
D13/D13.5 RFC reservation table). Their shapes depend on the `Transport`
interface (A19); committing a stub before A19 fixes the transport contract is
the libdbus failure P23 cites — retrofit a shape that does not fit the runtime.
Reservation suffices because no public API claims either name pre-1.0, so adding
them once async lands is purely additive (P20). Unlike `PushChannel` (A23) and
`WebSocketChannel` (A24), `DispatchedRequest` has no consumer-facing calling
site on the sync path; an `unimplemented()` stub would have no caller and serve
no diagnostic purpose. The `RequestBuilder` and `BuiltRequest` type docstrings
(`builder.nim`) carry the one-line forward-pointer to the policy file. The
mechanical gate (F6's re-export-hub snapshot failing if `sendAsync` /
`DispatchedRequest` are ever exported pre-1.0) lands with A26.

The policy-file content reserved is:

> **Async dispatch (lands with A19 + E1).** The async overload is
> a separate procedure `sendAsync` — never an overload of `send`,
> never a runtime flag (P22). Signature: `proc sendAsync(client:
> JmapClient, req: sink BuiltRequest):
> JmapResult[DispatchedRequest]`. `proc await(dr: sink
> DispatchedRequest): JmapResult[DispatchedResponse]` consumes the
> in-flight token and yields the same `DispatchedResponse` the
> sync path produces. The names `sendAsync` and
> `DispatchedRequest` are reserved for this contract; no public
> API claims them pre-1.0.

Add a one-line forward-pointer on the `RequestBuilder` and
`BuiltRequest` docstrings: `## Async dispatch (post-1.0) returns
DispatchedRequest from sendAsync; see
docs/policy/03-rfc-extension-policy.md.`

**Mechanical gate.** F6's re-export hub snapshot fails CI if any
public module exports `sendAsync` or `DispatchedRequest` pre-1.0.

### A22b. Inline docstrings at every JsonNode-public field declaration *(P19)* — ✅ DONE

Every public `JsonNode` field, parameter, and `MailboxRights`
declaration in `src/` carries an inline P19/P18 docstring footer
citing its exception. The 24 footer-bearing sites are:

- `MethodError.extras` and `SetError.extras` in
  `src/jmap_client/internal/types/errors.nim`.
- `addEcho(args)` and `addCapabilityInvocation(args)` parameters in
  `src/jmap_client/internal/protocol/builder.nim`.
- `MailboxRights` in `src/jmap_client/internal/mail/mailbox.nim`
  (P18 exception, Decision B6).
- 9 `rawXxxData` arms on `ServerCapability` in
  `src/jmap_client/internal/types/capabilities.nim` (ckWebsocket,
  ckMdn, ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars,
  ckSieve, ckUnknown).
- 10 `rawXxxData` arms on `AccountCapabilityEntry` in
  `src/jmap_client/internal/types/account_capability_schemas.nim`
  (ckCore, ckWebsocket, ckMdn, ckSmimeVerify, ckBlob, ckQuota,
  ckContacts, ckCalendars, ckSieve, ckUnknown).

Any additional public `JsonNode` declaration must either fall under
one of the four documented exception patterns above or carry an
A22b footer at its declaration site.

### A25b. Generate the type-shape snapshot mechanically *(P1)* — ✅ DONE

A25 specifies the snapshot file (`tests/wire_contract/type-shapes.txt`)
but a hand-maintained file rots fast, so the producer is mechanical and
shared with the lint.

**Implementation.** `just freeze-type-shapes` runs the API oracle in
`API_ORACLE_MODE=type-shapes`; `just lint-type-shapes` (H17) runs the
same binary in the same mode and diffs its output against the committed
file, so generator and lint cannot drift. Output format: one
`## <Type> [<module>]` section per public type, alphabetical by name,
each public field on its own line with its typed annotation and case
arms preserved at their relative indentation. Shapes are rendered from
the compiler's post-sem type AST rather than scraped from source, so
private fields are excluded by construction and no text parser has to
model Nim's visibility rules. CI (H17) fails if the recomputed shapes
disagree with the committed copy and the PR is not labelled
`[TYPE-SHAPE-CHANGE]`.

**Pointers.**
- `scripts/api_oracle.nim` (`API_ORACLE_MODE=type-shapes`) — the oracle.
- `justfile` — `_api-oracle`, `freeze-type-shapes`, `lint-type-shapes`.

### A28b. Wire-byte determinism for `BuiltRequest.toJson` *(P1)* — ✅ DONE

`$br.toJson()` produces the same bytes on every call for the same
`BuiltRequest`. Top-level key order is locked as `using`,
`methodCalls`, then `createdIds` (when present). Round-trip identity
holds through wire bytes:
`Request.fromJson(parseJson($br.toJson())).get() == br.request`.

100 random `BuiltRequest`s via `tests/mproperty.nim:genBuiltRequest`
exercise each invariant.

**Pointers.**
- `tests/property/twire_determinism.nim` — three property cases.
- `tests/mproperty.nim:genBuiltRequest` — generator added alongside
  the existing `genRequest` / `genResponse`.

### A30. Seal `Request` and `Response` as Pattern-A objects *(P5, P8, P15, P19)* — ✅ DONE

`Request` and `Response` are Pattern-A objects, matching the shape
that `Invocation` and `ResultReference` use elsewhere in
`envelope.nim`: private `raw*` fields and hub-private smart
constructors following the `initX` (total) / `parseX` (fallible)
convention. The read accessors (`req.\`using\``, `req.methodCalls`,
`req.createdIds`, `resp.methodResponses`, `resp.createdIds`,
`resp.sessionState`) serve internal consumers only — the whole
envelope surface is hub-internal (A30b), so they are reachable
exclusively by direct `envelope`-leaf import. The smart constructors
follow the `initX` (total) / `parseX` (fallible) convention:

- `initRequest` (total, build path) — used by
  `RequestBuilder.freeze`.
- `parseRequest` (fallible, wire boundary) — enforces RFC 8620
  §3.3's non-empty-`using` invariant; called only by
  `Request.fromJson`.
- `initResponse` (total) — Response is server-emitted only, with
  no client-construction case to validate; field-level invariants
  are enforced upstream by the field-level parsers.

Raw `Request(rawUsing: …, …)` construction is impossible outside
`envelope.nim`. `RequestBuilder.freeze` routes through
`initRequest` directly (no `.get()`, no panic risk — the build
path's non-empty-`using` invariant is proved upstream by
`initRequestBuilder` seeding the JMAP core URN). `Request.fromJson`
routes through `parseRequest` via `wrapInner` (bridging
`ValidationError` to `SerdeViolation`). `Response.fromJson` routes
through `initResponse` directly.

**Pointers.**
- `src/jmap_client/internal/types/envelope.nim` — Pattern-A sealed
  `Request` and `Response`, six read accessors, three smart
  constructors, shared nimalyzer rationale comment.
- `src/jmap_client/internal/types.nim` — `export envelope except
  arguments, initRequest, parseRequest, initResponse`.
- `src/jmap_client/internal/protocol/builder.nim` — `freeze`
  routes through `initRequest`.
- `src/jmap_client/internal/serialisation/serde_envelope.nim` —
  `Request.fromJson` via `wrapInner(parseRequest(...))`;
  `Response.fromJson` via `ok(initResponse(...))`.
- `tests/compile/tcompile_a1b_protocol_hub_surface.nim` — positive
  audit for accessor reachability through the hub; negative audit
  for raw-field construction and smart-constructor reachability.

### A31. Per-handle debug callback for wire inspection *(P11, P7)* — ✅ DONE

`JmapClient` carries an optional `DebugCallback` set via
`setDebugCallback`. Modelled after libcurl's
`CURLOPT_DEBUGFUNCTION`: the library invokes the callback once with
`wdSend` (request body bytes — empty `openArray[byte]` for the GET
on `fetchSession`) immediately before each `Transport.send`, and
once with `wdReceive` (response body bytes) immediately after. Both
`fetchSession` and `send` fire the callback. Closure-based; no
global state; no link-time symbol. Pass `nil` to detach; the
library does not provide a separate `clearDebugCallback`.

Pairs with A16's send-side `BuiltRequest.toJson` seam: the
application can render planned bytes and observe wire bytes
through two distinct, per-handle, typed surfaces. The two seams
compose — differences between planned and observed bytes are by
design (TLS-layer rewrites, `Content-Length` and `Authorization`
headers, connection pooling, server redirects) and live between
the two.

**Pointers.**
- `src/jmap_client/internal/client.nim` — `WireDirection` enum,
  `DebugCallback` proc type, `setDebugCallback`, private
  `debugCallback` field on `JmapClientObj`, `fireDebug` helper,
  four fire sites across `fetchSession` and `performSend`.
- `tests/unit/tdebug_callback.nim` — seven property anchors:
  nil-clears, byte-identity in both directions, fire order,
  `fetchSession` firing both, `send` firing both, callback
  replacement.
- `docs/design/04-layer-4-design.md` §1.7 — narrative covering
  both diagnostic seams (`BuiltRequest.toJson` and
  `setDebugCallback`) and how they compose.

### A30b. The envelope wire surface is hub-internal; `Referencable` is sealed *(P5, P7, P8, P15, P16, P19)* — ✅ DONE

The entire RFC 8620 §3.2–3.4/3.7 envelope surface is hub-internal.
`internal/types.nim` re-exports `envelope except` **every** public
symbol bar `Referencable` (the type) and `direct` (its direct-value
constructor) — so `Invocation`, `Request`, `Response`,
`ResultReference`, `ReferencableKind`, all their accessors
(`methodCallId`, `name`, `arguments`, `rawName`, `using`,
`methodCalls`, `createdIds`, `methodResponses`, `sessionState`,
`path`, `rawPath`, `resultOf`, `kind`, `asDirect`, `asReference`)
and all their constructors (`initInvocation` / `parseInvocation` /
`initRequest` / `parseRequest` / `initResponse` /
`initResultReference` / `parseResultReference` / `referenceTo`) are
reachable only by direct `envelope`-leaf import inside the library.
No hub-public API returns a raw envelope value (`request*` /
`response*` are themselves hub-filtered), so application code cannot
obtain one. The app-facing wire surface is the `BuiltRequest` /
`DispatchedResponse` handles plus `Referencable[T]`.

`Referencable[T]` is a sealed generic case object: private `rawKind`
/ `rawValue` / `rawReference`, public `kind` plus `asDirect` /
`asReference` `Opt`-accessors — consumers never read a raw arm.
`ResultReference` holds a private `rawResultOf` with a `resultOf`
accessor, closing discriminator-free partial construction on that
field. The single back-reference primitive is `reference[U](handle:
ResponseHandle[auto], name, path): Referencable[U]` (`dispatch.nim`).

**Design notes.**
- `reference` takes `ResponseHandle[auto]` with a single explicit
  generic `U` (the referenced value type), not `reference[U, T](handle:
  ResponseHandle[T], …)`: `U` appears only in the return type, and Nim
  2.2.8 will not infer a parameter-only generic when a return-only
  generic is supplied explicitly. `ResponseHandle[auto]` keeps the
  handle constrained while inferring its type argument; the call form
  is `reference[seq[Id]](h, name, path)`.
- Internal consumers of the demoted symbols import the `envelope` leaf
  directly (`call_meta.nim`, `methods.nim`, `mail_methods.nim`,
  `client.nim`, `dispatch.nim`, `serde_envelope.nim`) — the
  H10-sanctioned in-tree access path. Tests follow the same convention;
  there is no `menvelope` aggregator.

**Verification.** `tcompile_a30_envelope_hub_surface.nim` (negative:
`not declared` for every envelope type/ctor + the four `*ByRef`
builders; sealed-construction `not compiles`),
`tcompile_a30_envelope_internal_access.nim` (positive: leaf-import
reachability), `tcompile_a2_invocation_hub_surface.nim`,
`tcompile_a1b_protocol_hub_surface.nim`, `tcompile_a1_public_surface.nim`.

**Residue.** None. With A8b landed (below), every sealed sum in the library —
`SubmissionParam`, `Credential`, `SessionEndpoint` — is fully sealed (private
discriminator + read-only accessor); there is no public-discriminator residue
class.

### A8b. Reject discriminator-only partial construction of sealed sums *(P15, P16)* — ✅ DONE

`Credential` and `SessionEndpoint` are now **fully sealed**, mirroring
`SubmissionParam`: the discriminator is the module-private `rawScheme` /
`rawKind` field, surfaced read-only via a `scheme` / `kind` accessor func. So
`Credential(scheme: …)` / `SessionEndpoint(kind: …)` — and even the
discriminator-only `Credential(rawScheme: …)` / `SessionEndpoint(rawKind: …)` —
no longer compile outside the defining module: no field-bearing literal is
constructible elsewhere. Nim's zero-argument default `Credential()` /
`SessionEndpoint()` still compiles — sealing closes the literal, not the
implicit default — leaving only the inert default any non-`requiresInit`
object admits (see C12's identical treatment).

The TODO's original recommendation (boundary-reject for `Credential`) is
**superseded** by full-seal: it is strictly stronger (P16 — the illegal state
cannot exist, vs caught on use), cheaper (no `ValidationError` plumbing at
`initJmapClient` / `resolveEndpoint`, no new error variant), and unifies all
three sealed sums. The Rule-3 justification for a public discriminator does not
apply here: it governs `SetError` (whose payload arms are *public* and read
externally via `case se.errorType of …: se.variantField`); `Credential` /
`SessionEndpoint` already had *private* payload arms, so no external
variant-field read needed the public discriminator. The sole cross-module
discriminator read (`resolveEndpoint`) routes through the
`asDirectUrl` / `asDiscoveryDomain` Opt-accessors, never a raw field, so it is
unaffected. The two reject audits now assert the discriminator key itself is
inaccessible (`treject_a20`/`treject_a21`), and `tcompile_a20a21_hub_surface`
adds positive `not compiles(T(rawKind: …))` seal assertions; `scheme` / `kind`
read sites are byte-identical (the accessor name equals the old field name). No
wire/serde impact.

## Section B — Type-safety hardening

Mostly frozen-by-shipping too, but the gaps are correctness/illegal-
state issues rather than wire/surface decisions.

### B1. `Account.isPersonal` + `isReadOnly` → 4-state enum *(P18)* — ✅ DONE

`Account` (in `src/jmap_client/internal/types/session.nim`) stores
ownership and write-access as an `AccountPolicy` 4-state enum:
`apOwned`, `apOwnedReadOnly`, `apShared`, `apSharedReadOnly`. The
public read surface is the derived `isPersonal*` and `isReadOnly*`
accessors. The wire form remains the RFC 8620 §2 boolean pair —
`parseAccount` projects it onto the enum, `Account.toJson` emits both
booleans from the enum.

### B2. Sort-direction unification *(P18)* — ✅ DONE

`SortDirection { sdServerDefault, sdAscending, sdDescending }`
(`framework.nim`, ordinal-0 = `sdServerDefault` so zero-init yields the RFC
default) replaces the three divergent encodings, and the field is renamed
`isAscending` → `direction` (the `is*` name is a lie on a 3-valued enum):

- `Comparator.direction` (was `isAscending: bool`)
- `EmailComparator.direction` (was `isAscending: Opt[bool]`)
- `EmailSubmissionComparator.direction` (was `isAscending: bool`)

The three states map exactly onto the optional `isAscending` wire key's three
observable states, so the `bool`/`Opt[bool]` redundancy is gone. The wire
mapping is a single shared L2 translation in `serde_helpers.nim`:
`emitSortDirection` (`sdServerDefault` omits the key; the other two emit the
boolean) and `sortDirectionFromWire` (absent → `sdServerDefault`). All three
`serde` sites route through it. `Comparator.fromJson` keeps its strict
wrong-kind `JBool` check; `emailComparatorFromJson` stays lenient.

**Intended wire change.** `Comparator` and `EmailSubmissionComparator`
previously *always* emitted `isAscending: true`; with the `sdServerDefault`
default they now omit it (semantically identical per RFC 8620 §5.5 — absent ≡
ascending — but byte-different). The affected wire-assertion tests were updated
to expect the omission, plus a new test pins the explicit-`sdDescending`
emission path. The ~25 caller/generator/serde test sites and the
`tcompile_a1_public_surface.nim` audit were updated; the full fast suite passes.

### B3. `Filter[foNot]` arity + `foAnd|foOr` non-empty *(P16)* — ✅ DONE

The TODO's literal inner-discriminator sketch is **infeasible** — a direct-value
recursive `child: Filter[C]` field makes the type infinite-size and crashes Nim
codegen, and reading an inner variant field through a nested `case` is rejected
by `strictCaseObjects` Rule 4. The implemented shape (C1) is a flat **sealed**
`Filter[C]` (`{.ruleOff: "objects".}`): the operator arm holds a module-private
`rawOperands: NonEmptySeq[Filter[C]]` (so an empty operand list is
unrepresentable at the type level), and the construction surface is three smart
constructors that carry the arity:

- `filterNot(child): Filter[C]` — exactly one child (single-argument; a
  zero/multi-child NOT is not expressible).
- `filterAnd(operands) / filterOr(operands): Result[Filter[C], ValidationError]`
  — one or more (RFC 8620 §5.5 "one or more"; empty rejected).

`filterOperator` is **removed**. The public read accessor is
`operands*[C](f): seq[Filter[C]]` (a copy; empty for a leaf). The wire is
**byte-identical** (NOT still serialises as a one-element `conditions` array);
`serde_framework.toJson` reads via `operands`, and `fromJson` now **tightens**:
`NOT` with ≠1 children → `svkArrayLength`, empty `AND`/`OR` → `svkEmptyRequired`
(Postel: reject the structurally invalid). Test churn (~10 files): `.conditions`
reads → `operands`, `filterOperator` → the three constructors, the
permissive-arity assertions in `tframework`/`tprop_framework`/`trfc_8620`/
`tadversarial`/`tserde_framework` **inverted** to assert rejection, plus new
fromJson NOT-arity rejection tests and a sealed-construction reject in
`ttypesafety`. (Also fixed a pre-existing latent break in the skipped
`tstress.nim` — it relied on `int.toJson` from `mserde_fixtures` without
importing it.) Full fast suite passes.

### B4. `VacationResponse` window invariant *(P16)* — ✅ DONE

Both literal options in the original framing are unsound and were rejected:
(a) a fallible `parseVacationResponse` on the receive record violates Postel
(`VacationResponse`/`PartialVacationResponse` are receive-only — the library
must faithfully represent whatever the server sends); (b) a single
`Opt[VacationWindow] = (UTCDate, UTCDate)` destroys RFC 8621 §8 fidelity —
`fromDate`/`toDate` are *independently* nullable (from-only / to-only / neither
are all legal). Additionally, `UTCDate` is a structurally-validated opaque
string with no calendar semantics, so naive lexical `<` is temporally unsound
(`"…01.5Z"` sorts before `"…01Z"` because `.` < `Z`).

The implemented shape encodes the **honestly client-enforceable subset** (P16):
a module-private *sound* structural comparator `utcInstantLeq` in `vacation.nim`
(fixed 19-char prefix compared lexically == chronologically; the optional
fractional part compared as a right-zero-padded digit string) feeds
`windowOrderConflict`, which `initVacationResponseUpdateSet` folds into its
existing accumulating error pass. A single batch that sets BOTH endpoints to
concrete dates with `from > to` is rejected (`from == to` is a permitted
degenerate window); single-endpoint batches stay unprotected because the server
holds the other endpoint and is authoritative. The receive types, all serde,
and the wire bytes are untouched — captured replay and round-trips pass
unchanged. New `tvacation.nim` section D covers backward/forward/equal/
single/cleared windows, the fractional-second soundness pair, and the
window+duplicate co-occurrence (both error classes in one Err). The stale
"§7" comments across `vacation.nim`/`serde_vacation.nim`/`mail_methods.nim`
were corrected to the actual section (RFC 8621 §8).

### B5. `registerExtractableEntity(T)` compile-check — ✅ DONE

`registerExtractableEntity*(T)` in `entity.nim` mirrors
`registerQueryableEntity`'s serde probe: `when not compiles(fromJson(T,
default(JsonNode)))` → a domain-specific `{.error.}` naming the entity. It is
called after `registerJmapEntity` for the five full read-model entities
(`Thread`, `Identity`, `Mailbox`, `Email`, `AnyEmailSubmission`) in
`mail_entities.nim`, which now imports `serde_thread`/`serde_identity`/
`serde_mailbox`/`serde_email` (and already had `serde_email_submission`) so each
entity's `fromJson` is in scope — the same pattern `registerQueryableEntity`
uses for the filter-`toJson` probe. The imports stay hub-private (A1d).

**Post-A1c reconciliation.** `dispatch.get` now invokes the resolver closure
captured in `initResponseHandle`; the resolver body is `T.fromJson(args)`, so
`fromJson` is still the checkpoint. B5 moves the failure from the distant
`initResponseHandle[GetResponse[T]]` instantiation inside `addGet` to the
registration line.

**Scope — full entities only.** The getter-only `Partial*` projections (A3.6)
are deliberately not gated: the `compiles` probe spuriously drags in the generic
`FieldEcho.fromJson` candidate for their `FieldEcho`/`Opt` fields, yielding a
false-negative for a parser that demonstrably resolves at the real
`GetResponse[Partial*]` builder instantiation (and is exercised by the captured
and property tests). Bespoke non-entity responses (`EmailParse`,
`SearchSnippet/get`) and the singleton `VacationResponse` are likewise checked
locally where their builders live. The template docstring records this.

**Tests.** `tentity.nim` gains a positive mock (`MockExtractable` with a valid
`fromJson`) and a negative `assertNotCompiles(registerExtractableEntity(MockFoo))`;
`tcompile_a1b_protocol_hub_surface.nim` asserts `declared(registerExtractableEntity)`;
the `entity.nim` entity-module checklist docstring gains the new step.

### B6. Other illegal-state findings (lower severity) *(P16, P18)* — ⬜ TODO

The Account read-only/write-implying-capability illegal state is
addressed under B12 (smart-constructor silent-drop).

**Open, surfaced by the 2026-08-04 audit: the public `bool` parameter
family (P18).** A family of public builder / combinator / one-shot
parameters is typed `bool` because it mirrors an RFC 8621 wire boolean
one-for-one. Under a strict P18 reading each is flag soup and should be
a two- or three-state enum; under Postel's law and "code reads like the
spec" each is the RFC field itself, and an enum would rename a wire
concept the consumer already knows by name. Every member is a
*parameter*, not a stored field — and every public one carries a
default; only the hub-private `assembleQueryChangesArgs` takes its
`calculateTotal` positionally. So none of them makes an illegal state
representable, which is why this sits at B6's severity, not
B1/B2/B7/B8's.

The family, re-derived at audit time against
`tests/wire_contract/public-api.txt` (twelve public procs, plus two
hub-private helpers beneath them):

- `sortAsTree` / `filterAsTree` (RFC 8621 §2.3 `Mailbox/query`) —
  `addMailboxQuery` (`internal/mail/mail_builders.nim`),
  `addMailboxQueryThenGet` (`internal/mail/combinators.nim`),
  `queryMailboxes` (`internal/one_shot.nim`).
- `collapseThreads` (RFC 8621 §4.4 `Email/query`, semantics in §4.4.3)
  — `addEmailQuery`, `addEmailQueryChanges` and
  `addEmailQueryWithThreads` (default `true` on the last) in
  `mail_builders.nim`, `addEmailQueryWithSnippets`
  (`internal/mail/mail_methods.nim`), `addEmailQueryThenGet`
  (`combinators.nim`), `queryEmails` (`one_shot.nim`).
- `calculateTotal` (RFC 8620 §5.6 `/queryChanges`) — the per-entity
  `addMailboxQueryChanges` / `addEmailQueryChanges` (`mail_builders.nim`)
  and `addEmailSubmissionQueryChanges`
  (`internal/mail/submission_builders.nim`),
  and, hub-private beneath them, the generic `addQueryChanges`
  (`internal/protocol/builder.nim`) and `assembleQueryChangesArgs`
  (`internal/protocol/methods.nim`).
- `onDestroyRemoveEmails` (RFC 8621 §2.5 `Mailbox/set`) —
  `addMailboxSet` (`mail_builders.nim`).

**Needs decision (ship-or-affirm), NOT decided here.** Either affirm the
family as a documented P18 exception in the "Documented exceptions"
section above — on the same footing as `MailboxRights`' nine ACL flags,
whose carve-out already rests on "the RFC defines it as an independent
boolean" — or retype the members as enums, which is a breaking parameter
change and therefore must land before the 1.0 freeze. Affirming is the
cheaper answer and is the one the existing `MailboxRights` precedent
points at; deciding is out of scope for the 2026-08-04 documentation
reconciliation that surfaced it.

Otherwise reserved for future low-severity findings.

### B7. `mail_filters.nim` Opt[bool] → three-state enums *(P18)* — ✅ DONE

The three `Opt[bool]` filter fields in
`src/jmap_client/internal/mail/mail_filters.nim` are now named three-state
enums whose **zero value is the no-constraint state**, so `default(T)` and the
zero-init `MailboxFilterCondition()` / `EmailFilterCondition()` paths preserve
the prior "omit the key" behaviour exactly:

```nim
type HasAnyRoleFilter* = enum hrfNoConstraint, hrfRequireAny, hrfRequireNone
type SubscriptionFilter* = enum sfNoConstraint, sfSubscribed, sfNotSubscribed
type HasAttachmentFilter* = enum hafNoConstraint, hafYes, hafNo
```

`MailboxFilterCondition.hasAnyRole: HasAnyRoleFilter`,
`MailboxFilterCondition.isSubscribed: SubscriptionFilter`, and
`EmailFilterCondition.hasAttachment: HasAttachmentFilter`. The enums are
hub-public (they are filter-builder inputs). `serde_mail_filters.nim` emits via
an exhaustive `case` (no-constraint → omit; the other two → the RFC boolean) —
adding a variant forces a compile error at the emit site. All call sites
updated: the serde test (`tserde_mail_filters.nim`), the property generator and
reader (`mproperty.genEmailFilterCondition`, `tprop_mail_d.nim`), and two live
tests.

### B8. `Identity.mayDelete` → enum *(P18)* — ✅ DONE

`DeleteAuthority` (`daUnreported`, `daYes`, `daNo` — zero value is the
"server did not say" state) replaces the bool/`Opt[bool]` encoding of
`mayDelete` on the two server-authoritative Identity shapes:

- `Identity.mayDelete: DeleteAuthority` (was `bool`). The receive parser is
  now lenient on an absent `mayDelete` — Stalwart 0.15.5 elides it, and the
  prior `bool`/`getBool(false)` silently collapsed the omission to "may NOT
  delete", a security-relevant misreport. It now yields `daUnreported`.
- `IdentityCreatedItem.mayDelete: DeleteAuthority` (was `Opt[bool]`), the
  Identity/set `created[cid]` server-set subset.

`PartialIdentity.mayDelete` stays `Opt[bool]`: in a sparse projection the
`Opt` already carries the third state (`Opt.none` = not in this projection),
so `daUnreported` would be a redundant fourth state — documented inline.
`serde_identity.nim` gains shared `parseMayDelete` / `emitMayDelete` helpers
(lenient on absence, strict on wrong kind; `daUnreported` omits the key); the
`MailboxRights.mayDelete` ACL flag (a documented P18 exception) is untouched.
The `fromJsonMissingMayDelete` test now asserts the lenient `daUnreported`
outcome rather than a parse failure.

### B9. Consolidate the handle-pair zoo *(P9)* — ✅ DONE

**Resolution: (b-clean).** The decisive asymmetry: `ChainedHandles` (RFC 8620
§3.7 back-reference, two *distinct* call-ids) is reducible to two independent
`dr.get` calls, so the generic earns nothing; `CompoundHandles` (§5.4, one
*shared* call-id) is **not** reducible — its `implicit` is a `NameBoundHandle`
whose method-name filter only a builder can mint (`initNameBoundHandle` is
hub-private). Merge-to-`HandlePair` (option a) was rejected: it forces a generic
case object under `strictCaseObjects`, renames `CompoundResults.primary/implicit`
across ~14 sites, and breaks the domain aliases — all to buy nothing.

So the single-use generic `Chained*` plumbing was **deleted outright** (no dead
code): `ChainedHandles`, `ChainedResults`, the `getBoth(ChainedHandles)`
overload, `registerChainableMethod`, and the three `registerChainableMethod(…)`
calls are gone. Its one consumer — `EmailQuerySnippetChain` (formerly a
`ChainedHandles` alias) — is now a **bespoke record co-located with its
builder** in `mail_methods.nim`, with an `EmailQuerySnippetResults` and a
co-located `getBoth`, exactly mirroring the existing `EmailQueryThreadChain`
precedent (`mail_builders.nim`). The hub now exposes exactly two paired-handle
context types: `CompoundHandles` / `CompoundResults` (P9 satisfied). Wire and
serde are untouched (the handle types carry only captured `ParseProc` closures).
`tcompile_a1b_protocol_hub_surface.nim` flips `Chained*` /
`registerChainableMethod` from positive to `not declared`; the snippets live
test reads `pair.query` / `pair.snippets`. Full fast suite passes.

### B10. `lent` annotation pass on handle accessors *(P12)* — ✅ DONE

Fourteen raw-field-passthrough accessors that return a container now return
`lent T`, encoding the borrow in the signature (P12) and removing a per-call
deep copy; each carries a borrow-contract docstring note:

- `Session.accounts` / `primaryAccounts`, `Account.accountCapabilities`,
  `UriTemplate.parts` / `variables`, `CoreCapabilities.collationAlgorithms`,
  `MailAccountCapabilities.emailQuerySortOptions`, `Thread.emailIds`,
  `EmailBlueprint.extraHeaders` (the user-facing read-model accessors), plus
  the hub-internal wire/lifecycle accessors `Response.methodResponses`
  (the strongest case — `dispatch` scans it on every extraction),
  `Request.methodCalls` / `using`, `BuiltRequest.callLimits`, and the three
  `MailboxChangesResponse` change-field forwarders.

**The punch-list was corrected.** Two of the originally-named targets —
`Session.capabilities` and `RequestBuilder.capabilities` — are **computed**
accessors (`@[coreCap] & rawAdditional`; `capabilityUris.mapIt($it)`) that build
a fresh local container, so `lent` would dangle (compile error) — they correctly
stay by-value. (`RequestBuilder.capabilities` also returns `seq[string]`, not
`seq[CapabilityUri]`.) The sealed Pattern-A projection accessors
(`toSeq`/`toTable`/`toHashSet`, A8 §7) are deliberately left by-value — they
return defensive copies. Callers are all read-only (`len`/`[]`/`hasKey`/
`in`/`==`/`for`/`withValue`/owned-copy `let`), so none break — the existing
session/serde/envelope/property suites are the regression surface and pass
unchanged.

### B11. `Email[Lite | Hydrated]` phantom decision *(P16)* — ❌ DROPPED (premise invalid)

**The premise is factually wrong against RFC 8621, so both options are
rejected.** The claimed invariant `bodyValues.len>0 ⇒ bodyStructure.isSome`
does not exist: `bodyValues` IS a default Email/get property and `bodyStructure`
is NOT (RFC 8621 §4.2 default-property set), and `bodyValues` partIds reference
parts in any of `textBody` / `htmlBody` / `bodyStructure` (§4.1.4) — and
`textBody`/`htmlBody` are defaults. So "bodyValues populated + bodyStructure
absent" is the **normal, RFC-mandated default shape** for the single most common
fetch (reading an email's text), not a server bug. The library's own
`addEmailGet` sends no property filter, so a conformant server returns the
default set (no `bodyStructure`) for **every** full-record `Email`. A captured
Stalwart fixture (`tcaptured_email_multipart_alternative`) already exhibits the
state.

- **(a) phantom `Email[Lite|Hydrated]`** — rejected: unnecessary (the state is
  not incoherent) and propagates a marker through every `Email` consumer.
- **(b) reject `parseEmail`** — rejected, and actively harmful:
  `GetResponse[Email].fromJson` aborts the whole list on any per-entry `err`
  (→ `MethodError(serverFail)`), so a reject would fail
  `addEmailGet(..., fetchBodyValues=bvsText)` on conformant servers, and would
  directly contradict the shipped **A3** decision ("a sparse fetch cannot drive
  the Email parser to `MethodError`"). The parser is correctly lenient (A3.6 /
  Postel).

**Resolution.** Encode no precondition (P16 done right — a precondition that does
not exist must not be encoded). The corrective applied is: the
`Email.bodyValues` / `ParsedEmail.bodyValues` docstrings now state the actual
referential relationship and that the absent-`bodyStructure` shape is coherent
(citing §4.1.4 / §4.2), and the serde regression gate
`fromJsonBodyValuesWithoutBodyStructureIsCoherent`
(`tserde_email.nim`) locks acceptance of the shape so the false invariant cannot
be reintroduced. `PartialEmail` already models the two fields independently
(`FieldEcho` / `Opt`) and needs no coupling either.

### B12. `Account[ReadOnly | ReadWrite]` decision *(P16)* — ✅ DONE

`parseAccount` (hub-private smart constructor in
`src/jmap_client/internal/types/session.nim`) silently drops write-
implying capabilities when `isReadOnly=true`. The hub-public
`WriteImplyingAccountCapabilities` const documents the split:

- **Write-implying arms** (dropped under read-only): `ckMail`,
  `ckSubmission`, `ckVacationResponse`, `ckBlob`, `ckContacts`,
  `ckCalendars`, `ckSieve`, `ckMdn`, `ckSmimeVerify`.
- **Read-compatible arms** (retained): `ckCore` (RFC 8620 §2 is
  server-only, never legal at account scope but Postel-tolerated as
  raw data), `ckWebsocket` (RFC 8887 §2 is session-scope only),
  `ckQuota` (RFC 8909 §3.1 — `Quota/get` is the only operation,
  read-only), `ckUnknown` (vendor URNs whose semantics the library
  cannot inspect).

The smart-constructor approach (Postel on receive: drop the
contradicting entry rather than reject the whole account)
concentrates the check at the parse boundary without propagating
phantom-typed states through downstream APIs.

## Section C — Consumer ergonomics

Pre-1.0 quality bar. Each missing item is a day-one wrapper trigger.

### C1. Sample CLI consumer — pre-1.0 freeze gate *(P29)* — ✅ DONE

Campaign reconciliation (2026-06): DONE — `examples/jmap-cli/` plus
`examples/jmap-cli/AUDIT.md` exist, and the Phase-2 triage on
`api/triage` completes the deliverable (every awkwardness resolved,
accepted as a trade-off, or filed as a residual Cn).

P29 verbatim: "Before 1.0 lands, write a non-trivial sample app …
treat its painful spots as bugs against the API, not against the
user." This is a hard pre-1.0 freeze gate, not a 1.x feature.

At the time this gate was written, no `examples/`, `samples/`, or
`jmap-cli` existed; the closest "how do I start" was
`tests/integration/live/tcore_echo_live.nim`,
buried behind `forEachLiveTarget` macros. Build a CLI:
`jmap-cli mailbox list`, `jmap-cli email query --in inbox --unread`,
`jmap-cli email flag --add seen`. Use only the public Nim API.

**Deliverable.** `examples/jmap-cli/` directory with at least the
three commands above plus `examples/jmap-cli/AUDIT.md` listing every
awkwardness found and its resolution (resolved | accepted as
trade-off | filed as separate TODO entry). After each CLI command
implementation, log every awkward construction (UFCS chain >3
levels, raw `JsonNode` reference at call site, manual `.get()` chain
over an `Opt` of a `Result`). Each finding may not be deferred to
1.x without written justification in AUDIT.md.

Tied to F4 (CI smoke test reads from AUDIT.md).

### C2. Per-entity flatten of four-param `addSet` *(P7)* — ✅ DONE

Campaign reconciliation (2026-06): the per-entity flatten holds; S4
then REPLACED `addEmailSubmissionAndEmailSet` with one total
`addEmailSubmissionSet(spec)` over a validated `EmailSubmissionSetSpec`
value (`src/jmap_client/internal/mail/email_submission.nim`), so the
submission set builder was unified rather than left as a paired
wrapper.

The four-parameter generic `addSet[T, C, U, R]` is hub-private (A5;
filtered via `protocol.nim`'s `export builder except …` clause).
Public callers see only per-entity wrappers — `addEmailSet`,
`addMailboxSet`, `addEmailSubmissionSet`,
`addEmailSubmissionAndEmailSet`, `addVacationResponseSet` — each
taking `(b, accountId, ifInState?, create?, update?, destroy?)` with
typed creation models, typed update sets, and no `extras=`
parameter.

### C3. `byIds` per-entity helpers *(P7)* — 🟡 PARTIAL

Campaign reconciliation (2026-06): S4's bare-get one-shots
(`getEmails`/`getThreads`/… in `src/jmap_client/internal/one_shot.nim`)
made the common literal-ids fetch a one-liner, so the `byIds=`
builder overload is now low-value. (Precision note: these one-shots
take `ids: Opt[Referencable[seq[Id]]]`, not a bare `seq[Id]` — the
`directIds` primitive still mints that argument; verified present at
`src/jmap_client/internal/protocol/builder.nim:652`.) PARTIAL stands:
`directIds` is the primitive; the per-entity `byIds=` sugar remains
unbuilt but is now optional polish.

`src/jmap_client/internal/protocol/builder.nim` already provides `directIds` to
shave `Opt.some(direct(@[…]))` nesting. Extend per-entity:
`addEmailGet(b, accountId, byIds = @[id1, id2])`. UFCS chains read
materially better.

### C4. `MailboxRights` summary helpers *(P7)* — ✅ RESOLVED (S3 — won't-fix by decision)

Campaign reconciliation (2026-06): S3 deliberately shipped NO rights
roll-up. The nine RFC 8621 §2 `may*` rights stay orthogonal — a
blessed `canWrite`/`canRead`/`canDelete` digest would freeze one
library's opinion about which flags constitute each verb into the
API. See AUDIT `mailbox:rightsSummary` (resolved-S3, won't-fix).

`src/jmap_client/internal/mail/mailbox.nim` (the `MailboxRights`
type). Nine independent ACL booleans (Decision B6 documented
exception, correctly modelled). Add
roll-up helpers: `mb.canMutate(): bool`, `mb.canRead(): bool`,
`mb.canDelete(): bool`. Otherwise consumers chain
`mb.myRights.mayAddItems and mb.myRights.mayRemoveItems and …`.

### C5. Capability discovery convenience *(P7)* — ✅ DONE (S3)

Campaign reconciliation (2026-06): S3 shipped `requireMail` /
`requireSubmission` / `requireVacation`
(`src/jmap_client/internal/protocol/preflight.nim:64-77`), each a
soft-resolver over the cached `Session` capability set. See AUDIT
`session:capability` (resolved-S3).

Currently the capability chain runs through the `Session` that
`fetchSession` returns — `client.fetchSession().get().coreCapabilities()`
— correct but undocumented. Add helpers:
`client.supportsMail(): bool`, `client.coreCapabilities(): Opt[…]`,
`client.requireMail(): JmapResult[void]`. Pre-flight "does this
server support Mail?" should be one line.

### C5b. `HttpTransportConfig` sealed value *(P10, P17)* — ⬜ TODO

Campaign reconciliation (2026-06): NOT addressed by S0–S4; remains a
valid future additive (a validated transport-config value plus a
`config`-taking `newHttpTransport` overload). Under the campaign's
version-agnostic lens the "post-1.0" framing is dropped — it is
simply a future additive pass, not freeze-blocking.

`newHttpTransport*(timeout, maxRedirects, maxResponseBytes, …)` takes
its tuning as four default-argument parameters. For 1.0 this is
acceptable: default-arg overloads, no global state, no two-channel
config hazard, and it is the single config surface (P17). Post-1.0,
introduce a validated `HttpTransportConfig` sealed value (smart
constructor rejecting nonsensical combinations — e.g. zero timeout)
plus a `config`-taking overload, so the knobs travel as one typed,
invariant-checked value rather than a positional parameter list. Not
freeze-blocking; raised as the transport-side analogue of the A8b
sealing review.

### C6. Version surface *(P25, P28)* — ⬜ TODO

Campaign reconciliation (2026-06): NOT addressed by S0–S4. Verified
absent — `grep -rn 'clientVersion\|ClientVersion' src/` returns no
matches; the only version literal under `src/` is still the
`userAgent` default in `transport.nim`. A `clientVersion()` accessor
remains a valid future additive.

`src/jmap_client/internal/transport.nim` carries
`userAgent: string = "jmap-client-nim/0.1.0"` as the default
HTTP `User-Agent` for the default transport. That is the only
version literal under `src/`. C-library convention (curl,
OpenSSL) exposes `client_version()` for bug reports. Add:

```nim
const ClientVersion* = "0.1.0"  # synced with .nimble
func clientVersion*(): string = ClientVersion
```

**C-side half shipped with C24 (2026-08-30).**
`include/jmap_client.h` carries `JMAP_CLIENT_VERSION_MAJOR`, `_MINOR`
and `_PATCH` for compile-time checks, and `jmap_version()` returns
`"MAJOR.MINOR.PATCH"` at run time — the libcurl shape, callable before
`jmap_init()`. `ctests/t01_init_version.c` `_Static_assert`s the three
macros and the H19 snapshot locks them. The Nim-side `clientVersion()`
above is untouched and remains this item's whole open scope, which is
why the marker stays ⬜ TODO. It has more to unify than it did: the
version is now written out in four places — `jmap_client.nimble:6`,
`transport.nim`'s `userAgent` default, `jmapVersion`'s `cstring`
literal, and the header's three macros — with nothing holding them to
each other.

### C7. Charter clause on `convenience.nim` *(P6)* — ❌ MOOT (S4)

Campaign reconciliation (2026-06): S4 DISSOLVED the P6 quarantine.
`convenience.nim` no longer exists — its combinators moved to
`src/jmap_client/internal/mail/combinators.nim`, re-exported on the
always-on hub. An anti-semantic-convenience charter clause for a
deleted module is moot; the combinators are now first-class.

`convenience.nim`'s top docstring already states the P6 quarantine in
general terms (opt-in, not root-re-exported — C10). What is missing
is the explicit anti-semantic-convenience charter clause and its CI
enforcement. Add to the docstring:

> This module contains pipeline combinators (multi-method `add*`
> chains and paired `getBoth` extraction). It does NOT contain
> semantic convenience like `fetchInbox`, `archiveEmail`, `markRead`.
> Such helpers belong in user code. The zlib `gz_*` precedent shows
> what happens when convenience layers grow semantic helpers — the
> edge cases bleed back into the user's image of the core. P6 forbids
> this.

The backing enforcement (F3 reverse-leak grep + H7 charter lint) is
not yet implemented; both are ⬜ TODO.

### C1.1. Scaffold `examples/jmap-cli/` directory *(P29)* — ✅ DONE

Campaign reconciliation (2026-06): the `examples/jmap-cli/` directory
is scaffolded and benched — the sample CLI plus its `AUDIT.md`
findings catalogue exist and have been triaged on `api/triage`.

C1 declares the freeze gate but does not specify the file tree.
Without scaffolding, the gate has no execution path.

**Action.** Create at minimum:

```
examples/jmap-cli/
├── jmap-cli.nim                  # entry point, dispatches subcommands
├── commands/
│   ├── mailbox_list.nim          # `jmap-cli mailbox list`
│   ├── email_query.nim           # `jmap-cli email query --in inbox --unread`
│   └── email_flag.nim            # `jmap-cli email flag --add seen <id>`
├── AUDIT.md                      # ergonomic findings catalogue
├── README.md                     # build + run instructions
└── jmap_cli.nimble               # nimble project file
```

Build: `nim c -d:ssl -o:jmap-cli jmap-cli.nim`. The CLI imports only
`jmap_client` (the root re-export); reaching into
`jmap_client/internal/*` is forbidden and CI-checked (H7).

**AUDIT.md format.** Each awkwardness one bullet:
`- <call-site>: <description> [resolved | accepted | filed-as-Cn]`.
Examples to expect: UFCS chains > 3 levels, manual `.get()` chains
to read `coreCapabilities`, raw `JsonNode` references at call site.
Each `filed-as-Cn` becomes a new item in Section C of this TODO.

### C8. Capability pre-flight one-liner *(P7)* — ✅ DONE (S3)

Campaign reconciliation (2026-06): `requireMail` IS the one-liner —
shipped by S3 alongside `requireSubmission`/`requireVacation`
(`src/jmap_client/internal/protocol/preflight.nim:64-77`). See AUDIT
`session:capability` (resolved-S3).

C5 lists capability discovery helpers but underspecifies the
one-liner. The headline call site is "does this server support
JMAP Mail?" — `client.fetchSession().get().coreCapabilities()` then
walk a set. Day-one wrapper trigger.

**Action.** Add to `src/jmap_client/internal/client.nim`:

```nim
proc requireMail*(client: JmapClient): JmapResult[void]
  ## Returns ok() if Session is cached and declares
  ## ``urn:ietf:params:jmap:mail`` in capabilities; err(...) with
  ## ``cekRequest`` ``RequestErrorKind.retNotJson`` otherwise.
  ## Pre-flight check before adding mail-typed invocations to the
  ## builder.

proc requireSubmission*(client: JmapClient): JmapResult[void]
  ## Same shape; capability ``urn:ietf:params:jmap:submission``.

proc requireVacation*(client: JmapClient): JmapResult[void]
  ## Same shape; capability ``urn:ietf:params:jmap:vacationresponse``.
```

Each is a thin wrapper over capability-set lookup. Verified by
the C1.1 CLI — if `mailbox list` cannot use `requireMail`, file as
a Cn TODO.

### C9. Charter clause: convenience.nim exports no new public types *(P6, P9)* — ❌ MOOT (S4)

Campaign reconciliation (2026-06): moot for the same reason as C7 —
S4 dissolved the quarantine and `convenience.nim` no longer exists.
A structural "exports no new types" restriction on a deleted module
has nothing to lock; the relocated combinator bundle types in
`src/jmap_client/internal/mail/combinators.nim` are first-class.

C7 covers the prose charter; this item adds the structural
restriction. `convenience.nim`'s public surface today is exactly the
eight pipeline-combinator procs plus the six paired handle/result
bundle types those combinators return (`QueryGetHandles[T]`,
`ChangesGetHandles[T]`, `MailboxChangesGetHandles`,
`QueryGetResults[T]`, `ChangesGetResults[T]`,
`MailboxChangesGetResults`); it introduces no entity or semantic type
(C10 verifies the current surface). The restriction is therefore
satisfied in code, but is neither documented nor mechanically
locked.

**Action.** Document the restriction in the `convenience.nim` top
docstring; back it mechanically with the H7 lint (Section H, ⬜ TODO).
The lint scans `convenience.nim` for `type … * =` declarations and
admits exactly the six bundle types above, failing CI on any further
`type … * =`. The bundle types are the documented exception: a
combinator returning a pair of typed handles needs a pair type to
name (C10).

### C10. `convenience.nim` internal-access cleanup *(P5, P6)* — ✅ DONE

Campaign reconciliation (2026-06): S4 relocated the combinators to
`src/jmap_client/internal/mail/combinators.nim` (re-exported on the
hub), so the original `grep -n "internal" src/jmap_client/convenience.nim`
verification gate is obsolete (the module is gone). The H10
internal-boundary lint now covers the relocated module — a direct
import of it from outside the tree is forbidden.

`convenience.nim` imports only `jmap_client` — it reaches nothing
under `internal/`. Its public surface is eight per-entity pipeline
combinators (`addEmailQueryThenGet`, `addMailboxQueryThenGet`,
`addEmailSubmissionQueryThenGet`, `addEmailChangesToGet`,
`addIdentityChangesToGet`, `addThreadChangesToGet`,
`addEmailSubmissionChangesToGet`, `addMailboxChangesToGet`), each a
non-generic `func` over the public typed per-entity builders that
wires its back-reference internally with the public `reference`
primitive. Four generic handle/result bundle types
(`QueryGetHandles[T]` / `ChangesGetHandles[T]` and the matching
`*Results` records) plus a bespoke `MailboxChangesGet*` pair name
the paired handles; the `getBoth` overloads extract both responses.
A generic record bundling two already-typed handles is honest — it
is not the libdbus failure, which is a generic *function* needing
call-site scaffolding.

**Verification gate.** The original grep is dissolved with the
quarantine; what locks the invariant today is `just lint-module-paths`
(H13) — `tests/wire_contract/module-paths.txt` holds the single row
`jmap_client`, so no second public path can reappear — plus `just
lint-internal-boundary` (H10), which fails CI on any
`import jmap_client/internal/...` from outside the package tree.

### C11. Read-side `EmailLeaf` view type for `leafTextParts` *(P16)* — ⬜ TODO (future additive)

Residual of AUDIT `email read:isMultipart`. S3 shipped
`leafTextParts`/`decodedTextBody`
(`src/jmap_client/internal/mail/email.nim`), but a text leaf's
`partId`/`blobId` still sit behind the `EmailBodyPart` `isMultipart`
case — reaching them means matching the `of false` arm. A dedicated
read-side leaf view type would expose those fields without forcing
the consumer to match the case. This needs a NEW type, which is
outside S3's "no new types" scope. Future *additive* pass; not
freeze-blocking.

### C12. Raw `Blueprint*` part constructors made private *(P15)* — ✅ DONE (2026-08-04)

Residual of AUDIT `email send:raw-case-literals` /
`email send:parsePartIdFromServer`. S3/S4
(`plainTextBody`/`sendPlainText`) removed the common need to hand-build
parts, but `BlueprintLeafPart` and `BlueprintBodyPart`
(`src/jmap_client/internal/mail/body.nim`) remain public raw
case-object constructors — counter to "smart constructors only; raw
constructors private". A P15 tightening makes them private.

**DECIDED 2026-08-04 (user).** The privatisation ships as its own small
code PR, before the Layer-5 C ABI work starts. It is a non-additive
removal, so it must land pre-freeze rather than wait for a 1.x additive
window — which is precisely why it cannot ride along inside a larger
change.

**Shipped 2026-08-04** (branch `api/c12-seal-blueprint-parts`).
`BlueprintLeafPart` and `BlueprintBodyPart` are now fully sealed,
mirroring `ContentDisposition`/`SessionEndpoint` (A8b): every field is
renamed `raw*` and made module-private, including the two
discriminators (`rawIsMultipart`, `rawSource`), so
`BlueprintBodyPart(rawIsMultipart: …)` and
`BlueprintLeafPart(rawSource: …)` no longer compile outside
`body.nim`. What the seal delivers, and what the reject tests pin, is
that no field-bearing literal — not even the discriminator on its own —
is constructible elsewhere; every field name fails with "the field '…'
is not accessible". Nim's zero-argument default `BlueprintBodyPart()`
still compiles, exactly as `SessionEndpoint()` does under A8b: sealing
closes the literal, not the implicit default. Three total constructors
replace the raw literal: `inlinePart`, `blobRefPart`,
`multipartPart` (typed required
params, six shared metadata params defaulted). Every former field has
a same-named public read accessor that cases internally on the
private discriminator; `leaf` and `subParts` cross the container/leaf
split honestly (`Opt[BlueprintLeafPart]` / `@[]` respectively, since a
leaf list is a true empty case but a missing leaf is not). No new
validation was added — parts stay shapes; `parseEmailBlueprint` keeps
owning tree validation, so wire output and error text are
byte-identical to before the seal.

Both branch accessors also have a borrowed-traversal iterator of the
same name (`subParts`, `leaf`). A `for` loop resolves to the iterator,
so a recursive walk reads the subtree in place. Without them the
copying accessors turn every walk — the three `parseEmailBlueprint`
validation passes, `bodyValues`, and `BlueprintBodyPart.toJson` — into
one deep copy of the subtree per node visited: a 200 × 1 MiB
attachment body measured 137 ms per ten `toJson` calls against 0.14 ms
before the seal, and a 60-deep tree 22 ms against 0.06 ms. With the
iterators both return to their pre-seal cost. The `lent seq` shape
that would have kept one symbol is not expressible: a `const` empty
seq has no address to borrow, and a `let` global trips the module's
`noSideEffect` push.

**Verification gate.** `tests/wire_contract/public-api.txt` gained
exactly the 3 constructors + 16 accessors + 2 iterators
(`H16`/`lint-public-api`);
`tests/wire_contract/type-shapes.txt` lost every public field on both
types down to the bare private discriminator, same shape as
`ContentDisposition`/`SessionEndpoint` (`H17`/`lint-type-shapes`);
`tests/wire_contract/error-messages.txt` is unchanged (`H15`/
`lint-error-messages`). Two new compile-reject tests
(`tests/compile/treject_c12_sealed_blueprintbodypart_construction.nim`,
`tests/compile/treject_c12_sealed_blueprintleafpart_construction.nim`)
assert the discriminator-only literal is unreachable, mirroring the
A8b `treject_a20`/`treject_a21` pair. The five branch-co-location
scenarios that predate the seal (125a–125d in
`tests/unit/mail/tbody.nim`, 41 in
`tests/unit/mail/tblueprint_compile_time.nim`) now assert the same
rejection per payload field — `rawBlobId`, `rawCharset`, `rawPartId`,
`rawSubParts`, `rawValue` — each paired with the answer its accessor
gives instead, so the scenarios keep their subject and stop passing for
the wrong reason. `tests/compile/tcompile_a1d_mail_hub_surface.nim`
carries the matching positive half: all 16 accessors and both iterators
must stay readable through the hub.

### C13. D5 — broad `toJson` null-for-none serde-fidelity audit *(RFC 8620 §5.3)* — ⬜ TODO (future)

Only Email headers were fixed (RFC-sweep F1). A general audit is
needed of every `toJson` that emits `null` for an absent `Opt` field
rather than omitting the key (per RFC 8620 §5.3 `/set` PatchObject and
creation property-omission semantics; §5.1 `/get` has no such rule).
This is NOT a blind generalisation of the omit rule — each type needs
its own §5.3 check, since some fields legitimately serialise `null`.
No inline AUDIT anchor; surfaced by the S2 RFC audit. Future pass.

### C14. `ParsedEmail` body-reader overloads; `htmlBodies()`/`allBodies()` *(P29)* — ⬜ TODO (future additive)

S3 shipped `decodedTextBody` (text only;
`src/jmap_client/internal/mail/email.nim`). The HTML and all-bodies
reader siblings — `htmlBodies()` / `allBodies()` — plus the matching
`ParsedEmail` body-reader overloads are the obvious additive
completions of the same read-side family. No inline AUDIT anchor.
Future *additive* pass.

### C15. Email/set WRITE one-shot *(P7)* — ✅ DONE (2026-08-04)

Residual of AUDIT `email flag:set-construction` /
`email move:repetition`. S2 added projection iterators and S4 added
connect/read/send one-shots, but NOT a write one-shot. The "update
ONE email" case still paid the
`initEmailUpdateSet → parseNonEmptyEmailUpdates → addEmailSet` triple
seal. An `updateEmail`/`addEmailUpdate`-style one-shot (flag/move)
plus a vacation-set equivalent would fold that chain. That was outside
S4's connect/read/send scope, so it landed as its own additive pass.

**Shipped 2026-08-04** (branch `api/c15-easy-path-one-shots`). Five
write one-shots on `src/jmap_client/internal/one_shot.nim`, all on the
same `JmapResult` easy-path contract as S4's read/send one-shots:
`markEmailsRead`, `markEmailsUnread`, `moveEmails`, `destroyEmails`,
and `setVacationResponse` — the vacation-set equivalent this body
names, included by user decision so the item closes exactly as it was
written. A private `runSet` helper holds the shared Email/set body
(seal one update across every id, dispatch, collapse the method
outcome), so the three update procs are one line each and cannot drift
into three transcriptions of the same wire shape.
`moveEmails` is a full `mailboxIds` replace, because "move" means the
email is in the destination and nowhere else; additive membership
stays on the builder path's `addToMailbox`.

The rail split is the promise: whole-method failure rides `JmapError`
fail-fast, while per-id `SetError`s stay data on the returned
`SetResponse`, so one rejected email never hides its siblings'
results. The update rail rejects empty and duplicate id lists at the
seal, before any network traffic; `destroyEmails` deliberately does
not, because an empty `destroy` array is legal wire that destroys
nothing.

Adopting the one-shots in the P29 bench also exposed a container leak
in the six public `SetResponse` projection iterators
(`src/jmap_client/internal/protocol/methods.nim`): being generic,
their `for id, res in r.updateResults` resolved `pairs` at the
INSTANTIATION site, so a hub-only consumer had to add
`import std/tables` of its own and got the mismatch reported from
inside `methods.nim`, nowhere near its call site. Worse, Nim caches
one instantiation per type argument, so whether a module needed the
import depended on which sibling compiled first. Module-qualifying the
calls as `tables.pairs(...)` moves resolution to the definition scope;
no signature, yield type, or docstring changed. Every
`examples/jmap-cli/commands/` module and `tests/unit/tone_shot.nim`
dropped its `std/tables` import in the same commit, and `UnusedImport`
is a hard error here, so those drops are load-bearing proof the leak
is gone. Same container-leak class S3's `bodyValue` reader closed for
`Email.bodyValues`, except it leaked through a generic body rather
than a field type, so no signature review could have found it.

**Verification gate.** `tests/wire_contract/public-api.txt` gained the
five procs (`H16`/`lint-public-api`); no new public type accompanies
them, so `tests/wire_contract/type-shapes.txt` is unchanged for this
item (`H17`/`lint-type-shapes`), and the iterator qualification is a
no-op in both snapshots by construction — that is what makes it safe.
Thirteen new cases in `tests/unit/tone_shot.nim`
(`oneShotMarkEmailsRead*`, `oneShotMarkEmailsUnreadEmitsRemoval`,
`oneShotMoveEmailsReplacesMembership`, `oneShotDestroyEmails*`,
`oneShotSetVacationResponse*`) pin the emitted patch shape, the
per-id `SetError`-stays-data rule, both seal rejections, the legal
empty destroy, and the method-error rail for each family.

### C16. Query-then-snippets one-shot *(P7)* — ⬜ TODO (future additive)

Residual of AUDIT `search:helper-undiscoverable` /
`convenience:coverage-gap`. S0 made `addEmailQueryWithSnippets`
discoverable (api_oracle now lists it) and S4 dissolved the
quarantine, but no `queryEmailsWithSnippets`-style one-shot exists
(parallel to `queryEmails`); the search-highlight path still hand-wires
`getBoth(chain)`. Future *additive* pass.

### C17. Email/changes `/updated` back-reference combinator *(P7)* — ✅ DONE (2026-08-04)

AUDIT `email sync:changes-to-get-created-only` (**medium**).
`addEmailChangesToGet` (and siblings;
`src/jmap_client/internal/mail/combinators.nim`) back-referenced ONLY
the `/created` path, yet incremental mail sync overwhelmingly needs
`/updated` (read/flag/move changes). A combinator — or a path
parameter on the existing one — that back-references `/updated` would
cover the common case.

**Shipped 2026-08-04** (branch `api/c15-easy-path-one-shots`).
`addEmailChangesToGetAll` emits three invocations —
`Email/changes` plus one `Email/get` per back-referenced path,
`/created` and `/updated` — with `ChangesGetAllHandles[T]` /
`ChangesGetAllResults[T]` and a `getAll` extractor as the three-handle
analogues of the existing pair types and `getBoth`. Of the two shapes
this body offered, the new combinator is the one that ships: a path
parameter on `addEmailChangesToGet` would have edited a signature the
A26 public-API snapshot has frozen, so the existing combinator is
untouched and its two-invocation chain remains the right call for a
created-only fetch.
The handle and result types are generic in `T`, so the Mailbox /
Thread / Identity / EmailSubmission siblings are a later purely
additive step rather than a redesign. `syncEmails` (C23) is the
one-shot built on this combinator.

**Verification gate.** `tests/wire_contract/public-api.txt` gained
`addEmailChangesToGetAll` and `getAll`, and
`tests/wire_contract/type-shapes.txt` gained both generic records
(`H16`/`lint-public-api`, `H17`/`lint-type-shapes`).
`tests/protocol/tconvenience.nim` adds
`addEmailChangesToGetAllEmitsThreeInvocations` (three calls, in
dispatch order, with handles `c0`/`c1`/`c2`) and
`addEmailChangesToGetAllWiresBothReferences`, which asserts the second
get's `#ids` names `Email/changes` at path `/updated` — the exact
argument the old chain could not express.

### C18. Unify the sealed-seq projection on `asSeq` *(P9, DRY)* — ✅ DONE (this triage)

Six sealed non-empty wrappers exposed their backing seq as `toSeq`
(a copy), reintroducing the `std/sequtils.toSeq` clash that the
generic `NonEmptySeq[T].asSeq` was named to avoid. Unified on
`asSeq → lent seq[X]`
(`src/jmap_client/internal/types/primitives.nim`). Landed on this
branch (`types: unify sealed-seq projection on asSeq (drop toSeq)`).

### C19. Test standalone-compile hygiene *(P26)* — ✅ DONE (this triage)

Two test files failed strict standalone-compile (`UnusedImport`,
`Uninit`) but passed via the megatest JOIN; made self-contained.
Landed on this branch (`tests: make two suites standalone-compile
under the strict battery`).

### C20. Query filter/sort builder DSL *(P7, P16)* — ⬜ TODO (future additive)

AUDIT `email query:filter` / `email query:sort`.
`EmailFilterCondition` is a raw object literal with `Opt`-wrapped
fields, so a two-field filter needs `Opt.some` on each; `sort` is
`Opt[seq[EmailComparator]]`, so one comparator double-wraps. A
filter/sort builder DSL would remove the per-field `Opt.some`
ceremony. Future *additive* pass.

### C21. Per-type current-state accessor *(P7)* — ✅ DONE (2026-08-04)

AUDIT `email sync:state-acquisition`. `Email/changes` diffs against
the object state (`GetResponse.state`), but no command surfaced the
current per-type state, so a sync bootstrap had to issue an empty-ids
`Email/get` purely to read `resp.state` as the initial cursor. A
session- or get-level "current state per type" accessor would remove
that round-trip.

**Shipped 2026-08-04** (branch `api/c15-easy-path-one-shots`).
`getEmailState(client, accountId): JmapResult[JmapState]`
(`src/jmap_client/internal/one_shot.nim`) names the cursor the API
previously left implicit. The session-level variant is not available
to build: RFC 8620 §2 gives the Session object no per-type object
state, so the state can only come from a `/get` response. What the
accessor removes is therefore the *knowledge*, not the round-trip —
the empty-ids `Email/get` is now the library's payload-free internal
bootstrap instead of a trick the consumer has to know. The
`Opt.some(direct(newSeq[Id]()))` argument is deliberate and pinned:
a permissive `Opt.none` would fetch the whole account's Email list to
read one state string.

**Verification gate.** `tests/wire_contract/public-api.txt` gained
`getEmailState` (`H16`/`lint-public-api`).
`tests/unit/tone_shot.nim` adds `oneShotGetEmailStateSuccess`,
`oneShotGetEmailStateRequestShape` — which asserts the emitted
`Email/get` carries an explicit empty `ids` array, the payload-free
promise — and `oneShotGetEmailStateMethodError` for the rail.

### C22. Type the VacationResponse singleton id *(P15)* — ⬜ TODO (future additive)

AUDIT `vacation:singleton-id`. `VacationResponseSingletonId` is a raw
`string` ("singleton"), not a typed `Id`, so looking the singleton up
in `updateResults` (`Table[Id, _]`) needs `parseId(...).get()` first —
a newtype leak on the one place the id matters. A typed `Id` constant
(or a typed accessor) closes the leak. Future *additive* pass.

### C23. Email/changes sync one-shot *(P7)* — ✅ DONE (2026-08-04)

Opened and closed by the same PR (branch
`api/c15-easy-path-one-shots`), as `docs/design/17-L5-FFI-Principles.md`
§8 prescribed: the L5 C ABI wraps one-shots only, so `jmap_sync_emails`
needs a Nim `syncEmails` to wrap, and no ledger item covered it. C17
(the `/updated` back-reference) and C21 (the per-type state accessor)
are its *components*, not the one-shot itself — folding the work onto
either would have made both items dishonest, so this item records the
composition instead.

**Shipped 2026-08-04.** `syncEmails(client, accountId, sinceState,
maxChanges, bodyFetchOptions): JmapResult[EmailSync]`
(`src/jmap_client/internal/one_shot.nim`) returns the whole fetchable
delta from one round-trip: `EmailSync` carries `changes`, `created`,
and `updated`, every method outcome already collapsed onto the rail.
The bootstrap cursor comes from `getEmailState` (C21); the three
invocations come from `addEmailChangesToGetAll` (C17). Destroyed ids
stay on `changes` — there is nothing left to fetch for them, so no
third get exists. The docstring states the two obligations RFC 8620
§5.2 puts on the caller and the type cannot: persist `changes.newState`
as the next cursor, and loop while `changes.hasMoreChanges`; a record
both created and updated since `sinceState` may appear in both lists,
so a consumer merging them dedupes by id. Failure is fail-fast — the
changes call erroring is the root cause, so it is what the rail
reports.

Landing this forced one vendored-dependency fix. `nim-results`'
`raiseResultDefect` probed `when compiles($v)`, which proves only that
`$v` typechecks; the enclosing `func` is `noSideEffect`, so it also
needs `$v` proven pure, and std's derived `$` for `Email`'s
self-referentially recursive MIME body-part tree defeats Nim's generic
effect-inference fixed point. `.error` was therefore uncompilable for
any `Result` whose success type embeds `Email` — exactly what
`EmailSync` is, so its tests hit the failure the moment they tried to
render an error, and there was no way to route around it from calling
code.
The probe now wraps the render in a `noSideEffect` closure and lets
`compiles()` judge that instead, so a genuinely pure `$` keeps the
rich `"msg: value"` defect text and anything Nim cannot close on falls
back to the message-only defect, exactly as an absent `$` already did.
An in-file marker above the overload names the divergence so a
re-vendor does not silently drop it.

**Verification gate.** `tests/wire_contract/public-api.txt` gained
`syncEmails` and the `EmailSync` type, and
`tests/wire_contract/type-shapes.txt` gained `EmailSync`'s three
fields (`H16`/`lint-public-api`, `H17`/`lint-type-shapes`).
`tests/unit/tone_shot.nim` adds `oneShotSyncEmailsSuccess` — whose two
canned `Email/get` legs carry deliberately distinct `notFound` shapes,
so a transposition of the `created` and `updated` handles fails the
test rather than passing unnoticed, and which incidentally pins the
RFC 8620 §5.2 case where a record updated then destroyed since
`sinceState` surfaces as `notFound` on the `/updated` fetch — and
`oneShotSyncEmailsChangesErrorFailsFast` for the fail-fast rail.

### C24. Layer-5 C ABI v1 (easy path) *(P7, P29, D10)* — ✅ DONE (2026-08-30)

Opened and closed on branch `api/l5-c-abi`. D10 ratified the binding
principles (`docs/design/17-L5-FFI-Principles.md`) before anything was
built; no ledger item tracked the build itself, so this one records it.

**Shipped 2026-08-30.**

- **The export section** in `src/jmap_client.nim` (A10 — the sole module
  carrying `{.exportc.}`): 102 C symbols over the one-shot easy path.
  Connect and session, mailboxes, emails with decoded text bodies, the
  email query, threads, identities, the vacation read and update, the
  four write verbs, the sync cursor and delta, and send. Per-handle
  error state throughout — `jmap_errmsg` for prose, `jmap_errtype` for
  the wire `type` string of a typed failure, static `jmap_strerror` —
  with no thread-local last error anywhere (P14).
- **`include/jmap_client.h`**, hand-curated, self-contained, and the
  contract a consumer compiles against. It carries the version macros
  and `jmap_version()` (see C6 above).
- **The C compliance suite**, `ctests/t01`–`ctests/t13`: plain-C programs
  driving the ABI against canned transports, reaching all eight
  `JMAP_E_*` statuses.
- **The C consumer bench**, `examples/jmap-c-cli/` — P29 applied to the
  FFI. Its README's FINDINGS section records six awkward call sites, the
  wrap-rate evidence this item exists to produce. Building it is gated;
  running it against a live server is manual, because hosted CI stands
  up no JMAP server.
- **The panic-surface audits.** `tests/compliance/traw_index_audit.nim`
  is new — the second Tier-1 item of `docs/TODO/macro-tests-ffi.md`,
  extended to the `csize_t` narrowing a bracket audit cannot see — and
  joins the first, the assert/doAssert ban in
  `tests/compliance/tno_asserts_in_src.nim`. Both were behind no gate
  that runs on a push, which the new recipe fixes.

Where implementation overruled the design note, doc 17 carries a dated
amendment rather than a rewritten paragraph, so the record of what was
decided survives alongside what shipped. The consequential ones: the
`create`/`dealloc` pair (handles live on the shared heap, because the
contract lets a caller free one on another thread); the variadic option
setter (Nim cannot read a C `va_list`, so the query, message and
vacation-update handles take typed setters instead); the const-qualified
account accessors (the session is fetched lazily, so two of the three
mutate the handle); the single header gate (three shipped, and none of
them does what the sketched one did); and the ABI-freeze language,
which promised more than the header says — the library is pre-1.0, the
header states no compatibility promise, and the gates below are change
detectors, not compatibility checks.

**Verification gate.** `lint-c-header` (H18, the export/header name
inventory plus the four mandatory pragmas), `lint-c-header-snapshot`
(H19, `tests/wire_contract/c-header.txt` as an ordered render),
`lint-c-header-types` (H20, each declaration against the Nim signature
it stands for), `test-c` (the compliance suite under ASan and UBSan)
and `lint-defect-audits` (compiling `tno_asserts_in_src` and
`traw_index_audit` alongside `tffi_panic_surface` and
`tmail_e_reexport`). All five run in `just ci` and in
`.github/workflows/ci.yml`, which also builds the bench. The three Nim
wire-contract snapshots are unchanged: the C ABI wraps the Nim surface
without moving it.

## Section D — Process / policy artefacts

### D1. SemVer + deprecation + wire-byte contract policy *(P1, P2, P3, P10, P11, P25)* — 🟦 DEFERRED (2026-08-04, user decision)

Deferred by user decision 2026-08-04, together with its companion
D1.5; the rules below stand as the working policy until the file is
written.

Write `docs/policy/01-semver-and-deprecation.md`. Adopt strict SemVer:

- **Patch** (1.0.x): only fixes verifiably incorrect behaviour; no
  observable change to return values, raised errors, JSON keys
  emitted, or JSON structures accepted.
- **Minor** (1.x.0): additive only — new types, fields with
  default-omission, enum variants, proc overloads, default arguments,
  new top-level modules. Never rename, never repurpose, never remove.
  New JMAP RFCs (Contacts, Calendars, MDN, Sieve) ship as a new
  `mail`-sibling module + new `CapabilityKind` variant — NEVER as
  new top-level entry points (P20).
- **Major** (2.0.0): the only path for removing exported symbols,
  narrowing types, changing serialisation byte order, changing
  argument defaults, breaking wire-byte fixture replay.
- **Wire-byte contract**: `tests/testdata/captured/` fixtures are
  frozen inputs. Modifying any fixture file is a 2.0-flag PR; adding
  fixtures is fine. CI runs `git diff --name-status
  tests/testdata/captured/` against the previous tag — modified
  `.json` requires an explicit "WIRE BREAK" label.
- **Deprecation**: `{.deprecated: "use X instead".}` lives for at
  least one minor cycle before removal in the next major.
- **No-suffix-versioning rule (P3).** The strict/lenient distinction
  is encoded in name suffix `*FromServer`; this is a *semantic axis*,
  not a version. The library never uses `*V2`, `*2`, or numeric
  suffixes for evolved entry points — Nim overloading and default
  arguments serve that purpose.
- **No-globals rule (P10).** No module-level `var` in
  `src/jmap_client/*` outside `src/jmap_client.nim` (the L5 boundary).
  FFI thread-locals are an L5 concession only. Backed by lint H2.
- **No-callbacks rule (P11).** Every callback registered on a handle
  is a field on that handle, paired with a closure environment in Nim
  (or a `pointer` userdata at the FFI boundary). No module-level
  callback registration. Backed by code review.
- **License stance (P25).** All `src/`, `tests/`, `docs/design/`,
  `justfile`, `*.nimble`, `config.nims` files are BSD-2-Clause.
  Vendored artifacts may carry their upstream license. The library's
  effective license never changes after 1.0.

### D2. `public-api.txt` snapshot diffed in CI *(P1, P2)* — ✅ DONE

Reconciled 2026-08-04: the deliverable exists and gates. `just
freeze-api` regenerates `tests/wire_contract/public-api.txt` from the
compiler-as-library oracle (`scripts/api_oracle.nim` over
`scripts/api_probe.nim`), and `just lint-public-api` (H16,
`tests/lint/h16_public_api_snapshot.nim`) recomputes the same surface
through the same oracle and compares bidirectionally — a new `*` symbol
and a removed one both fail, with the `[API-CHANGE]` PR label as the
acknowledgement path. The recipe is wired into `just check` and `just
ci`. A26 names the snapshot and F6 is the CI-wiring side of the same
gate; A25/A25b/H17 cover the companion type-shape snapshot.

The residual — running the gate on hosted CI rather than only in the
local `just ci` — is the whole of F2's remaining scope, so it is tracked
there and not duplicated here.

P2 is "stability bought with tests"; before this landed, no test
asserted the exported symbol list.

### D3. Wire-byte fixture contract elevation *(P2)* — 🟡 PARTIAL

224 captured payloads exist under `tests/testdata/captured/` across
three servers (Stalwart, Apache James, Cyrus IMAP). Elevate from
"regression aid" to "frozen contract":

- Every `.json` is a wire shape the library promises to deserialise
  forever.
- Add a `tests/wire_contract/` category whose only failure mode is a
  serialisation change that breaks fixture replay.
- CI distinguishes "added new fixture" from "modified existing"; the
  latter is a major version unless the fixture was malformed.

### D4. Devendor or pin `nim-results` *(P1)* — ⬜ TODO

`vendor/nim-results` is currently a pinned, patched copy. Either:

- **(a)** Devendor before 1.0 — depend on upstream
  `nim-results` via nimble; commit `nimble.lock`.
- **(b)** Stay vendored, with a written commitment never to update
  the vendored copy without a major bump.

Vendored deps that change semantics under callers are how every
cautionary tale in the principles doc broke its API.

### D5. `.nimble` contract *(P1, P25)* — ⬜ TODO

The underlying facts hold today (`jmap_client.nimble` carries
`version = "0.1.0"` and `srcDir = "src"`; `src/jmap_client.nim` is the
single entry point; the public re-export tree is as A1 locks it), but
the deliverable — documenting them as part of the 1.0 contract in
`docs/policy/01-semver-and-deprecation.md` (D1.5) — is unwritten
because that policy file does not yet exist.

**Action.** Record in `docs/policy/01-semver-and-deprecation.md` that
`jmap_client.nimble`'s `version`, `srcDir`, the existence of
`src/jmap_client.nim` as the single entry point, and the public
re-export tree are all part of the 1.0 contract.

### D6. Generated docs as contract *(P28)* — ⬜ TODO

`nim doc --project` output structure (file paths, module headings) is
consumed by users browsing API. Lock the directory layout before
1.0; document in the policy doc.

### D7. Capability negotiation as the documented extension surface *(P20)* — ⬜ TODO

Write down explicitly: NEW JMAP RFCs (Contacts via RFC 8624,
Calendars, etc.) extend the library by:

1. Adding a new `CapabilityKind` variant (capabilities.nim).
2. Adding a new entity module under `src/jmap_client/<rfc>/` with
   the same shape as `src/jmap_client/mail/`.
3. Calling `registerJmapEntity(T)` etc. at module scope.

NEVER as a new top-level entry point that mirrors an old one.

Capability-extension *gettable properties* on existing entities need no
library change at all: they are requestable through the typed `…Other`
escape arm on the A3.6 get-property selectors (forward-compat, P20).

**Prohibitive clause (explicit, not implicit).** It is a 2.0 break to
add any of:

- a new public proc on `JmapClient` whose name does not begin with
  `send`, `setCredential`, `setDebugCallback`, or `fetchSession`;
- a new public top-level proc in `jmap_client.nim`;
- a new public module path under `src/jmap_client/` that is not
  nested under an entity directory.

Without this written down, the next contributor adds
`proc fetchCalendars(client: JmapClient)` and the door is open.
Backed by lint H5.

### D8. Threading invariants — class-wide rule *(P24)* — 🟡 PARTIAL

Reconciled 2026-08-04: the lifecycle half landed, the class-wide
sweep did not. `Session`, `RequestBuilder`, `BuiltRequest` and
`DispatchedResponse` gained the threading footer, joining the L1 value
types, `Credential`, `SessionEndpoint`, `Transport` and `JmapClient`.
That discharges Decision 5 of `docs/design/14-Nim-API-Principles.md`
("state the threading invariant for `Session`, `Client`, request
builders; document in the docstring") — the types a consumer's
lifetime questions actually land on now answer them in the docstring.

**Residual.** Roughly fifteen types carry the footer against the 272
`type` rows in `tests/wire_contract/public-api.txt`. Still unstated:
`ResponseHandle`, `NameBoundHandle` and `CompoundHandles`
(`internal/protocol/dispatch.nim`); the L1–L3 value types as a class
(`validation`, `primitives`, `identifiers`, `collation`, `envelope`,
`framework`, `errors`, `methods_enum`; `protocol/{entity, methods,
jmap_error, call_meta, preflight}`); and every `internal/mail/` entity
(`Email`, `Mailbox`, `Thread`, the blueprints and filters).
`PushChannel` / `WebSocketChannel` are deferred to whichever
implementation lands them. The Coverage-trace P24 row stays 🟡 until
that sweep runs.

The original scope, retained for the record:

`src/jmap_client/internal/client.nim` documents "not thread-safe"
for `JmapClient`. Six L1 types carry the explicit threading footer
already (`Account`, `CoreCapabilities`, `MailAccountCapabilities`,
`SubmissionAccountCapabilities`, `AccountCapabilityEntry`,
`ServerCapability` plus `SubmissionExtensionMap`). The remaining
work is the class-wide sweep applying the rule to every other
public type:

- **L1–L3 types as a class** (everything under
  `src/jmap_client/internal/types/` (`validation`, `primitives`,
  `identifiers`, `collation`, `capabilities`, `methods_enum`,
  `session`, `envelope`, `framework`, `errors`) and
  `src/jmap_client/internal/protocol/` (`methods`, `builder`,
  `dispatch`, `entity`), plus the `internal/mail/` siblings): "value
  type, immutable after construction, freely shareable across threads
  (enforced by `{.push raises: [], noSideEffect.}` and the absence of
  `var` fields on public types)."
- **L4 `JmapClient`**: "not thread-safe; one per thread."
- **Handles** (`ResponseHandle`, `NameBoundHandle`, `BuiltRequest`,
  `DispatchedRequest`): "tied to the parent builder/response; not
  independently shareable. Their lifetime ends with the response
  extraction."
- **`Transport`** (A19): "implementations are not required to be
  thread-safe; the library takes one transport per `JmapClient`."
- **`PushChannel`** (A23) / **`WebSocketChannel`** (A24): "per-
  implementation; specified when the implementations land."

Apply to every remaining public type via a one-line docstring
footer (or the type's full docstring if longer). One mass edit, not
25 individual decisions.

### D9. Long-form guide *(P28)* — 🟦 DEFERRED (2026-08-04, user decision)

Deferred by user decision 2026-08-04; the outline below stands as the
brief for whenever it is picked up.

Draft `docs/guide/everything-jmap.md` — a narrative companion to the
generated reference docs. Outline (14 chapters; libcurl's *Everything
curl* is the benchmark):

1. Discovering a session.
2. Building a request via the builder.
3. Dispatching and extracting typed responses.
4. Error handling on the three railways.
5. Result references and method chaining.
6. Sample workflows: mailbox listing, email query+get, set+update
   round-trip.
7. **Threading invariants and concurrency model** (cite D8).
8. **Capability negotiation: pre-flight checks** (cite C5).
9. **Server-extension forward-compat** — `extras`,
   `mnUnknown`/`ckUnknown`/`metUnknown`/`setUnknown` round-trip.
10. **Wire-byte reproducibility and captured fixtures** — how to
    consume `tests/testdata/captured/` for offline development.
11. **Migration from MIME/IMAP-shaped thinking to JMAP-shaped
    thinking** — the conceptual ramp.
12. **Choosing the right API surface** — there is one public
    layer (root `import jmap_client`); this chapter says so
    explicitly.
13. **Future FFI** — what the planned C ABI shape will look like
    (cite D10).
14. **Cookbook of small task recipes** (delegated to D14).

Need not be complete pre-1.0; needs to exist and reflect the locked
API.

### D10. L5 FFI design note *(P9, P14, future-FFI)* — ✅ DONE (2026-08-04, branch api/l5-ffi-design)

**Known contradiction (RESOLVED 2026-08-04).**
`.claude/rules/nim-ffi-boundary.md` mandated the opposite of what this
item requires: its rule 7 handed exported procs a `setLastError` /
`clearLastError` pair, and its rule 8 made thread-local error state via
`{.threadvar.}` a *mandatory* rule. That is the pattern P14 ("no
thread-local error queues; no last-error globals",
`docs/design/14-Nim-API-Principles.md` §Errors) forbids by name, that
the same document's anti-pattern list forbids again ("Last-error
thread-locals at the FFI boundary … errors travel through return values,
not through `int jmap_last_error()`"), and that its Decision 9 tells this
note to write down. The rules file and the skill content it drives were
therefore steering the future L5 implementation into the OpenSSL
anti-pattern. User decision 2026-08-04: resolve the contradiction inside
the Layer-5 C ABI design phase — the phase that authors this very note —
rather than patching the rules file ahead of it, so that one decision
settles the rules file, the skill content, and the design note together.

**Resolved 2026-08-04.** Settled per the user's decision: per-handle
error state — the SQLite/libcurl model (`jmap_status` return codes,
`jmap_errmsg(handle)` with `sqlite3_errmsg` semantics, static
`jmap_strerror`) — wins outright; thread-local last-error state is
forbidden (P14). `.claude/rules/nim-ffi-boundary.md` rules 3, 7, and 8
and all four `nim-ffi-boundary` skill files are rewritten to the
per-handle model in the same change that lands this note, so one
decision settles the rules file, the skill content, and the design note
together, with zero remaining contradiction.

Written as `docs/design/17-L5-FFI-Principles.md` (the tracker's planned
name for this note, `16-L5-FFI-Principles.md`, was taken by
`16-api-from-the-consumers-chair.md`, hence 17), mapping each principle
to its C-ABI manifestation. The note also supersedes
`docs/design/00-architecture.md` §5.1–5.4 on handle naming/inventory
and enum exposure; dated amendment pointers were added in that file.

**Carried through from this item's original requirement list.** Opaque
handles the C consumer cannot see inside (doc 17 §2); no
`EmailGetCtx*`/`MailboxQueryCtx*` proliferation (§2, P9);
`jmap_init()` / `jmap_cleanup()` with no thread-local setup ritual
(§2, §7, P10); per-handle callbacks with threaded `userdata` — the
`setDebugCallback`/A31 shape, never a `jmap_register_logger()` (§6,
P11); bring-your-own-HTTP transport mirroring A19's closure-vtable,
with the user's `close_fn` firing from the last drop (§6); A6's
`BuilderId` phantom-token strategy reserved as the C-ABI cookie
analogue for the future builder layer (§8). A12's stable `kind`
discriminator and bounded `message()` projection are the prerequisite
that makes the diagnostic accessor total, whichever surface it takes.

**Where the note settled differently, and why.**

- **Error surface: `sqlite3_errmsg` borrow, not `CURLOPT_ERRORBUFFER`.**
  This item assumed a caller-supplied error buffer. The user settled on
  a library-owned `const char *jmap_errmsg(handle)` borrow instead: no
  buffer sizing, no truncation protocol, no caller allocation on the
  error path, and the same per-handle (not thread-local) storage that
  was the point of the item. The anti-pattern verdict is unchanged —
  `int jmap_last_error()` stays forbidden (P14).
- **Handle spelling: forward-declared opaque structs, not a
  `distinct pointer` alias.** The C side declares
  `typedef struct jmap_client jmap_client;` — distinct incomplete types
  that keep `const` qualification and `jmap_client **out` meaningful,
  which a `void*` alias cannot. The Nim side is an L5-owned wrapper
  object reached as `ptr JmapClientHandle`, because the L4 handles are
  `ref`s over module-private objects (§2, P8).
- **Builder deferred; `jmap_transport` and `jmap_query` ship instead.**
  The transient `RequestBuilder*` of the original list is reserved for
  a future *additive* C layer — the libcurl easy→multi trajectory
  (P22) — because v1 wraps the one-shot easy path only. The two v1
  owning contexts are `jmap_client` and `jmap_transport`, with
  `jmap_query` as a transient spec handle (§2, §8).
- **Option enum scoped and renamed: `jmap_query_opt`, not an ABI-wide
  `JmapOption`.** The easy path's only structured input is the email
  query, so the tagged-option surface is quarantined to it rather than
  becoming a global option namespace (§5, P20).
- **Transport constructor is `jmap_transport_new` / `jmap_transport_free`,
  not `jmap_init_transport`** — the `_new`/`_free` pairing puts
  ownership in the signature (§6, P12) and keeps `init` meaning
  process initialisation only.
- **v1 scope has a Nim prerequisite.** The C ABI wraps one-shots only,
  so the missing write and sync one-shots land first: ledger **C15**
  (Email/set write one-shot) plus a new item for the Email/changes
  sync one-shot, since C17 and C21 are its components, not the
  one-shot itself. See doc 17 §8. The prerequisite PR has since
  shipped: C15, C17, and C21 are ✅ DONE and the missing item was
  opened and closed as **C23**.

### D11. Scope and non-goals policy *(P4)* — ⬜ TODO

Write `docs/policy/02-scope-and-non-goals.md`. Enumerate explicit
non-goals so the boundary survives turnover:

- **Out of scope.** IMAP, POP3, SMTP, Sieve script execution, CalDAV,
  CardDAV, OAuth2 token acquisition, IMAP-style search syntax, raw
  contact / calendar protocols outside JMAP.
- **In scope as additive capability modules.** JMAP Contacts (RFC
  drafts), JMAP Calendars (RFC drafts), JMAP MDN (RFC 9007), JMAP
  Sieve (RFC drafts) — all via the JMAP wire only, never as parallel
  protocol implementations.

Cite c-client (universal `MAILSTREAM*` over many backends → forced
union of every backend's quirks) and libdbus ("useful as a backend
for bindings" hedge made it useless to direct consumers) as
cautionary precedent. Mandate justification against this doc for any
PR adding non-JMAP-wire support. Backed by lint D12/H4.

### D12. Non-JMAP import lint *(P4)* — backs D11 — ⬜ TODO

Add a CI lint that rejects new `import std/smtp`, `import std/imap`,
`import std/pop3`-style imports (and any obvious non-JMAP-wire
library import) under `src/`. Backs D11 with mechanical enforcement.
Same hook as H4.

### D13. RFC extension policy *(P20)* — ✅ DONE

Reconciled 2026-08-04: `docs/policy/03-rfc-extension-policy.md` is
committed (landed in 78a1d5a) and carries every reservation enumerated
below as a table with the rule stated explicitly — "post-1.0,
implementing any reserved feature means landing the named type at the
named path with the named capability variant; deviating is a 2.0 break".
It also reserves the async surface (`sendAsync`, `DispatchedRequest`) by
policy, which is A7e's deliverable. D13.5 is the file-commit twin of
this item; A7e cites the same file as landed. Two section numbers in
the list below were wrong and are corrected here against the RFC text:
Push is RFC 8620 §7 (the policy file already had this right), and blob
upload/download is §6.1–6.3 — §6.5 does not exist, §6 stops at 6.3
`Blob/copy`.

The reservations, as written up in the policy file: for each
unimplemented RFC, the planned shape, so the names are reserved but
not the implementations.

- **RFC 8887 — JMAP over WebSocket.** `CapabilityKind`: `ckWebsocket`
  (already exists). Type: `WebSocketChannel` (A24). Path:
  `jmap_client/websocket`.
- **RFC 8620 §7 — Push.** `CapabilityKind`: future `ckPush`. Type:
  `PushChannel` (A23). Path: `jmap_client/push`.
- **RFC 8620 §6.1–6.3 — Blob upload/download.** Will extend
  `JmapClient` with `uploadBlob`/`downloadBlob` methods (additive on
  the existing handle, *not* a separate context type). Document the
  rationale before 1.0.
- **RFC 9007 — JMAP MDN.** New entity module
  `src/jmap_client/mdn/` mirroring `mail/`'s shape. `CapabilityKind`:
  `ckMdn` (already exists).
- **RFC 8624 — JMAP Contacts.** New entity module
  `src/jmap_client/contacts/`. `CapabilityKind`: `ckContacts` (already
  exists).
- **Future Calendars draft.** New entity module
  `src/jmap_client/calendars/`. `CapabilityKind`: `ckCalendars`
  (already exists).

Lock names pre-1.0; implement post-1.0 as additive minor.

### D14. Cookbook of recipes *(P28)* — ⬜ TODO

Plan `docs/guide/cookbook.md` of small task recipes — these become
the most-cited URLs by adoption pattern:

- "Flag an email read."
- "List the mailbox tree."
- "Move an email between mailboxes."
- "Parse a blob into `ParsedEmail`."
- "Send an email via Submission/set."
- "Set up a vacation responder."
- "Search threads with attachments."
- "Get + set in one batch (result-reference chain)."

Each recipe ≤ 30 lines of Nim, runnable against any of the three
target servers.

### D15. Lifecycle types design note *(P27)* — ❌ DROPPED

The lifecycle contract is documented inline at its enforcement
sites: type docstrings on `RequestBuilder` / `BuiltRequest` /
`DispatchedResponse` / `ResponseHandle` / `NameBoundHandle` /
`BuilderId` / `GetError`, plus `docs/design/03-layer-3-design.md`
§4.3 (two-level railway composition) and the lifecycle narrative in
`docs/design/00-architecture.md` (`newBuilder → add* → freeze → send
→ get`). A standalone design doc would duplicate those without adding
constraint information.

### D16. Convenience module design note *(P27)* — ❌ MOOT (S4)

Campaign reconciliation (2026-08-04): moot for the same reason as C7
and C9 — S4 dissolved the P6 quarantine and `convenience.nim` no longer
exists. A design note whose subject is "what this quarantined module is
and is not for" has no subject; the combinators are first-class on the
always-on hub in `src/jmap_client/internal/mail/combinators.nim`, and
the hub's own module docstring in `src/jmap_client.nim` states their
status.

Verify `convenience.nim` has a design note (in `docs/design/` or as a
comprehensive module docstring at minimum). If not, write one, citing
P6 as the constraint. The doc covers what the module is for (pipeline
combinators), what it explicitly is NOT for (semantic convenience —
see C7 charter), and how new helpers are vetted.

### D1.5. Commit `docs/policy/01-semver-and-deprecation.md` *(P1, P2, P25, P26)* — 🟦 DEFERRED (2026-08-04, user decision)

Deferred by user decision 2026-08-04, with D1 whose rules it commits.

D1 enumerates the SemVer rules but they live as bullet points in
this TODO, not as a tracked policy file. Until the file exists at
the canonical path, every PR that brushes the rules re-litigates
them.

**Action.** Write the policy file. Existence-gate: the file must
exist before 1.0 tag. Required sections (each verbatim from D1's
bullets, expanded into prose):

1. **Patch / minor / major split** — what each tier may change;
   what counts as "observable behaviour"; the wire-byte clause.
2. **No-suffix-versioning rule** (P3) — overloads and default args
   only; `*V2`, `*2`, numeric suffixes forbidden.
3. **No-globals rule** (P10) — module-level `var` permitted only
   in `src/jmap_client.nim` (the L5 boundary). Backed by H2.
4. **No-callbacks rule** (P11) — every callback is a field on its
   handle paired with closure environment; FFI uses `pointer`
   userdata. No module-level callback registration.
5. **License stance** (P25) — BSD-2-Clause across `src/`, `tests/`,
   `docs/design/`, build files. Vendored artifacts may carry
   upstream licence. Effective licence never changes after 1.0.
6. **Build-tooling clause** (P26) — `mise.toml`, `justfile`,
   `*.nimble`, `config.nims` are the single build surface. Per-OS
   conditional compilation in shipped code is forbidden; the only
   sanctioned `when defined(...)` is `when defined(ssl)` in
   `internal/client.nim` (HTTPS hint). New `when defined(<os>)` guards in
   `src/` require written justification in the policy doc.
7. **Observable-behaviour glossary** — exhaustive list of "what
   counts as observable": exported symbols, type signatures, JSON
   keys emitted, JSON structures accepted, error variant kinds,
   error message formats (A12 / H15 snapshot lint), wire-byte
   fixture replay.
   Each row is mapped to its CI gate.
8. **Closed set of public module paths** — mirrors the
   filesystem-derived snapshot at
   `tests/wire_contract/module-paths.txt` (A10a; H13 lint
   verifies). Currently one path: `jmap_client` (root). Adding a new
   public path is a minor bump per P20; removing or renaming
   an existing one is a 2.0 break per P1. Implementation lives
   under `src/jmap_client/internal/`; H10 forbids external
   `import jmap_client/internal/...`. The policy doc and the
   snapshot file must agree.

### D11.5. Commit `docs/policy/02-scope-and-non-goals.md` *(P4)* — ⬜ TODO

D11 enumerates scope; this item commits it as a tracked file.

**Action.** Write the policy file. Existence-gate: the file must
exist before 1.0 tag. The file contains:

- **Out of scope** (verbatim from D11): IMAP, POP3, SMTP, Sieve
  script execution, CalDAV, CardDAV, OAuth2 token acquisition,
  IMAP-style search syntax, raw contact / calendar protocols
  outside JMAP.
- **In scope as additive capability modules**: JMAP Contacts,
  JMAP Calendars, JMAP MDN (RFC 9007), JMAP Sieve.
- **Cautionary citations**: c-client universal `MAILSTREAM*`,
  libdbus "useful as a backend for bindings".
- **PR justification clause**: any PR adding a non-JMAP-wire
  feature must cite this doc and provide written justification.
- **Lint reference**: H4 forbids new non-JMAP imports.

### D13.5. Commit `docs/policy/03-rfc-extension-policy.md` *(P20)* — ✅ DONE

Reconciled 2026-08-04: the file exists at the canonical path, committed
in 78a1d5a. The existence gate is met.

D13 enumerates the RFC reservations; this item committed them as a
tracked file.

**Delivered.** `docs/policy/03-rfc-extension-policy.md` carries the
per-RFC table from D13 (RFC 8887 WebSocket, RFC 8620 §7 Push, §6 Blob,
RFC 9007 MDN, RFC 8624 Contacts, future Calendars). Each row
names: capability variant, reserved type name, reserved module path,
implementation status (deferred). The lock is stated: post-1.0,
implementing any of these requires landing the table-row's named
type at the table-row's named path; deviation is a 2.0 break. The
file additionally carries A7e's async-surface reservation
(`sendAsync`, `DispatchedRequest` — reserved by policy, not by type
stub) and the P23 rationale for keeping Push and WebSocket distinct.

### D17. Codify reviewer workflow: CONTRIBUTING.md + PR template *(P1, all)* — ⬜ TODO

The principles doc's "Verification" section says "At PR review
time, reviewers reference principles by number." Today no written
standard exists. `CONTRIBUTING.md` does not exist; `.github/`
contains only `workflows/`.

**Action.** Two files, both existence-gated for 1.0:

1. `CONTRIBUTING.md` at repo root. Contents:
   - Pointer to `docs/design/14-Nim-API-Principles.md` as the
     reviewer rubric.
   - The "would I do this in OpenSSL?" smell check — if a
     proposed design feels expedient, ask the question; if the
     answer is yes, redesign.
   - Pointer to `docs/policy/` for SemVer, scope, RFC extension
     rules.
   - Pointer to the Documented exceptions sub-section of this
     TODO.
2. `.github/pull_request_template.md`. Reviewer checklist:
   - Cite each principle the PR upholds or trades off
     (`P5: …`, `P19: …`).
   - Confirm CI snapshots regenerated if public surface changed
     (D2, A25, A26, F6).
   - Confirm no new `JsonNode` field outside the documented
     exception list (A22b).
   - Confirm no new `*`-export not justified in the PR body.
   - Tag the PR `[ERR-MSG-CHANGE]` if the H15 error-message
     snapshot changed
     (`tests/wire_contract/error-messages.txt`); reviewer
     verifies each diff is intentional and the change
     classification matches the SemVer level (A12 / §7 of
     `docs/design/15-error-surface.md`).
   - Confirm Coverage-trace section updated if a TODO item ticked
     (F7 verifies).

### D18. Pre-1.0 freeze checklist tracker *(P1)* — 🟦 DEFERRED (2026-08-04, user decision)

Deferred by user decision 2026-08-04; no checklist file exists, and
this file's status dashboard plus the per-item markers carry gate
status until one does.

The 1.0 release tag must fail if any freeze gate is unmet. Today
the gate list is dispersed across this TODO; nobody can answer
"are we ready?" in a single look.

**Action.** Create `docs/TODO/pre-1.0-freeze-checklist.md` (a
companion to this file, not a replacement). Format: one line per
freeze-gate item, status `[ ]` / `[x]`, link to the TODO item.
Categories:

- **Existence gates** — files that must exist before 1.0 (C1.1,
  D1.5, D9, D10, D11.5, D13.5, D16, D17, plus the A10c stub
  files `src/jmap_client/internal/{push,websocket}.nim`).
- **Mechanical gates** — CI lints that must pass (H1–H13).
- **Snapshot gates** — frozen files committed (A25, A26, F6,
  plus A10a `tests/wire_contract/module-paths.txt`).
- **Decision gates** — open choices that must be resolved (D4 devendor;
  A3.5, B9, and B12 are done, B11 dropped).
- **Test gates** — property tests that must exist (F1, A2b,
  A28b); diagnostic-format snapshot (A12 / H15) already in place.

CI gate (`just check-freeze` or `.github/workflows/release.yml`):
the 1.0 release tag fails if any `[ ]` row remains. The
checklist file is regenerable from this TODO; F7's consistency
check covers both files.

### D19. Project-wide stringly-surface sweep for get-properties *(P19)* — ⬜ TODO

A3.6 typed the get-property and `bodyProperties` selection surfaces.
Add an `H`-style mechanical lint
(`tests/lint/h14_no_stringly_get_properties.nim`, wired into
`just lint` / `just ci`) asserting that no exported
`add*Get` / `add*Parse` / display-property builder parameter is typed
`seq[string]` or `Opt[seq[string]]`. The lint records, by symbol, the
exemption list of legitimate open-string surfaces (the "true
boundaries" that genuinely are free-form strings, not closed property
sets):

- `EmailHeaderFilter.name: string` — RFC 5322 header names are an open
  free-form space.
- `addSearchSnippetGet` / `addSearchSnippetGetByRef` — `SearchSnippet/get`
  has no `properties` facility (fixed shape).
- `Request.using: seq[string]` — hub-private; the library owns the
  `seq[CapabilityUri] → seq[string]` conversion at `freeze()`.
- `SetError.invalidEmailPropertyNames: seq[string]` — a server-reported
  wire field, parsed passively; never client-constructed.

**Scope note.** The lint asserts its invariant over the A3.6 typed
get-property surface, which is in place; it is recorded here as the
freeze-gate that locks that surface against regression, to be
implemented as part of the H-lint sweep.

### D20. Layer design docs still describe the pre-S1/S4 architecture *(P27)* — ⬜ TODO

`docs/design/00-architecture.md` opens by declaring that it describes
the library as implemented and that the source tree is the source of
truth it mirrors. Four layer docs no longer hold to that, because the
S1 and S4 refactors landed in `src/` without a matching pass over
`docs/design/`:

- **The retired error rail (S1).** `01-layer-1-design.md` §8.5/§8.6 and
  `03-layer-3-design.md` still teach `ClientError` and `GetError` as
  live types with live constructors. The one consumer rail is the
  eight-arm `JmapError` in
  `src/jmap_client/internal/protocol/jmap_error.nim`
  (`JmapResult[T] = Result[T, JmapError]`); `jeTransport` / `jeRequest`
  absorbed `ClientError`, `jeMisuse` / `jeProtocol` absorbed `GetError`.
  `15-error-surface.md` was corrected in place on 2026-08-04 (§1–§5
  now describe the `JmapError` rail) and needs no further uplift.
- **The dissolved P6 quarantine (S4).** `03-layer-3-design.md` §13,
  `04-layer-4-design.md` (decision row D4.14), `00-architecture.md` and
  `05-mail-architecture.md` still present `convenience.nim` as a live
  opt-in module reached by `import jmap_client/convenience`. It was
  deleted; the combinators live in
  `src/jmap_client/internal/mail/combinators.nim`, the one-shots in
  `src/jmap_client/internal/one_shot.nim`, both on the always-on hub,
  and `tests/wire_contract/module-paths.txt` holds one row.

The 2026-08-04 reconciliation put a dated currency banner at the head
of each affected doc rather than half-correct them in a documentation
PR, since an uplift wants the same file-by-file verification against
`src/` that A1–A30 got. This item owns that uplift and the removal of
the banners.

**Action.** Re-derive each layer doc's affected sections from `src/` at
HEAD, then delete the banner. Existence-gate: no
`docs/design/*.md` carries a currency banner at the 1.0 tag.

## Section E — Defer to 1.x

Additive items that compose forward and do not block 1.0.

### E1. Async support *(P22)* — 🟦 DEFERRED (1.x)

Sync `JmapClient.send` is the headline. Async lands later via the
Transport interface (A19) — alternative transports wrap `chronos`,
`puppy`, etc. themselves. Do not import `std/asyncdispatch` or
`chronos` from L1–L3; that is already the case (verified clean).

## Section F — Verification gates

Pre-1.0 freeze gates. Each must pass before tagging.

### F1. Property-test serde round-trip — explicit checklist *(P2)* — 🟡 PARTIAL

`tests/property/` exists. Replace soft "inventory which public types
lack a property test" with explicit checklist
`tests/property/coverage.txt`. Every public type that crosses a serde
boundary listed; ticked off as part of the freeze gate. The principle:
any wire-bytes change must fail CI.

**CI step.** Add a `just test-wire-contract` recipe that runs every
file under `tests/property/`. The freeze gate fails if
`tests/property/coverage.txt` has any unchecked row.

The list at audit time spans (non-exhaustive):
- Envelope: `Invocation`, `Request`, `Response`, `ResultReference`
- Session: `Session`, `Account`, `AccountCapabilityEntry`,
  `UriTemplate`, `ServerCapability`, `CoreCapabilities`,
  `MailAccountCapabilities`, `SubmissionAccountCapabilities`
- Errors: `MethodError`, `SetError`, `RequestError`, `TransportError`,
  `ClientError`, `ValidationError`
- Methods: every `GetResponse[T]`, `SetResponse[T]`, `ChangesResponse`,
  `QueryResponse`, `CopyResponse`, `QueryChangesResponse`
- Mail: `Email`, `Mailbox`, `Thread`, `Identity`, `EmailSubmission`,
  `VacationResponse`, `SearchSnippet`, `EmailBlueprint`, `EmailUpdate`,
  `MailboxFilterCondition`, `EmailFilterCondition`,
  `SubmissionFilterCondition`, all body / header types

### F2. Wire the freeze gates into hosted CI *(P5, P1, P2)* — ⬜ TODO

**Rescoped 2026-08-04 (user decision).** The audit walk this item was
originally written for is finished: A1b, A1c and A1d walked the three
hubs symbol by symbol and demoted everything not load-bearing, and H16
(`tests/wire_contract/public-api.txt`, D2) now locks the resulting
surface mechanically, so "walk the exports by hand" no longer describes
work that remains. What remains is that the gates run only on a
developer's machine.

`just ci` runs the full gate set locally: `reuse`, `fmt-check`, `lint`,
`lint-isolated`, `lint-style`, `lint-internal-boundary` (H10),
`lint-typed-builder-jsonnode` (H11), `lint-sealed-distinct` (H1),
`lint-fallible-ctor-public-arm` (H1b), `lint-h12-no-test-backdoors`
(H12), `lint-module-paths` (H13), `lint-error-messages` (H15),
`lint-public-api` (H16), `lint-type-shapes` (H17), `analyse`, `test`.
`.github/workflows/ci.yml` runs a strict subset: a REUSE job, then
`fmt-check`, `lint`, `lint-isolated`, `lint-style`, `analyse`, `test`.

**Action.** Bring hosted CI up to the local gate set.

1. Add the nine unwired lint recipes as workflow steps — H1, H1b, H10,
   H11, H12, H13, H15, H16, H17. The three snapshot lints (H15, H16,
   H17) are the load-bearing ones: they are what makes an unreviewed
   change to the error-message, public-API, or type-shape contract fail
   for someone other than its author.
2. Run the server-independent suites that `just test` skips via
   `tests/testament_skip.txt` — by rule, so the list cannot rot: every
   entry in that file bar `tests/integration/live/*`, which is the
   property files, the serde files, the stress files, the non-joinable
   compliance files, `tests/protocol/tmail_builders.nim` and
   `tests/unit/tclient.nim`. They are skipped locally for
   wall-clock cost, which is the wrong trade-off on hosted runners: they
   need no live server, and they are the property-test half of the P2
   wire contract (F1). A `just test-full` step, or a matrix job pinned
   to the skip-list minus `tests/integration/live/`, covers them.

Live integration tests stay out of scope here — those need `just
jmap-up` and are F4's problem.

**Retained for the record — the original audit-walk targets** (count of
`*`-exported `type`/`proc`/`func`/`template`/`iterator` declarations;
rough order; re-derive with `grep -cE
'^\s*(proc|func|template|type|iterator)\s+\w+\*'`):

- `src/jmap_client/internal/mail/email_submission.nim` — ~50
- `src/jmap_client/internal/types/errors.nim` — ~42
- `src/jmap_client/internal/protocol/methods.nim` — ~36
- `src/jmap_client/internal/mail/mailbox.nim` — ~33
- `src/jmap_client/internal/mail/email.nim` — ~21
- `src/jmap_client/internal/mail/body.nim` — ~15
- `src/jmap_client/internal/client.nim` — 12 exports (`JmapClient`,
  `initJmapClient` ×2 overloads, `newBuilder`, `setCredential`,
  `fetchSession`, `isSessionStale`, `refreshSessionIfStale`, `send`,
  plus the A31 debug-callback surface — `WireDirection`,
  `DebugCallback`, `setDebugCallback` — plus the C5/C8 capability
  helpers once they land)
- `src/jmap_client/internal/transport.nim` — 9 exports
  (`HttpMethodKind`, `HttpRequest`, `HttpResponse`, `SendProc`,
  `CloseProc`, `Transport`, `newTransport`, `newHttpTransport`,
  `send`)

The numbers above do not include re-exports the public hub filters out
— they are raw module-level export counts and overstate the public
surface accordingly. A1c demonstrates the effect: the L2 modules export
their `fromJson` / `toJson` overloads liberally but only the four
envelope `toJson` overloads reach the public surface through
`protocol.nim`.

### F3. Convenience-leak check — bidirectional *(P6)* — ❌ MOOT (S4)

Campaign reconciliation (2026-08-04): moot for the same reason as C7
and C9 — S4 dissolved the P6 quarantine and `convenience.nim` no longer
exists. There is no separate layer left to leak in either direction:
the combinators live in `src/jmap_client/internal/mail/combinators.nim`
on the always-on hub, so L1–L3 docstrings naming one are describing the
public surface, not reaching across a quarantine boundary. H10's
internal-boundary lint covers what is left — nothing outside the tree
may import the module directly.

The original scope, retained for the record: a two-way grep pair over
the quarantine boundary. Forward — no L3 module under
`internal/protocol/` or `internal/mail/` may import
`convenience.nim`. Reverse — no L1–L3 docstring may name a
convenience helper, on P6-as-first-written's rule that "documentation
for the core does not assume the convenience layer".

### F4. Sample CLI smoke test against three servers — CI-wired *(P29)* — ⬜ TODO

Unblocked: C1 and C1.1 are ✅ DONE — `examples/jmap-cli/` and its
`AUDIT.md` exist and the audit findings are triaged. The CI wiring is
the only part outstanding.

Run the C1 CLI end-to-end against Stalwart, Apache James, and
Cyrus IMAP via the existing `just jmap-up` infrastructure. Each
awkward call site discovered is a bug against the API.

Run as a CI job (not a manual step), against at least Stalwart on
each push to main; full three-server matrix (Stalwart + James + Cyrus)
**required green** on every release-tagged PR. The 1.0 release tag
fails if any of the three is red. Read `examples/jmap-cli/AUDIT.md`
for the awkwardness catalogue (C1 + C1.1 deliverable); CI fails if
any item there has status "unresolved" or if the file has fewer than
the canonical three commands.

### F5. Behavioural snapshot tests *(P2)* — ⬜ TODO

Wire-byte fixtures (D3) catch serialisation changes; symbol-set
snapshot (D2) catches export changes; type-shape snapshot (A25)
catches field changes. Behavioural snapshots catch semantic drift in
public *behaviours* the other three miss:

- `RequestBuilder.build()` — call-id ordering, capability dedup,
  default `using` array contents.
- `assembleQueryArgs` / `assembleQueryChangesArgs` — argument
  composition order.
- `directIds` — wrapping behaviour.
- `serdeToMethodError` — closure construction, `extras` packing.
- `validateLimits` — rejection thresholds.

Each becomes a fixture-driven test under `tests/behavioural/`. Any
change to observed output requires explicit review.

### F6. Re-export hub snapshot diff in CI *(P1, P5)* — ✅ DONE

A26 names the snapshot; F6 is the CI step that makes it a gate.

**Implementation.** Rather than regenerate-then-`git diff` (which
relies on the committer having regenerated), the gate is a self-checking
lint: `just lint-public-api` runs the API oracle over
`scripts/api_probe.nim` and hands the live surface to
`tests/lint/h16_public_api_snapshot.nim`, which compares it against the
committed `tests/wire_contract/public-api.txt`
bidirectionally — a removed symbol and an added symbol both fail. On a
mismatch the lint prints the exact `+`/`-` symbol diff and the fix-it
(`just freeze-api`; `[API-CHANGE]` PR label), then exits non-zero. Wired
into both `check` and `ci`. The companion `lint-type-shapes` (H17) gates
A25 the same way; D3 wire fixtures gate with `[WIRE-CHANGE]`.

Because `freeze-api` and `lint-public-api` invoke the same oracle binary
in the same mode, a contributor cannot regenerate a snapshot the lint
would then reject — the two are the same computation.

**Pointers.**
- `tests/lint/h16_public_api_snapshot.nim` — H16 lint (the gate).
- `justfile` — `_api-oracle`, `lint-public-api` / `freeze-api` recipes;
  the two lints wired into `check` and `ci`.

### F7. Coverage-trace consistency check *(P1, P2)* — ⬜ TODO

The Coverage-trace section at the end of this file lists, per
principle, the items addressing it. The trace is hand-maintained
and can drift from the item bodies — overstating or understating
coverage. Without a CI check, it rots.

**Action.** Add `tests/lint/f7_coverage_trace.nim` (or shell script).
Logic:

1. Parse this TODO file's section-by-section content.
2. For each `*(P\d+(?:, P\d+)*)*` annotation in an item body,
   record `(item_id, principle_number)`.
3. Re-derive a coverage trace from the recorded pairs.
4. Compare with the committed Coverage-trace section.
5. CI fails on disagreement.

The same lint also enforces:

- Every principle P1–P29 appears in at least one item.
- Every item has at least one principle annotation.
- Conditional on D18 (deferred 2026-08-04): once
  `pre-1.0-freeze-checklist.md` exists, every freeze-gate item appears
  in it. Until then this check is unwritable and F7 ships without it.

## Section H — CI assertions and lints

The cross-cutting principle that *alignment is upheld by policy + CI,
not by accident*. Items here back the policy items in Sections A and
D with mechanical enforcement.

### H1. Sealed-distinct lint *(P15)* — backs A8 — ✅ DONE

`tests/lint/h1_sealed_distinct_construction.nim` enforces the
sealed Pattern-A invariant: zero public `distinct` type
declarations under `src/`. The seal that binds external consumers
(P15) is the sealed Pattern-A object pattern — a module-private
`rawValue` field — not any form of `distinct` wrapping. The scanner
strips an optional `type ` prefix and matches `Ident* … = distinct`
directly, so it fails on both the single-line `type Foo* = distinct …`
form and an in-`type`-block member line (`Foo* = distinct …`), and
covers generic (`Foo*[T]`) and pragma (`Foo* {.x.}`) forms.
`tests/compile/treject_a8_sealed_external_construction.nim` is
the complementary external-construction reject: it asserts at
compile time that raw `Foo(rawValue: ...)` from outside the
defining module fails with Nim's *"the field 'rawValue' is not
accessible."* diagnostic. The lint and the reject test together
provide the bidirectional gate on the P15 contract.

Wired to `just check` and `just ci` via
`just lint-sealed-distinct`. Source: zero violations under `src/`.

### H1b. Fallible-ctor ∩ public-arm lint *(P15, P16)* — backs A8 / A30b — ✅ DONE

`tests/lint/h1b_fallible_ctor_public_arm.nim` is the sum-type
counterpart to H1: where H1 covers the newtype (`distinct`) surface,
H1b covers public case objects. Per `src/` file it (1) collects every
`T` returned by an exported `func/proc NAME*(...): Result[T, …]`, then
(2) flags any public case-object declaration of such a `T` that
exposes a public arm whose payload is a *raw, externally-constructible*
type — a lowercase builtin (`int` / `string` / `seq[` / `set[` / …) or
a freely-constructible builtin container (`Opt[` / `Table[` /
`JsonNode` / …).

The payload test is the crux: a public arm whose payload is itself a
sealed domain newtype (e.g. `BlueprintHeaderMultiValue`'s
`NonEmptySeq[string]`) cannot be filled with an invariant-violating
value, so it is *not* a hole; only a raw-payload arm — a public
`set[…]` / `string` / `seq[…]` field, the shape that would let a caller
inject an invalid value — is. This is exactly why `SubmissionParam`
(whose `NOTIFY` arm would otherwise be a public `set[DsnNotifyFlag]`)
is sealed rather than transparent. The payload test is what keeps the
predicate from mis-flagging `BlueprintHeaderMultiValue`.

Wired to `just check` and `just ci` via
`just lint-fallible-ctor-public-arm`. Source: zero violations under
`src/` — `SubmissionParam` is sealed and `BlueprintHeaderMultiValue`'s
arms carry sealed payloads.

### H2. Module-level `var` lint *(P10)* — backs D1 no-globals rule — ⬜ TODO

CI test scanning `src/jmap_client/**.nim` for module-level `var`.
Excludes `src/jmap_client.nim` once L5 thread-locals land. Currently
zero violations; locks in P10.

**Implementation path.** `tests/lint/h2_no_module_var.nim`. Wired to
`just lint`. The current "zero violations" state is the test
fixture; any added module-level `var` outside the L5 boundary fails.

### H3. `{.threadvar.}` lint *(P14)* — backs D1, D10 — ⬜ TODO

CI grep-lint forbidding `{.threadvar.}` outside the designated FFI
module (`src/jmap_client.nim` once L5 lands; currently anywhere is
forbidden). Currently zero violations; locks in P14. The
`nim-ffi-boundary` skill must be updated in parallel (D10) so the L5
author isn't pulled toward the OpenSSL anti-pattern by their own
tooling.

**Implementation path.** `tests/lint/h3_no_threadvar.nim`. Wired to
`just lint`.

### H4. Non-JMAP import lint *(P4)* — backs D11, D12 — ⬜ TODO

CI lint rejecting `import std/imap`, `import std/smtp`,
`import std/pop3`, and any obvious non-JMAP-wire library import
under `src/`. Same hook as D12.

**Implementation path.** `tests/lint/h4_no_non_jmap_imports.nim`.
Wired to `just lint`. Allowlist: `std/[json, httpclient, strutils,
tables, hashes, sets, sequtils, sugar, options, times, uri,
nativesockets, net, base64, parseutils, sysrand]`. Anything else
under `src/` requires explicit allowlist entry with rationale.

**`std/sysrand` allowlist note.**
`src/jmap_client/internal/client.nim` imports `std/sysrand` for
the `BuilderId.clientBrand` draw (A6). The failure mode on
unavailable OS entropy is loud failure
(a `ValidationError`); no
`std/monotimes` fallback exists. The H4 allowlist therefore
includes `std/sysrand`.

### H5. Forbidden top-level public proc patterns *(P20)* — backs D7 — ⬜ TODO

CI assertion: no new top-level public proc is added with names
matching forbidden patterns (e.g. `^fetch[A-Z]|^get[A-Z]|^send[A-Z]`)
outside `convenience.nim`. The closed set of public procs on
`JmapClient` is named in D7's prohibitive clause; the closed set of
top-level public procs in `jmap_client.nim` is empty (it is a re-
export hub only).

**Implementation path.** `tests/lint/h5_forbidden_top_level_procs.nim`.
Wired to `just lint`.

### H6. License hygiene *(P25)* — backs D1 — ⬜ TODO

`reuse lint` runs in CI (already in `just ci`). Verify `LICENSES/`
contains only referenced licenses. Audit at freeze time: prune
`Apache-2.0.txt` and `MIT.txt` if not referenced by any
SPDX-License-Identifier in the repo. Add this audit as a pre-1.0 gate.

**Implementation path.** `tests/lint/h6_license_audit.nim` runs at
the freeze gate; `reuse lint` runs continuously. The freeze gate
fails if `LICENSES/` contains entries unreferenced by any
`SPDX-License-Identifier` header in `src/`, `tests/`, or `docs/`.

### H7. Convenience charter lint *(P6, P9)* — backs C7, C9, F3 — ❌ MOOT (S4)

Campaign reconciliation (2026-08-04): moot with the three items it
backs. S4 dissolved the P6 quarantine and `convenience.nim` no longer
exists, so both of the lint's checks target a deleted file. The
combinators are first-class hub surface in
`src/jmap_client/internal/mail/combinators.nim`. The type-allowlist
check is superseded by H16's public-API snapshot, which locks their
signatures — not their docstrings — against un-frozen drift; the
docstring-leak check has nothing left to police, since with no
quarantine an L1–L3 docstring naming a combinator is describing the
same public surface it belongs to.

The original scope, retained for the record: a
`tests/lint/h7_convenience_charter.nim` wired to `just lint`, failing
CI on either of two checks — (1) a `type … * =` declaration in
`convenience.nim` outside the six allowlisted `*GetHandles` /
`*GetResults` bundle types, holding C9's "only procs returning core
types" charter; (2) any mention of a combinator in a module under
`src/jmap_client/internal/`, holding F3's reverse-leak check that
L1–L3 docstrings never name a convenience helper.

### H8. `.get()` invariant comment lint — locks existing project rule — ⬜ TODO

`nim-functional-core.md` (pattern 8, "Invariant-proved `.get()` on
Result", restated in its hard-prohibitions list) already requires
`.get()` on a `Result` to carry an adjacent invariant comment proving
Ok. The convention is unenforced — review-discipline only.

**Implementation path.** `tests/lint/h8_get_invariant.nim`. Wired
to `just lint`. Logic: scan every `.get()` invocation under
`src/jmap_client/`; require an adjacent comment matching
`# invariant:` within the preceding three lines, or a lower-line
`# @invariant:` annotation. Whitelisted patterns: `?` operator
expansion, `valueOr:` block, generated code under `vendor/`. Any
unlabelled `.get()` fails CI with a pointer to the rule.

### H9. Catch-all `else` over finite enum lint *(P18, P20)* — ⬜ TODO

The principles doc's anti-pattern list explicitly forbids
catch-all `else` on `case` statements over finite enums — adding a
variant must force compile errors at every consuming site. Nim's
exhaustiveness checker covers this for sum-type case objects, but
finite-enum `case`s with `else: discard` slip through.

**Implementation path.** `tests/lint/h9_no_catchall_else.nim`.
Wired to `just lint`. Logic: AST-walk every `case` whose discriminator
is an enum type defined under `src/jmap_client/`; flag any `else:
discard` arm. Whitelisted: enums with explicit `*Unknown` catch-all
variants (`MethodName`, `CapabilityKind`, `RequestErrorKind`,
`MethodErrorKind`, `SetErrorKind`) where `else` is the documented
catch-all path; require an inline `# catch-all by design` comment
on the `else:` arm.

### H10. Internal-boundary lint *(P5)* — backs A1 — ✅ DONE

The principles doc's P5 "single public layer" rule must be enforceable
by CI, not by review-discipline. Without a mechanical gate, downstream
or in-repo example code can drift back to importing private
implementation modules and re-couple consumers to internal churn.

**Implementation path.** Both `tests/lint/th10_internal_boundary.nim`
(a runnable Nim program walking the repo) AND `lint-internal-boundary:`
recipe in `justfile`. Wired to `just check`, `just ci`. Logic: scan
every `.nim` file under the repo (excluding `vendor/` and
`.nim-reference/`); fail on any line beginning with `import
jmap_client/internal/` or `from jmap_client/internal/` unless the file
sits under `src/jmap_client/` (the package itself) or `tests/` (which
are permitted to reach private helpers). Error message names the
public hubs and points at A1.

**Current-state assertion.** Zero violations under the current layout.

### H11. Typed-builder JsonNode lint *(P19)* — backs A5 — ✅ DONE

Every exported `add<Entity><Method>*` declaration must be free of
`JsonNode` in its parameter list. The closed allowlist of public
JsonNode-accepting builders is `addEcho` (RFC 8620 §4 Core/echo is
structurally JSON-typed — A22) and `addCapabilityInvocation` (RFC
8620 §2.5 vendor URN escape — A5). `addInvocation` is hub-private
(filtered via `protocol.nim`'s `except` clause) and exempted so the
typed wrappers can route through it internally.

**Implementation path.** `tests/lint/h11_typed_builder_no_jsonnode.nim`
walks `src/jmap_client/internal/{protocol,mail}/` and
`src/jmap_client.nim` (the `mail/` sweep now covers the relocated
pipeline combinators). Wired to `just check`, `just ci`, and the
standalone `just lint-typed-builder-jsonnode` recipe.

**Current-state assertion.** Zero violations.

### H12. Test-backdoor-symbol lint *(P5, P8, P14)* — backs A9 — ✅ DONE

No exported symbol on `src/jmap_client/**` carries a `*ForTest` /
`*ForTesting` / `setSessionFor*` / `lastRaw*` / `last*Response*` /
`last*Request*` naming shape. These naming shapes are the giveaway
for test-only escape hatches on the public surface (A9); the lint
blocks regression mechanically.

**Implementation path.**
`tests/lint/h12_no_test_backdoor_symbols.nim` walks every `.nim`
file under `src/jmap_client/`, extracts each exported symbol name
(`func`, `proc`, `template`, `type`, `iterator`), and fails on any
name matching the forbidden patterns. Wired to `just check`,
`just ci`, and the standalone `just lint-h12-no-test-backdoors`
recipe.

**Allowlist.** None. The naming shapes are sentinel — any new
occurrence on the public surface is a regression.

**Current-state assertion.** Zero violations.

### H13. Module-path lock lint *(P1, P5, P6, P20, P23)* — backs A10 — ✅ DONE

The set of `.nim` files directly under `src/jmap_client/` matches
the closed allowlist committed in
`tests/wire_contract/module-paths.txt` exactly. Bidirectional:
files missing from disk (a path in the snapshot with no backing
file) and files extra on disk (a new public path snuck in without
freezing the snapshot) both fail CI.

**Implementation path.**
`tests/lint/h13_module_path_lock.nim` reads
`tests/wire_contract/module-paths.txt`, walks
`src/jmap_client/*.nim` (plus `src/jmap_client.nim` for the
root), compares as sets, and emits a fix-it pointer
(`just freeze-module-paths`) on divergence. Wired to
`just check`, `just ci`, and the standalone
`just lint-module-paths` recipe.

**Pair.** H10 closes the boundary in the other direction: no
external `import jmap_client/internal/...`. H10 + H13 together
make the public/internal boundary symmetric.

**Current-state assertion.** Zero violations; snapshot lists
exactly one path (`jmap_client`).

### H14. Wire-enum invariant lint *(P1, P19, P20)* — backs A11 — ⬜ TODO

A11's compile-time regression defence
(`tests/compile/tcompile_a11_wire_enum_invariant.nim`) is a
hand-maintained named list: removal of a known catch-all variant
fails CI, but addition of a NEW wire enum without a catch-all
variant is undetected. The comprehensive defence is an AST-walking
lint that proves both invariants over the type graph.

**Implementation path.** `tests/lint/h14_wire_enum_invariant.nim`.
Logic:

1. AST-walk every ``type T* = enum`` declaration under
   ``src/jmap_client/internal/types/`` and
   ``src/jmap_client/internal/mail/``.
2. Detect string-backed enums (any variant uses ``= "literal"``
   syntax).
3. Skip the documented closed-world exemption list (UndoStatus,
   FilterOperator, HeaderForm, BodyValueScope, PlainSortProperty,
   KeywordSortProperty, EmailComparatorKind,
   EmailSubmissionSortProperty, BodyEncoding, DsnRetType,
   DsnNotifyFlag, DeliveryByMode) — sourced from A11's documented
   list, not hardcoded inside the lint.
4. For each remaining string-backed enum, assert presence of a
   catch-all variant (name matches ``*Unknown`` / ``*Other`` /
   ``*Extension``) AND a ``raw…`` field on the carrier type.
5. Carrier-type detection: heuristic match on ``<EnumName>`` ↔
   carrier name (e.g., ``MethodName`` → ``Invocation``,
   ``RequestErrorKind`` → ``RequestError``). Where the heuristic
   fails, require an inline annotation in the enum's docstring
   pointing at the carrier type (a ``# carrier: <TypeName>``
   pragma-style line is sufficient).

Wired to ``just lint``. Failure message names the missing variant
or field and points at A11.

**Pair.** Companions H9 (catch-all ``else`` lint) and the
named-list regression defence in
``tests/compile/tcompile_a11_wire_enum_invariant.nim``.

**Current-state assertion (pre-implementation).** Zero violations
expected: 11 open-world wire enums all comply (see A11's compliance
matrix); 12 closed-world wire enums exempt via A11's documented
list.

### H15. Error-message snapshot lock lint *(P1, P5, P13, P18, P20)* — backs A12 — ✅ DONE

The canonical ``message()`` projection over the 38 representative
error values matches the locked snapshot committed at
``tests/wire_contract/error-messages.txt`` exactly. Bidirectional:
samples missing from the live computation (a label in the snapshot
with no backing producer), samples extra in the live computation
(an emitted label not in the snapshot), and changed projections
(label in both, message differs) all fail CI.

**Implementation path.**
``tests/lint/h15_error_message_snapshot.nim`` reads
``tests/wire_contract/error-messages.txt``, inlines the 38 live
samples in matching declaration order, computes ``message()`` on
each, and emits a fix-it pointer (``just freeze-error-messages``)
on divergence. Wired to ``just check``, ``just ci``, and the
standalone ``just lint-error-messages`` recipe.

**Pair.** Companions H9 (catch-all ``else`` lint, ⬜ TODO) and H14
(wire-enum invariant lint, ⬜ TODO). H15 is the surface-snapshot
analogue of H13 — locking the diagnostic-format contract the way
H13 locks the module-path contract.

**Current-state assertion.** Zero violations; the snapshot enumerates
exactly 38 samples spanning every variant of every error type.

## Coverage trace — every principle to at least one item

Every principle has at least one TODO item that, if executed, brings
the codebase into alignment. Every row also names the **verification
gate** locking the alignment in (CI lint, snapshot, property test,
or existence file). F7 (Coverage-trace consistency check) will
verify this section against the item bodies on every CI run once
it lands; until then the principle annotations are maintained by
hand.

Status legend:

- **🟢 Verified** — item shipped AND verification gate runs.
- **🟡 Planned** — item listed; gate named; not yet implemented.
- **🔴 Open** — choice not yet made; freeze-blocking.

| Principle | Items | Gate | Status |
|---|---|---|---|
| P1 (lock contract) | A1, A1b, A2, A2b, A4, A6, A10, A11, A12, A13, A16, A25, A25b, A26, D1, D1.5, D2, D4, D5, D17, D18, F6, F7, H14, H15 | API snapshot diff (F6/H16, D2); H13 lint (A10b); module-paths.txt snapshot (A10a); H15 lint (A12); error-messages.txt snapshot (A12); freeze checklist (D18) deferred 2026-08-04 | 🟡 |
| P2 (tests) | A25, A28b, D2, D3, F1, F5 | Property tests (F1); wire-byte fixtures (D3) | 🟡 |
| P3 (overloads not `_v2`) | C2, C3, D1.5 (no-suffix rule) | H5 lint; review | 🟡 |
| P4 (scope) | D11, D11.5, D12, H4 | H4 non-JMAP-import lint | 🟡 |
| P5 (single layer) | A1, A1b, A1c, A1d, A6, A9, A10, A12, A14, A16, A19, A30, F2, F6 | H5; H10; H12; F6 snapshot; H13 lint (A10b); module-paths.txt snapshot (A10a); A1c + A1d compile audits | 🟡 |
| P6 (easy path first-class; core stands without it) | A10, C7, C9, C10, F3, D16, H7 | H13 lint (A10b); module-paths.txt snapshot (A10a); H10 internal-boundary lint (the charter lint H7 is moot — S4 dissolved the quarantine) | 🟢 |
| P7 (wrap rate) | A12, A16, A31, B5, C1, C1.1, C2–C5, C8, F4 | F4 CLI smoke test | 🟡 |
| P8 (opaque handles) | A6, A6.5, A6.6, A7b, A9, A13, A16, A19, A27, A28, A28b, A30 | F2 audit; H1; H12 | 🟡 |
| P9 (two contexts max) | A6.5, A6.6, A7, A7b, B9, C9, D10 | B9 resolution (H7 moot — S4 dissolved the convenience layer) | 🟡 (B9 resolved; D10 closed) |
| P10 (no globals) | D1.5 (no-globals rule), H2 | H2 lint | 🟡 |
| P11 (no global callbacks) | A19 (closure-vtable per-handle), A31 (per-handle debug callback), D1.5 (no-callbacks rule), D10 | review; future L5 callback lint | 🟡 |
| P12 (memory ownership in types) | A13, A19, B10 | review | 🟡 |
| P13 (one error rail) | A6, A12 | H8 `.get()` invariant lint; H15 snapshot lint (A12) | 🟡 |
| P14 (no thread-local errors) | A9 (no `last*` state on handle), A19 (`HttpResponse` returned by value, not stashed on Transport), D10, H3, H12 | H3 lint; H12 lint | 🟡 |
| P15 (smart constructors) | A8 (sealed Pattern-A objects across every public value-carrying type + `IdOrCreationRef` + 3 internal), A12 (library-internal error constructors filtered off the hub), A15 (sealed `SerializedSort` / `SerializedFilter`; no JsonNode-keyed argument-construction shims on the public surface; `directIds` is the sole helper), A19 (`newTransport`, `newHttpTransport` Result-returning), A30 (Pattern-A `Request` and `Response` with `initX` / `parseX` smart constructors), A30b (whole envelope surface demoted off the hub; `Referencable`, `SubmissionParam` + `NotifySet`, and `NonEmptyRcptList` sealed; closed-A8 enumeration), H1, H1b | testament reject tests `treject_a8_sealed_external_construction.nim` + `treject_submissionparam_notify_construction.nim`; A12 compile audits; A1b compile audit `doAssert not declared(initCreates)` lock; A30 envelope-demotion compile audits; H1 + H1b lints (regression prevention) | 🟢 |
| P16 (preconditions in types) | A6, A6.5, A6.6, A7b, A7c, A7d, A29, B3, B4, B6, B12 | H9; A7c testament `action: reject` test; B11 dropped (premise invalid — RFC 8621 §4.2 makes `bodyValues` the default, so the phantom split it proposed is unsound) | 🟡 (only B6 lower-severity findings open) |
| P17 (one config surface) | A14, A19 (HTTP config on `newHttpTransport` only), A20, A21 | review; F6 snapshot; sealed `SessionEndpoint`/`Credential` (A20/A21); `treject_a20`/`treject_a21` reject audits | 🟡 |
| P18 (sum types over flag soup) | A6, A12, B1, B2, B6, B7, B8, H9 | H9 catch-all lint; A12 exhaustive `case` in `SetError.message` / `TransportError.message` / mail extractors | 🟡 |
| P19 (schema-driven types) | A2, A2b, A3, A3.5, A4, A5, A14, A15, A16, A17, A18, A21, A22, A22b, A28, A28b, A30, H14 | H11 typed-builder lint (A5); A22b inline docstrings; F1; A1b compile audit (A30 negative for raw construction) | 🟡 |
| P20 (additive variants) | A10, A11, A12, A23, A24, D7, D13, D13.5, H5, H14 | H5 lint; H13 lint (A10b); module-paths.txt snapshot (A10a); H15 lint (A12); error-messages.txt snapshot (A12) | 🟡 |
| P21 (lifecycle types) | A6, A6.5, A6.6, A7, A7b, A7c, A7d, A23, A24, A27, A28 | type-shape snapshot (A25); A7c testament `action: reject` test | 🟡 |
| P22 (sync first, async via interface) | A6, A7e, A19, E1 | A7e policy entry; F6 snapshot blocks pre-1.0 export of reserved names | 🟡 |
| P23 (push as separate type) | A7e, A10, A23, A24, D13.5 | existence gate (A7e in D13.5 file; A23, A24 type files); H13 lint (A10b); module-paths.txt snapshot (A10a) | 🟡 |
| P24 (threading invariant) | A6, A13, A19 (closure-vtable threading invariant in `Transport` and `JmapClient` docstrings), D8 | D8 docstring footer; review | 🟡 |
| P25 (license) | D1.5, H6 | `reuse lint`; H6 freeze gate | 🟡 |
| P26 (build) | current `mise.toml`/`justfile`/`.nimble`; D1.5 documents the single `when defined(ssl)` concession in `internal/client.nim` | review | 🟡 |
| P27 (architecture docs) | D7, D9, D16 | existence gates (D9 deferred 2026-08-04; D16 moot — S4) | 🟡 (D7 open) |
| P28 (long-form docs) | A12, D9, D10, D14 | existence gates (D9 deferred 2026-08-04) | 🟡 |
| P29 (sample consumer) | C1, C1.1, F4 | F4 CI smoke + AUDIT.md | 🟡 |

### Anti-pattern lockout matrix

Every explicit anti-pattern in `docs/design/14-Nim-API-Principles.md`
(end of "Anti-patterns explicitly forbidden") has a CI-mechanical
lockout. Review-only locks are **forbidden** — anti-patterns
must fail CI, not depend on reviewer attention.

| Anti-pattern | TODO items | CI gate |
|---|---|---|
| Global mutable state | D1.5 (no-globals rule), H2 | H2 lint |
| Global callbacks | D1.5 (no-callbacks rule), D10 | future L5 callback lint |
| Two-channel configuration | A14, A20, A21 | F6 snapshot diff (catches future drift); sealed `SessionEndpoint`/`Credential`; `treject_a20`/`treject_a21` |
| Stringly-typed APIs | A2, A2b, A3, A3.5, A4, A5, A8 (closes the disguise by sealing the underlying `rawValue` field), A14, A15, A17, A18, A20, A21, A22b | H11 typed-builder lint; A8 testament reject test; reviewer grep on `JsonNode` outside Documented exceptions |
| Multiple coexisting public layers | A1, A1b, A1c, A1d, A9, A10, A16, A30 | H13 lint (A10b); module-paths.txt snapshot (A10a); F6 snapshot (A26); A1c + A1d compile audits |
| Easy path leaking into the core | C10, D16 (moot — S4 dissolved the quarantine) | H10 internal-boundary lint; H16 public-API snapshot |
| Catch-all `else` on finite enums | A11, A12, H9 | H9 lint; A12 exhaustive `case` in `SetError.message` / `TransportError.message` / 5 `mail_errors.nim` extractors |
| Wire-enum catch-all + raw missing | A11, H14 | named-list compile-time test (A11); AST lint (H14) |
| `.get()` without invariant | (rule) + H8 | H8 lint |
| Last-error thread-locals | D10, H3 | H3 lint |
| Behaviour changes in patch releases | D1.5 (policy) | wire-byte fixture diff (D3) |
| Renaming after 1.0 | D1.5 (policy), H5 | F6 snapshot diff; H5 lint |
| Test backdoors / last-operation state on public handle | A9, A13, A19, H12 | H12 lint |

### Concrete-decisions checklist

The principles doc's "Concrete decisions to make before 1.0" list
contains 10 items. Each must be either delivered by a TODO item
**and** have a verification gate. Row status is carried by the
per-item markers above until D18's freeze-checklist file lands, at
which point the 1.0 release tag fails on any unticked row.

| # | Decision | Item | Gate |
|---|---|---|---|
| 1 | Choose the public layer | A1, A1b, A6, A10 | F6 snapshot; H13 (A10b); module-paths.txt (A10a) |
| 2 | Public symbol audit | A1, A6, F2 | F6 snapshot |
| 3 | Lock the wire contract | F1, A2b, A28b, D3 | property tests + fixture diff |
| 4 | Name the Push channel type | A23, D13.5 | existence gate |
| 5 | Threading invariant | D8 | docstring footer audit |
| 6 | Sample consumer | C1, C1.1, F4 | CI smoke + AUDIT.md |
| 7 | Long-form guide | D9 | existence gate |
| 8 | License confirmation | H6 | `reuse lint`; freeze audit |
| 9 | L5 FFI design note | D10 | existence gate |
| 10 | Easy-path charter | C10 | H10 internal-boundary lint; H16 public-API snapshot; module-paths.txt (A10a) |
