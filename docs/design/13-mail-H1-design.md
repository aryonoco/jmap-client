# RFC 8621 JMAP Mail — Design H1: Type-Lift Completion

H1 closes the RFC 8621 type-lift surface. Every RFC 8621 invariant is
either encoded in the type system or carried by a smart constructor
whose failure lives on the `Result` error rail.

The thesis:

> Replace runtime conventions with type-level guarantees. Illegal states
> unrepresentable. Invariants enforced by `parseX`. Errors carried as
> named variants on domain ADTs. A single translator projects each
> domain ADT to the wire error shape; adding a variant forces a compile
> error at exactly one site.

H1 covers five surfaces:

1. **Implicit-call compound handles** (RFC 8620 §5.4) — the generic
   `CompoundHandles[A, B]` paired with one-line type-alias
   specialisations carrying domain vocabulary.
2. **Back-reference chains** (RFC 8620 §3.7) — `ChainedHandles[A, B]`
   for arity-2 chains and a purpose-built `EmailQueryThreadChain`
   record for the arity-4 first-login workflow.
3. **`ParsedSmtpReply`** — `ReplyCode` + `Opt[EnhancedStatusCode]` +
   text + raw bytes, with atomic detectors composed via `?` and a
   single `SmtpReplyViolation → ValidationError` translator.
4. **Compile-time participation gates** — `registerCompoundMethod` and
   `registerChainableMethod` templates surface mis-registrations at
   module scope.
5. **RFC §10 IANA traceability matrix** — a complete cross-reference
   from every registered RFC 8621 §10 item to a symbol in source.

---

## Table of Contents

- §1. Scope
- §2. `CompoundHandles[A, B]` — RFC 8620 §5.4 compound handles
- §3. `ChainedHandles[A, B]` and `addEmailQueryWithSnippets`
- §4. `EmailQueryThreadChain` and `addEmailQueryWithThreads`
- §5. `ParsedSmtpReply` — RFC 5321 §4.2 + RFC 3463 §2 parsed once
- §6. RFC 8621 §10 IANA traceability matrix
- §7. Decision Traceability Matrix
- §8. Appendix: Deliberately Out of Scope

---

## 1. Scope

### 1.1. Thesis

H1 is a type-lift, not a new method surface. Every line either removes
runtime ambiguity by hoisting a convention into the type system, or
removes structural duplication by promoting a hand-rolled shape into a
generic. Nothing H1 adds is new wire behaviour — RFC 8621 compliance
at Part G1 is already complete; H1 governs the Nim surface that
mediates it.

The discipline is three-part:

- **Compile-time honesty.** Invariants the RFC states in prose (the
  first-login workflow shape, the SMTP Reply-code grammar, the sibling
  call-id convention of compound methods) are shapes the compiler can
  see — generics parameterised by response type, distinct newtypes per
  grammatical production, domain ADTs whose exhaustive `case` forces
  one compile error per violation class.
- **Single translator boundary.** Every domain ADT has exactly one
  `toValidationError` (or `toSerdeViolation`) function; adding a
  variant forces one compile error at one site. Detection stays
  shape-agnostic; the translator handles all wire-format concerns.
- **Clean-refactor.** No `{.deprecated.}` pragma, no
  `type OldName* = NewName` alias, no proxy accessor.

### 1.2. Design invariants

Every section of H1 satisfies all eight:

1. **Single translator invariant.** Every domain ADT has exactly one
   `toValidationError` (or `toSerdeViolation`) function; adding a
   variant forces one compile error at one site. Examples:
   `toValidationError(SmtpReplyViolation, raw)` at
   `submission_status.nim:190`, `toValidationError(Conflict)` at
   `email_update.nim`.

2. **Distinct newtype invariant.** Every semantically-distinct
   numeric or tokenised string is a distinct type with a smart
   constructor; no bare `uint16`/`string` carries domain meaning past
   the serde boundary. Examples: `ReplyCode`, `SubjectCode`,
   `DetailCode` at `submission_status.nim:100-117`, alongside the
   pre-H1 G1 examples (`HoldForSeconds`, `MtPriority`,
   `RFC5321Keyword`).

3. **Module-pragma purity invariant.** Every L1–L3 module sits under
   `{.push raises: [], noSideEffect.}`, so any `func` defined in the
   module is automatically pure and total. Pragma inheritance does
   the work — no per-routine annotation required.

4. **Parse-once invariant.** The rich type is constructed at the
   serde boundary and carried in the interior. No interior
   re-parsing. Example: `DeliveryStatus.smtpReply: ParsedSmtpReply`
   at `submission_status.nim:515`.

5. **Wire-byte-identical invariant.** Each parsed type carries a
   deterministic emission for canonical inputs; existing serde
   round-trip tests pin the invariant. Non-canonical inputs are
   canonicalised with an explicit documented policy (§5.7).

6. **Stdlib-delegation invariant.** If stdlib has the right
   primitive, use it — no wrapper. `toHashSet`, `withValue`,
   `containsOrIncl`, `fieldPairs` are the vocabulary.

7. **Compile-time participation invariant.** Any method that joins a
   compound or a chain is gated by a registration template checked
   at module scope, not at first call site. See `registerCompoundMethod`
   and `registerChainableMethod` at `dispatch.nim:266-282, 315-324`,
   invoked at `mail_entities.nim:371-384`.

8. **Clean-refactor invariant.** No `{.deprecated.}` pragma, no
   `type Old* = New` alias, no proxy accessor, no
   `when defined(...)` compatibility shim survives anywhere in
   `src/` or `tests/`. The `ParsedSmtpReply.raw*` field exists for
   diagnostic fidelity, not as a back-compat escape hatch.

### 1.3. Module map

| File | Surface defined |
|---|---|
| `src/jmap_client/dispatch.nim` | `CompoundHandles[A, B]` / `CompoundResults[A, B]` (§5.4); `ChainedHandles[A, B]` / `ChainedResults[A, B]` (§3.7); overloaded `getBoth` extractors; `registerCompoundMethod` / `registerChainableMethod` gates |
| `src/jmap_client/methods_enum.nim` | `RefPath` enum — every RFC 8620 §3.7 JSON Pointer back-reference path the codebase uses, including `rpListThreadId` and `rpListEmailIds` for the first-login chain |
| `src/jmap_client/mail/mail_builders.nim` | `EmailCopyHandles` / `EmailCopyResults` type-alias specialisations; `addEmailCopyAndDestroy` compound builder; `addEmailGetByRef`, `addThreadGetByRef` back-reference siblings; `EmailQueryThreadChain` / `EmailQueryThreadResults` records, monomorphic `getAll` extractor, `DefaultDisplayProperties` const, `addEmailQueryWithThreads` builder |
| `src/jmap_client/mail/mail_methods.nim` | `addSearchSnippetGetByRef`, `EmailQuerySnippetChain` type alias, `addEmailQueryWithSnippets` |
| `src/jmap_client/mail/mail_entities.nim` | `registerCompoundMethod` and `registerChainableMethod` invocations at module scope |
| `src/jmap_client/mail/email_submission.nim` | `EmailSubmissionHandles` / `EmailSubmissionResults` type-alias specialisations |
| `src/jmap_client/mail/submission_builders.nim` | `addEmailSubmissionAndEmailSet` compound builder |
| `src/jmap_client/mail/submission_status.nim` | `ReplyCode`, `StatusCodeClass`, `SubjectCode`, `DetailCode`, `EnhancedStatusCode`, `ParsedSmtpReply`, `SmtpReplyViolation` (15 variants), atomic detectors, composite parser, single translator, `parseSmtpReply` / `renderSmtpReply` entry points |
| `src/jmap_client/mail/serde_submission_status.nim` | `DeliveryStatus.fromJson` / `toJson` route through `parseSmtpReply` / `renderSmtpReply` |

H1 surface is entirely L1–L3. No C ABI, no L4 transport, no L5 export
surface.

---

## 2. `CompoundHandles[A, B]` — RFC 8620 §5.4 compound handles

### 2.1. Shape

RFC 8620 §5.4 implicit calls share a `MethodCallId` between the
primary method and the server-emitted follow-up. The handle for the
follow-up carries both the call-id *and* the expected method name — a
`NameBoundHandle[T]` (`dispatch.nim:60-72`) — so dispatch can
disambiguate the sibling invocations without a filter argument at the
extraction site.

The compound-handle generic lives alongside `ResponseHandle[T]` and
`NameBoundHandle[T]` in `dispatch.nim:240-264`:

```nim
type CompoundHandles*[A, B] {.ruleOff: "objects".} = object
  ## Paired handles for RFC 8620 §5.4 implicit-call compound methods.
  ## ``primary`` is the declared method's response (type ``A``);
  ## ``implicit`` is the server-emitted follow-up response (type ``B``),
  ## carrying a method-name filter because it shares the primary's
  ## call-id per RFC 8620 §5.4.
  primary*:  ResponseHandle[A]
  implicit*: NameBoundHandle[B]

type CompoundResults*[A, B] {.ruleOff: "objects".} = object
  primary*:  A
  implicit*: B

func getBoth*[A, B](
    dr: DispatchedResponse, handles: CompoundHandles[A, B]
): Result[CompoundResults[A, B], GetError] =
  mixin fromJson
  let primary  = ?dr.get(handles.primary)
  let implicit = ?dr.get(handles.implicit)
  ok(CompoundResults[A, B](primary: primary, implicit: implicit))
```

`{.ruleOff: "objects".}` matches the existing per-record discipline
elsewhere in the codebase.

### 2.2. Type-alias specialisations

Two compound participants exist, each with a one-line type-alias
specialisation. Domain vocabulary lives at the type-alias level; field
names reflect RFC 8620 §5.4 vocabulary (`primary`/`implicit`).

In `src/jmap_client/mail/mail_builders.nim:304-314`:

```nim
type EmailCopyHandles* =
  CompoundHandles[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem, PartialEmail]]

type EmailCopyResults* =
  CompoundResults[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem, PartialEmail]]
```

In `src/jmap_client/mail/email_submission.nim:605-615`:

```nim
type EmailSubmissionHandles* =
  CompoundHandles[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem, PartialEmail]]

type EmailSubmissionResults* =
  CompoundResults[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem, PartialEmail]]
```

Field access at consumer sites uses the spec-verbatim names:
`handles.primary`, `handles.implicit`, `results.primary`,
`results.implicit`. The domain vocabulary (the type-alias name —
`EmailCopyHandles` vs `EmailSubmissionHandles`) names *which*
compound the call site is in.

### 2.3. Compile-time participation gate (`registerCompoundMethod`)

Each compound participant is registered at module scope so a missing
or malformed registration surfaces at module load, not at first
builder invocation (`dispatch.nim:266-282`):

```nim
template registerCompoundMethod*(Primary, Implicit: typedesc) =
  ## Compile-checks that ``Primary`` parametrises ``ResponseHandle``
  ## and that ``Implicit`` parametrises ``NameBoundHandle``.
  static:
    when not compiles(ResponseHandle[Primary]):
      {.error: "registerCompoundMethod: " & $Primary &
        " cannot back a ResponseHandle".}
    when not compiles(NameBoundHandle[Implicit]):
      {.error: "registerCompoundMethod: " & $Implicit &
        " not NameBoundHandle-compatible".}
```

Applied in `src/jmap_client/mail/mail_entities.nim:371-372`:

```nim
registerCompoundMethod(CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem, PartialEmail])
registerCompoundMethod(EmailSubmissionSetResponse, SetResponse[EmailCreatedItem, PartialEmail])
```

Adding a new §5.4 compound method requires a matching
`CompoundHandles[...]` type alias and a `registerCompoundMethod`
invocation; omitting the latter is a static assertion failure.

### 2.4. Wire-byte identicality

`CompoundHandles` and its specialisations are structural — wire bytes
flow through `addEmailCopyAndDestroy` (`mail_builders.nim:320-351`)
and `addEmailSubmissionAndEmailSet` (`submission_builders.nim:129-169`)
unchanged from the underlying `addCopy` and `addSet` builders.
Regressions are pinned by the existing serde round-trip fixtures:

- `tests/serde/mail/tserde_email_copy.nim` — `EmailCopyHandles`
  extraction round-trips.
- `tests/serde/mail/tserde_email_submission.nim` — analogous coverage
  for `EmailSubmissionHandles`.
- `tests/serde/mail/tserde_submission_status.nim` — `DeliveryStatus`
  serde, indirectly exercised whenever an EmailSubmission carrying a
  `deliveryStatus` is round-tripped.

### 2.5. Decisions

- **H1. Promotion threshold — Rule-of-Two, not Rule-of-Three.** Two
  compound sites is the threshold because the structural repetition is
  *exact* (field shapes match to the byte, `getBoth` bodies are
  identical modulo type substitution) and §3–§4 confirm the
  §5.4-vs-§3.7 split is real architecture rather than a coincidence of
  arity. Options considered: (A) keep per-site records and `getBoth`
  bodies; (B) Rule-of-Three (defer until a third compound surface).
  Chose Rule-of-Two because the second axis of variation
  (`NameBoundHandle` on the implicit side) is itself the stable
  feature; Rule-of-Three remains the default elsewhere.

- **H2. Field names `primary`/`implicit`.** Spec-verbatim:
  RFC 8620 §5.4 calls them the *call* and the *implicit call*. Domain
  vocabulary (`copy`, `destroy`, `submission`, `emailSet`) survives at
  the type-alias level, where it names *which* compound this is.
  Options considered: (A) domain-named record fields
  (`copy`/`destroy`/`submission`/`emailSet`); (B) spec-verbatim
  (`primary`/`implicit`); (C) proxy accessors atop domain names. Chose
  B for "RFC vocabulary at field level; domain vocabulary at
  type-alias level."

- **H3. `getBoth` lives in `dispatch.nim`.** The generic is fully
  parametric in `A` and `B`; there is no mail-specific obligation. It
  composes from `ResponseHandle[T]` and `NameBoundHandle[T]`, both of
  which live in `dispatch.nim`. Options considered: (A) `dispatch.nim`
  alongside the primitives it composes from; (B) a mail-specific
  module. Chose A so any future non-mail §5.4 compound can reuse the
  generic without a gratuitous import.

- **H4. Compile-time gate at module scope via
  `registerCompoundMethod(Primary, Implicit)`.** Mirrors
  `registerSettableEntity(T)` at `entity.nim:128`. Options considered:
  (A) no gate; (B) per-call-site assertion; (C) module-scope
  registration template. Chose C so regression surfaces at module
  load, not at first builder invocation.

---

## 3. `ChainedHandles[A, B]` and `addEmailQueryWithSnippets`

### 3.1. A sibling generic, not a subtype of `CompoundHandles`

RFC 8620 §3.7 back-reference chains and RFC 8620 §5.4 implicit calls
are superficially similar — both tie two responses together in one
request — but structurally distinct:

| | §5.4 implicit call | §3.7 back-reference chain |
|---|---|---|
| Number of invocations | 1 request, 2 responses | 2 requests, 2 responses |
| Call-id | 1, shared | 2, distinct |
| Disambiguation | method-name filter (`NameBoundHandle`) | distinct call-ids (plain `ResponseHandle`) |
| Extraction | `NameBoundHandle` overload on the implicit side | plain `get[T]` on both |
| Typical RFC usage | `onSuccessDestroyOriginal`, `onSuccessUpdateEmail` | `#ids` back-reference to a preceding query's `/ids` |

A unified super-generic would either (a) carry a superfluous
method-name filter on the §3.7 side, which is noise in its semantics;
or (b) bury the §5.4 invariant under an `Opt[MethodName]` evaluated
only sometimes. Two sibling generics describe two RFC mechanisms; the
choice between them at a call site IS the spec-level distinction the
builder is making.

### 3.2. Shape

In `dispatch.nim:288-313`:

```nim
type ChainedHandles*[A, B] {.ruleOff: "objects".} = object
  ## Paired handles for RFC 8620 §3.7 back-reference chains. Each
  ## handle binds a distinct ``MethodCallId``; no method-name filter
  ## is needed because the call-ids are unique.
  first*:  ResponseHandle[A]
  second*: ResponseHandle[B]

type ChainedResults*[A, B] {.ruleOff: "objects".} = object
  first*:  A
  second*: B

func getBoth*[A, B](
    dr: DispatchedResponse, handles: ChainedHandles[A, B]
): Result[ChainedResults[A, B], GetError] =
  mixin fromJson
  let first  = ?dr.get(handles.first)
  let second = ?dr.get(handles.second)
  ok(ChainedResults[A, B](first: first, second: second))
```

`getBoth` is overloaded for both `CompoundHandles` and
`ChainedHandles`; both overloads live in `dispatch.nim` and the
compiler picks by argument type (no structural overlap).

### 3.3. `addEmailQueryWithSnippets`

The builder emits two invocations: `Email/query` followed by
`SearchSnippet/get` with a `ResultReference` that chains the snippet
request to the query's `/ids`. The RFC 8621 §4.10 example shows this
exact pattern.

In `src/jmap_client/mail/mail_methods.nim:267-297`:

```nim
type EmailQuerySnippetChain* =
  ChainedHandles[QueryResponse[Email], SearchSnippetGetResponse]

func addEmailQueryWithSnippets*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = false,
): (RequestBuilder, EmailQuerySnippetChain) =
  let (b1, queryHandle) =
    addEmailQuery(b, accountId, Opt.some(filter), sort, queryParams, collapseThreads)
  let emailIdsRef = initResultReference(
    resultOf = callId(queryHandle), name = mnEmailQuery, path = rpIds
  )
  let (b2, snippetHandle) =
    addSearchSnippetGetByRef(b1, accountId, filter, emailIdsRef = emailIdsRef)
  (b2, EmailQuerySnippetChain(first: queryHandle, second: snippetHandle))
```

`addSearchSnippetGetByRef` (`mail_methods.nim:248-265`) is the
back-reference sibling of `addSearchSnippetGet`
(`mail_methods.nim:221-241`); the latter takes a literal
`firstEmailId: Id` + `restEmailIds: seq[Id]` cons-cell and cannot
express a back-reference, so the two builders coexist:
`addSearchSnippetGet` for direct callers, `addSearchSnippetGetByRef`
for chain builders.

### 3.4. Filter handling and invariants

- **`filter` is mandatory**, not `Opt[Filter[EmailFilterCondition]]`.
  RFC 8621 §5.1 ¶2 is explicit: SearchSnippet/get returns snippets for
  the given search criteria. A snippet request without a filter is
  semantically void — the library refuses to construct one at the type
  level.
- **Filter duplicated literally on the wire**, not shared via a second
  `ResultReference`. RFC 8620 §3.7 permits both: the chain builder
  could emit a single `filter` in the `Email/query` invocation and
  reference it from the snippet invocation. Literal duplication is
  simpler and each invocation stays self-contained; if a future
  optimisation materialises a `#filter` reference path, §8.6 covers
  adding it.
- **Empty-ids back-reference is legal.** If the `Email/query` resolves
  to zero ids, the `SearchSnippet/get` request receives an empty
  `emailIds` array via the back-reference. RFC 8620 §5.1 does not
  forbid this. The cons-cell discipline of `addSearchSnippetGet`
  enforces non-emptiness at compile time for the direct-call case;
  that discipline does not propagate through the back-reference case
  because the back-reference target cannot be statically known. A
  caller wanting the non-empty-by-construction guarantee builds two
  invocations manually.

### 3.5. Compile-time participation gate (`registerChainableMethod`)

Analogue of `registerCompoundMethod` at `dispatch.nim:315-324`:

```nim
template registerChainableMethod*(Primary: typedesc) =
  ## Compile-checks that ``Primary`` parametrises ``ResponseHandle``,
  ## so a back-reference to it can be constructed with a typed
  ## response handle.
  static:
    when not compiles(ResponseHandle[Primary]):
      {.error: "registerChainableMethod: " & $Primary &
        " cannot back a ResponseHandle".}
```

Applied in `src/jmap_client/mail/mail_entities.nim:378-384` to every
response type that fronts a chain step:

```nim
registerChainableMethod(QueryResponse[Email])
registerChainableMethod(GetResponse[Email])
registerChainableMethod(GetResponse[thread.Thread])
```

`QueryResponse[Email]` fronts `addEmailQuery` (the first step in
`addEmailQueryWithSnippets` and `addEmailQueryWithThreads`).
`GetResponse[Email]` and `GetResponse[Thread]` are intermediate steps
in `addEmailQueryWithThreads` whose responses chain out further.
Adding a new chain whose first step references an unregistered method
is a static assertion failure at module load.

### 3.6. Decisions

- **H5. `ChainedHandles[A, B]` as a sibling to `CompoundHandles[A, B]`,
  not a subtype or unified super-generic.** Type-level honesty over
  spurious unification. Options considered: (A) force into one generic
  with `Opt[MethodName]`; (B) subtype; (C) sibling generic. Chose C.

- **H6. `filter: Filter[EmailFilterCondition]` is mandatory, not
  `Opt[Filter[...]]`.** RFC 8621 §5.1 ¶2 forbids a snippet request
  without a filter; the library lifts that obligation into the type
  of the builder argument.

- **H7. Filter duplicated literally on the wire, not shared via a
  second `ResultReference`.** RFC 8620 §3.7 permits both; chose
  literal duplication for simplicity and wire-level self-containment.

- **H8. Cons-cell non-emptiness of `addSearchSnippetGet` does NOT
  propagate into the back-reference chain.** A back-reference resolves
  at request-execution time, not at compile time. If the back-reference
  target is empty, the library still emits a valid (if degenerate)
  request per RFC.

- **H9. Compile-time gate via `registerChainableMethod(Primary)`.**
  Mirrors `registerCompoundMethod`. Emitted at module scope in
  `mail_entities.nim` for every response type that fronts a chain
  step.

---

## 4. `EmailQueryThreadChain` and `addEmailQueryWithThreads`

### 4.1. A purpose-built record, not an arity-4 generic

RFC 8621 §4.10's canonical "first-login" workflow is a four-invocation
back-reference chain:

1. `Email/query` — find the messages.
2. `Email/get` `{threadId}` — fetch only the thread ids of those messages.
3. `Thread/get` — fetch the threads and the email ids within each.
4. `Email/get` — fetch the full display properties for the emails in
   those threads.

Structurally this is a four-step chain — but the parametric shape
stops there. The four steps have specific domain meaning (query,
threadIdFetch, threads, displayGet); the back-reference paths are
three distinct RFC 6901 JSON Pointers (`/ids`, `/list/*/threadId`,
`/list/*/emailIds`); and there is one inhabitant — the first-login
workflow itself.

A generic `ChainedHandles4[A, B, C, D]` with `first`/`second`/`third`/
`fourth` fields would have the shape of parametric abstraction without
the substance: it would satisfy no law that a purpose-built record
does not, and it would trade domain-named fields for positional ones.
The §2 "domain-at-type-alias, structural-at-field-level" factoring
relies on a second inhabitant (a second type alias over the same
generic) to anchor the domain; with one inhabitant, that layer
collapses, and positional fields would have no compensating domain
anchor.

`ChainedHandles[A, B]` of §3 IS parametric — two-step back-reference
chains have a real law (RFC 8620 §3.7 distinct call-ids, independent
extraction). Arity 4 stays concrete until a second arity-4 chain
materialises; §8.4 spells out the retrofit.

### 4.2. Shape

In `src/jmap_client/mail/mail_builders.nim:367-403`:

```nim
type EmailQueryThreadChain* {.ruleOff: "objects".} = object
  ## Paired handles for the RFC 8621 §4.10 first-login workflow.
  ## Each handle binds a distinct ``MethodCallId``; the domain role
  ## of each step lives at the field level because there is no
  ## generic above this record to carry it.
  queryH*:         ResponseHandle[QueryResponse[Email]]
  threadIdFetchH*: ResponseHandle[GetResponse[Email]]
  threadsH*:       ResponseHandle[GetResponse[thread.Thread]]
  displayH*:       ResponseHandle[GetResponse[Email]]

type EmailQueryThreadResults* {.ruleOff: "objects".} = object
  ## Plain domain names; the enclosing type name conveys "responses".
  query*:         QueryResponse[Email]
  threadIdFetch*: GetResponse[Email]
  threads*:       GetResponse[thread.Thread]
  display*:       GetResponse[Email]

func getAll*(
    dr: DispatchedResponse, handles: EmailQueryThreadChain
): Result[EmailQueryThreadResults, GetError] =
  ## Extract all four responses from the first-login workflow.
  ## Monomorphic over ``EmailQueryThreadChain`` — not a parametric
  ## ``getAll[A, B, C, D]``, because the record it serves is not
  ## parametric either.
  mixin fromJson
  let query         = ?dr.get(handles.queryH)
  let threadIdFetch = ?dr.get(handles.threadIdFetchH)
  let threads       = ?dr.get(handles.threadsH)
  let display       = ?dr.get(handles.displayH)
  ok(EmailQueryThreadResults(
    query: query, threadIdFetch: threadIdFetch,
    threads: threads, display: display))
```

`getAll` is co-located with the builder in `mail_builders.nim` rather
than in `dispatch.nim` because the extractor is no more parametric
than the builder it serves.

### 4.3. `addEmailQueryWithThreads`

In `src/jmap_client/mail/mail_builders.nim:405-470`:

```nim
func addEmailQueryWithThreads*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    sort: seq[EmailComparator] = @[],
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = true,
    displayProperties: seq[string] = DefaultDisplayProperties,
    displayBodyFetchOptions: EmailBodyFetchOptions = EmailBodyFetchOptions(
      fetchBodyValues: bvsAll, maxBodyValueBytes: Opt.some(UnsignedInt(256))),
): (RequestBuilder, EmailQueryThreadChain) =
  let sortOpt =
    if sort.len > 0: Opt.some(sort)
    else:            Opt.none(seq[EmailComparator])

  let (b1, queryH) = addEmailQuery(
    b, accountId, Opt.some(filter), sortOpt, queryParams, collapseThreads)

  let (b2, threadIdFetchH) = addEmailGetByRef(
    b1, accountId,
    idsRef = initResultReference(
      resultOf = callId(queryH), name = mnEmailQuery, path = rpIds),
    properties = Opt.some(@["threadId"]))

  let (b3, threadsH) = addThreadGetByRef(
    b2, accountId,
    idsRef = initResultReference(
      resultOf = callId(threadIdFetchH), name = mnEmailGet,
      path = rpListThreadId))

  let (b4, displayH) = addEmailGetByRef(
    b3, accountId,
    idsRef = initResultReference(
      resultOf = callId(threadsH), name = mnThreadGet,
      path = rpListEmailIds),
    properties = Opt.some(displayProperties),
    bodyFetchOptions = displayBodyFetchOptions)

  (b4, EmailQueryThreadChain(
    queryH: queryH, threadIdFetchH: threadIdFetchH,
    threadsH: threadsH, displayH: displayH))
```

Argument shapes:

- `filter` is mandatory — RFC 8621 §4.10 ¶1 first-login always filters
  to a user-visible mailbox scope.
- `sort` defaults to `@[]`; an empty seq translates to `Opt.none` for
  the underlying `addEmailQuery`.
- `collapseThreads` defaults to `true` per RFC §4.10 example.
- `displayProperties` defaults to `DefaultDisplayProperties` (§4.4).
- `displayBodyFetchOptions` defaults to `fetchBodyValues: bvsAll` with
  a 256-byte cap per the RFC §4.10 example. The full
  `EmailBodyFetchOptions` struct flows through to `addEmailGetByRef`,
  so a caller can override `bodyProperties` / `fetchBodyValues` /
  `maxBodyValueBytes` independently if needed. `fetchBodyValues` is a
  single `BodyValueScope` enum (`bvsNone` / `bvsText` / `bvsHtml` /
  `bvsTextAndHtml` / `bvsAll`) replacing the three RFC booleans with
  one domain-meaningful choice.

The four back-reference invocations use `addEmailGetByRef`
(`mail_builders.nim:167-186`) and `addThreadGetByRef`
(`mail_builders.nim:192-205`) — siblings of the literal-ids overloads
that accept a `ResultReference` for `ids` and route it through the
generic `addGet[T]`'s `Referencable` path.

### 4.4. `DefaultDisplayProperties`

The RFC 8621 §4.10 example enumerates nine display properties for the
fourth invocation. `mail_builders.nim:358-365` exposes them as a
module-level `const`:

```nim
const DefaultDisplayProperties*: seq[string] = @[
  "threadId", "mailboxIds", "keywords", "hasAttachment",
  "from", "subject", "receivedAt", "size", "preview",
]
```

Callers who want different properties pass their own list to
`displayProperties`. The const is one named, auditable default.

### 4.5. Back-reference path constants — the `RefPath` enum

RFC 8621 §4.10 uses three JSON Pointer paths as back-reference
targets: `/ids`, `/list/*/threadId`, `/list/*/emailIds`. All three are
variants of the existing `RefPath` enum at
`src/jmap_client/methods_enum.nim:69-80`:

```nim
type RefPath* = enum
  ## JMAP result-reference paths (RFC 8620 §3.7) — the JSON Pointer
  ## fragments a chained method call reads out of a prior invocation's
  ## response.
  rpIds                = "/ids"
  rpListIds            = "/list/*/id"
  rpAddedIds           = "/added/*/id"
  rpCreated            = "/created"
  rpUpdated            = "/updated"
  rpUpdatedProperties  = "/updatedProperties"
  rpListThreadId       = "/list/*/threadId"
  rpListEmailIds       = "/list/*/emailIds"
```

Builder call sites use the typed constructor with `rpX` values
directly — no stringification, no parallel enum:

```nim
path = rpIds            # "/ids"
path = rpListThreadId   # "/list/*/threadId"
path = rpListEmailIds   # "/list/*/emailIds"
```

Adding a future back-reference path is a one-line variant addition;
§8.6 covers when that is justified.

### 4.6. Decisions

- **H10. Purpose-built `EmailQueryThreadChain` record, not an arity-4
  generic.** Abstraction requires both structural repetition AND a
  parametric law. `CompoundHandles[A, B]` (§2) satisfies both (two
  inhabitants, `getBoth` is genuinely polymorphic in `A` and `B`); the
  arity-4 chain has one inhabitant and no law over arity-4 chains as a
  class. Options considered: (A) purpose-built record with
  domain-named fields; (B) named generic
  `ChainedHandles4[A, B, C, D]` with positional fields; (C) variadic
  `ChainedHandlesN` macro now. Chose A. §8.4 spells out the retrofit
  if a second arity-4 inhabitant arrives.

- **H11. Field names `queryH` / `threadIdFetchH` / `threadsH` /
  `displayH` on the handle record; `query` / `threadIdFetch` /
  `threads` / `display` on the results record.** Domain-named,
  role-descriptive, mechanical to read at call sites. The `H` suffix
  on the handles record marks "handle, not response" and avoids
  collision when both records appear at the same call site; the
  results record uses plain names because the type name
  (`EmailQueryThreadResults`) already conveys "these are responses".
  Asymmetric with H2 (which picks structural `primary`/`implicit` for
  `CompoundHandles[A, B]`) precisely because that asymmetry matters:
  H2 applies when multiple type aliases inhabit one generic; H11
  applies when there is no generic and the record itself must carry
  domain vocabulary.

- **H12. `DefaultDisplayProperties` as a module-level `const` with
  RFC docstring.** Override is a normal argument. One named,
  auditable default, visible at one site.

- **H13. `collapseThreads` defaults to `true`.** RFC §4.10 example
  default.

- **H14. `getAll` is one monomorphic function, co-located with the
  builder.** Partial extraction is a user concern —
  `dr.get(handles.queryH)` is already available via field access.
  `getAll` lives in `mail_builders.nim`, not in `dispatch.nim`,
  because it has no parametric shape to share with `dispatch`-layer
  generics.

- **H15. Variadic `ChainedHandlesN` macro deferred.** Today there is
  one parametric generic (`ChainedHandles[A, B]`, §3) and one
  purpose-built record (`EmailQueryThreadChain`, §4); a variadic
  arity-N macro arrives only when a second inhabitant at some other
  arity (or a second arity-4 inhabitant) justifies it. §8.4 lays out
  the retrofit path.

- **H16. Back-reference paths extend the existing `RefPath` enum, not
  a parallel `ResultRefPath`.** `RefPath`'s docstring already claims
  the RFC 8620 §3.7 JSON Pointer slot verbatim; a parallel enum would
  violate the no-parallel-systems clean-refactor invariant. New paths
  arrive as new `RefPath` variants.

---

## 5. `ParsedSmtpReply` — RFC 5321 §4.2 + RFC 3463 §2 parsed once

### 5.1. Why parse-once

`DeliveryStatus.smtpReply` carries the fully-decomposed RFC 5321 §4.2
Reply-line plus the optional RFC 3463 §2 enhanced-status-code triple.
Parsing happens once at the serde boundary; consumers branch on typed
fields; no one re-parses the text.

The shape mirrors three sibling patterns elsewhere in the codebase:

- `ParsedDeliveredState` / `ParsedDisplayedState`
  (`submission_status.nim:74-94`) — classification plus raw-backing
  string for round-trip.
- `Session.rawCore` — type-level split between parsed core and raw
  extension capabilities.
- `SetError` — payload-bearing arms whose data is parsed at the
  `errors.nim` boundary, not at consumer call sites.

`ParsedSmtpReply.raw*` exists for diagnostic fidelity (mail tracing,
log correlation), not as a back-compat escape hatch.

### 5.2. Distinct newtypes + a string-backed enum

In `src/jmap_client/mail/submission_status.nim:100-117`:

```nim
type ReplyCode* = distinct uint16
  ## RFC 5321 §4.2.3 three-digit Reply-code. Validated via
  ## ``detectReplyCodeGrammar``. First digit ∈ {2,3,4,5}, second ∈
  ## {0..5}, third ∈ {0..9}.

type StatusCodeClass* = enum
  ## RFC 3463 §3.1 class digit. String-backed for lossless round-trip;
  ## closed — RFC 3463 cannot extend this digit.
  sccSuccess          = "2"
  sccTransientFailure = "4"
  sccPermanentFailure = "5"

type SubjectCode* = distinct uint16
  ## RFC 3463 §4 subject sub-code. Bounded 0..999 (lenient within the
  ## IANA registry's extensibility policy).

type DetailCode* = distinct uint16
  ## RFC 3463 §4 detail sub-code. Bounded 0..999, same rationale.
```

Borrow templates for each distinct newtype follow `nim-type-safety.md`:
`==`, `$`, `hash` only — `<` / `<=` are deliberately omitted because
ordering is not a meaningful domain operation
(`submission_status.nim:119-143`).

`StatusCodeClass` is closed because RFC 3463 §3.1 binds the class
digit to {2, 4, 5} and cannot extend. `SubjectCode` and `DetailCode`
are bounded `0..999` lenient because the IANA Enhanced Status Codes
registry is extensible per RFC 3463 §4 — hard-coding currently-
registered values would force a library update on every IANA
extension. Mirrors the `DeliveredState` / `DisplayedState`
catch-all-arm idiom for forward compatibility.

### 5.3. `EnhancedStatusCode` and `ParsedSmtpReply`

In `submission_status.nim:145-161`:

```nim
type EnhancedStatusCode* {.ruleOff: "objects".} = object
  ## RFC 3463 §2 triple ``class.subject.detail``. Plain object —
  ## structural equality is auto-derived (no case discriminator).
  klass*:   StatusCodeClass
  subject*: SubjectCode
  detail*:  DetailCode

type ParsedSmtpReply* {.ruleOff: "objects".} = object
  ## RFC 5321 §4.2 multi-line Reply parsed once, plus optional RFC 3463
  ## §2 enhanced-status-code triple from the final line. ``raw``
  ## preserves the exact ingress bytes; ``renderSmtpReply`` emits the
  ## canonical LF form.
  replyCode*: ReplyCode
  enhanced*:  Opt[EnhancedStatusCode]
  text*:      string
  raw*:       string
```

Field ordering: discriminators first (`replyCode`), then typed
subcomponent (`enhanced`), then diagnostic strings (`text`, `raw`).
Matches the `ParsedDeliveredState` / `ParsedDisplayedState` shape at
`submission_status.nim:74-80, 90-94`.

### 5.4. `SmtpReplyViolation`

`submission_status.nim:163-188` defines an exported 15-variant enum
covering the RFC 5321 §4.2 surface grammar (10 variants) and the
RFC 3463 §2 enhanced-status-code grammar (5 variants):

```nim
type SmtpReplyViolation* = enum
  ## Structural and enhanced-code grammatical failures.
  ## Public for test introspection; the public parser projects these
  ## to ``ValidationError`` via ``toValidationError`` — every failure
  ## message lives in one place.

  # Surface grammar (RFC 5321 §4.2).
  srEmpty
  srControlChars
  srLineTooShort
  srBadReplyCodeDigit1
  srBadReplyCodeDigit2
  srBadReplyCodeDigit3
  srBadSeparator
  srMultilineCodeMismatch
  srMultilineContinuation
  srMultilineFinalHyphen

  # Enhanced-status-code grammar (RFC 3463 §2).
  srEnhancedMalformedTriple
  srEnhancedClassInvalid
  srEnhancedSubjectOverflow
  srEnhancedDetailOverflow
  srEnhancedMultilineMismatch
```

The single domain-to-wire translator at `submission_status.nim:190-229`:

```nim
func toValidationError(v: SmtpReplyViolation, raw: string): ValidationError =
  case v
  of srEmpty:                  validationError("SmtpReply", "must not be empty", raw)
  of srControlChars:           validationError("SmtpReply", "contains disallowed control characters", raw)
  of srLineTooShort:           validationError("SmtpReply", "line shorter than 3-digit Reply-code", raw)
  of srBadReplyCodeDigit1:     validationError("SmtpReply", "first Reply-code digit must be in 2..5", raw)
  of srBadReplyCodeDigit2:     validationError("SmtpReply", "second Reply-code digit must be in 0..5", raw)
  of srBadReplyCodeDigit3:     validationError("SmtpReply", "third Reply-code digit must be in 0..9", raw)
  of srBadSeparator:           validationError("SmtpReply", "character after Reply-code must be SP, HT, or '-'", raw)
  of srMultilineCodeMismatch:  validationError("SmtpReply", "multi-line reply has inconsistent Reply-codes", raw)
  of srMultilineContinuation:  validationError("SmtpReply", "non-final reply line must use '-' continuation", raw)
  of srMultilineFinalHyphen:   validationError("SmtpReply", "final reply line must not use '-' continuation", raw)
  of srEnhancedMalformedTriple:    validationError("SmtpReply", "enhanced status code not a numeric dot-separated triple", raw)
  of srEnhancedClassInvalid:       validationError("SmtpReply", "enhanced status-code class must be 2, 4, or 5", raw)
  of srEnhancedSubjectOverflow:    validationError("SmtpReply", "enhanced status-code subject out of 0..999", raw)
  of srEnhancedDetailOverflow:     validationError("SmtpReply", "enhanced status-code detail out of 0..999", raw)
  of srEnhancedMultilineMismatch:  validationError("SmtpReply", "multi-line reply has inconsistent enhanced status codes", raw)
```

Adding a variant forces a compile error here and nowhere else.

### 5.5. Atomic detectors and composer

The module sits under `{.push raises: [], noSideEffect.}` so every
`func` defined within is automatically pure and total — atomic
detectors are exported `func`s, not templates. Pragma inheritance
through the module-level pragma does the work.

Atomic detectors (`submission_status.nim:233-309`):

```nim
func detectReplyCodeGrammar*(line: string): Result[ReplyCode, SmtpReplyViolation]
  ## Three-digit Reply-code grammar (RFC 5321 §4.2.3). Precondition
  ## ``line.len >= 3`` (caller-enforced).

func detectSeparator*(line: string, isFinal: bool): Result[void, SmtpReplyViolation]
  ## Byte after the Reply-code: SP/HT on the final line, ``'-'`` on a
  ## continuation. A bare 3-char line with no separator is legal only
  ## as the final line.

func detectClassDigit*(c: char): Result[StatusCodeClass, SmtpReplyViolation]
  ## RFC 3463 §3.1 class digit.

func detectSubjectInRange*(n: uint16): Result[SubjectCode, SmtpReplyViolation]
  ## Bounds check for RFC 3463 §4 subject sub-code.

func detectDetailInRange*(n: uint16): Result[DetailCode, SmtpReplyViolation]
  ## Bounds check for RFC 3463 §4 detail sub-code.

func detectConsistentItems*[T](
    per: openArray[T], violation: SmtpReplyViolation
): Result[void, SmtpReplyViolation]
  ## Verifies every element of ``per`` compares equal to the first.
  ## Used for RFC 5321 §4.2.1 Reply-code consistency across multi-line
  ## replies AND for RFC 3463 §2 enhanced-code consistency across
  ## those lines that carry a triple — one helper, two call sites.
```

`detectConsistentItems` is generic over `T` (no callback parameter
needed) — the comparator is the type's own `==`.

Module-internal helpers (`submission_status.nim:311-439`):

- `parseEnhancedComponent(raw: string): Opt[uint16]` — parses an
  ASCII-digit run into `uint16`; bounded 1..5 chars to fit `uint16`.
  Internal because `parseInt` raises `ValueError`, unusable under
  `raises: []`.
- `detectEnhancedTriple(raw: string): Result[EnhancedStatusCode, SmtpReplyViolation]`
  — RFC 3463 §2 `class "." subject "." detail`. Composes
  `detectClassDigit` + bounds-checked subject and detail via `?`.
- `splitReplyLines(raw: string): Result[seq[string], SmtpReplyViolation]`
  — normalises CRLF/LF/CR to LF, drops a trailing empty segment from
  CRLF-terminated payloads, returns the non-empty line set.
  `err(srEmpty)` on input that degenerates to zero content lines.
- `detectLineGrammar(lines: openArray[string]): Result[seq[ReplyCode], SmtpReplyViolation]`
  — per-line surface grammar: length floor, three-digit Reply-code,
  separator dispatch. Returns the Reply-code sequence for the
  consistency check.
- `extractTextstrings(lines: openArray[string]): seq[string]` —
  per-line textstring (bytes after the Reply-code separator, empty
  for a bare 3-char final line).
- `detectEnhancedOnLine(text: string): Result[Opt[EnhancedStatusCode], SmtpReplyViolation]`
  — extract an optional triple from the head of a line's textstring.
  `Opt.none` when no candidate is present; `Opt.some(triple)` when a
  dot-containing leading token parses; a candidate that *looks* like a
  triple but fails the grammar fails the whole reply.
- `collectEnhanced(perLine: openArray[Opt[EnhancedStatusCode]]): seq[EnhancedStatusCode]`
  — projection of only those lines that carry a triple, for the
  cross-line consistency check.
- `assembleText(texts: openArray[string], perLineEnhanced: openArray[Opt[EnhancedStatusCode]]): string`
  — concatenate per-line textstrings (LF-joined) with the
  enhanced-status-code prefix stripped from lines that carried one.

Composer (`submission_status.nim:441-466`):

```nim
func detectParsedSmtpReply(raw: string):
    Result[ParsedSmtpReply, SmtpReplyViolation] =
  ## Composer: emptiness, global byte-set, line splitting, per-line
  ## surface grammar, Reply-code consistency, optional enhanced-status-
  ## code triple per line, enhanced-code consistency, and final
  ## assembly. Each phase is delegated to a helper so this function
  ## reads as the RFC's layered pipeline.
  if raw.len == 0:
    return err(srEmpty)
  if not raw.allIt(it in ReplyAllowedBytes):
    return err(srControlChars)
  let lines = ?splitReplyLines(raw)
  let codes = ?detectLineGrammar(lines)
  ?detectConsistentItems(codes, srMultilineCodeMismatch)
  let texts = extractTextstrings(lines)
  var perLineEnhanced: seq[Opt[EnhancedStatusCode]] = @[]
  for text in texts:
    perLineEnhanced.add ?detectEnhancedOnLine(text)
  let enhancedLinesOnly = collectEnhanced(perLineEnhanced)
  ?detectConsistentItems(enhancedLinesOnly, srEnhancedMultilineMismatch)
  let text = assembleText(texts, perLineEnhanced)
  let enhanced =
    if enhancedLinesOnly.len > 0: Opt.some(enhancedLinesOnly[0])
    else:                         Opt.none(EnhancedStatusCode)
  ok(ParsedSmtpReply(
    replyCode: codes[0], enhanced: enhanced, text: text, raw: raw))
```

Public entry points (`submission_status.nim:468-505`):

```nim
func parseSmtpReply*(raw: string): Result[ParsedSmtpReply, ValidationError] =
  ## Public entry point for the RFC 5321 §4.2 + RFC 3463 §2 parse.
  let parsed = detectParsedSmtpReply(raw).valueOr:
    return err(toValidationError(error, raw))
  ok(parsed)

func renderSmtpReply*(p: ParsedSmtpReply): string =
  ## Deterministic canonical rendering. Not equal to ``p.raw`` in
  ## general — ``p.raw`` preserves the ingress bytes (including CRLF);
  ## this emits LF-terminated lines only, with no trailing whitespace,
  ## and the enhanced-status-code prefix (when present) re-emitted on
  ## the final line between the SP separator and ``p.text``.
```

### 5.6. `DeliveryStatus`

In `submission_status.nim:511-517`:

```nim
type DeliveryStatus* {.ruleOff: "objects".} = object
  ## RFC 8621 §7 ``deliveryStatus`` entry. Composes the fully-parsed
  ## SMTP Reply-line (with RFC 3463 §2 enhanced status code, when
  ## present) with the two parsed recipient-state classifications.
  smtpReply*: ParsedSmtpReply
  delivered*: ParsedDeliveredState
  displayed*: ParsedDisplayedState
```

`DeliveryStatusMap` at `submission_status.nim:519` is a
`distinct Table[RFC5321Mailbox, DeliveryStatus]`; named domain
operations `countDelivered` (line 534) and `anyFailed` (line 542)
provide the consumer surface.

### 5.7. Serde routing

In `src/jmap_client/mail/serde_submission_status.nim:97-123`:

```nim
func fromJson*(
    T: typedesc[DeliveryStatus], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[DeliveryStatus, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  let smtpReplyNode = ?fieldJString(node, "smtpReply", path)
  let smtpReply =
    ?wrapInner(parseSmtpReply(smtpReplyNode.getStr("")), path / "smtpReply")
  let deliveredNode = ?fieldJString(node, "delivered", path)
  let delivered = ?ParsedDeliveredState.fromJson(deliveredNode, path / "delivered")
  let displayedNode = ?fieldJString(node, "displayed", path)
  let displayed = ?ParsedDisplayedState.fromJson(displayedNode, path / "displayed")
  ok(DeliveryStatus(
    smtpReply: smtpReply, delivered: delivered, displayed: displayed))

func toJson*(x: DeliveryStatus): JsonNode =
  ## Emit the canonical wire form. ``smtpReply`` renders via
  ## ``renderSmtpReply`` — LF-terminated, no trailing whitespace;
  ## ingress CRLF is normalised out. ``delivered`` / ``displayed``
  ## round-trip via their preserved raw backing tokens.
  result = newJObject()
  result["smtpReply"] = %renderSmtpReply(x.smtpReply)
  result["delivered"] = %x.delivered.rawBacking
  result["displayed"] = %x.displayed.rawBacking
```

`wrapInner` lifts the `ValidationError` from `parseSmtpReply` onto the
`SerdeViolation` rail with the right JSON path attached.

### 5.8. Wire round-trip canonicalisation

`parseSmtpReply` is lenient on input per Postel's law: it accepts
CRLF, bare LF, and bare CR line terminators; accepts an optional
trailing empty segment from CRLF-terminated payloads; accepts any
byte in `{HT, SP..~}` on textstring lines. The
`ParsedSmtpReply.raw*` field preserves the exact ingress bytes,
including the ingress line-ending variant.

`toJson(DeliveryStatus)` (via `renderSmtpReply`) emits the
**canonical form**:

- Line terminator: **LF** (`\n`), never CRLF, never bare CR. JMAP
  wire is JSON-in-HTTP; CRLF is an SMTP wire convention not required
  in the JMAP `smtpReply` string value.
- Final line: `<ReplyCode><SP><enhanced-prefix?><text>` (no trailing
  newline).
- Multi-line: each non-final line `<ReplyCode><->...<LF>`.
- No trailing whitespace on any line.

Consequences:

- **Canonical input → identical output.** When `raw` is already
  canonical, `renderSmtpReply(parseSmtpReply(raw).get) == raw`.
  Existing fixtures in `tests/serde/mail/tserde_submission_status.nim`
  and `tests/mfixtures.nim` that use canonical LF-terminated replies
  are byte-identical.
- **Non-canonical input → canonicalised output.** CRLF in, LF out.
  Trailing CR in, stripped out. The `raw` field on the parsed object
  still holds the original ingress bytes, so diagnostic paths
  (logging, tracing) see the exact wire as received.

### 5.9. Decisions

- **H17. `ParsedSmtpReply` carries the fully-decomposed Reply-line.**
  `raw*` preserves the diagnostic identity of the ingress wire bytes;
  the typed fields carry the parsed structure for consumers. Options
  considered: (A) `distinct string` with on-demand parser helper; (B)
  layered parser atop a string type; (C) parsed-object field with raw
  preservation. Chose C — parse-once invariant.

- **H18. Four distinct newtypes plus a string-backed enum.** No bare
  `uint16` or `string` carries domain meaning past the serde boundary.
  `ReplyCode`, `SubjectCode`, `DetailCode` are distinct `uint16`;
  `StatusCodeClass` is a closed enum with backing strings.

- **H19. `SubjectCode`/`DetailCode` bounded `0..999` lenient, not a
  sealed enum.** IANA Enhanced Status Codes registry is extensible
  per RFC 3463 §4; hard-coding currently-registered values would
  force a library update on every IANA extension. Matches the
  `DeliveredState`/`DisplayedState` catch-all-arm idiom.
  `StatusCodeClass`, by contrast, IS a closed enum — RFC 3463 §3.1
  binds the class digit to {2, 4, 5} and cannot extend.

- **H20. Single `SmtpReplyViolation` enum, single translator.** All
  15 variants live in one enum (`submission_status.nim:163-188`) with
  one `toValidationError` translator (`submission_status.nim:190-229`).
  Adding a variant forces one compile error at the translator.
  Options considered: (A) split surface vs enhanced into two enums;
  (B) single enum with single translator. Chose B for one
  domain-to-wire mapping.

- **H21. Atomic detectors as `func`, not `template`.** The module
  sits under `{.push raises: [], noSideEffect.}`, so every `func`
  defined inside is automatically pure and total. Pragma inheritance
  at the module level does the work; per-routine template expansion
  for purity is unnecessary. Templates remain idiomatic when callers
  outside the module need the body inlined to inherit *their*
  pragmas (cf. `validateUniqueByIt` at `validation.nim`); the
  detectors here are called only from within `submission_status.nim`,
  so funcs are simpler.

- **H22. `detectConsistentItems` is one generic helper, two call
  sites.** RFC 5321 §4.2.1 Reply-code consistency and RFC 3463 §2
  enhanced-code consistency are the same operation: `seq[T]` →
  `Result[void, SmtpReplyViolation]` parametrised by which violation
  to emit. The element type is the parametric variation; `==` is the
  comparator. No callback parameter is needed.

- **H23. `DeliveryStatus.smtpReply: ParsedSmtpReply`.** Parse-once
  invariant. The entity carries the rich type; consumers get
  structured access for free; no downstream helper is needed.

- **H24. `renderSmtpReply` is the deterministic inverse of
  `parseSmtpReply` for canonical inputs.** Non-canonical inputs are
  canonicalised to LF terminators per §5.8.
  `ParsedSmtpReply.raw*` preserves the exact ingress form for
  diagnostic purposes.

- **H25. `parseSmtpReply` is the public entry; atomic detectors are
  exported for test introspection.** Tests assert against
  `SmtpReplyViolation` variants directly (the translator is tested
  once, not per-parser); atomic detectors are test-visible so failing
  a specific detector in isolation is a legal test shape.

---

## 6. RFC 8621 §10 IANA traceability matrix

Pure documentation. Four subsections mirror RFC §10's structure;
every registered item maps to a symbol in the library (or is
documented as intentionally absent).

### 6.1. Capabilities (§10.1–10.3)

| RFC § | URI | `CapabilityKind` variant | File:line |
|---|---|---|---|
| §10.1 | `urn:ietf:params:jmap:mail` | `ckMail` | `src/jmap_client/capabilities.nim:26` |
| §10.2 | `urn:ietf:params:jmap:submission` | `ckSubmission` | `src/jmap_client/capabilities.nim:28` |
| §10.3 | `urn:ietf:params:jmap:vacationresponse` | `ckVacationResponse` | `src/jmap_client/capabilities.nim:29` |

`MailCapabilities` (RFC §2) — server-advertised limits for
`urn:ietf:params:jmap:mail`:

| RFC field | Nim field | File:line |
|---|---|---|
| `maxMailboxesPerEmail` | `maxMailboxesPerEmail*: Opt[UnsignedInt]` | `src/jmap_client/mail/mail_capabilities.nim:40` |
| `maxMailboxDepth` | `maxMailboxDepth*: Opt[UnsignedInt]` | `src/jmap_client/mail/mail_capabilities.nim:41` |
| `maxSizeMailboxName` | `maxSizeMailboxName*: Opt[UnsignedInt]` | `src/jmap_client/mail/mail_capabilities.nim:42` |
| `maxSizeAttachmentsPerEmail` | `maxSizeAttachmentsPerEmail*: UnsignedInt` | `src/jmap_client/mail/mail_capabilities.nim:47` |
| `emailQuerySortOptions` | `emailQuerySortOptions*: HashSet[string]` | `src/jmap_client/mail/mail_capabilities.nim:48` |
| `mayCreateTopLevelMailbox` | `mayCreateTopLevelMailbox*: bool` | `src/jmap_client/mail/mail_capabilities.nim:49` |

`SubmissionCapabilities` (RFC §7) — server-advertised limits for
`urn:ietf:params:jmap:submission`:

| RFC field | Nim field | File:line |
|---|---|---|
| `maxDelayedSend` | `maxDelayedSend*: UnsignedInt` | `src/jmap_client/mail/mail_capabilities.nim:54` |
| `submissionExtensions` | `submissionExtensions*: SubmissionExtensionMap` | `src/jmap_client/mail/mail_capabilities.nim:55` |

`VacationResponseCapabilities` (RFC §8) has no server-advertised
fields per the RFC — the capability is a presence flag only. No Nim
type needed beyond the `ckVacationResponse` variant.

### 6.2. Keywords (§10.4)

RFC §10.4 registers four JMAP-originated keywords and reserves one
(`$recent`) with "Do not use" scope.

| RFC § | Keyword | Nim binding | File:line |
|---|---|---|---|
| §10.4.1 | `$draft` | `const kwDraft* = Keyword("$draft")` | `src/jmap_client/mail/keyword.nim:41` |
| §10.4.2 | `$seen` | `const kwSeen* = Keyword("$seen")` | `src/jmap_client/mail/keyword.nim:42` |
| §10.4.3 | `$flagged` | `const kwFlagged* = Keyword("$flagged")` | `src/jmap_client/mail/keyword.nim:43` |
| §10.4.4 | `$answered` | `const kwAnswered* = Keyword("$answered")` | `src/jmap_client/mail/keyword.nim:44` |
| §10.4.5 | `$recent` | **intentionally absent** — RFC §10.4.5 scope: "reserved"; client libraries MUST NOT set it. | — |

`keyword.nim:45-48` also exposes `kwForwarded`, `kwPhishing`,
`kwJunk`, `kwNotJunk` — these are NOT RFC 8621 §10.4 registrations;
they are IANA IMAP and JMAP Keywords registry entries referenced as
informative examples in RFC 8621 §4.1.1. See §8.5.

### 6.3. Mailbox roles (§10.5)

RFC §10.5.1 is the only RFC 8621 registration — `inbox` role. The
other `MailboxRoleKind` arms derive from the IANA IMAP Mailbox Name
Attributes registry (RFC 6154, RFC 5258) that RFC 8621 §2 references.

| RFC § | Role | `MailboxRoleKind` variant | File:line |
|---|---|---|---|
| **§10.5.1** | **`inbox` (RFC 8621 registration)** | **`mrInbox = "inbox"`** | **`src/jmap_client/mail/mailbox.nim:29`** |
| RFC 6154 | `drafts` | `mrDrafts = "drafts"` | `src/jmap_client/mail/mailbox.nim:30` |
| RFC 6154 | `sent` | `mrSent = "sent"` | `src/jmap_client/mail/mailbox.nim:31` |
| RFC 6154 | `trash` | `mrTrash = "trash"` | `src/jmap_client/mail/mailbox.nim:32` |
| RFC 6154 | `junk` | `mrJunk = "junk"` | `src/jmap_client/mail/mailbox.nim:33` |
| RFC 6154 | `archive` | `mrArchive = "archive"` | `src/jmap_client/mail/mailbox.nim:34` |
| RFC 6154 | `important` | `mrImportant = "important"` | `src/jmap_client/mail/mailbox.nim:35` |
| RFC 5258 | `all` | `mrAll = "all"` | `src/jmap_client/mail/mailbox.nim:36` |
| RFC 5258 | `flagged` | `mrFlagged = "flagged"` | `src/jmap_client/mail/mailbox.nim:37` |
| RFC 5465 | `subscriptions` | `mrSubscriptions = "subscriptions"` | `src/jmap_client/mail/mailbox.nim:38` |
| (catch-all) | vendor-extension role | `mrOther` | `src/jmap_client/mail/mailbox.nim:39` |

### 6.4. SetError codes (§10.6)

RFC 8621 §10.6 registers twelve entity-specific SetError codes across
Mailbox/set, Email/set, and EmailSubmission/set. RFC 8621 §7.5
additionally specifies `cannotUnsend` for EmailSubmission/set update —
mentioned in §7.5 prose but not in the §10.6 registry. All thirteen
are `SetErrorType` variants in `errors.nim`:

| RFC origin | Code | Variant | File:line |
|---|---|---|---|
| RFC 8621 §2.3 Mailbox/set | `mailboxHasChild` | `setMailboxHasChild = "mailboxHasChild"` | `src/jmap_client/errors.nim:275` |
| RFC 8621 §2.3 Mailbox/set | `mailboxHasEmail` | `setMailboxHasEmail = "mailboxHasEmail"` | `src/jmap_client/errors.nim:276` |
| RFC 8621 §4.6 Email/set | `blobNotFound` | `setBlobNotFound = "blobNotFound"` | `src/jmap_client/errors.nim:278` |
| RFC 8621 §4.6 Email/set | `tooManyKeywords` | `setTooManyKeywords = "tooManyKeywords"` | `src/jmap_client/errors.nim:279` |
| RFC 8621 §4.6 Email/set | `tooManyMailboxes` | `setTooManyMailboxes = "tooManyMailboxes"` | `src/jmap_client/errors.nim:280` |
| RFC 8621 §7.5 EmailSubmission/set | `invalidEmail` | `setInvalidEmail = "invalidEmail"` | `src/jmap_client/errors.nim:282` |
| RFC 8621 §7.5 EmailSubmission/set | `tooManyRecipients` | `setTooManyRecipients = "tooManyRecipients"` | `src/jmap_client/errors.nim:283` |
| RFC 8621 §7.5 EmailSubmission/set | `noRecipients` | `setNoRecipients = "noRecipients"` | `src/jmap_client/errors.nim:284` |
| RFC 8621 §7.5 EmailSubmission/set | `invalidRecipients` | `setInvalidRecipients = "invalidRecipients"` | `src/jmap_client/errors.nim:285` |
| RFC 8621 §7.5 EmailSubmission/set | `forbiddenMailFrom` | `setForbiddenMailFrom = "forbiddenMailFrom"` | `src/jmap_client/errors.nim:286` |
| RFC 8621 §7.5 EmailSubmission/set | `forbiddenFrom` | `setForbiddenFrom = "forbiddenFrom"` | `src/jmap_client/errors.nim:287` |
| RFC 8621 §7.5 EmailSubmission/set | `forbiddenToSend` | `setForbiddenToSend = "forbiddenToSend"` | `src/jmap_client/errors.nim:288` |
| RFC 8621 §7.5 EmailSubmission/set | `cannotUnsend` | `setCannotUnsend = "cannotUnsend"` | `src/jmap_client/errors.nim:289` |

RFC 8620 §5.3 standard SetError codes (`forbidden`, `overQuota`,
`tooLarge`, `rateLimit`, `notFound`, `invalidPatch`, `willDestroy`,
`invalidProperties`, `alreadyExists`, `singleton`) are also
`SetErrorType` variants (`setForbidden`..`setSingleton` at
`src/jmap_client/errors.nim:264-273`) but are RFC 8620 core, not
RFC 8621 §10.6 — included here for completeness of the error-code
vocabulary only. RFC 8620 §5.3 also lists `stateMismatch` as a
SetError code; this codebase exposes `stateMismatch` only at the
MethodError level (`metStateMismatch` at
`src/jmap_client/errors.nim:220`), which the RFC also permits via its
parallel listing in §3.6.2 (request-level errors).

---

## 7. Decision Traceability Matrix

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|---|---|---|---|
| H1 | Promotion threshold for `CompoundHandles[A, B]` | (A) keep per-site, (B) Rule-of-Three (defer), (C) Rule-of-Two (promote) | **C** — promote under Rule-of-Two; structural repetition is exact and §3–§4 confirm the §5.4-vs-§3.7 split is load-bearing | Duplicated appearance IS duplicated knowledge when the knowledge is structural |
| H2 | Field names on `CompoundHandles` | (A) domain-named (`copy`/`destroy`/`submission`/`emailSet`), (B) spec-verbatim (`primary`/`implicit`), (C) proxy accessors atop domain names | **B** — spec-verbatim, with type-alias names carrying domain meaning | RFC vocabulary at field level; domain vocabulary at type-alias level |
| H3 | Where `CompoundHandles` + `getBoth` lives | (A) `dispatch.nim` (with `ResponseHandle`/`NameBoundHandle`), (B) mail-specific module | **A** — `dispatch.nim`; no mail-specific obligation | One source of truth per generic |
| H4 | Compile-time gate for compound participants | (A) none, (B) per-call-site assertion, (C) module-scope registration template | **C** — `registerCompoundMethod(Primary, Implicit)` | Mirror the `registerSettableEntity(T)` precedent |
| H5 | `ChainedHandles[A, B]` relative to `CompoundHandles[A, B]` | (A) force into one generic with `Opt[MethodName]`, (B) subtype, (C) sibling generic | **C** — sibling; §3.7 and §5.4 are structurally distinct RFC mechanisms | Type-level honesty over spurious unification |
| H6 | `filter` in `addEmailQueryWithSnippets` | (A) `Opt[Filter[...]]`, (B) mandatory `Filter[...]` | **B** — mandatory; RFC 8621 §5.1 forbids snippets without filter | Make the wrong thing hard; lift RFC invariant to type level |
| H7 | Filter shared via back-reference vs duplicated | (A) second `ResultReference` sharing the filter, (B) literal duplication | **B** — literal duplication | Each invocation self-contained; no new `ResultReference` path invented |
| H8 | Non-emptiness of `emailIds` back-reference | (A) refuse empty (impossible at back-reference), (B) accept empty | **B** — accept degenerate-but-valid per RFC; cons-cell discipline does not propagate through back-reference | Honest about what the type can enforce |
| H9 | Compile-time gate for chain participants | (A) none, (B) `registerChainableMethod(Primary)` | **B** — mirror of H4, applied to every response type that fronts a chain step | Mirror the `registerSettableEntity(T)` precedent |
| H10 | Arity-4 chain representation | (A) purpose-built `EmailQueryThreadChain` record with domain-named fields, (B) named generic `ChainedHandles4[A, B, C, D]` with positional fields, (C) variadic `ChainedHandlesN` macro now | **A** — purpose-built record; abstraction requires structural repetition AND a parametric law, and arity-4 has neither | No parametric law over arity-4 chains; domain vocabulary survives at the record level when there is no generic above it |
| H11 | Field names on `EmailQueryThreadChain` / `EmailQueryThreadResults` | (A) `first`/`second`/`third`/`fourth`, (B) domain-named `queryH`/`threadIdFetchH`/`threadsH`/`displayH` on handles + `query`/`threadIdFetch`/`threads`/`display` on results | **B** — domain-named; asymmetric with H2 because the record has no generic above it | Code reads like the spec; RFC §4.10 step names survive to the field level |
| H12 | `DefaultDisplayProperties` location | (A) hard-coded in builder, (B) module-level `const` with docstring, (C) configuration object | **B** — one named auditable default, RFC-cited | One source of truth per fact |
| H13 | `collapseThreads` default | (A) `false`, (B) `true` per RFC §4.10 example | **B** | Match RFC canonical example |
| H14 | Partial-extraction functions | (A) `getAll` only, monomorphic, co-located with the builder; (B) `getAll` + `getFirstTwo` + `getLastThree` + etc.; (C) parametric `getAll` in `dispatch.nim` | **A** — one function; partial extraction via field access | Avoid combinatorial explosion; co-locate monomorphic extractors with their monomorphic builders |
| H15 | Variadic `ChainedHandlesN` macro | (A) implement now, (B) defer until a second arity-N inhabitant arrives | **B** — deferred to §8.4; retrofit re-expresses `ChainedHandles[A, B]` as `ChainedHandles2[A, B]` and `EmailQueryThreadChain` as a type alias over `ChainedHandles4[...]` with field-projection helpers | Abstraction follows two inhabitants at each arity |
| H16 | Back-reference path constants | (A) string literals at call sites, (B) parallel `ResultRefPath` enum in `dispatch.nim`, (C) the existing `RefPath` enum in `methods_enum.nim` | **C** — single source of truth for RFC 8620 §3.7 paths | `RefPath`'s docstring already claims the slot; no parallel systems |
| H17 | `ParsedSmtpReply` shape | (A) `distinct string` with on-demand parser helper, (B) layered parser atop a string type, (C) parsed-object field with raw preservation | **C** — parsed-object field; `raw*` for diagnostic fidelity | Parse-once invariant |
| H18 | Typed Reply-code / subject / detail | (A) bare `uint16`, (B) distinct newtypes + string-backed enum for class | **B** — four distinct newtypes + `StatusCodeClass` enum | Distinct-newtype invariant |
| H19 | Closed enum vs lenient bounds for subject/detail | (A) sealed enum over currently-registered values, (B) bounded 0..999 lenient | **B** — IANA Enhanced Status Codes registry is extensible; lenient accepts future codes | `DeliveredState`/`DisplayedState` catch-all-arm precedent |
| H20 | `SmtpReplyViolation` shape | (A) split surface vs enhanced into two enums, (B) single enum with single translator | **B** — same enum, same `sr` prefix; one translator forces one compile-error site per new variant | Single ADT per domain |
| H21 | Atomic detectors: `func` vs `template` | (A) `func`, (B) `template` | **A** — `func`; module sits under `{.push raises: [], noSideEffect.}` so funcs are pure by pragma inheritance and there is no caller outside the module needing inline expansion | Module-pragma purity invariant |
| H22 | `detectConsistentItems` shape | (A) two per-check detectors, (B) one generic helper parameterised by the violation to emit | **B** — one helper, two call sites | DRY where knowledge is shared |
| H23 | Parse-once entity-field vs on-demand helper | (A) add `parseSmtpReplyStructured` helper, keep `DeliveryStatus.smtpReply: SmtpReply`; (B) `DeliveryStatus.smtpReply: ParsedSmtpReply` | **B** — entity carries the rich type | Parse-once invariant |
| H24 | Wire canonicalisation policy | (A) faithful round-trip of ingress bytes; `toJson == raw`, (B) canonical emission; `raw` preserved for diagnostics | **B** — canonical LF-terminated emission; `raw` holds ingress bytes | One canonical wire form; diagnostic fidelity independent of emission |
| H25 | Detector / translator test surface | (A) test only `parseSmtpReply`, (B) export atomic detectors + `SmtpReplyViolation` for introspection | **B** — atomic detectors exported; enum exported; tests assert per-variant | Translator tested once; atomics tested in isolation |

---

## 8. Appendix: Deliberately Out of Scope

### 8.1. Push / Subscription / TypeState (RFC §1.5)

RFC 8620 §1.5 describes PushSubscription, state-changed events, and
the typed-state protocol for efficient change notification. These are
**server-directed MUSTs** — a server MUST support the protocol, but a
client is RFC-compliant by polling `/changes` and discovering state
diffs via state strings. The library implements the correctness
substrate (state strings, `*/changes` methods, `stateMismatch` error
handling) but no push transport.

The omission is intentional: push requires a transport-layer
subscription (EventSource or WebSocket), which is an FFI consumer
concern — Layer 5 embedders plug push into their own event loops.
Push lands as a separate architectural deliverable, not bolted onto
H1.

### 8.2. EmailDelivery TypeState key

RFC 8621 §1.5 defines the `EmailDelivery` type-state key used by push
subscriptions to signal that new mail has arrived. It carries no
methods and no data — it is purely a push signal. Meaningful only
under §8.1; deferred with push.

### 8.3. C ABI / Layer 5 exports

`src/jmap_client.nim` re-exports the Nim surface only. Layer 5 C ABI
exports (`{.exportc: "jmap_name", dynlib, cdecl, raises: [].}`) are a
separate architectural deliverable per `CLAUDE.md`. H1 is a type-lift
entirely within L1–L3.

### 8.4. Variadic `ChainedHandlesN`

The library has arity 2 as a parametric generic
(`ChainedHandles[A, B]`, §3) and arity 4 as a purpose-built record
(`EmailQueryThreadChain`, §4). One inhabitant does not justify a
generic at arity 4. When a second arity-4 chain materialises, or a
distinct arity (3, 5+) is justified by a real builder, the variadic
macro lands and the existing surface migrates mechanically:

1. Re-express `ChainedHandles[A, B]` as
   `type ChainedHandles[A, B] = ChainedHandles2[A, B]`. One-line
   alias; existing call sites keep working verbatim.
2. Re-express `EmailQueryThreadChain` as a type alias over
   `ChainedHandles4[QueryResponse[Email], GetResponse[Email],
   GetResponse[Thread], GetResponse[Email]]`, with field-projection
   templates preserving the domain-named accessors:

   ```nim
   template queryH*(c: EmailQueryThreadChain): auto = c.first
   template threadIdFetchH*(c: EmailQueryThreadChain): auto = c.second
   template threadsH*(c: EmailQueryThreadChain): auto = c.third
   template displayH*(c: EmailQueryThreadChain): auto = c.fourth
   ```

   Same pattern for `EmailQueryThreadResults`.

The asymmetry with §2 (Rule-of-Two promotion for `CompoundHandles`)
is principled: §2 promotes at two sites because both inhabitants are
genuine — each has its own type alias carrying domain vocabulary, and
the generic's `getBoth` is polymorphic in `A` and `B` with a real law.
§4 declines to promote at arity 4 with one inhabitant because there
is no second type alias to anchor domain vocabulary and no parametric
law beyond "four specific fields in a specific order."

### 8.5. `$forwarded` / `$phishing` / `$junk` / `$notjunk` keywords

RFC 8621 §4.1.1 references these as informative examples from the
IANA IMAP and JMAP Keywords registry — they are NOT RFC 8621 §10
registrations. They are represented in
`src/jmap_client/mail/keyword.nim:45-48` (`kwForwarded`, `kwPhishing`,
`kwJunk`, `kwNotJunk`), so §6.2's audit table (which tracks RFC §10
specifically) correctly omits them. If the RFC 8621 §10.4 registry
expands in a future RFC revision to include these, they are one-line
registry additions at §6.2 — no code change required.

### 8.6. Back-reference path constant generalisation

The `RefPath` enum (`methods_enum.nim:69-80`) enumerates the RFC 8620
§3.7 JSON Pointer paths the codebase uses today (`/ids`,
`/list/*/id`, `/added/*/id`, `/created`, `/updated`,
`/updatedProperties`, `/list/*/threadId`, `/list/*/emailIds`). A
broader enumeration covering every JMAP back-reference path observed
in the wild is out of scope — variants arrive when a new chain
builder needs one. Adding `/list/*/blobId` (for a hypothetical
blob-fetching chain) is a one-line enum extension plus a new builder.
