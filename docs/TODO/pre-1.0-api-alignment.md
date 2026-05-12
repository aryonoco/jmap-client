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
  unit test fails on regression. H1–H11 are mechanical gates.
- **Snapshot gate**. A frozen file under `tests/wire_contract/`
  whose diff requires explicit `[API-CHANGE]`, `[WIRE-CHANGE]`, or
  `[TYPE-SHAPE-CHANGE]` PR labelling. A25, A26, F6 are snapshot
  gates.
- **Existence gate**. A file must exist at a stated path before
  the 1.0 release tag. C1, D1.5, D9, D10, D11.5, D13.5, D15, D16,
  D17 are existence gates.

The pre-1.0 freeze checklist that tracks gate status per item lives
at `docs/TODO/pre-1.0-freeze-checklist.md` (D18). The 1.0 release
build fails if any gate row is unchecked.

The principle of this section: **alignment is upheld by policy + CI,
not by accident.** A new contributor opening a PR cannot violate a
principle without CI catching it.

## Documented exceptions to the principles

Four patterns in `src/` are intentional violations of P19
("schema-driven types") justified by the RFC or by Postel's law.
Reviewers must not re-litigate these — the exception is permanent
and recorded here so future contributors do not waste cycles
attempting to retype them.

- **`MailboxRights` 9 independent boolean fields**
  (`src/jmap_client/mail/mailbox.nim`). RFC 8621 §2.4 defines nine
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

### A1. Pick the headline public layer; demote the rest *(P5, P7)*

`src/jmap_client.nim` re-exports `types`, `serialisation`, `protocol`,
`client`, `mail` — five parallel surfaces. A consumer today can build a
`Request` via the L3 builder *or* hand-rolled L1+L2
(`initInvocation` + `Request.toJson`). Pick one as the documented "use
this" API; mark the other private.

**Resolution.** L3 builder + dispatch is the headline. Root
`import jmap_client` re-exports `types`, `serialisation`, `protocol`,
`client`, `mail`. `jmap_client/convenience` is publicly importable but
opt-in (must be imported explicitly; not re-exported by the root).
Everything else relocates under `jmap_client/internal/` and is
excluded from the public contract.

**Action.**

- Strip `*` from internal serde modules. The complete strip-list is the
  23 serde files: `serde.nim`, `serde_envelope.nim`, `serde_framework.nim`,
  `serde_session.nim`, `serde_errors.nim`, plus all 18 mail
  `serde_*.nim` (`serde_addresses`, `serde_body`, `serde_email`,
  `serde_email_blueprint`, `serde_email_submission`, `serde_email_update`,
  `serde_headers`, `serde_identity`, `serde_identity_update`,
  `serde_keyword`, `serde_mail_capabilities`, `serde_mail_filters`,
  `serde_mailbox`, `serde_snippet`, `serde_submission_envelope`,
  `serde_submission_status`, `serde_thread`, `serde_vacation`). They
  remain importable via the `serialisation.nim` hub but are not public
  commitments individually.
- Move L4 + non-builder L1/L2 internals under
  `src/jmap_client/internal/` so the directory layout itself signals
  privacy. Document the convention: `jmap_client/internal/*` is
  reserved for implementation churn.
- Update `jmap_client.nim`'s re-export tree to match.

### A1b. Per-symbol audit of `protocol.nim` re-exports *(P5)* — **DONE**

`protocol.nim` re-exports the user-facing surface using Nim's
`export module except sym1, sym2, …` form. Registration plumbing,
pre-serialisation helpers, internal merge functions, and the
stringly-typed `addInvocation` escape hatch (P19) are hub-private
without disturbing the `import jmap_client` symbol-resolution graph
(the captured-fixture replay tests use `envelope.Response.fromJson(j)`
to disambiguate from per-method response types — `envelope` collides
with the `EmailSubmissionBlueprint.envelope*` UFCS accessor, and the
resolver's outcome is sensitive to the export form, so blanket
`export module` was avoided in favour of selective filtering).

**Final public surface per module**:

- `entity.nim` — `registerJmapEntity`, `registerQueryableEntity`,
  `registerSettableEntity` (3 templates). Per-entity overloads
  (`methodEntity`, `getMethodName`, `setMethodName`, `capabilityUri`,
  `filterType`, etc.) live in `internal/mail/mail_entities.nim` and
  reach user code via `mail.nim`'s re-export chain because `mixin`
  requires call-site visibility — out of scope for A1b's protocol-hub
  audit.
- `methods.nim` — request types `GetRequest`, `ChangesRequest`,
  `SetRequest`, `CopyRequest`; response types `GetResponse`,
  `ChangesResponse`, `SetResponse`, `CopyResponse`, `QueryResponse`,
  `QueryChangesResponse`; copy disposition `CopyDestroyModeKind`,
  `CopyDestroyMode`, `keepOriginals`, `destroyAfterSuccess`; serde
  `toJson`, `fromJson`. Hub-private (stripped of `*`): `optState`,
  `optUnsignedInt`, `mergeCreateResults`. Hub-private (`*` retained
  for cross-internal use, filtered via `except`): `SerializedSort`,
  `SerializedFilter`, `toJsonNode`, `serializeOptSort`,
  `serializeOptFilter`, `serializeFilter`, `assembleQueryArgs`,
  `assembleQueryChangesArgs`.
- `dispatch.nim` — handle types `ResponseHandle`, `NameBoundHandle`,
  `CompoundHandles`, `CompoundResults`, `ChainedHandles`,
  `ChainedResults`; extraction `callId`, `get`, `getBoth`; references
  `reference`, `idsRef`, `listIdsRef`, `addedIdsRef`, `createdRef`,
  `updatedRef`; registration `registerCompoundMethod`,
  `registerChainableMethod`; operators `==`, `$`, `hash`. Hub-private
  (stripped of `*`): `serdeToMethodError`.
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

1. **`*`-stripping** — for symbols with no cross-module callers,
   strip `*` so they are file-private. Tests that exercised them
   directly relocate to whitebox files using Nim's `include`
   directive (`tests/protocol/tmethods_whitebox.nim`,
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

Future A1c, A1d, ... hub audits follow the same pattern.

### A2. Privatise `Invocation.arguments*` *(P19, P5, P8, P25)* — **DONE**

`src/jmap_client/internal/types/envelope.nim:29`. Mirrors the
already-private `rawName` / `rawMethodCallId` siblings: the
`arguments` field is module-private, with a `func arguments*(inv:
Invocation): JsonNode` accessor exported from envelope.nim for
internal consumers (`internal/serialisation/serde_envelope.nim`,
`internal/protocol/dispatch.nim`, `internal/protocol/builder.nim`).
The hub re-export (`src/jmap_client/types.nim`) excludes the
accessor via `export envelope except arguments`, so application
developers doing `import jmap_client` cannot reach raw JsonNode
args; typed accessors (`name`, `methodCallId`, `toJson`) are the
only public surface. **No `withArguments` setter was added** — the
original sketch's "diagnostic / replay" framing was the libdbus
stringly-typed back door; replay flows through `parseInvocation`
from captured wire bytes, construction flows through
`RequestBuilder`, and there is no JsonNode-shaped mutation API on
`Invocation`. The seal is verified in both directions by
`tests/compile/tcompile_a2_invocation_hub_surface.nim` (sealed from
`import jmap_client`) and
`tests/compile/tcompile_a2_invocation_internal_access.nim`
(reachable via direct internal import).

**Scope expanded during planning.** The same commit also closed
two related smells whose deferral would have left A2's anti-pattern
alive in adjacent code:

- *L1-relocation drift in CLAUDE.md.* A1 moved L1 modules to
  `internal/types/` but CLAUDE.md still listed pre-relocation paths.
  Updated the "Important Directories" section so the agent-facing
  instruction file no longer misdirects.
- *L4 raw-args reads in `src/jmap_client/client.nim:409–455`.*
  `detectGetLimit` / `detectSetLimit` walked `inv.arguments`
  JsonNode keys to count ids / create / update / destroy and enforce
  `maxObjectsInGet` / `maxObjectsInSet`. Replaced with typed
  `CallLimitMeta` threaded through `RequestBuilder` (private
  `callLimits` field + `callLimits*` accessor; new internal-only
  module `internal/protocol/call_meta.nim`). Each `add*` builder
  constructs the typed metadata from its typed inputs. The 4
  NonEmpty*Updates wrappers (`NonEmptyIdentityUpdates`,
  `NonEmptyEmailUpdates`, `NonEmptyEmailSubmissionUpdates`,
  `NonEmptyMailboxUpdates`) gained a borrowed `len*` so the generic
  `addSet[T, C, U, R]` resolves `u.len` at instantiation via
  `mixin len`.
  Post-condition: `rg 'inv\.arguments' src/` matches only
  `internal/serialisation/serde_envelope.nim` (L2 wire boundary)
  and `internal/protocol/dispatch.nim` (L3 typed-decoding boundary).

The two `validateLimits*` overloads in `client.nim` are now
asymmetric by design: `validateLimits(builder, caps)` performs full
pre-flight (max-calls + per-call /get + per-call /set);
`validateLimits(request, caps)` (the lower-level escape hatch used
by raw-Request senders) enforces only `maxCallsInRequest`.
Documented in both docstrings — the asymmetry is the visible cost
of refusing to walk wire shape for type-derivable information.
`send(client, builder)` routes through the builder-aware overload;
`send(client, request)` routes through the narrow overload.

### A3. Type `GetResponse[T].list` *(P19)* — **DONE**

`GetResponse[T].list` is now `seq[T]`, parsed per-entry via `mixin
T.fromJson` inside `GetResponse[T].fromJson`
(`src/jmap_client/internal/protocol/methods.nim`). The wrapper-trigger
`Entity.fromJson(getResp.list[0]).expect(...)` is removed from the
test corpus (51 files mechanically rewritten across Patterns
F/G/H/I/J/K/E). Implementation mirrors `mergeCreateResults[T]` and
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

Adjacent items still tracked: A3.6 (NEW; partial-entity types for
sparse `/get`), A4 + A3.5 (`updateResults` typing + decision), A29
(`parseGetResponse[T]` coherence invariant), F1 (property test
wiring), D10 (L5 FFI design).

Doc references: `03-layer-3-design.md`, `00-architecture.md`,
`07-mail-b-design.md` (D3.6 narrative — get-side full-record half
retired; update-side half stays pending A4; sparse half documented
under A3.6).

### A4. Type `SetResponse[T].updateResults` *(P19)* — **DONE**

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

### A5. Typed extension wrappers; one JsonNode escape for vendor URNs *(P19)* — **DONE**

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

- `CapabilityUri = distinct string`
  (`src/jmap_client/internal/types/capabilities.nim:82`) carries
  RFC 8620 §2 capability URIs end-to-end. Raw constructor
  module-private (P15); `parseCapabilityUri` validates the RFC 8141
  URN envelope. `RequestBuilder.capabilityUris` holds
  `seq[CapabilityUri]`; `build()` / `capabilities()` unwrap to
  `seq[string]` for the RFC 8620 §3.3 wire shape.

- `MethodNameLiteral = distinct string`
  (`src/jmap_client/internal/types/methods_enum.nim:96`) is the
  validated wire-name carrier for `addCapabilityInvocation`.
  Distinct from the `MethodName` enum because vendor methods cannot
  be enumerated; `parseMethodNameLiteral` enforces 1..255 octets, no
  control chars, contains `/`.

- Per-call typed metadata lives in
  `src/jmap_client/internal/protocol/call_meta.nim` — `setMeta` /
  `getMeta` helpers fold typed create/update/destroy/ids inputs into
  `CallLimitMeta` once; the stripped generic builders delegate.

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

Every `ResponseHandle[T]`, `NameBoundHandle[T]`, `BuiltRequest`, and
`DispatchedResponse` carries a `BuilderId` brand. `handle.get(dr)`
compares the brands and returns `err(gekHandleMismatch)` on
mismatch with diagnostic payload `(expected, actual, callId)`.
Catches cross-builder reuse within one client and cross-client
reuse across `JmapClient` instances (multi-account scenarios).

`BuilderId` is composite: `clientBrand: uint64` drawn via
`std/sysrand.urandom` once per `JmapClient` (entropy failure
surfaces as `jcvEntropyUnavailable` `ValidationError`), plus
`serial: uint64` monotonic per client.

**Pointers.**
- `src/jmap_client/internal/types/identifiers.nim` — `BuilderId`
  + `initBuilderId` + `clientBrand` / `serial` accessors.
- `src/jmap_client/internal/protocol/dispatch.nim` — sealed
  handle shape + brand-check at `get` / `getBoth`.
- `src/jmap_client/internal/protocol/builder.nim` — `BuilderId`
  threading through every `add*` via the chokepoint
  `addInvocation`.
- `src/jmap_client/client.nim` — brand draw via `drawClientBrand`
  + `newBuilder`.
- `tests/protocol/tdispatch.nim` — cross-builder and cross-client
  mismatch blocks exercise the brand check.

### A7. Lifecycle types *(P21, P23)*

Separate four lifecycle phases as distinct types; transitions are
functions:

`RequestBuilder` (mutable accumulator) → `BuiltRequest` (frozen,
dispatch-ready) → `DispatchedRequest` (sent, awaiting) → `Response`
(received).

`JmapClient.send` takes `BuiltRequest` and returns
`Result[Response, ClientError]` (or `DispatchedRequest` on the async
path once the Transport interface lands — A19). Each phase has a
distinct invariant. The compiler enforces that you cannot dispatch a
`RequestBuilder` directly, cannot re-bind a `DispatchedRequest`, etc.

**`DispatchedRequest` may be a stub today** — its shape locks the
position before async/push lands (P23 alignment). Removing or renaming
it post-1.0 is a major break. Naturally clusters with A6.

### A8. Privatise raw distinct-type constructors *(P15)*

The largest single P15 gap in the codebase. Every public `distinct`
type's raw constructor `Foo(rawValue)` is reachable from outside its
defining module.

**Action.** Apply CI lint H1 rejecting `<DistinctTypeName>(`
invocations outside the defining module. Wrapping every distinct in a
sealed object is mechanical work for ~60 types; the lint is cheaper
and equally rigorous.

**Canonical list.** Generated by
`grep -E "^type \w+\* = distinct" src/jmap_client/**/*.nim` plus the
case-objects with private discriminator but exposed raw fields. The
list at audit time:

- `src/jmap_client/primitives.nim:20, 26, 32, 39, 44, 51` — `Id`,
  `UnsignedInt`, `JmapInt`, `Date`, `UTCDate`, `MaxChanges`.
- `src/jmap_client/identifiers.nim:15, 21, 31, 41, 51` — `AccountId`,
  `JmapState`, `MethodCallId`, `CreationId`, `BlobId`.
- `src/jmap_client/framework.nim:17` — `PropertyName`.
- `src/jmap_client/methods.nim:285, 288` — `SerializedSort`,
  `SerializedFilter` (`distinct JsonNode`).
- `src/jmap_client/mail/keyword.nim:20, 50` — `Keyword`, `KeywordSet`
  (raw constructor lets callers bypass `parseKeyword`'s
  lowercase normalisation and forbidden-char check).
- `src/jmap_client/mail/body.nim:37` — `PartId`.
- `src/jmap_client/mail/mailbox.nim:176, ~200` — `MailboxIdSet`,
  `NonEmptyMailboxIdSet`.
- `src/jmap_client/mail/email.nim:338` — `NonEmptyEmailImportMap`.
- `src/jmap_client/mail/email_update.nim` — `EmailUpdateSet`.
- `src/jmap_client/mail/vacation.nim:88` — `VacationResponseUpdateSet`.
- `src/jmap_client/mail/submission_atoms.nim:45, 108, 116` —
  `RFC5321Keyword`, `OrcptAddrType`, `ReplyCode`/`SubjectCode`/
  `DetailCode` (`distinct uint16` admit values outside RFC range).
- `src/jmap_client/mail/submission_mailbox.nim:74`,
  `submission_status.nim:100, 112, 116`,
  `submission_param.nim:71, 91`,
  `headers.nim:331, 403`.
- Case-objects with private `case kind` discriminator but exposed raw
  fields: `MailboxRole` (mailbox.nim:41), `IdOrCreationRef`
  (email_submission.nim:463), `ContentDisposition` (headers.nim).

Without the H1 lint, every smart constructor in the library is
bypassable.

### A9. Hide test backdoors *(P5, P8)*

These are `*`-exported on `client.nim` and become permanent public
commitments at 1.0:

- `src/jmap_client/client.nim:582` — `setSessionForTest*`
- `src/jmap_client/client.nim:587` — `lastRawResponseBody*`
  (the underlying field privatisation is incomplete — the accessor
  itself is the leak)
- `src/jmap_client/client.nim:747` — `sendRawHttpForTesting*`
- `src/jmap_client/client.nim:487` — `validateLimits*`
- `src/jmap_client/client.nim:293` — `bearerToken*` (returns a secret;
  audit whether load-bearing — likely demote)

**Action.** Move to `src/jmap_client/internal/testing.nim` that the
public API does not re-export, OR gate behind
`when defined(jmapClientTesting)`.

### A10. Module-path lock *(P5, P25)*

Module paths are part of the contract: `import jmap_client/mail`,
`import jmap_client/types`, `import jmap_client/mail/email` — all of
these are public commitments the moment 1.0 ships.

**Public module paths** (closed set; everything else relocates under
`internal/`):

- `jmap_client` (root)
- `jmap_client/types`
- `jmap_client/serialisation`
- `jmap_client/protocol`
- `jmap_client/client`
- `jmap_client/mail`
- `jmap_client/convenience`
- `jmap_client/push` (A23 reservation)
- `jmap_client/websocket` (A24 reservation)

Document the convention: anything outside the closed set is reserved
for implementation churn (SQLite-style "no opaque struct ever"
reservation).

### A11. Forward-compat enum audit *(P1, P20)*

Every enum that crosses the wire must have a catch-all variant AND a
`raw…` field for lossless preservation. Confirmed catch-all coverage:
`MethodName.mnUnknown`, `CapabilityKind.ckUnknown`,
`RequestErrorType.retUnknown`, `MethodErrorType.metUnknown`,
`SetErrorType.setUnknown`. Audit needed:

- **Bug.** `src/jmap_client/envelope.nim:113–120` — `RefPath` silently
  falls back to `rpIds` for unknown server paths. Should preserve via
  `rawPath` only OR add `rpUnknown` variant. Currently coerces
  unknown paths to `/ids` semantics.
- `CollationAlgorithm` (collation.nim) — verify catch-all.
- `MailboxRole` — partial: `mrOther` carries `rawIdentifier`. Confirm
  serde round-trip.
- `RequestContext` (errors.nim:145–148) — internal but re-exported
  via `errors → types`; verify it does not leak.
- `AccountCapabilityEntry.data: JsonNode` (session.nim:25) — confirm
  unknown account-level capabilities round-trip losslessly (subsumed
  by A17 case-object refactor).

### A12. Error diagnostic surface *(P13 cohort, P7)*

No `message(ClientError)` / `$err` for production logs. Live tests
read as `.expect("initJmapClient[" & $target.kind & "]")` because
there is no one-line "format this for my logs" path on the public
surface. SQLite ships `sqlite3_errmsg`; libcurl ships
`curl_easy_strerror`; this library ships nothing equivalent. Day-one
wrapper trigger.

**Action.** Add `func message*(err: T): string` and
`func '$''*(err: T): string` for **all four** error types:
`ClientError`, `MethodError`, `SetError`, `ValidationError`.

**Deterministic format**: `"<errorTypeName>: <message> (context:
<rcSession|rcApi>)"`. For `SetError`, fold variant payloads into the
message string so the diagnostic is self-contained
(e.g. `"setInvalidProperties: properties=[…]"`). For `MethodError`,
include the `description: Opt[string]` payload when present.

**Property test**: two equal-shape error values produce equal `$`
output. Document the format in the long-form guide (D9 §4).

### A13. JmapClient destruction semantics *(P8, P12, P24)*

`src/jmap_client/client.nim:34, 46–47, 314–323`. `JmapClient` is a
`ref object` with an `=destroy` ARC hook. No `client.close()` ritual
(P8); the close-on-copy footgun is removed structurally.

**P24 implication.** ARC ref-counting is thread-safe; user-defined
`=destroy` may not be. Document `{.gcsafe.}` analysis on the
destructor explicitly. The `=destroy` hook tears down the underlying
`Transport` (A19); whichever thread releases the last ref runs the
teardown.

### A14. Demote `addInvocation*` *(P5, P19)*

`src/jmap_client/builder.nim:107–121`. `addInvocation*` is a stringly-
typed escape hatch parallel to the typed `addGet[T]`/`addSet[T]`/etc.
Once shipped, every consumer who builds extensions through it locks
the argument shape forever — the libdbus `"a{sv}"` failure mode.

**Action.** Move to `src/jmap_client/internal/builder_invocation.nim`
(or behind `when defined(jmapClientInternal)`). Public consumers
extend via capability negotiation + entity registration (D7, D13),
not through a stringly-typed escape hatch.

### A15. Demote remaining JsonNode-typed escape hatches *(P19)*

- `src/jmap_client/builder.nim:401–410` — `initCreates` returns
  `Opt[Table[CreationId, JsonNode]]`. The typed `addSet[T, C, U, R]`
  already takes `Opt[Table[CreationId, C]]`; `initCreates` is the
  JsonNode-typed parallel path. Demote to internal or remove.
- `src/jmap_client/builder.nim:149–156` — `addEcho` returns
  `ResponseHandle[JsonNode]`. Decision deferred to A22 (Echo is the
  RFC-mandated input-echoes-output method; document the exception).
- `src/jmap_client/methods.nim:285–297` —
  `SerializedSort = distinct JsonNode` and
  `SerializedFilter = distinct JsonNode` admit raw `JsonNode(s)`
  construction (same leak class as A8). Wrap in sealed Pattern-A
  objects with private `raw…` field exposed only by smart constructors
  `parseSerializedFilter[C]` / `parseSerializedSort[T]`.

### A16. `Response.toJson` publicness *(P19, P1)*

`src/jmap_client/methods.nim:553–581`. Currently public — locking it
means the library promises 2031 wire emission for responses (mostly a
testing convenience today).

**Action.** Lock with deterministic key-order spec (the wire-byte
contract D3 covers it). Document `Response.toJson` as canonical-form
emission. If the wire-contract suite does not yet cover it, demote
to internal/test-only until it does.

### A17. `AccountCapabilityEntry.data: JsonNode` *(P19)*

`src/jmap_client/session.nim:21–26`. The comment says *"may evolve to
a case object when typed account-level capabilities are added (e.g.
RFC 8621)."* RFC 8621 is implemented; this should already be a case
object discriminated by `CapabilityKind`, mirroring `ServerCapability`
(capabilities.nim:52–60).

**Destination shape.** Case object on `CapabilityKind` with required
typed arms `ckMail`, `ckSubmission`, `ckVacationResponse`, `ckBlob`,
`ckQuota`, `ckSieve`, plus `else: rawData*: JsonNode` for unknown.
Smart constructor `parseAccountCapabilityEntry`. The flat
`AccountCapabilityEntry` becomes sealed with private discriminator.

### A18. `ServerCapability` typed arms *(P19)*

`src/jmap_client/capabilities.nim:52–60`. Has `else: rawData*: JsonNode`
for non-`ckCore` arms. Reasonable for unknown capabilities, but
`ckMail`, `ckSubmission`, `ckVacationResponse`, `ckBlob`, `ckQuota`,
`ckSieve` all have typed schemas. Add explicit case-object arms;
preserve `rawData` for unknown only.

### A19. Define the `Transport` interface *(P22)*

`src/jmap_client/client.nim:48` — `httpClient: HttpClient` hard-binds
`JmapClient` to `std/httpclient`. **Without this freeze item, P22 is
unrecoverable post-1.0** because the field's *type* on `JmapClient` is
contractual at 1.0; adding a `Transport` interface in 1.x requires
either a sum-typed `JmapClient` (breaking), wedging `Transport` into
the existing `httpClient` field (impossible — different type), or a
parallel `JmapClientWithTransport` type (the c-client god-handle anti-
pattern).

**Action.** Define `Transport` as a Nim concept (or trait):

```nim
type Transport* = concept t
  proc httpRequest(t, url: string, body: Opt[string],
                   httpMethod: HttpMethod,
                   headers: openArray[(string, string)]):
                   Result[HttpResponse, TransportError]
```

`JmapClient`'s transport field is typed as the abstract interface, not
the concrete `HttpClient`. The default constructor wires up an
`HttpClientTransport` adapter (a thin wrapper around `std/httpclient`
that matches the interface).

This ships *without* a second concrete implementation; the existence
of the abstraction is what locks framework freedom. Once typed,
`chronos`-backed and `puppy`-backed transports compose without
touching `client.nim`.

### A20. Collapse session entry points *(P17)*

`client.nim:207–267` — `initJmapClient` and `discoverJmapClient` are
two functions for the same concept (the session URL). Discovery
domain `"example.com"` and a precomputed
`"https://example.com/.well-known/jmap"` reach the session URL via
two parsers — exactly what P17 forbids.

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

`discoverJmapClient` is removed (its behaviour is now
`initJmapClient(discoveryEndpoint("example.com").get(), ...)`).

### A21. Type the auth scheme *(P17, P19)*

`client.nim:210` — `authScheme: string = "Bearer"` is a stringly-typed
enum-shaped surface. Anti-pattern by P19; potential P17 drift if a
second source ever sets it.

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

### A22. `addEcho` JsonNode argument policy *(P19)*

`builder.nim:150` — `addEcho(b, args: JsonNode)`. RFC 8620 §4 makes
Core/echo "server returns input verbatim", which is structurally
JsonNode-shaped.

**Decision.** Keep `args: JsonNode` for `addEcho`; document
`Core/echo` in the docstring as the explicit RFC-mandated exception
to P19. `addEcho` returns `ResponseHandle[JsonNode]` accordingly. Any
other JsonNode-typed public proc requires a similar written
exception.

### A23. Sketch `PushChannel` type stub *(P20, P23)*

P23 says "the type they will inhabit is named in the public design
now". A name reservation without a type stub means any future 1.x can
land *any shape* of `PushChannel` — including a shape that puts it on
`JmapClient` as a method (the libdbus retrofit P23 exists to prevent).

**Action.** Sketch the stub before 1.0:

```nim
# src/jmap_client/push.nim
type PushChannel* = ref object
  # all fields private

proc unimplemented*(p: PushChannel): Result[void, ClientError] =
  err(unimplementedError("Push not yet implemented; tracking RFC 8620 §6"))

# `=destroy` placeholder for future ARC integration.
```

The signal: future Push lands by adding methods to `PushChannel`,
never by adding methods to `JmapClient`. The module path
`jmap_client/push` is reserved (A10).

### A24. Sketch `WebSocketChannel` type stub *(P20, P23)*

Same shape as A23 but for RFC 8887 (WebSocket). Distinct type from
`PushChannel`. One-sentence rationale in the docstring: "WebSocket is
a different transport, not a push variant." Module path
`jmap_client/websocket` reserved (A10).

### A25. Type-shape snapshot in CI *(P1, P2)*

D2's `public-api.txt` snapshot catches symbol-set drift but not
field-set drift. A `Request` whose `using*: seq[string]` field is
silently changed to `seq[CapabilityUri]` would break consumers; D2
would not flag it.

**Action.** Add `tests/wire_contract/type-shapes.txt`. Generated from
`nim doc --project` output (or a custom scraper) — every public
type's full field signature, with type names. CI diffs the file; any
field-shape change requires explicit "TYPE BREAK" label in the PR.

### A26. Re-export hub snapshot *(P1)*

The `export` clause set of every re-export hub is a public commitment
once 1.0 ships. Adding/removing a re-exported symbol changes the
import graph users observe.

**Action.** Snapshot the `export` clauses of `jmap_client.nim`,
`protocol.nim`, `types.nim`, `serialisation.nim`, `mail.nim`,
`mail/types.nim`, `mail/serialisation.nim`. CI diffs.

### A27. Seal the handle types *(P8)* — ✅ DONE

All handle types are sealed Pattern-A objects with private `raw*`
fields and explicit accessors:
`ResponseHandle[T]`, `NameBoundHandle[T]`, `CompoundHandles[A, B]`,
`ChainedHandles[A, B]`, plus `DispatchedResponse` (the sealed
wrapper that pairs the wire `Response` with a `BuilderId`).

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

### A29. `parseGetResponse[T]` smart constructor *(P16)*

`methods.nim` `GetResponse[T]` permits structurally `list ∩ notFound ≠
∅` — a server bug could put the same id in both, and the type allows
it. P16 says encode preconditions in types.

**Action.** Add `parseGetResponse[T]` smart constructor enforcing
`list ∩ notFound = ∅`. Lenient on receive: log + drop the duplicate
on the `notFound` side, or reject as a `MethodError`. Document the
choice.

### A2b. Property test: `Invocation` round-trip *(P19, P2)*

A2 privatises the field but only a wire-byte round-trip property
test makes the seal observable to CI. Without it, a future change
to `Invocation.toJson` that drops a key silently passes A2's
"private field" check.

**Action.** Add `tests/property/tinvocation_roundtrip.nim` covering:

- `parseInvocation(toJson(inv)) == ok(inv)` for every method-name
  variant, including `mnUnknown` with a synthesised raw name.
- `Request.toJson` and `Response.toJson` produce identical bytes
  when called twice on equivalent inputs (canonical-form
  determinism).

Wire to `just test-wire-contract` (F1).

### A3.5. Decide `SetResponse[T].updateResults` payload shape *(P19)* — **RESOLVED**

Resolved by A4 D2 — typed `Opt[U]` chosen, with `U` = per-entity
`PartialT`. The `Opt[void]` fallback option was not needed because
the `PartialT` family shipped together with A4 (integrated cut). No
semver-upgrade path required.

### A3.6. Partial-entity types for sparse `/get` responses *(P5, P7, P19)* — **DONE for types; PARTIAL on public surface**

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

### A6.5. Stub `BuiltRequest` and `DispatchedRequest` types *(P21, P23)* — ✅ DONE (`BuiltRequest`); 🟡 deferred (`DispatchedRequest`)

`BuiltRequest` is the sealed, branded carrier produced by
`RequestBuilder.freeze()` and consumed by `JmapClient.send`.
`DispatchedResponse` is the sibling sealed type returned by
`send`, carrying the wire `Response` plus the brand.

`DispatchedRequest` is reserved as the future async carrier for
when A19 + E1 land — the async overload of `send` will return
`JmapResult[DispatchedRequest]` and `DispatchedRequest.await` will
yield `JmapResult[DispatchedResponse]`. **Not introduced today**
because no async path exists; the sync `send` completes
synchronously and returns the `DispatchedResponse` directly.

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
Future async-path overload (A19 + E1) returns
`JmapResult[DispatchedRequest]` additively.

**Pointers.**
- `src/jmap_client/internal/protocol/builder.nim` — `freeze` and
  `BuiltRequest`.
- `src/jmap_client/client.nim` — `send(BuiltRequest)`;
  `validateLimits` operates on `BuiltRequest`.

### A12b. Implement `message()` and `$` for every error type *(P7, P13)*

A12 lists all four error types (`ClientError`, `MethodError`,
`SetError`, `ValidationError`) but `message()` exists only on
`RequestError` (errors.nim:81) and `ClientError` (errors.nim:127).
The other three have no public diagnostic accessor — every consumer
hand-formats from raw fields.

**Action.** Add to `src/jmap_client/errors.nim` and
`src/jmap_client/validation.nim`:

```nim
func message*(me: MethodError): string =
  ## Human-readable: description if present, else rawType.
  me.description.valueOr: me.rawType

func message*(se: SetError): string =
  ## Folds variant payload into the message — diagnostic is
  ## self-contained.
  case se.errorType
  of setInvalidProperties:
    "setInvalidProperties: properties=" & $se.properties
  of setAlreadyExists:
    "setAlreadyExists: existingId=" & $se.existingId
  else:
    se.description.valueOr: se.rawType

func message*(ve: ValidationError): string =
  ## ``typeName: message (value=…)`` deterministic format.
  ve.typeName & ": " & ve.message & " (value=" & ve.value & ")"

func `$`*(me: MethodError): string = me.message
func `$`*(se: SetError): string = se.message
func `$`*(ve: ValidationError): string = ve.message
```

**Property test.** Two structurally equal error values produce
equal `$` output (deterministic format).

### A22b. Inline docstrings at every JsonNode-public field declaration *(P19)*

The "Documented exceptions" sub-section at the top of this file
records the three justified `JsonNode` patterns. A22b makes the
exception visible at the declaration site so reviewers reading the
type don't need to consult this TODO.

**Action.** At each declaration, add a docstring footer citing the
exception:

- `src/jmap_client/capabilities.nim` — `ServerCapability.rawData`:
  `## P19 exception: forward-compatibility for unknown capabilities`.
- `src/jmap_client/errors.nim` — `MethodError.extras`,
  `SetError.extras`: same footer.
- `src/jmap_client/session.nim` — `AccountCapabilityEntry.data`:
  same footer (until A17 lands; remove footer when A17 case-objects
  the field).
- `src/jmap_client/builder.nim` — `addEcho(args: JsonNode)`:
  `## P19 exception: RFC 8620 §4 Core/echo is structurally JSON-typed`.
- `src/jmap_client/mail/mailbox.nim` — `MailboxRights` field block:
  `## P18 exception (Decision B6): RFC 8621 §2.4 mandates 9 independent ACL flags`.

CI lint H7 (added below) verifies that any other public `JsonNode`
field appearing in `src/` carries the same exception footer or
fails the build.

### A25b. Generate the type-shape snapshot mechanically *(P1)*

A25 specifies the snapshot file (`tests/wire_contract/type-shapes.txt`)
but does not specify the producer. A hand-maintained file rots fast.

**Action.** Add a `just freeze-type-shapes` recipe that produces
the file from `nim doc --project src/jmap_client.nim` JSON output
(or a small custom AST scraper). Output format: one type per
section, alphabetical by name, each field on its own line with its
typed annotation. CI fails if the regenerated file disagrees with
the committed copy and the PR is not labelled `[TYPE-SHAPE-CHANGE]`.

### A28b. Wire-byte determinism property test for `Request` and `Response` *(P2, P19)*

A28 leaves `Request` and `Response` as wire-data carriers with
public fields. The compensating promise is wire-byte determinism:
`Request.toJson(req)` produces the same bytes every time for the
same input. Without a property test, this promise is unenforced.

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

### B1. `Account.isPersonal` + `isReadOnly` → 4-state enum *(P18)*

`src/jmap_client/session.nim:32–33`. Two independent Bools encoding
four legal combinations. Replace with
`enum AccountPolicy { apOwned, apOwnedReadOnly, apShared, apSharedReadOnly }`.

### B2. Sort-direction unification *(P18)*

Three sites currently use ad-hoc Bool / Opt[bool] for sort direction:

- `src/jmap_client/mail/email.nim:65, 76, 88` —
  `EmailComparator.isAscending: Opt[bool]` (three-state via Opt adds
  "absent" to true/false)
- `src/jmap_client/framework.nim:64` — `Comparator.isAscending: bool`
  (two-state)
- `src/jmap_client/mail/email_submission.nim:358` —
  `EmailSubmissionComparator.isAscending: bool` (two-state)

Replace all three with
`enum SortDirection { sdServerDefault, sdAscending, sdDescending }`.
Three sites total — the inconsistency between them is itself a smell.

### B3. `Filter[foNot]` arity + `foAnd|foOr` non-empty *(P16)*

`src/jmap_client/framework.nim:39–46`. RFC 8620 §5.5 says `foNot` MUST
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

### B4. `VacationResponse` window invariant *(P16)*

`src/jmap_client/mail/vacation.nim:18–26`. `fromDate: Opt[UTCDate]`
and `toDate: Opt[UTCDate]` independent. `Opt.some(from) &&
Opt.some(to) && from > to` is structurally allowed but RFC-forbidden.
Smart-construct via `parseVacationResponse: Result`, or hold a single
typed `Opt[VacationWindow] = (UTCDate, UTCDate)` whose constructor
enforces the order.

### B5. `registerExtractableEntity(T)` compile-check

Mirror `registerSettableEntity` (`src/jmap_client/entity.nim:128–162`)
which already compile-checks `T.toJson` for /set entities. Add a
template that compile-checks `T.fromJson(JsonNode):
Result[T, SerdeViolation]` is in scope. Without it, `dispatch.get[T]`
fails at instantiation, not registration — the error sites are
distant and unhelpful.

### B6. Other illegal-state findings (lower severity)

- `Account` (session.nim:27–34): `isReadOnly: true` and
  `accountCapabilities` carrying a write-implying capability can
  coexist. Phantom on `Account[ReadOnly]`/`Account[ReadWrite]` or a
  smart constructor.

### B7. `mail_filters.nim` Opt[bool] → three-state enums *(P18)*

`src/jmap_client/mail/mail_filters.nim:32, 33, 91` — three-state
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

### B8. `Identity.mayDelete` → enum *(P18)*

`src/jmap_client/mail/identity.nim:53` and
`src/jmap_client/mail/mail_entities.nim:118` `mayDelete: Opt[bool]` —
three-state via Opt encodes "Stalwart omits the field". Replace with:

```nim
type DeleteAuthority* = enum daYes, daNo, daUnreported
```

Document the Stalwart workaround in the type docstring.

### B9. Consolidate the handle-pair zoo *(P9)*

`dispatch.nim:240, 249, 288, 297` — `CompoundHandles[A, B]`,
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
cost is lower at the API surface that the post-A1 headline layer
exposes. Default recommendation: **(b)**, demote `Chained*` as
internal — the principle of "one concept, one type" outweighs minor
caller flexibility. Lock the choice in a B9 sub-section with the
rationale before tagging 1.0. If (a) is picked instead, record the
`HandlePairKind` enum in `tests/wire_contract/type-shapes.txt` (A25).

### B10. `lent` annotation pass on handle accessors *(P12)*

P12 says ownership in the type. Today every accessor that returns a
container deep-copies on each call. Annotate:

- `JmapClient.session*` — `lent Session`
- `Session.accounts*`, `primaryAccounts*`, `capabilities*` — `lent T`
- `RequestBuilder.capabilities*` — `lent seq[CapabilityUri]`
- `UriTemplate.parts*`, `variables*` — `lent T`

Cross-cutting pattern: any handle accessor whose return value is a
container (`Table`, `seq`, `HashSet`) gets `lent`. Verify ownership
contracts are documented for each.

### B11. `Email[Lite | Hydrated]` phantom decision *(P16)*

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

### B12. `Account[ReadOnly | ReadWrite]` decision *(P16)*

`src/jmap_client/session.nim:32`. The B6 sub-bullet flags that
`Account.isReadOnly: true` and `accountCapabilities` carrying a
write-implying capability can coexist — structurally allowed but
RFC-incoherent. Promote to a primary item: this is the same shape
of P16 violation as B11.

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

### C1. Sample CLI consumer — pre-1.0 freeze gate *(P29)*

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

### C2. Per-entity flatten of four-param `addSet` *(P7)* — **DONE**

The four-parameter generic `addSet[T, C, U, R]` is hub-private (A5;
filtered via `protocol.nim`'s `export builder except …` clause).
Public callers see only per-entity wrappers — `addEmailSet`,
`addMailboxSet`, `addEmailSubmissionSet`,
`addEmailSubmissionAndEmailSet`, `addVacationResponseSet` — each
taking `(b, accountId, ifInState?, create?, update?, destroy?)` with
typed creation models, typed update sets, and no `extras=`
parameter.

### C3. `byIds` per-entity helpers *(P7)*

`src/jmap_client/builder.nim:394` already provides `directIds` to
shave `Opt.some(direct(@[…]))` nesting. Extend per-entity:
`addEmailGet(b, accountId, byIds = @[id1, id2])`. UFCS chains read
materially better.

### C4. `MailboxRights` summary helpers *(P7)*

`src/jmap_client/mail/mailbox.nim:213–224`. Nine independent ACL
booleans (Decision B6 documented exception, correctly modelled). Add
roll-up helpers: `mb.canMutate(): bool`, `mb.canRead(): bool`,
`mb.canDelete(): bool`. Otherwise consumers chain
`mb.myRights.mayAddItems and mb.myRights.mayRemoveItems and …`.

### C5. Capability discovery convenience *(P7)*

Currently `client.session().get().coreCapabilities()` chain is
correct but undocumented. Add helpers:
`client.supportsMail(): bool`, `client.coreCapabilities(): Opt[…]`,
`client.requireMail(): JmapResult[void]`. Pre-flight "does this
server support Mail?" should be one line.

### C6. Version surface *(P25, P28)*

`src/jmap_client/client.nim` references
`userAgent: string = "jmap-client-nim/0.1.0"` as the only version
literal. C-library convention (curl, OpenSSL) exposes
`client_version()` for bug reports. Add:

```nim
const ClientVersion* = "0.1.0"  # synced with .nimble
func clientVersion*(): string = ClientVersion
```

### C7. Charter clause on `convenience.nim` *(P6)*

Add to `convenience.nim`'s top docstring:

> This module contains pipeline combinators (multi-method `add*`
> chains and paired `getBoth` extraction). It does NOT contain
> semantic convenience like `fetchInbox`, `archiveEmail`, `markRead`.
> Such helpers belong in user code. The zlib `gz_*` precedent shows
> what happens when convenience layers grow semantic helpers — the
> edge cases bleed back into the user's image of the core. P6 forbids
> this.

CI grep enforces (F3 + F3b).

### C1.1. Scaffold `examples/jmap-cli/` directory *(P29)*

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
`jmap_client` (post-A1 root re-export); reaching into
`jmap_client/internal/*` is forbidden and CI-checked (H7).

**AUDIT.md format.** Each awkwardness one bullet:
`- <call-site>: <description> [resolved | accepted | filed-as-Cn]`.
Examples to expect: UFCS chains > 3 levels, manual `.get()` chains
to read `coreCapabilities`, raw `JsonNode` references at call site.
Each `filed-as-Cn` becomes a new item in Section C of this TODO.

### C8. Capability pre-flight one-liner *(P7)*

C5 lists capability discovery helpers but underspecifies the
one-liner. The headline call site is "does this server support
JMAP Mail?" — currently
`client.session().get().coreCapabilities()` then walk a set.
Day-one wrapper trigger.

**Action.** Add to `src/jmap_client/client.nim`:

```nim
proc requireMail*(client: JmapClient): JmapResult[void]
  ## Returns ok() if Session is cached and declares
  ## ``urn:ietf:params:jmap:mail`` in capabilities; err(...) with
  ## ``cekRequest`` ``RequestErrorType.retNotJSON`` otherwise.
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

### C9. Charter clause: convenience.nim exports no new public types *(P6, P9)*

C7 covers the docstring; this item adds the structural restriction.
`convenience.nim` may export only procs and may return only
core-API types (`RequestBuilder`, `ResponseHandle[T]`,
`CompoundHandles[A, B]`, `BuiltRequest`). It must not introduce
new public types — those belong in core (L3) or user code.

**Action.** Document in the `convenience.nim` top docstring; back
mechanically with H7 lint (added in Section H). The lint scans
`convenience.nim` for `type … * =` declarations and fails CI on
any match. Existing `QueryGetHandles[T]` is grandfathered if
documented as the sole exception; otherwise the lint forces it
into a private alias before 1.0.

## Section D — Process / policy artefacts

### D1. SemVer + deprecation + wire-byte contract policy *(P1, P2, P3, P10, P11, P25)*

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

### D2. `public-api.txt` snapshot diffed in CI *(P1, P2)*

P2 is "stability bought with tests"; no current test asserts the
exported symbol list. Add `just freeze-api` that regenerates a
`public-api.txt` from `nim doc --project` output (or a custom scraper
over `*` patterns). CI diffs the file; any new `*` symbol requires
explicit acknowledgement in the PR description.

### D3. Wire-byte fixture contract elevation *(P2)*

224 captured payloads exist under `tests/testdata/captured/` across
three servers (Stalwart, Apache James, Cyrus IMAP). Elevate from
"regression aid" to "frozen contract":

- Every `.json` is a wire shape the library promises to deserialise
  forever.
- Add a `tests/wire_contract/` category whose only failure mode is
  "we changed serialisation in a way that breaks fixture replay".
- CI distinguishes "added new fixture" from "modified existing"; the
  latter is a major version unless the fixture was malformed.

### D4. Devendor or pin `nim-results` *(P1)*

`vendor/nim-results` is currently a pinned, patched copy. Either:

- **(a)** Devendor before 1.0 — depend on upstream
  `nim-results` via nimble; commit `nimble.lock`.
- **(b)** Stay vendored, with a written commitment never to update
  the vendored copy without a major bump.

Vendored deps that change semantics under callers are how every
cautionary tale in the principles doc broke its API.

### D5. `.nimble` contract *(P1, P25)*

Document in `docs/policy/01-semver-and-deprecation.md` that
`jmap_client.nimble`'s `version`, `srcDir`, the existence of
`src/jmap_client.nim` as the single entry point, and the public
re-export tree are all part of the 1.0 contract.

### D6. Generated docs as contract *(P28)*

`nim doc --project` output structure (file paths, module headings) is
consumed by users browsing API. Lock the directory layout before
1.0; document in the policy doc.

### D7. Capability negotiation as the documented extension surface *(P20)*

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

### D8. Threading invariants — class-wide rule *(P24)*

`src/jmap_client/client.nim:34` already documents
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

### D9. Long-form guide *(P28)*

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
12. **Choosing the right API surface** (post-A1 — there is one
    public layer; this chapter says so explicitly).
13. **Future FFI** — what the planned C ABI shape will look like
    (cite D10).
14. **Cookbook of small task recipes** (delegated to D14).

Need not be complete pre-1.0; needs to exist and reflect the locked
API.

### D10. L5 FFI design note *(P9, P14, future-FFI)*

Write `docs/design/15-L5-FFI-Principles.md` mapping each principle to
its C-ABI manifestation:

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

### D11. Scope and non-goals policy *(P4)*

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

### D12. Non-JMAP import lint *(P4)* — backs D11

Add a CI lint that rejects new `import std/smtp`, `import std/imap`,
`import std/pop3`-style imports (and any obvious non-JMAP-wire
library import) under `src/`. Backs D11 with mechanical enforcement.
Same hook as H4.

### D13. RFC extension policy *(P20)*

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

### D14. Cookbook of recipes *(P28)*

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

### D16. Convenience module design note *(P27)*

Verify `convenience.nim` has a design note (in `docs/design/` or as a
comprehensive module docstring at minimum). If not, write one, citing
P6 as the constraint. The doc covers what the module is for (pipeline
combinators), what it explicitly is NOT for (semantic convenience —
see C7 charter), and how new helpers are vetted.

### D1.5. Commit `docs/policy/01-semver-and-deprecation.md` *(P1, P2, P25, P26)*

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
   `errors.nim:18` (HTTPS hint). New `when defined(<os>)` guards in
   `src/` require written justification in the policy doc.
7. **Observable-behaviour glossary** — exhaustive list of "what
   counts as observable": exported symbols, type signatures, JSON
   keys emitted, JSON structures accepted, error variant kinds,
   error message formats (after A12b), wire-byte fixture replay.
   Each row is mapped to its CI gate.

### D11.5. Commit `docs/policy/02-scope-and-non-goals.md` *(P4)*

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

### D13.5. Commit `docs/policy/03-rfc-extension-policy.md` *(P20)*

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

### D17. Codify reviewer workflow: CONTRIBUTING.md + PR template *(P1, all)*

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
   - Confirm Coverage-trace section updated if a TODO item ticked
     (F7 verifies).

### D18. Pre-1.0 freeze checklist tracker *(P1)*

The 1.0 release tag must fail if any freeze gate is unmet. Today
the gate list is dispersed across this TODO; nobody can answer
"are we ready?" in a single look.

**Action.** Create `docs/TODO/pre-1.0-freeze-checklist.md` (a
companion to this file, not a replacement). Format: one line per
freeze-gate item, status `[ ]` / `[x]`, link to the TODO item.
Categories:

- **Existence gates** — files that must exist before 1.0 (C1.1,
  D1.5, D9, D10, D11.5, D13.5, D15, D16, D17).
- **Mechanical gates** — CI lints that must pass (H1–H11).
- **Snapshot gates** — frozen files committed (A25, A26, F6).
- **Decision gates** — open choices that must be resolved (A3.5,
  B9, B11, B12, D4 devendor).
- **Test gates** — property tests that must exist (F1, A2b, A28b,
  A12b).

CI gate (`just check-freeze` or `.github/workflows/release.yml`):
the 1.0 release tag fails if any `[ ]` row remains. The
checklist file is regenerable from this TODO; F7's consistency
check covers both files.

## Section E — Defer to 1.x

Additive items that compose forward and do not block 1.0.

### E1. Async support *(P22)*

Sync `JmapClient.send` is the headline. Async lands later via the
Transport interface (A19) — alternative transports wrap `chronos`,
`puppy`, etc. themselves. Do not import `std/asyncdispatch` or
`chronos` from L1–L3; that is already the case (verified clean).

## Section F — Verification gates

Pre-1.0 freeze gates. Each must pass before tagging.

### F1. Property-test serde round-trip — explicit checklist *(P2)*

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

### F2. Public-symbol audit walk *(P5)*

High-export files to scrutinise (count of `*`-exported field/proc):

- `src/jmap_client/mail/email.nim` — 75 exports
- `src/jmap_client/methods.nim` — 54 exports
- `src/jmap_client/mail/mailbox.nim` — 37 exports
- `src/jmap_client/mail/body.nim` — 33 exports
- `src/jmap_client/mail/email_submission.nim` — 28 exports
- `src/jmap_client/errors.nim` — 26 exports

For each, ask "load-bearing public commitment?". Default to private
for anything not justified. Run after A1 (so the audit measures the
new headline surface, not the current one).

### F3. Convenience-leak check — bidirectional *(P6)*

**Forward (existing).** `grep -rn "import.*convenience"` from L3
modules (`src/jmap_client/{builder,dispatch,methods,entity}.nim` and
the `mail/*` siblings). Must return only test/external — no L3 module
imports `convenience.nim`. (Already documented at
`convenience.nim:7–10`.)

**Reverse (new).** `grep -rn
"convenience\|addQueryThenGet\|addChangesToGet\|getBoth"
src/jmap_client/{builder,dispatch,methods,entity,framework,envelope,
capabilities,session}.nim src/jmap_client/mail/*.nim` — must return
only forward references inside `convenience.nim` itself. Any
docstring in L1–L3 mentioning a convenience helper is a leak (CI
fail). P6 says "Documentation for the core does not assume the
convenience layer."

### F4. Sample CLI smoke test against three servers — CI-wired

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

### F5. Behavioural snapshot tests *(P2)*

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

### F6. Re-export hub snapshot diff in CI *(P1, P5)*

A26 names the snapshot but not the CI step. Without a named
mechanical gate, the snapshot rots silently — committers regenerate
it without scrutiny on every PR.

**Action.** Add a `just freeze-api` recipe that produces
`tests/wire_contract/public-api.txt` from the `*` exports of every
public module (`jmap_client`, `types`, `serialisation`, `protocol`,
`client`, `mail`, `convenience`, `push`, `websocket`). CI step:

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

### F7. Coverage-trace consistency check *(P1, P2)*

The Coverage-trace section at the end of this file lists, per
principle, the items addressing it. Today the trace is hand-
maintained; Agent A's audit found 13 principles where the trace
overstates coverage. Without a CI check, the trace rots.

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

### H1. Distinct-type raw-constructor lint *(P15)* — backs A8

Nimalyzer rule (or grep lint) rejecting `<DistinctTypeName>(`
invocations outside the defining `.nim` module. Inputs: the canonical
list of distinct types from enhanced A8 (auto-generated by
`grep -E "^type \w+\* = distinct" src/jmap_client/**/*.nim` plus the
manually-listed sealed case-objects).

Failure mode: any external raw construction is a CI error, with the
message "use `parse<TypeName>` smart constructor instead" and a
pointer to the principle doc P15.

**Implementation path.** `tests/lint/h1_distinct_constructors.nim`.
Wired to `just lint`. The canonical list is regenerated from the
`type \w+\* = distinct` grep on every CI run; if the regenerated
list disagrees with a hand-maintained allowlist of constructor
sites, fail.

### H2. Module-level `var` lint *(P10)* — backs D1 no-globals rule

CI test scanning `src/jmap_client/**.nim` for module-level `var`.
Excludes `src/jmap_client.nim` once L5 thread-locals land. Currently
zero violations; locks in P10.

**Implementation path.** `tests/lint/h2_no_module_var.nim`. Wired to
`just lint`. The current "zero violations" state is the test
fixture; any added module-level `var` outside the L5 boundary fails.

### H3. `{.threadvar.}` lint *(P14)* — backs D1, D10

CI grep-lint forbidding `{.threadvar.}` outside the designated FFI
module (`src/jmap_client.nim` once L5 lands; currently anywhere is
forbidden). Currently zero violations; locks in P14. The
`nim-ffi-boundary` skill must be updated in parallel (D10) so the L5
author isn't pulled toward the OpenSSL anti-pattern by their own
tooling.

**Implementation path.** `tests/lint/h3_no_threadvar.nim`. Wired to
`just lint`.

### H4. Non-JMAP import lint *(P4)* — backs D11, D12

CI lint rejecting `import std/imap`, `import std/smtp`,
`import std/pop3`, and any obvious non-JMAP-wire library import
under `src/`. Same hook as D12.

**Implementation path.** `tests/lint/h4_no_non_jmap_imports.nim`.
Wired to `just lint`. Allowlist: `std/[json, httpclient, strutils,
tables, hashes, sets, sequtils, sugar, options, times, uri,
nativesockets, net, base64, parseutils, sysrand]`. Anything else
under `src/` requires explicit allowlist entry with rationale.

**Forward-pointer for A6.** A6 introduces `std/sysrand` in
`src/jmap_client/client.nim` for the `BuilderId.clientBrand`
draw — the chosen failure mode is loud failure
(`jcvEntropyUnavailable` `ValidationError`), so `std/monotimes`
is NOT imported and no fallback path exists. When H4 lands, the
allowlist must include `std/sysrand`. The H4 lint does not yet
exist; this is a forward-pointer for whoever lands H4.

### H5. Forbidden top-level public proc patterns *(P20)* — backs D7

CI assertion: no new top-level public proc is added with names
matching forbidden patterns (e.g. `^fetch[A-Z]|^get[A-Z]|^send[A-Z]`)
outside `convenience.nim`. The closed set of public procs on
`JmapClient` is named in D7's prohibitive clause; the closed set of
top-level public procs in `jmap_client.nim` is empty (it is a re-
export hub only).

**Implementation path.** `tests/lint/h5_forbidden_top_level_procs.nim`.
Wired to `just lint`.

### H6. License hygiene *(P25)* — backs D1

`reuse lint` runs in CI (already in `just ci`). Verify `LICENSES/`
contains only referenced licenses. Audit at freeze time: prune
`Apache-2.0.txt` and `MIT.txt` if not referenced by any
SPDX-License-Identifier in the repo. Add this audit as a pre-1.0 gate.

**Implementation path.** `tests/lint/h6_license_audit.nim` runs at
the freeze gate; `reuse lint` runs continuously. The freeze gate
fails if `LICENSES/` contains entries unreferenced by any
`SPDX-License-Identifier` header in `src/`, `tests/`, or `docs/`.

### H7. Convenience charter lint *(P6, P9)* — backs C7, C9, F3

`convenience.nim` may export only procs returning core types and
must not introduce new public types (C9). L1–L3 docstrings must
not mention convenience helpers (F3 reverse leak check).

**Implementation path.** `tests/lint/h7_convenience_charter.nim`.
Wired to `just lint`. Two checks:

1. `grep "^type \w\+\* =" src/jmap_client/convenience.nim` returns
   only the grandfathered allowlist (currently empty post-C9).
2. `grep -rn "addQueryThenGet\|addChangesToGet\|getBoth" src/jmap_client/{builder,dispatch,methods,entity,framework,envelope,capabilities,session}.nim src/jmap_client/mail/*.nim`
   returns nothing.

Either check failing fails CI.

### H8. `.get()` invariant comment lint — locks existing project rule

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

### H9. Catch-all `else` over finite enum lint *(P18, P20)*

The principles doc's anti-pattern list explicitly forbids
catch-all `else` on `case` statements over finite enums — adding a
variant must force compile errors at every consuming site. Nim's
exhaustiveness checker covers this for sum-type case objects, but
finite-enum `case`s with `else: discard` slip through.

**Implementation path.** `tests/lint/h9_no_catchall_else.nim`.
Wired to `just lint`. Logic: AST-walk every `case` whose discriminator
is an enum type defined under `src/jmap_client/`; flag any `else:
discard` arm. Whitelisted: enums with explicit `*Unknown` catch-all
variants (`MethodName`, `CapabilityKind`, `RequestErrorType`,
`MethodErrorType`, `SetErrorType`) where `else` is the documented
catch-all path; require an inline `# catch-all by design` comment
on the `else:` arm.

### H10. Internal-boundary lint *(P5)* — backs A1

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

**Current-state assertion.** Zero violations under the post-A1 layout.

### H11. Typed-builder JsonNode lint *(P19)* — backs A5

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

## Coverage trace — every principle to at least one item

Every principle has at least one TODO item that, if executed, brings
the codebase into alignment. Every row also names the **verification
gate** locking the alignment in (CI lint, snapshot, property test,
or existence file). F7 (Coverage-trace consistency check) verifies
this section against the item bodies on every CI run; do not
hand-edit the principle annotations without running F7 locally.

Status legend:

- **🟢 Verified** — item shipped AND verification gate runs.
- **🟡 Planned** — item listed; gate named; not yet implemented.
- **🔴 Open** — choice not yet made; freeze-blocking.

| Principle | Items | Gate | Status |
|---|---|---|---|
| P1 (lock contract) | A1, A1b, A2, A2b, A4, A6, A11, A13, A16, A25, A25b, A26, D1, D1.5, D4, D5, D17, D18, F6, F7 | API snapshot diff (F6); freeze checklist (D18) | 🟡 |
| P2 (tests) | A25, A28b, D2, D3, F1, F5 | Property tests (F1); wire-byte fixtures (D3) | 🟡 |
| P3 (overloads not `_v2`) | C2, C3, D1.5 (no-suffix rule) | H5 lint; review | 🟡 |
| P4 (scope) | D11, D11.5, D12, H4 | H4 non-JMAP-import lint | 🟡 |
| P5 (single layer) | A1, A1b, A6, A9, A10, A14, F2, F6 | H5; H10; F6 snapshot | 🟡 |
| P6 (convenience quarantine) | C7, C9, F3, D16, H7 | H7 charter lint | 🟡 |
| P7 (wrap rate) | A12, A12b, B5, C1, C1.1, C2–C5, C8, F4 | F4 CLI smoke test | 🟡 |
| P8 (opaque handles) | A6, A6.5, A6.6, A7b, A9, A13, A27, A28, A28b | F2 audit; H1 | 🟡 |
| P9 (two contexts max) | A6.5, A6.6, A7, A7b, B9, C9, D10 | H7; B9 resolution | 🔴 (B9 open) |
| P10 (no globals) | D1.5 (no-globals rule), H2 | H2 lint | 🟡 |
| P11 (no global callbacks) | D1.5 (no-callbacks rule), D10 | review; future H10 once L5 lands | 🟡 |
| P12 (memory ownership in types) | A13, B10 | review | 🟡 |
| P13 (one error rail) | A6, A12, A12b | H8 `.get()` invariant lint | 🟡 |
| P14 (no thread-local errors) | D10, H3 | H3 lint | 🟡 |
| P15 (smart constructors) | A8, A15 (SerializedSort/Filter), H1 | H1 lint | 🟡 |
| P16 (preconditions in types) | A6, A6.5, A6.6, A7b, A29, B3, B4, B6, B11, B12 | H9; B11/B12 resolution | 🔴 (B11, B12 open) |
| P17 (one config surface) | A14, A20, A21 | review; F6 snapshot | 🟡 |
| P18 (sum types over flag soup) | A6, B1, B2, B7, B8, H9 | H9 catch-all lint | 🟡 |
| P19 (schema-driven types) | A2, A2b, A3, A3.5, A4, A5, A14, A15, A16, A17, A18, A21, A22, A22b, A28, A28b | H11 typed-builder lint (A5); A22b inline docstrings; F1 | 🟡 |
| P20 (additive variants) | A11, A23, A24, D7, D13, D13.5, H5 | H5 lint | 🟡 |
| P21 (lifecycle types) | A6, A6.5, A6.6, A7, A7b, A23, A24, A27, A28 | type-shape snapshot (A25) | 🟡 |
| P22 (sync first, async via interface) | A6, A19, E1 | review; transport interface lands first | 🟡 |
| P23 (push as separate type) | A23, A24, D13.5 | existence gate (A23, A24, D13.5 files) | 🟡 |
| P24 (threading invariant) | A6, A13, D8 | D8 docstring footer; review | 🟡 |
| P25 (license) | D1.5, H6 | `reuse lint`; H6 freeze gate | 🟡 |
| P26 (build) | current `mise.toml`/`justfile`/`.nimble`; D1.5 documents the single `when defined(ssl)` concession in `errors.nim:18` | review | 🟢 |
| P27 (architecture docs) | D7, D9, D16 | existence gates | 🟡 |
| P28 (long-form docs) | D9, D10, D14 | existence gates | 🟡 |
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
| Stringly-typed APIs | A2, A2b, A3, A3.5, A4, A5, A14, A15, A17, A18, A21, A22b | H11 typed-builder lint; H7 (convenience charter); reviewer grep on `JsonNode` outside Documented exceptions |
| Multiple coexisting public layers | A1, A1b, A9, A10 | F6 snapshot |
| Convenience layer leaking | C7, C9, F3, H7 | H7 lint |
| Catch-all `else` on finite enums | A11, H9 | H9 lint |
| `.get()` without invariant | (rule) + H8 | H8 lint |
| Last-error thread-locals | D10, H3 | H3 lint |
| Behaviour changes in patch releases | D1.5 (policy) | wire-byte fixture diff (D3) |
| Renaming after 1.0 | D1.5 (policy), H5 | F6 snapshot diff; H5 lint |

### Concrete-decisions checklist

The principles doc's "Concrete decisions to make before 1.0" list
contains 10 items. Each must be either delivered by a TODO item
**and** have a verification gate. The 1.0 release tag fails (D18)
if any row is unticked.

| # | Decision | Item | Gate |
|---|---|---|---|
| 1 | Choose the public layer | A1, A1b, A6 | F6 snapshot |
| 2 | Public symbol audit | A1, A6, F2 | F6 snapshot |
| 3 | Lock the wire contract | F1, A2b, A28b, D3 | property tests + fixture diff |
| 4 | Name the Push channel type | A23, D13.5 | existence gate |
| 5 | Threading invariant | D8 | docstring footer audit |
| 6 | Sample consumer | C1, C1.1, F4 | CI smoke + AUDIT.md |
| 7 | Long-form guide | D9 | existence gate |
| 8 | License confirmation | H6 | `reuse lint`; freeze audit |
| 9 | L5 FFI design note | D10 | existence gate |
| 10 | Convenience module quarantine | C7, C9, F3, D16, H7 | H7 lint + grep audit |
