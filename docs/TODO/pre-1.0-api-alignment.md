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

The pre-1.0 freeze checklist that tracks gate status per item lives
at `docs/TODO/pre-1.0-freeze-checklist.md` (D18). The 1.0 release
build fails if any gate row is unchecked.

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
- **🟦 DEFERRED** — explicitly deferred to a post-1.0 release.
- **❌ DROPPED** — superseded or rejected; the body explains why.
- **RESOLVED** — a design-decision item rather than an
  implementation task; the body records the decision reached.
- **(FREEZE-BLOCKING)** — appended where the gap blocks the 1.0
  tag.

Where an item has no marker, treat it as ⬜ TODO until verified.

## Status dashboard

This dashboard is regenerated mechanically from the per-item status
markers below. Re-derive the counts with
`grep -c "— ✅ DONE" docs/TODO/pre-1.0-api-alignment.md` (and the
sibling marker forms). F7 (Coverage-trace consistency check) will
be the freeze-time gate that mechanically catches dashboard drift;
until it lands, the counts are maintained by hand.

| Status | Count | What it means |
|---|---|---|
| ✅ DONE | 34 | Implemented and verified against source / tests. |
| 🟡 PARTIAL | 14 | Some parts implemented; gaps named in the item body. |
| ⬜ TODO | 60 | Not yet implemented. |
| 🟦 DEFERRED | 1 | Explicitly deferred to a post-1.0 release (E1). |
| ❌ DROPPED | 1 | Superseded or rejected (D15). |
| **RESOLVED** | 1 | Design decision made (A3.5). |

**Freeze-blocking gaps** (must close before 1.0 tag): B9, B11, B12,
C1, C1.1, plus the four ⬜ TODO surfaces that change observable
behaviour (A17, A20, A21, A26). The outstanding lint backstops
(H2–H9 plus H14) can ship in the same window or shortly after;
H1, H10–H13, and H15 are already in place. The freeze checklist
(D18) tracks per-item gate status.

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
- **`*.rawData` and `*.extras` `JsonNode` fields** for unknown
  server extensions. Three sites:
  - `ServerCapability.rawData` — unknown capability payloads.
  - `MethodError.extras` — non-standard server fields.
  - `SetError.extras` — non-standard server fields.

  These exist for forward compatibility (Postel's law: lenient on
  receive). Future RFCs that lift fields out of `extras` go through
  capability negotiation (D7). Inline docstrings at each declaration
  cite this exception (A22b).

Any new public `JsonNode` field, parameter, or return type added
after 1.0 is a P19 violation unless it falls under one of the four
patterns above. Reviewers can grep for `JsonNode` under `src/` to
spot new occurrences; the typed-builder family is additionally
guarded by the H11 lint.

## Section A — Must FREEZE before 1.0

These items become unfixable after 1.0 ships. Anything load-bearing on
the public surface (exported types, fields, function signatures, module
paths) cannot be retracted in 1.x without a major bump.

### A1. Headline public layer + demoted alternatives *(P5, P7)* — ✅ DONE

L3 builder + dispatch is the headline API. The closed public-path
set is exactly two paths: root (`import jmap_client`) and
`jmap_client/convenience` (P6 quarantine; opt-in, NOT re-exported
by the root). All other modules — types, serialisation, protocol,
transport, client, mail entities, `PushChannel` /
`WebSocketChannel` reservation types — live under
`jmap_client/internal/` and reach consumers exclusively through
the root re-export. A10 locks this layout; H13 (A10b) enforces it.

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
- `dispatch.nim` — handle types `ResponseHandle`, `NameBoundHandle`,
  `CompoundHandles`, `CompoundResults`, `ChainedHandles`,
  `ChainedResults`; extraction `callId`, `get`, `getBoth`; reference
  construction `reference` (the sole back-reference primitive);
  registration `registerCompoundMethod`, `registerChainableMethod`;
  operators `==`, `$`, `hash`. Module-private (no `*` qualifier):
  `serdeToMethodError`.
- `builder.nim` — `RequestBuilder`, `initRequestBuilder`,
  `methodCallCount`, `isEmpty`, `capabilities`, `build`, `addEcho`,
  `addGet`, `addChanges`, `addSet`, `addCopy`, `addQuery`,
  `addQueryChanges`, `directIds`, `initCreates`. Hub-private (`*`
  retained for `mail_methods.nim` cross-internal callers, filtered
  via `except`): `addInvocation` (the typed `add*` family is the
  user surface; `addInvocation` would re-introduce the P19
  stringly-typed escape hatch). A typed `BuiltRequest` wrapper
  around `Request` is deferred to A7.

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
sites inside `internal/protocol/dispatch.nim`). By the time an
application developer inspects an error, every L2 type has been
collapsed into a string message inside `TransportError`. The same
P19 logic applies to envelope `fromJson` — typed envelope parsing
is library plumbing, never application code.

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
- `serde_envelope_emit.nim` (user-facing via `protocol.nim`)
  carries `Invocation.toJson`, `Request.toJson`, `Response.toJson`,
  `ResultReference.toJson` — diagnostic emission per P19's
  "Diagnostic emission (`Request.toJson`, `Response.toJson`) is
  fine".
- `serde_envelope_parse.nim` (hub-private) carries the matching
  `fromJson` overloads plus the internal `referencableKey` and
  `fromJsonField` helpers. P19's "the reverse direction is not"
  applies: typed envelope parsing has no application-code path.
- `serde_envelope.nim` is an L2-internal aggregator that imports
  both halves and re-exports them so existing in-tree callers
  (`client.nim`, `classify.nim`, `dispatch.nim`, `methods.nim`)
  reach the full envelope ser/de via a single import path.

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

**Re-export from the protocol hub.** `internal/protocol.nim` is
the sole module that surfaces L2 to user scope, and only the
emit half: `export serde_envelope_emit`. `Invocation.toJson`,
`Request.toJson`, `Response.toJson`, `ResultReference.toJson`
flow through. Nothing else does.

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
`MaxChanges` and `UriTemplate` ser/de, the envelope parse-half
overloads, and the field-echo and framework helpers.
The `when declared` check is **not** applied to
`toValidationError`: the name is also a public L1 helper
(`validation.nim` for `TokenViolation`, `session.nim` for
`UriTemplateViolation`, `primitives.nim` for `DateViolation`,
`collation.nim` for `CollationViolation`), and the L1 overload
is legitimately surfaced. The L2 overload over `SerdeViolation`
is hub-private; absence of the other L2 symbols is the
indirect proof.

**Pattern relationship to A1b.** A1b's `protocol.nim` mixes
user-facing and internal symbols, so it uses `export module
except sym, …` to filter per symbol. A1c's L2 modules have no
user-facing symbols beyond the four envelope `toJson` overloads
emitted from `serde_envelope_emit`; the hub aggregator is
absent rather than filtered, and the user-facing surface
re-exports through `protocol.nim` instead.

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
   `reference(handle, name, path)` — non-`mixin`, dragging no
   registration scaffolding into the caller's scope. Common chains
   are expressed through the per-entity wrappers in `convenience.nim`
   and the per-entity compound builders; no generic `mixin`-based
   reference helper is public.

`tests/compile/tcompile_a1d_mail_hub_surface.nim` pins this surface
— positive `doAssert declared` for the entity records, typed
builders, and convenience wrappers; negative `when compiles` /
`when declared` probes for the entity-registration overloads and
mail serde — mirroring A1b/A1c. `tcompile_mail_f_public_surface.nim`
and `tcompile_mail_g_public_surface.nim` cover specific RFC-feature
slices; A1d covers the mail hub as a whole.

### A2. Privatise `Invocation.arguments*` *(P19, P5, P8, P25)* — ✅ DONE

`src/jmap_client/internal/types/envelope.nim` (`Invocation.arguments` field). Mirrors the
already-private `rawName` / `rawMethodCallId` siblings: the
`arguments` field is module-private, with a `func arguments*(inv:
Invocation): JsonNode` accessor exported from envelope.nim for
internal consumers (`internal/serialisation/serde_envelope.nim`,
`internal/protocol/dispatch.nim`, `internal/protocol/builder.nim`).
The hub re-export (`src/jmap_client/internal/types.nim`) excludes the
accessor via `export envelope except arguments`, so application
developers doing `import jmap_client` cannot reach raw JsonNode
args; typed accessors (`name`, `methodCallId`, `toJson`) are the
only public surface. No JsonNode-shaped mutation API exists on
`Invocation`: replay flows through `parseInvocation` from captured
wire bytes, construction flows through `RequestBuilder`. A
`withArguments` setter would re-introduce the libdbus stringly-
typed back door (P19). The seal is verified in both directions by
`tests/compile/tcompile_a2_invocation_hub_surface.nim` (sealed from
`import jmap_client`) and
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
  `u.len` at instantiation via `mixin len`. Post-condition:
  `rg 'inv\.arguments' src/` matches only
  `internal/serialisation/serde_envelope.nim` (L2 wire boundary)
  and `internal/protocol/dispatch.nim` (L3 typed-decoding boundary).

The two `validateLimits*` overloads in `client.nim` are asymmetric
by design: `validateLimits(builder, caps)` performs full pre-flight
(max-calls + per-call /get + per-call /set);
`validateLimits(request, caps)` (the lower-level escape hatch used
by raw-`Request` senders) enforces only `maxCallsInRequest`. The
asymmetry is the visible cost of refusing to walk wire shape for
type-derivable information; both docstrings state it explicitly.
`send(client, builder)` routes through the builder-aware overload;
`send(client, request)` routes through the narrow overload.

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
- Full-record receive only. Sparse-property `/get` responses
  (consumer-requested elision of required fields) have no public
  application-API path until A3.6 ships `PartialT` types — they
  surface `MethodError(metServerFail)` on the public typed entry
  point because `T.fromJson` is full-record strict. A2's seal on
  `Invocation.arguments` is preserved; `internal/` access stays
  library-internal-only.

Related items: A3.6 (partial-entity types for sparse `/get`),
A4 + A3.5 (`updateResults` typing + decision), A29
(`parseGetResponse[T]` coherence invariant), F1 (property test
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
  per-entity wrappers and `convenience.nim` reach them via direct
  internal import, but are filtered from `protocol.nim`'s
  `export builder except …` clause — `import jmap_client` does not
  see them.

- Per-IETF-method, the user-facing surface is a typed wrapper:
  `addMailboxGet`, `addMailboxChanges`, `addMailboxQuery`,
  `addMailboxQueryChanges`, `addMailboxSet`; `addEmailGet`,
  `addEmailGetByRef`, `addPartialEmailGet`, `addPartialEmailGetByRef`,
  `addEmailChanges`, `addEmailQuery`, `addEmailQueryChanges`,
  `addEmailSet`, `addEmailCopy`, `addEmailCopyAndDestroy`,
  `addEmailParse`, `addEmailImport`; `addThreadGet`,
  `addThreadGetByRef`, `addThreadChanges`; `addEmailSubmissionGet`,
  `addEmailSubmissionChanges`, `addEmailSubmissionQuery`,
  `addEmailSubmissionQueryChanges`, `addEmailSubmissionSet`,
  `addEmailSubmissionAndEmailSet`; `addVacationResponseGet`,
  `addVacationResponseSet`; `addSearchSnippetGet`,
  `addSearchSnippetGetByRef`. Entity-specific extension keys are
  typed parameters (e.g. `EmailBodyFetchOptions` on `addEmailGet` /
  `addPartialEmailGet` / `addEmailParse`).

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
`src/jmap_client/internal/{protocol,mail}/`, `src/jmap_client.nim`,
and `src/jmap_client/convenience.nim`; CI fails on any exported
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
surfaces as `jcvEntropyUnavailable` `ValidationError`) plus
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

### A7. Lifecycle types *(P21, P16, P22, P23)* — 🟡 PARTIAL

Sync chain is in place: `RequestBuilder` → `BuiltRequest` →
`DispatchedResponse`, with `BuiltRequest` uncopyable (`=copy` and
`=dup` are `{.error.}`) and `send` consuming via `sink`. Remaining
gaps tracked in A7d (structural escalation of `RequestBuilder` to
uncopyable) and A7e (async surface name reservation).

The synchronous dispatch chain is the entire 1.0 lifecycle: each
phase is a distinct sealed type and transitions are functions
returning the next type.

`RequestBuilder` (immutable value-accumulator) → `BuiltRequest`
(frozen, branded, dispatch-ready) → `DispatchedResponse` (received,
branded, handle-extractable).

Three types, three phase invariants, two transitions (`freeze` /
`send`). Both transitions consume their input (`sink`), so any
post-transition use of the predecessor is a compile error: a
builder feeds exactly one `freeze`, a `BuiltRequest` feeds exactly
one `send`. Wire-data carriers `Request` and `Response` sit off
the dispatch chain — they belong to the fixture/replay path (A28),
not the live dispatch path.

A6 carries the `BuilderId` brand through every transition so
cross-builder / cross-client misuse fails at handle extraction with
`gekHandleMismatch`. The brand is the type-level encoding of
"handle was issued by this dispatch's builder" (P16). The
`sink`-on-`freeze` and `sink`-on-`send` signatures (A7c, A7d) close
the residual brand-aliasing hazard the runtime check could not
detect: two `BuiltRequest`s from one builder or two
`DispatchedResponse`s from one `BuiltRequest` would share a
`BuilderId`, and a single handle set would validate against either.

Umbrella sub-items:

- **A6.5** seals `BuiltRequest` and `DispatchedResponse` (done).
- **A7b** wires `freeze` and `send` (done).
- **A7c** consumes `BuiltRequest` on `send` via `sink` (done).
- **A7d** puts the advisory `sink RequestBuilder` on `freeze`
  (done); escalating `RequestBuilder` to structurally uncopyable
  is the outstanding part (partial).
- **A7e** is the other outstanding tightening: the async-surface
  name reservation in the RFC-extension policy.

The asynchronous chain extends the same `BuiltRequest` additively
once async lands; that contract is named in A7e, never stubbed
onto the sync surface (P23: async is a different type with a
different lifecycle, not a flag on the existing one).

**Pointers.**
- `src/jmap_client/internal/protocol/builder.nim:47, 60, 139` —
  `RequestBuilder`, `BuiltRequest`, `freeze` (`sink RequestBuilder`).
- `src/jmap_client/internal/protocol/dispatch.nim:237` —
  `DispatchedResponse`.
- `src/jmap_client/internal/client.nim` `send` — `send(sink BuiltRequest)`.
- `tests/compile/tcompile_a7c_send_consumes_builtrequest.nim` —
  compile-reject anchor for double-`send`.
- `tests/compile/tcompile_a7d_freeze_consumes_builder.nim` —
  compile-reject anchor for double-`freeze` and post-freeze
  accumulation.

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
`RFC5321Keyword`, `OrcptAddrType` (`mail/submission_atoms.nim`);
`RFC5321Mailbox` (`mail/submission_mailbox.nim`); `HoldForSeconds`,
`MtPriority` (`mail/submission_param.nim`); `ReplyCode`,
`SubjectCode`, `DetailCode` (`mail/submission_status.nim`).

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
`SubmissionExtensionMap` (`mail/mail_capabilities.nim`).

**Generic sealed type** — `NonEmptySeq[T]` (`primitives.nim`),
plus the standalone `head*[T]` accessor and `asSeq*[T]`
borrow-projection consumed by `defineSealedNonEmptySeqOps`.

**Case-object sealing** — every public discriminated union with a
construction invariant has its discriminator and arm payloads
private to its defining module: `IdOrCreationRef`
(`mail/email_submission.nim`) exposes `kind*`, `asDirectRef*`,
`asCreationRef*` accessors plus `directRef` / `creationRef` smart
constructors; `MailboxRole` (`mail/mailbox.nim`),
`ContentDisposition` (`mail/body.nim`), `CollationAlgorithm`
(`internal/types/collation.nim`), `Comparator`, `AddedItem`
(`framework.nim`), and `Thread`, `PartialThread` (`mail/thread.nim`)
are likewise sealed.

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

**Transparent ADTs intentionally not sealed** — variant types whose
payloads ARE the data and carry no construction invariant:
`SubmissionParam` (12 variants, each carrying its own validated
payload type), `SubmissionParamKey`, `JsonPathElement`,
`BodyPartLocation`, `EmailBodyPart`, `SerdeViolation`, `Filter[C]`,
every `*Update` case object, `HeaderValue`,
`BlueprintHeaderMultiValue`. P15 applies where a smart constructor
enforces an invariant the raw constructor would bypass; these
unions have no such invariant.

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
operational surface: `initJmapClient`, `discoverJmapClient`,
`newBuilder`, `setBearerToken`, `fetchSession`, `isSessionStale`,
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
- **Limit enforcement** — `validateLimits*` is module-private
  inside `client.nim`; its sole caller is `send`, and tests drive
  limit checks through `client.send()` against a canned-session
  Transport.
- **Bearer token** — `setBearerToken` is a write-only mutator; the
  token is read per-call when the client builds each request's
  `Authorization` header. No `bearerToken` getter exists.

**Verification gate.** `tests/lint/h12_no_test_backdoor_symbols.nim`
(H12) — a mechanical lint, run in `just ci`, fails on any exported
symbol under `src/jmap_client/**` matching the forbidden naming
shapes. Zero violations.

### A10. Module-path lock *(P1, P5, P6, P20, P23)* — ✅ DONE

Module paths are part of the contract: every importable path under
`jmap_client/...` is a public commitment the moment 1.0 ships. The
closed set is the SQLite/libcurl minimum-surface model: one headline
entry plus one explicit P6 quarantine.

**Closed set of public module paths.** Two paths total. The
filesystem-derived snapshot at
`tests/wire_contract/module-paths.txt` is the contract; the H13
lint (A10b) verifies snapshot vs filesystem bidirectionally on
every CI run.

```
jmap_client                  — the headline API (everything)
jmap_client/convenience      — opt-in convenience (P6 quarantine)
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

**Source locations.**

- `RefPath.rpUnknown` sits at ordinal 0 in
  `src/jmap_client/internal/types/methods_enum.nim`; `parseRefPath`
  in the same module mirrors `parseMethodName`. `ResultReference.path`
  in `src/jmap_client/internal/types/envelope.nim` delegates to
  `parseRefPath(rr.rawPath)`. Both wire emission
  (`internal/serialisation/serde_envelope_emit.nim`) and wire parsing
  (`internal/serialisation/serde_envelope_parse.nim`) route through
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
`tests/wire_contract/error-messages.txt` (32 representative
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

### A15. Demote remaining JsonNode-typed escape hatches *(P19)* — 🟡 PARTIAL

**Done.** `SerializedSort` / `SerializedFilter` in
`src/jmap_client/internal/protocol/methods.nim` are sealed
Pattern-A objects (A8). `serializeOptSort[S]`,
`serializeOptFilter[C]`, `serializeFilter[C]` retain their
pre-serialisation semantics and are the only producers; external
`SerializedSort(...)` / `SerializedFilter(...)` field-init from
outside `methods.nim` fails to compile via the `rawValue`-private
mechanism that binds A8. The three serialize helpers are
hub-private (filtered via `except` in `internal/protocol.nim`).

**Remaining gap — `initCreates`.**
`src/jmap_client/internal/protocol/builder.nim` exposes
`initCreates*` returning `Opt[Table[CreationId, JsonNode]]`. The
typed `addSet[T, C, U, R]` already takes
`Opt[Table[CreationId, C]]`; `initCreates` is the JsonNode-typed
parallel path. It reaches consumers via `import jmap_client`
through the protocol hub (not filtered by the current `except`
clause). Demote to internal or remove pre-1.0.

**Documented exception — `addEcho(args: JsonNode)`.** Echo is the
RFC-mandated input-echoes-output method; documented as an
exception in the "Documented exceptions to the principles" section
of this doc.

### A16. `Response.toJson` publicness *(P19, P1)* — 🟡 PARTIAL

`Response.toJson` lives at
`src/jmap_client/internal/serialisation/serde_envelope.nim:122`
and is publicly reachable via `import jmap_client` (testing
convenience today).

**Remaining gap.** Lock with deterministic key-order spec (the
wire-byte contract D3 covers it). Document `Response.toJson` as
canonical-form emission OR demote to internal/test-only until the
wire-contract suite covers it. The lock is freeze-blocking
because once 1.0 ships, the emission byte order becomes a public
commitment.

### A17. `AccountCapabilityEntry.data: JsonNode` *(P19)* — ⬜ TODO

`src/jmap_client/internal/types/session.nim:21–26` —
`AccountCapabilityEntry` is a flat object with `data*: JsonNode`.
The inline comment acknowledges that this *"may evolve to a case
object when typed account-level capabilities are added (e.g. RFC
8621)."* RFC 8621 is implemented, so this is the largest
JsonNode-typed escape on the public surface that has a typed
schema available.

**Destination shape.** Case object on `CapabilityKind` with
typed arms `ckMail`, `ckSubmission`, `ckVacationResponse`,
`ckBlob`, `ckQuota`, `ckSieve`, plus `else: rawData*: JsonNode`
for unknown. Smart constructor `parseAccountCapabilityEntry`.
The flat `AccountCapabilityEntry` becomes sealed with private
discriminator. Mirrors `ServerCapability` (capabilities.nim) per
A18.

### A18. `ServerCapability` typed arms *(P19)* — 🟡 PARTIAL

`src/jmap_client/internal/types/capabilities.nim:54–62` —
`ServerCapability` is a case object with one typed arm
(`ckCore: core*: CoreCapabilities`) and `else: rawData*: JsonNode`
for every other variant. The standard RFC 8621 capabilities
(`ckMail`, `ckSubmission`, `ckVacationResponse`, `ckBlob`,
`ckQuota`, `ckSieve`) have typed schemas defined elsewhere in the
codebase but fall through to `rawData` here.

**Remaining gap.** Add explicit case-object arms for the six
standard capabilities; preserve `rawData` for unknown only.

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

**Two-overload constructor surface** (P3 additive):

- `initJmapClient(transport, sessionUrl, bearerToken, authScheme)`
  — primary; application developer supplies the transport.
- `initJmapClient(sessionUrl, bearerToken, authScheme)` —
  convenience; delegates to `newHttpTransport()`.
- `discoverJmapClient(transport, domain, bearerToken, authScheme)`
  / `discoverJmapClient(domain, bearerToken, authScheme)` — same
  pair for the `.well-known/jmap` URL-construction convenience.

**C-FFI alignment.** The closure-vtable shape projects directly to
a single C function-pointer-plus-userdata pair at L5. Future C
consumers bring their own HTTP library via callback (the libcurl
`CURLOPT_WRITEFUNCTION` / SQLite-VFS model). See D10's forward
pointer.

### A20. Collapse session entry points *(P17)* — ⬜ TODO

`src/jmap_client/internal/client.nim:176–241` exposes four
overloads for the same concept (the session URL):

1. `initJmapClient(transport, sessionUrl, bearerToken, authScheme)`
2. `initJmapClient(sessionUrl, bearerToken, authScheme)` (uses
   default `newHttpTransport()`)
3. `discoverJmapClient(transport, domain, bearerToken, authScheme)`
4. `discoverJmapClient(domain, bearerToken, authScheme)`

Discovery domain `"example.com"` and a precomputed
`"https://example.com/.well-known/jmap"` reach the session URL
via two parsers — exactly what P17 forbids.

**Action.** Collapse to one constructor with a `SessionEndpoint` sum:

```nim
type SessionEndpointKind* = enum
  sekDiscoveryDomain
  sekDirectUrl

type SessionEndpoint* = object
  case kind*: SessionEndpointKind
  of sekDiscoveryDomain: domain*: string
  of sekDirectUrl: url*: string

func discoveryEndpoint*(domain: string): Result[SessionEndpoint, ValidationError]
func directEndpoint*(url: string): Result[SessionEndpoint, ValidationError]

proc initJmapClient*(endpoint: SessionEndpoint, bearerToken: string,
                     ...): Result[JmapClient, ClientError]
```

`discoverJmapClient` does not exist after this change; its
behaviour is reached via
`initJmapClient(discoveryEndpoint("example.com").get(), ...)`.

### A21. Type the auth scheme *(P17, P19)* — ⬜ TODO

`src/jmap_client/internal/client.nim:60, 180, 208, 222, 236` —
`authScheme: string = "Bearer"` is a stringly-typed enum-shaped
surface. Anti-pattern by P19; potential P17 drift if a second
source ever sets it. No `AuthScheme` enum exists; no
`parseAuthScheme()` smart constructor exists.

**Action.** Replace with:

```nim
type AuthScheme* = enum
  asBearer = "Bearer"
  asBasic = "Basic"
  # extend additively per RFC

func parseAuthScheme*(raw: string): Result[AuthScheme, ValidationError]
  ## Lenient: preserves raw scheme for forward-compat (Postel's law).
  ## Unknown schemes round-trip via a future `asUnknown` arm + raw field
  ## once a third scheme appears; today the closed set is exhaustive.
```

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
in the same section. A22b's docstring footer is the remaining
work on this surface.

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

### A25. Type-shape snapshot in CI *(P1, P2)* — ⬜ TODO

D2's `public-api.txt` snapshot catches symbol-set drift but not
field-set drift. A `Request` whose `using*: seq[string]` field is
silently changed to `seq[CapabilityUri]` would break consumers; D2
would not flag it.

`tests/wire_contract/` currently contains only
`module-paths.txt` (A10a) and `tsnapshot_well_formed.nim` (the
testament-anchor). `type-shapes.txt` does not exist yet.

**Action.** Add `tests/wire_contract/type-shapes.txt`. Generated
from `nim doc --project` output (or a custom scraper) — every
public type's full field signature, with type names. CI diffs the
file; any field-shape change requires explicit "TYPE BREAK"
label in the PR. The mechanical generator is tracked separately
as A25b.

### A26. Re-export hub snapshot *(P1)* — ⬜ TODO

The `export` clause set of every re-export hub is a public
commitment once 1.0 ships. Adding/removing a re-exported symbol
changes the import graph users observe.

There is one curated public re-export hub:
`src/jmap_client.nim`. The mail leaves' `*` surfaces are already
covered by `tcompile_mail_f_public_surface.nim` and
`tcompile_mail_g_public_surface.nim`; they are re-exported
transitively from root through `internal/mail.nim`.

**Action.** Snapshot the root's `export` clauses to
`tests/wire_contract/public-api.txt` (or equivalent). CI diffs
the snapshot on every PR; any add/remove requires an explicit
`[API-CHANGE]` label. F6 names the CI-wiring side of the same
gate.

### A27. Seal the handle types *(P8)* — ✅ DONE

All handle types are sealed Pattern-A objects with private `raw*`
fields and explicit accessors:
`ResponseHandle[T]`, `NameBoundHandle[T]`, `CompoundHandles[A, B]`,
`ChainedHandles[A, B]`, plus `DispatchedResponse` (the sealed
wrapper that pairs the wire `Response` with a `BuilderId`). The
two single-call handles additionally carry a `rawParseProc:
ParseProc[T]` field — the captured resolver bound at handle
construction time (A6, A1c).

**Pointer.** `src/jmap_client/internal/protocol/dispatch.nim`.

### A28. `Request` and `Response` opacity decision *(P8, P19)* — ✅ DONE

`Request` and `Response` are pure wire-data carriers. Dispatch
metadata lives on sealed wrappers: `BuiltRequest` on the request
side, `DispatchedResponse` on the response side. SQLite-style
opacity (compiled dispatch artifact vs row data); libcurl-style
ownership (easy handle vs response bytes).

**Pointers.**
- `src/jmap_client/internal/protocol/builder.nim` —
  `BuiltRequest` sealed; `request` / `builderId` / `callLimits`
  accessors hub-private.
- `src/jmap_client/internal/protocol/dispatch.nim` —
  `DispatchedResponse` sealed; `response` / `builderId`
  hub-private; `sessionState` / `createdIds` hub-public.

### A29. `parseGetResponse[T]` smart constructor *(P16)* — ⬜ TODO

`internal/protocol/methods.nim` `GetResponse[T]` permits
structurally `list ∩ notFound ≠ ∅` — a server bug could put the
same id in both, and the type allows it. P16 says encode
preconditions in types. No `parseGetResponse` smart constructor
exists today.

**Action.** Add `parseGetResponse[T]` smart constructor enforcing
`list ∩ notFound = ∅`. Lenient on receive: log + drop the
duplicate on the `notFound` side, or reject as a `MethodError`.
Document the choice.

### A2b. Property test: `Invocation` round-trip *(P19, P2)* — 🟡 PARTIAL

`tests/property/tprop_envelope.nim:90–97` covers
`propInvocationPreservesFields` — partial field-preservation
property. Missing:

- `parseInvocation(toJson(inv)) == ok(inv)` for every method-name
  variant, including `mnUnknown` with a synthesised raw name.
- `Request.toJson` and `Response.toJson` produce identical bytes
  when called twice on equivalent inputs (canonical-form
  determinism).

**Action.** Extend `tprop_envelope.nim` (or add
`tprop_invocation_roundtrip.nim`) covering the two missing
properties; wire to `just test-wire-contract` (F1). A28b tracks
the determinism slice specifically.

### A3.5. Decide `SetResponse[T].updateResults` payload shape *(P19)* — **RESOLVED**

Resolved by A4 D2 — `updateResults` carries typed `Opt[U]`, with
`U` the per-entity `PartialT`. No semver-upgrade path is required:
the `PartialT` family is part of A4's surface.

### A3.6. Partial-entity types for sparse `/get` responses *(P5, P7, P19)* — 🟡 PARTIAL

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
(A4), so every `/set` echo path is `PartialT`-typed even where no
typed `/get` wrapper exists.

**Public sparse-`/get` surface.** Email only. Two wrappers —
`addPartialEmailGet` and `addPartialEmailGetByRef` — carry the
typed `EmailBodyFetchOptions` parameter and route through the
hub-private `addGet[PartialEmail]`. For Mailbox, Identity, Thread,
EmailSubmission, VacationResponse the typed builders for full-record
`/get` exist (`addMailboxGet`, …) but their `PartialT` siblings
(`addPartialMailboxGet`, …) do not — A5 made the generic
`addGet[PartialT]` hub-private, so consumers of `import jmap_client`
have no public typed path to sparse `/get` for those five entities.

**Left to do.**

- Decision (freeze-blocking if "ship the wrappers"): either land
  per-entity Partial-`/get` wrappers for the remaining five entities
  (`addPartialMailboxGet`, `addPartialIdentityGet`,
  `addPartialThreadGet`, `addPartialEmailSubmissionGet`,
  `addPartialVacationResponseGet`) parallel to their full-record
  siblings, OR record an explicit pre-1.0 decision to ship Email-
  only sparse `/get` and document the rationale (sparse `/get`
  matters most where records are large; the other five entities are
  small enough that full `/get` suffices). Whichever path is taken,
  the typed-`updateResults` rail (A4) is unaffected — the `PartialT`
  family is already in place there.

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
`docs/policy/03-rfc-extension-policy.md` (A7e), not by stub. Its
shape depends on the `Transport` interface and lands once async
arrives as additive surface (P20).

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

### A7b. Refactor lifecycle: `RequestBuilder.freeze()` and `JmapClient.send(BuiltRequest)` *(P21, P16)* — ✅ DONE

`RequestBuilder.freeze() → BuiltRequest` produces the frozen,
branded carrier. `JmapClient.send(BuiltRequest) →
JmapResult[DispatchedResponse]` is the sole blessed send path —
neither raw `Request` nor unfrozen `RequestBuilder` is accepted.
Future async-path overload (A19 + E1) extends the chain
additively per A7e.

**Pointers.**
- `src/jmap_client/internal/protocol/builder.nim:139` — `freeze`.
- `src/jmap_client/internal/protocol/builder.nim:60` —
  `BuiltRequest`.
- `src/jmap_client/internal/client.nim` `send` — `send(BuiltRequest)`;
  `validateLimits` (`client.nim`) operates on `BuiltRequest`.

### A7c. Consume `BuiltRequest` on `send` *(P16, P21)* — ✅ DONE

`src/jmap_client/internal/client.nim` — `proc send*(client: var JmapClient,
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
`callLimits`) take `lent BuiltRequest`, so an accessor read does
not trigger the copy machinery; the same applies to
`validateLimits(req: lent BuiltRequest, …)`, which `send` invokes
once before consuming `req`.

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

### A7d. Consume `RequestBuilder` on `freeze` *(P16, P21)* — 🟡 PARTIAL (advisory `sink` only; uncopyable hook deferred)

`src/jmap_client/internal/protocol/builder.nim` — `func freeze*(b:
sink RequestBuilder): BuiltRequest`. The `sink` qualifier is
**advisory only**: the standard Nim sink semantics insert a silent
copy at a non-last use rather than failing. To upgrade `sink` to a
structural single-use contract, `RequestBuilder` would need
`=copy` + `=dup` `{.error.}` hooks (the A7c mechanism).

The hook upgrade is deferred because:

- The full builder chain runs at module top-level in every
  `block <name>:` integration and protocol test (~80 sites). Nim
  2.2.x's move analysis at module top-level treats the implicit
  `=destroy` at module exit as a non-last "read", so even a single
  `b.freeze()` after `let b = …` fails compilation with the
  *"requires a copy because it's not the last read"* diagnostic.
  Wrapping each test body in `tests/mtestblock.testCase` works for
  `BuiltRequest`-binding sites (the A7c path) but cascades into
  pre-existing latent issues (`Uninit`, `UnusedImport` warnings
  surfacing under proc-wrap that were silent at module top-level)
  in many of the 80 affected files.
- `Result[(RequestBuilder, …), ValidationError]` returns
  (`addCapabilityInvocation`, `addEmailSubmissionAndEmailSet`) cannot
  be unwrapped via `.get()` for uncopyable `T`. nim-results' `value`
  proc body assigns `result = self.vResultPrivate` (a copy);
  callers would have to switch to `unsafeValue` after explicit
  `isOk` checks.

Every `add*` function that takes a builder still consumes via
`sink`: the 10 builders in `protocol/builder.nim`
(`addInvocation`, `addEcho`, `addRawInvocation`,
`addCapabilityInvocation`, `addGet`, `addChanges`, `addSet`,
`addCopy`, `addQuery`, `addQueryChanges`) and the 35 mail-domain
builders across
`internal/mail/{mail_builders,mail_methods,submission_builders,identity_builders}.nim`
plus the eight `convenience.nim` per-entity wrappers. Template
aliases (`addChanges[T]`, `addQuery[T]`, `addQueryChanges[T]`,
`addSet[T]`, `addCopy[T]`) carry the advisory contract
through to the underlying procs. A second `freeze` or
post-`freeze` `add*` on the same builder will silently copy
(advisory only) — the brand-alias hazard is documented but not
type-enforced.

Builder bodies thread the brand through tuple returns via a
`let brand = newBuilder.builderId` binding before the return
expression, so upgrading the type to uncopyable is a localised
type-level change (add the `=copy` + `=dup` hooks) once the
test-suite friction above is addressed. No `clone(b:
RequestBuilder)` helper is needed: zero dual-derivation patterns
exist that would motivate one.

**Compile-reject anchors.** None present. The reject tests
`tests/compile/treject_a7d_freeze_consumes_builder.nim` and
`tests/compile/treject_a7d_post_freeze_add.nim` are intentionally
absent until the uncopyable-hook escalation lands; both must
exist before the gate flips to ✅.

### A7e. Async surface name reservation *(P20, P22, P23)* — ⬜ TODO

The asynchronous chain extends the sync chain additively:

`RequestBuilder` → `BuiltRequest` → `DispatchedRequest` (in-flight
token) → `DispatchedResponse` (received).

`DispatchedRequest` and its companion procedure `sendAsync` are
reserved by policy, not by type stub. Their shapes depend on the
`Transport` interface (A19); committing a stub before A19 fixes
the transport contract is the libdbus failure P23 cites — retrofit
a shape that does not fit the runtime. Reservation suffices
because no public API claims either name pre-1.0, so adding them
once async lands is purely additive (P20). Unlike `PushChannel`
(A23) and
`WebSocketChannel` (A24), `DispatchedRequest` has no consumer-
facing calling site on the sync path; an `unimplemented()` stub
would have no caller and serve no diagnostic purpose.

**Action.** Add to `docs/policy/03-rfc-extension-policy.md`
(D13.5):

> **Async dispatch (lands with A19 + E1).** The async overload is
> a separate procedure `sendAsync` — never an overload of `send`,
> never a runtime flag (P22). Signature: `proc sendAsync(client:
> var JmapClient, req: sink BuiltRequest):
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

### A22b. Inline docstrings at every JsonNode-public field declaration *(P19)* — ⬜ TODO

The "Documented exceptions" sub-section at the top of this file
records the justified `JsonNode` patterns. A22b makes the
exception visible at the declaration site so reviewers reading
the type don't need to consult this TODO.

**Action.** At each declaration, add a docstring footer citing
the exception:

- `internal/types/capabilities.nim` — `ServerCapability.rawData`:
  `## P19 exception: forward-compatibility for unknown capabilities`.
- `internal/types/errors.nim` — `MethodError.extras`,
  `SetError.extras`: same footer.
- `internal/types/session.nim` — `AccountCapabilityEntry.data`:
  same footer (until A17 lands; remove footer when A17
  case-objects the field).
- `internal/protocol/builder.nim` — `addEcho(args: JsonNode)`:
  `## P19 exception: RFC 8620 §4 Core/echo is structurally JSON-typed`.
- `internal/mail/mailbox.nim` — `MailboxRights` field block:
  `## P18 exception (Decision B6): RFC 8621 §2.4 mandates 9 independent ACL flags`.

CI lint H7 (Section H) verifies that any other public `JsonNode`
field appearing in `src/` carries the same exception footer or
fails the build.

### A25b. Generate the type-shape snapshot mechanically *(P1)* — ⬜ TODO

A25 specifies the snapshot file (`tests/wire_contract/type-shapes.txt`)
but does not specify the producer. A hand-maintained file rots fast.
No `just freeze-type-shapes` recipe exists yet.

**Action.** Add a `just freeze-type-shapes` recipe that produces
the file from `nim doc --project src/jmap_client.nim` JSON output
(or a small custom AST scraper). Output format: one type per
section, alphabetical by name, each field on its own line with
its typed annotation. CI fails if the regenerated file disagrees
with the committed copy and the PR is not labelled
`[TYPE-SHAPE-CHANGE]`.

### A28b. Wire-byte determinism property test for `Request` and `Response` *(P2, P19)* — ⬜ TODO

A28 leaves `Request` and `Response` as wire-data carriers with
public fields. The compensating promise is wire-byte determinism:
`Request.toJson(req)` produces the same bytes every time for the
same input. Without a property test, this promise is unenforced.
No `tests/property/twire_determinism.nim` exists today.

**Action.** Add `tests/property/twire_determinism.nim` covering:

- `Request.toJson` is canonical-form: key order is
  `using`, `methodCalls`, `createdIds` (alphabetical or
  RFC-mandated).
- `Response.toJson` is canonical-form: same treatment.
- 100 random inputs; identical bytes across two calls; identical
  bytes after a `parseRequest(toJson(req))` round-trip.

Wire to `just test-wire-contract` (F1).

## Section B — Type-safety hardening

Mostly frozen-by-shipping too, but the gaps are correctness/illegal-
state issues rather than wire/surface decisions.

### B1. `Account.isPersonal` + `isReadOnly` → 4-state enum *(P18)* — ⬜ TODO

`src/jmap_client/internal/types/session.nim:32–33`. Two independent Bools encoding
four legal combinations. Replace with
`enum AccountPolicy { apOwned, apOwnedReadOnly, apShared, apSharedReadOnly }`.

### B2. Sort-direction unification *(P18)* — ⬜ TODO

Three sites currently use ad-hoc Bool / Opt[bool] for sort direction:

- `src/jmap_client/internal/mail/email.nim:65, 76, 88` —
  `EmailComparator.isAscending: Opt[bool]` (three-state via Opt adds
  "absent" to true/false)
- `src/jmap_client/internal/types/framework.nim:64` — `Comparator.isAscending: bool`
  (two-state)
- `src/jmap_client/internal/mail/email_submission.nim:358` —
  `EmailSubmissionComparator.isAscending: bool` (two-state)

Replace all three with
`enum SortDirection { sdServerDefault, sdAscending, sdDescending }`.
Three sites total — the inconsistency between them is itself a smell.

### B3. `Filter[foNot]` arity + `foAnd|foOr` non-empty *(P16)* — ⬜ TODO

`src/jmap_client/internal/types/framework.nim:39–46`. RFC 8620 §5.5 says `foNot` MUST
have exactly one child. The type currently allows
`Filter(kind: fkOperator, operator: foNot, conditions: @[])` and
`…, conditions: @[a, b])`. Encode as a separate inner discriminator:

```nim
case operator: FilterOperator
of foNot: child: Filter[C]
of foAnd, foOr: conditions: NonEmptySeq[Filter[C]]
```

**RFC cross-check.** RFC 8620 §5.5 literal text: "FilterOperator is
defined as a list of one or more `FilterOperator` or `FilterCondition`
values." So the arity for `foAnd|foOr` is `>=1` (`NonEmptySeq`), not
`>=2`. The `foNot` arity (exactly one) stays. If `>=2` is desired as
a consumer-friendly tightening, document the choice in the type
docstring with rationale.

### B4. `VacationResponse` window invariant *(P16)* — ⬜ TODO

`src/jmap_client/internal/mail/vacation.nim:18–26`. `fromDate: Opt[UTCDate]`
and `toDate: Opt[UTCDate]` independent. `Opt.some(from) &&
Opt.some(to) && from > to` is structurally allowed but RFC-forbidden.
Smart-construct via `parseVacationResponse: Result`, or hold a single
typed `Opt[VacationWindow] = (UTCDate, UTCDate)` whose constructor
enforces the order.

### B5. `registerExtractableEntity(T)` compile-check — ⬜ TODO

Mirror `registerSettableEntity` (`src/jmap_client/internal/protocol/entity.nim`)
which already compile-checks `T.toJson` for /set entities. Add a
template that compile-checks `T.fromJson(JsonNode):
Result[T, SerdeViolation]` is in scope. Without it, `dispatch.get[T]`
fails at instantiation, not registration — the error sites are
distant and unhelpful.

### B6. Other illegal-state findings (lower severity) — ⬜ TODO

- `Account` (`internal/types/session.nim`): `isReadOnly: true` and
  `accountCapabilities` carrying a write-implying capability can
  coexist. Phantom on `Account[ReadOnly]`/`Account[ReadWrite]` or a
  smart constructor.

### B7. `mail_filters.nim` Opt[bool] → three-state enums *(P18)* — ⬜ TODO

`src/jmap_client/internal/mail/mail_filters.nim:32, 33, 91` — three-state
`Opt[bool]` filter fields. Each becomes a named three-state enum:

```nim
type HasAnyRoleFilter* = enum hrfRequireAny, hrfRequireNone, hrfNoConstraint
type SubscriptionFilter* = enum sfSubscribed, sfNotSubscribed, sfNoConstraint
type HasAttachmentFilter* = enum hafYes, hafNo, hafNoConstraint
```

`hasAnyRole: Opt[bool]` → `hasAnyRole: HasAnyRoleFilter`;
`isSubscribed: Opt[bool]` → `isSubscribed: SubscriptionFilter`;
`hasAttachment: Opt[bool]` → `hasAttachment: HasAttachmentFilter`.

Default value for each is `*NoConstraint` so the default behaviour is
unchanged.

### B8. `Identity.mayDelete` → enum *(P18)* — ⬜ TODO

`src/jmap_client/internal/mail/identity.nim:53` and
`src/jmap_client/internal/mail/mail_entities.nim:118` `mayDelete: Opt[bool]` —
three-state via Opt encodes "Stalwart omits the field". Replace with:

```nim
type DeleteAuthority* = enum daYes, daNo, daUnreported
```

Document the Stalwart workaround in the type docstring.

### B9. Consolidate the handle-pair zoo *(P9)* — ⬜ TODO (FREEZE-BLOCKING)

`internal/protocol/dispatch.nim` (`CompoundHandles`, `ChainedHandles`) — `CompoundHandles[A, B]`,
`CompoundResults[A, B]`, `ChainedHandles[A, B]`, `ChainedResults[A, B]`
are four context types serving the single concept "a typed reference
into a response, paired". P9's "two context types per concept" cap is
breached.

**Resolution choice.**

- **(a)** Merge `CompoundHandles` and `ChainedHandles` into a single
  `HandlePair[A, B]` with a `kind: HandlePairKind` tag; same for
  `Results`. Caller-side ergonomics shift slightly.
- **(b)** Demote two of the four (e.g. `Chained*`) as private; expose
  the other two only.

**Resolution (freeze gate).** This decision is freeze-blocking — the
four-type zoo cannot ship in 1.0. Pick the option whose call-site
cost is lower at the API surface that the headline layer exposes.
Default recommendation: **(b)**, demote `Chained*` as
internal — the principle of "one concept, one type" outweighs minor
caller flexibility. Lock the choice in a B9 sub-section with the
rationale before tagging 1.0. If (a) is picked instead, record the
`HandlePairKind` enum in `tests/wire_contract/type-shapes.txt` (A25).

### B10. `lent` annotation pass on handle accessors *(P12)* — ⬜ TODO

P12 says ownership in the type. Today every accessor that returns a
container deep-copies on each call. Annotate:

- `JmapClient.session*` — `lent Session`
- `Session.accounts*`, `primaryAccounts*`, `capabilities*` — `lent T`
- `RequestBuilder.capabilities*` — `lent seq[CapabilityUri]`
- `UriTemplate.parts*`, `variables*` — `lent T`

Cross-cutting pattern: any handle accessor whose return value is a
container (`Table`, `seq`, `HashSet`) gets `lent`. Verify ownership
contracts are documented for each.

### B11. `Email[Lite | Hydrated]` phantom decision *(P16)* — ⬜ TODO (FREEZE-BLOCKING)

`Email.bodyValues: Table[PartId, EmailBodyValue]` is populated only
when a `bodyStructure` is requested. The combination "bodyValues
populated + bodyStructure absent" is structurally allowed but server-
incoherent.

**Resolution choice.**

- **(a)** Phantom-typed states `Email[Lite]` (no body fetched),
  `Email[Hydrated]` (body fetched). `addEmailGet` returns the right
  variant based on properties requested.
- **(b)** Smart constructor `parseEmail` enforces
  `bodyValues.len > 0 ⇒ bodyStructure.isSome`. Reject the incoherent
  state.

**Resolution (freeze gate).** Default recommendation: **(b)**, smart
constructor — phantom-typed `Email[State]` propagates through every
API consuming an `Email`, multiplying the surface for marginal
benefit (the incoherent state arises only from server bugs). The
smart constructor approach concentrates the check at the parse
boundary. Lock the choice; document the parse-time rejection
behaviour (`MethodError` vs lenient drop) in the B11 body before
tagging 1.0.

### B12. `Account[ReadOnly | ReadWrite]` decision *(P16)* — ⬜ TODO (FREEZE-BLOCKING)

`src/jmap_client/internal/types/session.nim:32`. The B6 sub-bullet
flags that `Account.isReadOnly: true` and `accountCapabilities`
carrying a write-implying capability can coexist — structurally
allowed but RFC-incoherent. The same shape of P16 violation as
B11.

**Resolution choice.**

- **(a)** Phantom-typed states `Account[ReadOnly]` /
  `Account[ReadWrite]`. `Session.accounts` returns `seq[Account[…]]`
  via a sum type; consumers branch on the discriminator.
- **(b)** Smart constructor `parseAccount` rejects accounts whose
  `isReadOnly` flag contradicts their declared capabilities.
  Lenient on receive: log + clear the contradicting capability.

**Resolution (freeze gate).** Default recommendation: **(b)**, same
rationale as B11 — smart constructor concentrates the check at the
parse boundary without propagating phantoms through downstream
APIs. Pair with B1 (the `AccountPolicy` 4-state enum) so that the
same parse pass produces both the discriminator and the
contradiction check.

## Section C — Consumer ergonomics

Pre-1.0 quality bar. Each missing item is a day-one wrapper trigger.

### C1. Sample CLI consumer — pre-1.0 freeze gate *(P29)* — ⬜ TODO (FREEZE-BLOCKING)

P29 verbatim: "Before 1.0 lands, write a non-trivial sample app …
treat its painful spots as bugs against the API, not against the
user." This is a hard pre-1.0 freeze gate, not a 1.x feature.

No `examples/`, `samples/`, or `jmap-cli` exists. The closest existing
"how do I start" is `tests/integration/live/tcore_echo_live.nim`,
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


The four-parameter generic `addSet[T, C, U, R]` is hub-private (A5;
filtered via `protocol.nim`'s `export builder except …` clause).
Public callers see only per-entity wrappers — `addEmailSet`,
`addMailboxSet`, `addEmailSubmissionSet`,
`addEmailSubmissionAndEmailSet`, `addVacationResponseSet` — each
taking `(b, accountId, ifInState?, create?, update?, destroy?)` with
typed creation models, typed update sets, and no `extras=`
parameter.

### C3. `byIds` per-entity helpers *(P7)* — 🟡 PARTIAL

`src/jmap_client/internal/protocol/builder.nim:394` already provides `directIds` to
shave `Opt.some(direct(@[…]))` nesting. Extend per-entity:
`addEmailGet(b, accountId, byIds = @[id1, id2])`. UFCS chains read
materially better.

### C4. `MailboxRights` summary helpers *(P7)* — ⬜ TODO

`src/jmap_client/internal/mail/mailbox.nim:213–224`. Nine independent ACL
booleans (Decision B6 documented exception, correctly modelled). Add
roll-up helpers: `mb.canMutate(): bool`, `mb.canRead(): bool`,
`mb.canDelete(): bool`. Otherwise consumers chain
`mb.myRights.mayAddItems and mb.myRights.mayRemoveItems and …`.

### C5. Capability discovery convenience *(P7)* — ⬜ TODO

Currently `client.session().get().coreCapabilities()` chain is
correct but undocumented. Add helpers:
`client.supportsMail(): bool`, `client.coreCapabilities(): Opt[…]`,
`client.requireMail(): JmapResult[void]`. Pre-flight "does this
server support Mail?" should be one line.

### C6. Version surface *(P25, P28)* — ⬜ TODO

`src/jmap_client/internal/transport.nim` carries
`userAgent: string = "jmap-client-nim/0.1.0"` as the default
HTTP `User-Agent` for the default transport. That is the only
version literal under `src/`. C-library convention (curl,
OpenSSL) exposes `client_version()` for bug reports. Add:

```nim
const ClientVersion* = "0.1.0"  # synced with .nimble
func clientVersion*(): string = ClientVersion
```

### C7. Charter clause on `convenience.nim` *(P6)* — 🟡 PARTIAL

Add to `convenience.nim`'s top docstring:

> This module contains pipeline combinators (multi-method `add*`
> chains and paired `getBoth` extraction). It does NOT contain
> semantic convenience like `fetchInbox`, `archiveEmail`, `markRead`.
> Such helpers belong in user code. The zlib `gz_*` precedent shows
> what happens when convenience layers grow semantic helpers — the
> edge cases bleed back into the user's image of the core. P6 forbids
> this.

CI grep enforces (F3 + F3b).

### C1.1. Scaffold `examples/jmap-cli/` directory *(P29)* — ⬜ TODO (FREEZE-BLOCKING)

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

### C8. Capability pre-flight one-liner *(P7)* — ⬜ TODO

C5 lists capability discovery helpers but underspecifies the
one-liner. The headline call site is "does this server support
JMAP Mail?" — currently
`client.session().get().coreCapabilities()` then walk a set.
Day-one wrapper trigger.

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

### C9. Charter clause: convenience.nim exports no new public types *(P6, P9)* — 🟡 PARTIAL

C7 covers the docstring; this item adds the structural restriction.
`convenience.nim`'s public surface is the pipeline-combinator procs
plus the paired handle/result bundle types those combinators
return — `QueryGetHandles[T]` and its siblings. It introduces no
entity or semantic type; those belong in core (L3) or user code.

**Action.** Document in the `convenience.nim` top docstring; back
mechanically with H7 lint (added in Section H). The lint scans
`convenience.nim` for `type … * =` declarations and admits exactly
the paired handle/result bundle types the combinators return —
`QueryGetHandles[T]`, `ChangesGetHandles[T]`,
`MailboxChangesGetHandles`, `QueryGetResults[T]`,
`ChangesGetResults[T]`, `MailboxChangesGetResults` — failing CI on
any further `type … * =`. The bundle types are the documented
exception: a combinator returning a pair of typed handles needs a
pair type to name (C10).

### C10. `convenience.nim` internal-access cleanup *(P5, P6)* — ✅ DONE

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

**Verification gate.** `grep -n "internal" src/jmap_client/convenience.nim`
returns zero matches.

## Section D — Process / policy artefacts

### D1. SemVer + deprecation + wire-byte contract policy *(P1, P2, P3, P10, P11, P25)* — ⬜ TODO

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

### D2. `public-api.txt` snapshot diffed in CI *(P1, P2)* — ⬜ TODO

P2 is "stability bought with tests"; no current test asserts the
exported symbol list. Add `just freeze-api` that regenerates a
`public-api.txt` from `nim doc --project` output (or a custom scraper
over `*` patterns). CI diffs the file; any new `*` symbol requires
explicit acknowledgement in the PR description.

### D3. Wire-byte fixture contract elevation *(P2)* — 🟡 PARTIAL

224 captured payloads exist under `tests/testdata/captured/` across
three servers (Stalwart, Apache James, Cyrus IMAP). Elevate from
"regression aid" to "frozen contract":

- Every `.json` is a wire shape the library promises to deserialise
  forever.
- Add a `tests/wire_contract/` category whose only failure mode is
  "we changed serialisation in a way that breaks fixture replay".
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

### D5. `.nimble` contract *(P1, P25)* — 🟡 PARTIAL

Document in `docs/policy/01-semver-and-deprecation.md` that
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

**Prohibitive clause (explicit, not implicit).** It is a 2.0 break to
add any of:

- a new public proc on `JmapClient` whose name does not begin with
  `send`, `close`, `setBearerToken`, or `fetchSession`;
- a new public top-level proc in `jmap_client.nim`;
- a new public module path under `src/jmap_client/` that is not
  nested under an entity directory.

Without this written down, the next contributor adds
`proc fetchCalendars(client: JmapClient)` and the door is open.
Backed by lint H5.

### D8. Threading invariants — class-wide rule *(P24)* — 🟡 PARTIAL

`src/jmap_client/internal/client.nim:34` already documents
"not thread-safe" for `JmapClient`. Replace per-type invariants with
a class-wide rule applied to every public type:

- **L1–L3 types as a class** (everything under
  `src/jmap_client/{validation,primitives,identifiers,collation,
  capabilities,methods_enum,session,envelope,framework,methods,
  errors,builder,dispatch,entity}.nim` and the `mail/` siblings): "value
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
  implementation; will be specified when the implementations land."

Apply to every public type via a one-line docstring footer (or the
type's full docstring if longer). One mass edit, not 25 individual
decisions.

### D9. Long-form guide *(P28)* — ⬜ TODO

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

### D10. L5 FFI design note *(P9, P14, future-FFI)* — ⬜ TODO

Write `docs/design/16-L5-FFI-Principles.md` mapping each principle to
its C-ABI manifestation:

A12 shipped the stable `kind` discriminator and the bounded
diagnostic projection per error type — both prerequisites for the
`CURLOPT_ERRORBUFFER`-style FFI surface this doc describes.


- Opaque handles via `distinct pointer` types.
- **Errors via per-handle error buffer (libcurl `CURLOPT_ERRORBUFFER`
  model), NOT thread-local last-error globals.** Thread-local
  `int jmap_last_error()` is forbidden — that is the OpenSSL anti-
  pattern P14 cites by name. Update the `nim-ffi-boundary` skill
  content to remove the `{.threadvar.}` pattern as the default; per-
  handle is canonical.
- One `Client*` + transient `RequestBuilder*` only — no
  `EmailGetCtx*`/`MailboxQueryCtx*` proliferation (P9).
- Variadic-style options via tagged `JmapOption` enum, not
  per-method-name procs (P20 in C ABI).
- Initialisation: `jmap_init()` / `jmap_cleanup()` with no
  thread-local setup ritual (P10).
- Cite A6's `BuilderId` phantom-token strategy as the C-ABI-level
  analogue (cookie/handle); the C ABI mints opaque builder ids that
  the library validates on use.
- Per-handle callbacks (P11): future logging/progress/auth-refresh
  callbacks land as fields on `JmapClient`, paired with a `pointer`
  userdata that the library threads back unchanged. Never a
  `jmap_register_logger()` top-level proc.
- **HTTP backend via callback (libcurl model).** A19's
  `Transport` is a per-handle closure-vtable (`SendProc` +
  `CloseProc`); the C ABI exposes `jmap_init_transport(send_fn,
  close_fn, userdata, ...)` mirroring this shape directly. The C
  consumer brings its own HTTP library via callback (libcurl-style
  integration is a first-class use case). The `=destroy` hook on
  Nim's `TransportObj` corresponds to a C-ABI `jmap_client_free`
  that invokes the user's `close_fn` on the last reference.

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

### D13. RFC extension policy *(P20)* — ⬜ TODO

Write `docs/policy/03-rfc-extension-policy.md`. For each
unimplemented RFC, write the planned shape so the names are reserved
(but not the implementations):

- **RFC 8887 — JMAP over WebSocket.** `CapabilityKind`: `ckWebsocket`
  (already exists). Type: `WebSocketChannel` (A24). Path:
  `jmap_client/websocket`.
- **RFC 8620 §6 — Push.** `CapabilityKind`: future `ckPush`. Type:
  `PushChannel` (A23). Path: `jmap_client/push`.
- **RFC 8620 §6.5 — Blob upload/download.** Will extend `JmapClient`
  with `uploadBlob`/`downloadBlob` methods (additive on the existing
  handle, *not* a separate context type). Document the rationale
  before 1.0.
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
§4.3 (two-level railway composition) and
`docs/design/00-architecture.md` §lifecycle. A standalone design
doc would duplicate those without adding constraint information.

### D16. Convenience module design note *(P27)* — ⬜ TODO

Verify `convenience.nim` has a design note (in `docs/design/` or as a
comprehensive module docstring at minimum). If not, write one, citing
P6 as the constraint. The doc covers what the module is for (pipeline
combinators), what it explicitly is NOT for (semantic convenience —
see C7 charter), and how new helpers are vetted.

### D1.5. Commit `docs/policy/01-semver-and-deprecation.md` *(P1, P2, P25, P26)* — ⬜ TODO

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
   verifies). Currently two paths: `jmap_client` (root) and
   `jmap_client/convenience` (P6 quarantine). Adding a new
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

### D13.5. Commit `docs/policy/03-rfc-extension-policy.md` *(P20)* — ⬜ TODO

D13 enumerates the RFC reservations; this item commits them as a
tracked file.

**Action.** Write the policy file. Existence-gate: the file must
exist before 1.0 tag. The file contains the per-RFC table from
D13 (RFC 8887 WebSocket, RFC 8620 §6 Push, §6.5 Blob, RFC 9007
MDN, RFC 8624 Contacts, future Calendars). Each row names:
capability variant, reserved type name, reserved module path,
implementation status (deferred). The lock is: post-1.0,
implementing any of these requires landing the table-row's named
type at the table-row's named path; deviation is a 2.0 break.

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

### D18. Pre-1.0 freeze checklist tracker *(P1)* — ⬜ TODO

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
- **Decision gates** — open choices that must be resolved (A3.5,
  B9, B11, B12, D4 devendor).
- **Test gates** — property tests that must exist (F1, A2b,
  A28b); diagnostic-format snapshot (A12 / H15) already in place.

CI gate (`just check-freeze` or `.github/workflows/release.yml`):
the 1.0 release tag fails if any `[ ]` row remains. The
checklist file is regenerable from this TODO; F7's consistency
check covers both files.

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
- Session: `Session`, `Account`, `AccountCapabilityEntry` (after A17),
  `UriTemplate`, `ServerCapability` (after A18), `CoreCapabilities`
- Errors: `MethodError`, `SetError`, `RequestError`, `TransportError`,
  `ClientError`, `ValidationError`
- Methods: every `GetResponse[T]`, `SetResponse[T]`, `ChangesResponse`,
  `QueryResponse`, `CopyResponse`, `QueryChangesResponse`
- Mail: `Email`, `Mailbox`, `Thread`, `Identity`, `EmailSubmission`,
  `VacationResponse`, `SearchSnippet`, `EmailBlueprint`, `EmailUpdate`,
  `MailboxFilterCondition`, `EmailFilterCondition`,
  `SubmissionFilterCondition`, all body / header types

### F2. Public-symbol audit walk *(P5)* — ⬜ TODO

High-export files to scrutinise (count of `*`-exported
`type`/`proc`/`func`/`template`/`iterator` declarations; rough
order; re-derive at audit time with `grep -cE '^\s*(proc|func|template|type|iterator)\s+\w+\*'`):

- `src/jmap_client/internal/mail/email_submission.nim` — ~50
- `src/jmap_client/internal/types/errors.nim` — ~42
- `src/jmap_client/internal/protocol/methods.nim` — ~36
- `src/jmap_client/internal/mail/mailbox.nim` — ~33
- `src/jmap_client/internal/mail/email.nim` — ~21
- `src/jmap_client/internal/mail/body.nim` — ~15
- `src/jmap_client/internal/client.nim` — 11 exports (`JmapClient`,
  `initJmapClient` ×2 overloads, `discoverJmapClient` ×2 overloads,
  `newBuilder`, `setBearerToken`, `fetchSession`, `isSessionStale`,
  `refreshSessionIfStale`, `send`, plus the C5/C8 capability
  helpers once they land)
- `src/jmap_client/internal/transport.nim` — 9 exports
  (`HttpMethodKind`, `HttpRequest`, `HttpResponse`, `SendProc`,
  `CloseProc`, `Transport`, `newTransport`, `newHttpTransport`,
  `send`)

For each, ask "load-bearing public commitment?". Default to private
for anything not justified. The walk measures the headline surface
A1 locked. The numbers above do not include re-exports the public
hub filters out — they are raw module-level export counts and
overstate the public surface accordingly. A1c demonstrates the
effect: the L2 modules export their `fromJson` / `toJson` overloads
liberally but only the four envelope `toJson` overloads reach the
public surface through `protocol.nim`.

### F3. Convenience-leak check — bidirectional *(P6)* — ⬜ TODO

**Forward (existing).** `grep -rn "import.*convenience"` from L3
modules under `src/jmap_client/internal/protocol/` and
`src/jmap_client/internal/mail/`. Must return only test/external
— no L3 module imports `convenience.nim`. (Already documented in
the `convenience.nim` top docstring.)

**Reverse (new).** `grep -rn
"convenience\|QueryThenGet\|ChangesToGet\|getBoth"
src/jmap_client/internal/` — must return only forward references
inside `convenience.nim` itself. Any docstring in L1–L3
mentioning a convenience helper is a leak (CI fail). P6 says
"Documentation for the core does not assume the convenience
layer."

### F4. Sample CLI smoke test against three servers — CI-wired — ⬜ TODO (blocked by C1)

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

### F6. Re-export hub snapshot diff in CI *(P1, P5)* — ⬜ TODO

A26 names the snapshot but not the CI step. Without a named
mechanical gate, the snapshot rots silently — committers regenerate
it without scrutiny on every PR.

**Action.** Add a `just freeze-api` recipe that produces
`tests/wire_contract/public-api.txt` from the symbols reachable
through the two public module paths — `import jmap_client` and
`import jmap_client/convenience` (A10). CI step:

```yaml
- name: API snapshot diff
  run: |
    just freeze-api
    if ! git diff --quiet tests/wire_contract/public-api.txt; then
      echo "::error::Public API surface changed."
      echo "Add [API-CHANGE] to the PR title and commit the snapshot."
      exit 1
    fi
```

PR title must contain `[API-CHANGE]` (or `[TYPE-SHAPE-CHANGE]` for
A25, or `[WIRE-CHANGE]` for D3) before the diff is allowed to merge.

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
- Every freeze-gate item appears in `pre-1.0-freeze-checklist.md`
  (D18).

## Section H — CI assertions and lints

The cross-cutting principle that *alignment is upheld by policy + CI,
not by accident*. Items here back the policy items in Sections A and
D with mechanical enforcement.

### H1. Sealed-distinct lint *(P15)* — backs A8 — ✅ DONE

`tests/lint/h1_sealed_distinct_construction.nim` enforces the
post-A8 invariant: zero public `distinct` type declarations under
`src/`. The seal that binds external consumers (P15) is the
sealed Pattern-A object pattern — a module-private `rawValue`
field — not any form of `distinct` wrapping; the lint blocks
regression by failing on any `type Foo* = distinct ...`
declaration. The complementary external-construction reject
(`tests/compile/treject_a8_sealed_external_construction.nim`)
asserts at compile time that raw `Foo(rawValue: ...)` from
outside the defining module fails with Nim's *"the field
'rawValue' is not accessible."* diagnostic.

**Implementation path.** Both `tests/lint/h1_sealed_distinct_construction.nim`
and the `lint-sealed-distinct:` recipe in `justfile`. Wired to
`just check` and `just ci` via `just lint-sealed-distinct`.

**Current-state assertion.** Zero violations; no public
`distinct` types declared under `src/`.

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

**Forward-pointer for A6.** A6 introduces `std/sysrand` in
`src/jmap_client/internal/client.nim` for the `BuilderId.clientBrand`
draw — the chosen failure mode is loud failure
(`jcvEntropyUnavailable` `ValidationError`), so `std/monotimes`
is NOT imported and no fallback path exists. When H4 lands, the
allowlist must include `std/sysrand`. The H4 lint does not yet
exist; this is a forward-pointer for whoever lands H4.

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

### H7. Convenience charter lint *(P6, P9)* — backs C7, C9, F3 — ⬜ TODO

`convenience.nim` may export only procs returning core types and
must not introduce new public types (C9). L1–L3 docstrings must
not mention convenience helpers (F3 reverse leak check).

**Implementation path.** `tests/lint/h7_convenience_charter.nim`.
Wired to `just lint`. Two checks:

1. `grep "^type \w\+\* =" src/jmap_client/convenience.nim` returns
   only the allowlisted paired handle/result bundle types — the
   six `*GetHandles` / `*GetResults` types (C9).
2. `grep -rn "convenience\|QueryThenGet\|ChangesToGet"
   src/jmap_client/internal/` returns nothing — no L1–L3 module
   references a convenience combinator (the F3 reverse-leak check).

Either check failing fails CI.

### H8. `.get()` invariant comment lint — locks existing project rule — ⬜ TODO

`nim-conventions.md` already requires `.get()` on a `Result` to
carry an adjacent invariant comment proving Ok. The convention is
unenforced — review-discipline only.

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
walks `src/jmap_client/internal/{protocol,mail}/`,
`src/jmap_client.nim`, and `src/jmap_client/convenience.nim`. Wired
to `just check`, `just ci`, and the standalone
`just lint-typed-builder-jsonnode` recipe.

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
exactly two paths (`jmap_client`, `jmap_client/convenience`).

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

The canonical ``message()`` projection over the 32 representative
error values matches the locked snapshot committed at
``tests/wire_contract/error-messages.txt`` exactly. Bidirectional:
samples missing from the live computation (a label in the snapshot
with no backing producer), samples extra in the live computation
(an emitted label not in the snapshot), and changed projections
(label in both, message differs) all fail CI.

**Implementation path.**
``tests/lint/h15_error_message_snapshot.nim`` reads
``tests/wire_contract/error-messages.txt``, inlines the 32 live
samples in matching declaration order, computes ``message()`` on
each, and emits a fix-it pointer (``just freeze-error-messages``)
on divergence. Wired to ``just check``, ``just ci``, and the
standalone ``just lint-error-messages`` recipe.

**Pair.** Companions H9 (catch-all ``else`` lint, ⬜ TODO) and H14
(wire-enum invariant lint, ⬜ TODO). H15 is the surface-snapshot
analogue of H13 — locking the diagnostic-format contract the way
H13 locks the module-path contract.

**Current-state assertion.** Zero violations; the snapshot enumerates
exactly 32 samples spanning every variant of every error type.

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
| P1 (lock contract) | A1, A1b, A2, A2b, A4, A6, A10, A11, A12, A13, A16, A25, A25b, A26, D1, D1.5, D4, D5, D17, D18, F6, F7, H14, H15 | API snapshot diff (F6); freeze checklist (D18); H13 lint (A10b); module-paths.txt snapshot (A10a); H15 lint (A12); error-messages.txt snapshot (A12) | 🟡 |
| P2 (tests) | A25, A28b, D2, D3, F1, F5 | Property tests (F1); wire-byte fixtures (D3) | 🟡 |
| P3 (overloads not `_v2`) | C2, C3, D1.5 (no-suffix rule) | H5 lint; review | 🟡 |
| P4 (scope) | D11, D11.5, D12, H4 | H4 non-JMAP-import lint | 🟡 |
| P5 (single layer) | A1, A1b, A1c, A1d, A6, A9, A10, A12, A14, A19, F2, F6 | H5; H10; H12; F6 snapshot; H13 lint (A10b); module-paths.txt snapshot (A10a); A1c + A1d compile audits | 🟡 |
| P6 (convenience quarantine) | A10, C7, C9, C10, F3, D16, H7 | H7 charter lint; H13 lint (A10b); module-paths.txt snapshot (A10a) | 🟡 |
| P7 (wrap rate) | A12, B5, C1, C1.1, C2–C5, C8, F4 | F4 CLI smoke test | 🟡 |
| P8 (opaque handles) | A6, A6.5, A6.6, A7b, A9, A13, A19, A27, A28, A28b | F2 audit; H1; H12 | 🟡 |
| P9 (two contexts max) | A6.5, A6.6, A7, A7b, B9, C9, D10 | H7; B9 resolution | 🔴 (B9 open) |
| P10 (no globals) | D1.5 (no-globals rule), H2 | H2 lint | 🟡 |
| P11 (no global callbacks) | A19 (closure-vtable per-handle), D1.5 (no-callbacks rule), D10 | review; future H10 once L5 lands | 🟡 |
| P12 (memory ownership in types) | A13, A19, B10 | review | 🟡 |
| P13 (one error rail) | A6, A12 | H8 `.get()` invariant lint; H15 snapshot lint (A12) | 🟡 |
| P14 (no thread-local errors) | A9 (no `last*` state on handle), A19 (`HttpResponse` returned by value, not stashed on Transport), D10, H3, H12 | H3 lint; H12 lint | 🟡 |
| P15 (smart constructors) | A8 (sealed Pattern-A objects across every public value-carrying type + `IdOrCreationRef` + 3 internal), A12 (library-internal error constructors filtered off the hub), A15 (SerializedSort / SerializedFilter sealed via A8), A19 (`newTransport`, `newHttpTransport` Result-returning), H1 | testament reject test `tests/compile/treject_a8_sealed_external_construction.nim`; A12 compile audits; H1 lint (regression prevention) | 🟢 |
| P16 (preconditions in types) | A6, A6.5, A6.6, A7b, A7c, A7d, A29, B3, B4, B6, B11, B12 | H9; B11/B12 resolution; A7c testament `action: reject` test | 🔴 (B11, B12 open) |
| P17 (one config surface) | A14, A19 (HTTP config on `newHttpTransport` only), A20, A21 | review; F6 snapshot | 🟡 |
| P18 (sum types over flag soup) | A6, A12, B1, B2, B7, B8, H9 | H9 catch-all lint; A12 exhaustive `case` in `SetError.message` / `TransportError.message` / mail extractors | 🟡 |
| P19 (schema-driven types) | A2, A2b, A3, A3.5, A4, A5, A14, A15, A16, A17, A18, A21, A22, A22b, A28, A28b, H14 | H11 typed-builder lint (A5); A22b inline docstrings; F1 | 🟡 |
| P20 (additive variants) | A10, A11, A12, A23, A24, D7, D13, D13.5, H5, H14 | H5 lint; H13 lint (A10b); module-paths.txt snapshot (A10a); H15 lint (A12); error-messages.txt snapshot (A12) | 🟡 |
| P21 (lifecycle types) | A6, A6.5, A6.6, A7, A7b, A7c, A7d, A23, A24, A27, A28 | type-shape snapshot (A25); A7c testament `action: reject` test | 🟡 |
| P22 (sync first, async via interface) | A6, A7e, A19, E1 | A7e policy entry; F6 snapshot blocks pre-1.0 export of reserved names | 🟡 |
| P23 (push as separate type) | A7e, A10, A23, A24, D13.5 | existence gate (A7e in D13.5 file; A23, A24 type files); H13 lint (A10b); module-paths.txt snapshot (A10a) | 🟡 |
| P24 (threading invariant) | A6, A13, A19 (closure-vtable threading invariant in `Transport` and `JmapClient` docstrings), D8 | D8 docstring footer; review | 🟡 |
| P25 (license) | D1.5, H6 | `reuse lint`; H6 freeze gate | 🟡 |
| P26 (build) | current `mise.toml`/`justfile`/`.nimble`; D1.5 documents the single `when defined(ssl)` concession in `internal/client.nim` | review | 🟡 |
| P27 (architecture docs) | D7, D9, D16 | existence gates | 🟡 |
| P28 (long-form docs) | A12, D9, D10, D14 | existence gates | 🟡 |
| P29 (sample consumer) | C1, C1.1, F4 | F4 CI smoke + AUDIT.md | 🟡 |

### Anti-pattern lockout matrix

Every explicit anti-pattern in `docs/design/14-Nim-API-Principles.md`
(end of "Anti-patterns explicitly forbidden") has a CI-mechanical
lockout. Review-only locks are **forbidden** — anti-patterns
must fail CI, not depend on reviewer attention.

| Anti-pattern | TODO items | CI gate |
|---|---|---|
| Global mutable state | D1.5 (no-globals rule), H2 | H2 lint |
| Global callbacks | D1.5 (no-callbacks rule), D10 | future H10 once L5 lands |
| Two-channel configuration | A14, A20, A21 | F6 snapshot diff (catches future drift) |
| Stringly-typed APIs | A2, A2b, A3, A3.5, A4, A5, A8 (closes the disguise by sealing the underlying `rawValue` field), A14, A15, A17, A18, A21, A22b | H11 typed-builder lint; H7 (convenience charter); A8 testament reject test; reviewer grep on `JsonNode` outside Documented exceptions |
| Multiple coexisting public layers | A1, A1b, A1c, A1d, A9, A10 | H13 lint (A10b); module-paths.txt snapshot (A10a); F6 snapshot (A26); A1c + A1d compile audits |
| Convenience layer leaking | C7, C9, C10, F3, H7 | H7 lint |
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
**and** have a verification gate. The 1.0 release tag fails (D18)
if any row is unticked.

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
| 10 | Convenience module quarantine | C7, C9, C10, F3, D16, H7 | H7 lint + grep audit |
