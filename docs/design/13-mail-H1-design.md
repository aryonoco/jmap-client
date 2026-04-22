# RFC 8621 JMAP Mail — Design H1: Type-Lift Completion — Specification

Parts A–G1 delivered every RFC 8621 method surface and the entity vocabulary
behind each one. H1 adds no new RFC surface. It closes the book on RFC 8621
by **finishing the typed-FP lift campaign** that has run through the recent
commits — taking the remaining places where the implementation still sits on
a weakly-typed or stringly-typed shape and raising each into a domain ADT
with a single translator at the wire boundary. After H1 every RFC 8621
invariant is either encoded in the type system or carried by a smart
constructor whose failure lives on the `Result` error rail.

The campaign's thesis — visible across `be21db0`, `c8f45b3`, `515f3bd`,
`769d56a`, `a23f39a`, and siblings — is:

> Replace runtime conventions with type-level guarantees. Illegal states
> unrepresentable. Invariants enforced by `parseX`. Errors carried as named
> variants on domain ADTs. A single translator projects each domain ADT to
> the wire error shape; adding a variant forces a compile error at exactly
> one site.

H1 applies that thesis to five remaining surfaces:

1. **Implicit-call compound handles** (RFC 8620 §5.4) — two hand-rolled
   `getBoth` bodies collapse into one generic, mirroring the
   `SetRequest[T, C, U]` promotion of `be21db0`.
2. **Back-reference chains** (RFC 8620 §3.7) — introduce a typed chain
   generic, then specialise it for the two RFC 8621 §4.10 canonical
   workflows (search-snippets-alongside-query, first-login).
3. **`SmtpReply` decomposition** — retire the `distinct string` wrapper
   for a `ParsedSmtpReply` object carrying `ReplyCode` +
   `Opt[EnhancedStatusCode]` + text, driven by atomic detectors composed
   with `?` and a single `SmtpReplyViolation → ValidationError`
   translator. Straight analogue of `TokenViolation` (`515f3bd`),
   `SerdeViolation` (`c8f45b3`), and `ContentDisposition` (`a23f39a`).
4. **Compile-time participation gates** — extend the
   `registerSettableEntity(T)` pattern (`be21db0`) to
   `registerCompoundMethod` and `registerChainableMethod`, so regressions
   surface at module scope, not at first call site.
5. **RFC §10 IANA traceability audit** — full matrix so the next reader
   can cite every registered item without grepping.

H1 also encodes the refactoring discipline as a first-class design
invariant: every migrated symbol is DELETED — no shim, no alias, no
compat bridge, no stale docstring (see §9 — the Deletions inventory).

---

## Table of Contents

- §1. Scope
- §2. `CompoundHandles[A, B]` — collapsing two per-site compound types
- §3. `ChainedHandles[A, B]` and `addEmailQueryWithSnippets`
- §4. `ChainedHandles4[A, B, C, D]` and `addEmailQueryWithThreads`
- §5. `ParsedSmtpReply` — retiring `SmtpReply`
- §6. RFC 8621 §10 IANA traceability matrix
- §7. Decision Traceability Matrix
- §8. Appendix: Deliberately Out of Scope
- §9. Clean-refactor: Deletions inventory + grep gate
- §10. Verification — when this document is complete

---

## 1. Scope

### 1.1. Campaign Thesis

H1 is a type-lift, not a new method surface. Every line of Nim this
document proposes either removes runtime ambiguity by hoisting a
convention into the type system, or removes structural duplication by
promoting a hand-rolled shape into a generic. Nothing H1 adds is new
wire behaviour, and nothing H1 retires is a supported public surface —
RFC 8621 compliance at Part G1 was already complete; H1 is about the
Nim surface that mediates it.

The discipline is three-part, and every H1 section is obligated to
satisfy all three:

- **Compile-time honesty.** Invariants the RFC states in prose (the
  first-login workflow shape, the SMTP Reply-code grammar, the sibling
  call-id convention of compound methods) become shapes the compiler can
  see — generics parameterised by response type, distinct newtypes per
  grammatical production, domain ADTs whose exhaustive `case` forces one
  compile error per violation class.
- **Single translator boundary.** Every new domain ADT has exactly one
  `toValidationError` (or `toSerdeViolation`) function; adding a variant
  forces one compile error at one site. Detection stays shape-agnostic;
  the translator handles all wire-format concerns.
- **Clean-refactor discipline.** Retired symbols leave no trace. No
  `{.deprecated.}` pragma, no `type OldName* = NewName` alias, no proxy
  accessor. The lift erases the old form entirely; call sites are
  grep-and-replaced in the same commit that introduces the new
  generic/type/ADT.

### 1.2. Discharge table — F1 and G1 deferrals

The deferrals recorded in `docs/design/11-mail-F1-design.md` §1.3 and
`docs/design/12-mail-G1-design.md` §1.3 are discharged here as follows.
Prior design docs are append-only history; they are not edited. This
table is the canonical cross-reference.

| Deferral | Origin | Discharged in | Mechanism |
|---|---|---|---|
| Generic `CompoundHandles[A, B]` | G1 §1.3, F1 §F3 (Rule-of-Three) | H1 §2 | Rule-of-Two promotion: two compound sites is enough because the structural repetition is exact and §3–§4 confirm the §5.4-vs-§3.7 split is load-bearing |
| `SmtpReply` structured parser (RFC 3463) | G1 §1.3, G1 §3.3, `submission_status.nim:239` | H1 §5 | Entity-field lift: `DeliveryStatus.smtpReply: SmtpReply` → `ParsedSmtpReply`; no on-demand helper |
| `addEmailQueryWithSnippets` compound builder | F1 Rule-of-Three backlog | H1 §3 | New builder atop `ChainedHandles[A, B]`; uses existing `addSearchSnippetGet` internally |
| First-login `addEmailQueryWithThreads` | G1 Appendix Roadmap | H1 §4 | New builder atop `ChainedHandles4[A, B, C, D]`; emits the RFC 8621 §4.10 canonical 4-invocation chain byte-for-byte |
| `ResultRefPath` constant enumeration | Implicit in every existing back-reference builder | H1 §4 | Path constants centralised in `dispatch.nim`; stringly-typed paths retired at call sites touched |
| Compile-time participation gates | Implicit in `be21db0` | H1 §2a, §3.5 | `registerCompoundMethod(P, I)` and `registerChainableMethod(P)` templates emitted at `mail_entities.nim` module scope |
| RFC §10 IANA audit | Never explicit; implicit in every capability/role/keyword commit | H1 §6 | Full matrix per RFC 8621 §10 subsection, cross-referenced to file:line |

G1 §1.3 also deferred **Part G2 (EmailSubmission test specification)**.
That remains deferred — §8.4 confirms it is out of scope for H1 and
handled separately per user direction.

### 1.3. Design invariants H1 holds itself to

Every section of H1 is obligated to satisfy all eight of these. Any
proposal that cannot is restructured or deferred to §8.

1. **Single translator invariant.** Every new domain ADT has exactly
   one `toValidationError` (or `toSerdeViolation`) function; adding a
   variant forces one compile error at one site. Mirrors `515f3bd`'s
   `TokenViolation` translator, `c8f45b3`'s `SerdeViolation` translator,
   and `769d56a`'s `Conflict → ValidationError` translator.

2. **Distinct newtype invariant.** Every semantically-distinct numeric
   or tokenised string is a distinct type with a smart constructor; no
   bare `uint16`/`string` carries domain meaning past the serde
   boundary. Mirrors G1's `HoldForSeconds`, `MtPriority`, and
   `RFC5321Keyword`.

3. **Template inheritance invariant.** Any re-used kernel that must
   live under `{.push raises: [], noSideEffect.}` is exported as a
   `template`, not a `func`, so its body expands inline at the caller's
   purity pragma. Mirrors `7ecddb8`'s `validateUniqueByIt` /
   `duplicatesByIt` templates.

4. **Parse-once invariant.** The rich type is constructed at the serde
   boundary and carried in the interior. No interior re-parsing, no
   "consumers can call the parser on demand." Mirrors `a23f39a`'s
   `Session.rawCore` split and `SetError`'s five payload-bearing arms.

5. **Wire-byte-identical invariant.** Every type migration preserves
   wire output byte-for-byte for canonical inputs; existing serde
   round-trip tests pin the invariant. Non-canonical inputs
   (whitespace, line-ending variation) are canonicalised with an
   explicit documented policy. Mirrors `be21db0`'s explicit
   "wire output is byte-identical" framing.

6. **Stdlib-delegation invariant.** If stdlib has the right primitive,
   use it — no wrapper. `toHashSet`, `withValue`, `containsOrIncl`,
   `fieldPairs` are the vocabulary. Mirrors `c4a2445`'s retirement of
   hand-rolled set-construction loops.

7. **Compile-time participation invariant.** Any method that joins a
   compound or a chain is gated by a registration template checked at
   module scope, not at first call site. Mirrors `be21db0`'s
   `registerSettableEntity(T)`.

8. **Clean-refactor invariant.** Every migrated symbol is DELETED, not
   aliased, deprecated, or bridged. No `{.deprecated.}` pragma on any
   retired type, field, or function. No `type SmtpReply* =
   ParsedSmtpReply` alias preserving a retired name. No proxy accessor
   (e.g. `func copy(h: EmailCopyHandles): auto = h.primary`). No
   `when defined(...)` conditional-compile shim. No stale docstring,
   inline comment, or `TODO`/`FIXME`/`XXX` marker referencing the old
   design. The `ParsedSmtpReply.raw*` field exists for diagnostic
   fidelity, **not** as a back-compat escape hatch. If a field, type,
   function, or enum variant is replaced, the old form leaves zero
   trace in source, tests, or prose. Mirrors `515f3bd`'s
   "`validateServerAssignedToken` deleted entirely, no compat shim"
   and `c8f45b3`'s wholesale `SerdeViolation` replacement without
   transitional arms. §9 encodes this as a grep-verifiable inventory.

### 1.4. Module-and-file impact summary

| File | Verb | § | Wire-byte impact |
|---|---|---|---|
| `src/jmap_client/dispatch.nim` | Add `CompoundHandles`, `ChainedHandles`, `ChainedHandles4` generics; `getBoth`/`getAll` extractors; `registerCompoundMethod` / `registerChainableMethod` gates; `ResultRefPath` enum | §2, §3, §4 | none |
| `src/jmap_client/mail/mail_builders.nim` | Replace object-type bodies for `EmailCopyHandles`/`EmailCopyResults` with type-alias specialisations; delete per-site `getBoth`; add `EmailQueryThreadChain` alias, `DefaultDisplayProperties` const, `addEmailQueryWithThreads` builder | §2, §4 | none (wire output of `addEmailCopyAndDestroy` unchanged; new builder is additive) |
| `src/jmap_client/mail/mail_methods.nim` | Add `addEmailQueryWithSnippets` + `EmailQuerySnippetChain` alias | §3 | none (new surface) |
| `src/jmap_client/mail/mail_entities.nim` | Emit `registerCompoundMethod` and `registerChainableMethod` invocations at module scope | §2.4, §3.5 | none |
| `src/jmap_client/mail/email_submission.nim` | Replace object-type bodies for `EmailSubmissionHandles`/`EmailSubmissionResults` with type-alias specialisations | §2 | none |
| `src/jmap_client/mail/submission_builders.nim` | Delete per-site `getBoth` for `EmailSubmissionHandles` | §2 | none |
| `src/jmap_client/mail/submission_status.nim` | Retire `SmtpReply`; add `ReplyCode`, `StatusCodeClass`, `SubjectCode`, `DetailCode`, `EnhancedStatusCode`, `ParsedSmtpReply`; extend `SmtpReplyViolation` from 10 to 15 variants; add atomic-detector templates + composite detector + single translator; migrate `DeliveryStatus.smtpReply` field | §5 | canonical byte-identical |
| `src/jmap_client/mail/serde_submission_status.nim` | Route `DeliveryStatus` serde through `parseSmtpReply` / `renderSmtpReply` | §5 | canonical byte-identical |

No C ABI, no L4 transport, no L5 export surface changes. H1 is entirely
L1–L3.

### 1.5. Lineage — campaign commits H1 explicitly mirrors

Each of these commits demonstrates a pattern H1 copies. Short hashes
are cited inline throughout the design; this table is the master list.

| Commit | Pattern |
|---|---|
| `be21db0` | `SetRequest[T, C, U]` associated-type widening; `registerSettableEntity(T)` compile-time overload gate at module scope |
| `7ecddb8` | Atomic helpers exported as templates so `{.push raises: [], noSideEffect.}` inherits through expansion to every caller |
| `c4a2445` | Delegate to stdlib when stdlib is correct; retire hand-rolled loops whose shape duplicates `toHashSet` / `withValue` |
| `c8f45b3` | `SerdeViolation` aeson/yojson-shaped sum; RFC 6901 path carried through composition; single translator at the L3/L4 boundary |
| `769d56a` | `withValue` over raising `Table.[]`; small named domain ADT (`Conflict`, `PathShape`, `PathOp`) for internal classification; single translation to `ValidationError` |
| `515f3bd` | `TokenViolation` ADT; six atomic `detectX` + five composite detectors; `typeName`-parameterised translator; smart ctor `validateServerAssignedToken` retired entirely, no compat shim |
| `a23f39a` | `ContentDisposition` sealed sum; `Session.rawCore` split; `SetError` extended with five RFC 8621 payload-bearing arms — runtime assertion lifted into type-level invariant |

---

## 2. `CompoundHandles[A, B]` — collapsing two per-site compound types

### 2.1. The shape

RFC 8620 §5.4 implicit calls share a `MethodCallId` between the primary
method and the server-emitted follow-up. The handle for the follow-up
must carry both the call-id *and* the expected method name — a
`NameBoundHandle[T]` — so dispatch can disambiguate the sibling
invocations without a filter argument at the extraction site. The
library already embodies this at `dispatch.nim:34, 59`; H1 does not
change it.

What H1 changes is the per-site compound-handle record. The library has
two instances of the same structural shape: `EmailCopyHandles` at
`src/jmap_client/mail/mail_builders.nim:253-260` and
`EmailSubmissionHandles` at `src/jmap_client/mail/email_submission.nim:536-553`.
Both pair a `ResponseHandle[A]` with a `NameBoundHandle[B]`; both have
a mirror results type pairing an `A` with a `B`; both have an
almost-identical `getBoth` body (`mail_builders.nim:310-320` and
`submission_builders.nim:127-140`) that extracts the pair and returns
`Result[Results, MethodError]`. The repetition is exact, and the pattern
is a direct encoding of RFC 8620 §5.4 — generic over the pair of
response types.

The generic belongs in `dispatch.nim` alongside the `ResponseHandle[T]`
and `NameBoundHandle[T]` primitives it composes from:

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
  ## Paired extraction target for ``getBoth(CompoundHandles[A, B])``.
  primary*:  A
  implicit*: B

func getBoth*[A, B](
    resp: Response, handles: CompoundHandles[A, B]
): Result[CompoundResults[A, B], MethodError] =
  ## Extract both responses from a §5.4 implicit-call compound. The
  ## ``primary`` handle dispatches through the default ``get[T]``
  ## overload; ``implicit`` dispatches through the ``NameBoundHandle``
  ## overload, which applies the method-name filter from the handle.
  mixin fromJson
  let primary  = ?resp.get(handles.primary)
  let implicit = ?resp.get(handles.implicit)
  ok(CompoundResults[A, B](primary: primary, implicit: implicit))
```

`{.ruleOff: "objects".}` is consistent with the existing per-site
record declarations; the generic inherits the convention rather than
introducing a new rule posture.

### 2.2. Type-alias specialisations

The two sites become one-line type aliases. The domain name lives at
the type-alias level; the field names reflect RFC 8620 §5.4 vocabulary
verbatim (H2 below).

In `src/jmap_client/mail/mail_builders.nim` — replacing the object
bodies at lines 253–265:

```nim
type EmailCopyHandles* = CompoundHandles[
  CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]

type EmailCopyResults* = CompoundResults[
  CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]
```

In `src/jmap_client/mail/email_submission.nim` — replacing the object
bodies at lines 536–553:

```nim
type EmailSubmissionHandles* = CompoundHandles[
  EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]

type EmailSubmissionResults* = CompoundResults[
  EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]
```

The per-site `getBoth` bodies in `mail_builders.nim:310-320` and
`submission_builders.nim:127-140` are DELETED. The generic `getBoth`
in `dispatch.nim` subsumes them.

### 2.3. Migration at call sites

| Old access | New access |
|---|---|
| `handles.copy` | `handles.primary` |
| `handles.destroy` | `handles.implicit` |
| `handles.submission` | `handles.primary` |
| `handles.emailSet` | `handles.implicit` |
| `results.copy` | `results.primary` |
| `results.destroy` | `results.implicit` |
| `results.submission` | `results.primary` |
| `results.emailSet` | `results.implicit` |

Call sites in `src/` and `tests/` are grep-and-replaced. No UFCS
wrappers, no proxy accessors (H2 below), no three-option buffet. The
domain-named field vocabulary is retired because the replacement
(`primary`/`implicit`) is RFC 8620 §5.4 verbatim — at the field level
the spec dichotomy is the truth, and the domain vocabulary survives
at the type-alias level where it belongs.

Expected grep queries for migration coverage (§9 enumerates them):

```
rg -n '\bhandles\.copy\b|\bhandles\.destroy\b' src/ tests/
rg -n '\bhandles\.submission\b|\bhandles\.emailSet\b' src/ tests/
rg -n '\bresults\.copy\b|\bresults\.destroy\b' src/ tests/
rg -n '\bresults\.submission\b|\bresults\.emailSet\b' src/ tests/
```

Each must return zero hits post-migration.

### 2.4. Compile-time participation gate (`registerCompoundMethod`)

Mirroring `be21db0`'s `registerSettableEntity(T)`, each compound
participant gets a module-scope registration template that compile-
checks the types involved. Regression surfaces at compile time, not
at first call:

```nim
template registerCompoundMethod*(Primary, Implicit: typedesc) =
  ## Compile-checks that ``Primary`` has a registered method name and
  ## that ``Implicit`` is nameable via ``NameBoundHandle``. Call at
  ## module scope in ``mail_entities.nim`` for each compound
  ## participant. Regression surfaces as a ``static:`` failure at
  ## module load, not at first builder invocation.
  static:
    doAssert declared(methodName(Primary)),
      $Primary & " not registered via registerMethod"
    doAssert compiles(NameBoundHandle[Implicit]),
      $Implicit & " not NameBoundHandle-compatible"
```

Applied in `src/jmap_client/mail/mail_entities.nim`:

```nim
registerCompoundMethod(
  CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem])
registerCompoundMethod(
  EmailSubmissionSetResponse, SetResponse[EmailCreatedItem])
```

Adding a new §5.4 compound method (e.g. a hypothetical
`Identity/set` + implicit `Email/set`) requires both a matching
`CompoundHandles[...]` type alias and a `registerCompoundMethod`
invocation; omitting the latter is a static assertion failure.

### 2.5. Wire-byte identicality

The generic is a structural refactor with zero wire consequences. The
existing regression net pins byte-identicality:

- `tests/serde/mail/tserde_email_copy.nim` — `EmailCopyHandles`
  extraction round-trips.
- `tests/unit/mail/tmail_builders.nim` — compound-scenario wire
  output assertions for `addEmailCopyAndDestroy`.
- `tests/serde/mail/tserde_email_submission.nim` and
  `tests/unit/mail/tsubmission_builders.nim` — analogous coverage for
  `EmailSubmissionHandles`.

Implementation PRs MUST not modify these tests except for the field-
name migration (§2.3). Any change to assertion payloads, method-call
order, or response envelope shape is an unintended wire regression.

### 2.6. File impact

- `src/jmap_client/dispatch.nim` — add `CompoundHandles`,
  `CompoundResults`, generic `getBoth`, `registerCompoundMethod`.
- `src/jmap_client/mail/mail_builders.nim:253-265, 310-320` —
  `EmailCopyHandles`/`EmailCopyResults` become type aliases; per-site
  `getBoth` deleted.
- `src/jmap_client/mail/email_submission.nim:536-553` —
  `EmailSubmissionHandles`/`EmailSubmissionResults` become type aliases.
- `src/jmap_client/mail/submission_builders.nim:127-140` — per-site
  `getBoth` deleted.
- `src/jmap_client/mail/mail_entities.nim` — add two
  `registerCompoundMethod` invocations at module scope.

Wire impact: zero.

### 2.7. Decisions

- **H1. Promotion threshold — Rule-of-Two, not Rule-of-Three.** G1
  §1.3 declared F1's Rule-of-Three unmet with two compound sites. H1
  promotes anyway, and the reasoning is explicit: the structural
  repetition is *exact* (field shapes match to the byte, `getBoth`
  bodies are identical modulo type substitution), the collapse removes
  two `getBoth` bodies (one in each mail module), and §3–§4 introduce
  structurally distinct machinery (back-reference chains, arity-4
  chain) — confirming that the §5.4-vs-§3.7 split is real architecture
  rather than a coincidence of arity. `be21db0` promoted
  `SetRequest[T, C, U]` over three `/set` call sites; H1 promotes over
  two because the second axis of variation (`NameBoundHandle` on the
  implicit side) is itself the stable feature. Rule-of-Three remains
  the default elsewhere in the codebase.

- **H2. Field names `primary`/`implicit`, not `copy`/`destroy` or
  `submission`/`emailSet`.** Old field names `copy`/`destroy`/
  `submission`/`emailSet` are DELETED at every call site — no proxy
  accessors, no field-rename aliases, no `{.deprecated.}` stubs, no
  "for backward compatibility" comments. The replacement vocabulary
  is RFC 8620 §5.4 verbatim: the spec calls them the *call* and the
  *implicit call*, which in Nim field-name style becomes `primary` and
  `implicit`. Domain vocabulary (`copy`, `destroy`, `submission`,
  `emailSet`) survives at the type-alias level, where it names *which*
  compound we are in. Matches `c4a2445`'s "duplicated appearance IS
  duplicated knowledge when the knowledge is domain-specific" — here
  the knowledge at the field level is RFC-spec-level.

- **H3. `getBoth` lives in `dispatch.nim`, not in a mail-specific
  module.** The generic is fully parametric in `A` and `B`; there is
  no mail-specific obligation. It composes from `ResponseHandle[T]`
  and `NameBoundHandle[T]`, both of which live in `dispatch.nim`.
  Placing the generic there also enables `CompoundHandles[A, B]` to
  be reused for any future non-mail §5.4 compound without a gratuitous
  import.

- **H4. Compile-time gate at module scope via
  `registerCompoundMethod(Primary, Implicit)`.** Mirrors `be21db0`'s
  `registerSettableEntity(T)`. Regression surfaces at module load,
  not at first builder invocation. The `static:` block verifies that
  `Primary` has a registered method name and that `Implicit` can
  legally inhabit a `NameBoundHandle`.

---

## 3. `ChainedHandles[A, B]` and `addEmailQueryWithSnippets`

### 3.1. Why a sibling generic, not a subtype of `CompoundHandles`

RFC 8620 §3.7 back-reference chains and RFC 8620 §5.4 implicit calls
are superficially similar — both tie two responses together in one
request — but structurally distinct:

| | §5.4 implicit call | §3.7 back-reference chain |
|---|---|---|
| Number of invocations | 1 request, 2 responses | 2 requests, 2 responses |
| Call-id | 1, shared | 2, distinct |
| Disambiguation | method-name filter (`NameBoundHandle`) | distinct call-ids (plain `ResponseHandle`) |
| Extraction | requires `NameBoundHandle` overload on the implicit side | plain `get[T]` on both |
| Typical RFC usage | `onSuccessDestroyOriginal`, `onSuccessUpdateEmail` | `#ids` back-reference to a preceding query's `/ids` |

Hiding both behind a single generic would force one of two bad
outcomes: (a) the §3.7 side carries a superfluous method-name filter
that is noise in its semantics, or (b) the §5.4 invariant is buried
under an `Opt[MethodName]` that evaluates the filter only sometimes —
which is the worst of both worlds. Type-level honesty over spurious
unification (H5).

The library is the richer for having two named generics that describe
two RFC mechanisms. `CompoundHandles[A, B]` at §2 and
`ChainedHandles[A, B]` at §3 are siblings, and the choice between them
at a call site IS the spec-level distinction the builder is making.

### 3.2. The shape

```nim
type ChainedHandles*[A, B] {.ruleOff: "objects".} = object
  ## Paired handles for RFC 8620 §3.7 back-reference chains. Each
  ## handle binds a distinct ``MethodCallId``; no method-name filter
  ## is needed because the call-ids are unique.
  first*:  ResponseHandle[A]
  second*: ResponseHandle[B]

type ChainedResults*[A, B] {.ruleOff: "objects".} = object
  ## Paired extraction target for ``getBoth(ChainedHandles[A, B])``.
  first*:  A
  second*: B

func getBoth*[A, B](
    resp: Response, handles: ChainedHandles[A, B]
): Result[ChainedResults[A, B], MethodError] =
  mixin fromJson
  let first  = ?resp.get(handles.first)
  let second = ?resp.get(handles.second)
  ok(ChainedResults[A, B](first: first, second: second))
```

Note the overloading: `getBoth` is defined for both `CompoundHandles`
and `ChainedHandles`. Both overloads live in `dispatch.nim`; the
compiler picks the right one by argument type. There is no ambiguity
because the argument types have no structural overlap.

### 3.3. `addEmailQueryWithSnippets` — RFC 8621 §4.10 encoded in types

The builder emits two invocations: `Email/query` followed by
`SearchSnippet/get` with a `ResultReference` that chains the snippet
request to the query's `/ids`. The RFC 8621 §4.10 example shows this
exact pattern; H1 §3 encodes it as a single builder.

Public signature, in `src/jmap_client/mail/mail_methods.nim`:

```nim
type EmailQuerySnippetChain* = ChainedHandles[
  QueryResponse[Email], SearchSnippetGetResponse]

func addEmailQueryWithSnippets*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = false,
): (RequestBuilder, EmailQuerySnippetChain) =
  ## Compound Email/query + SearchSnippet/get (RFC 8621 §4.10 + §5.1).
  ## Emits two invocations with a RFC 8620 §3.7 back-reference from
  ## the snippet request's ``emailIds`` to the query's ``/ids``.
  ## ``filter`` is mandatory — snippets are meaningless without a
  ## query context (RFC 8621 §5.1 ¶2).
  let (b1, queryHandle) = addEmailQuery(
    b, accountId, filter, sort, queryParams, collapseThreads)
  let (b2, snippetHandle) = addSearchSnippetGetByRef(
    b1, accountId, filter,
    emailIdsRef = ResultReference(
      resultOf: callId(queryHandle),
      name: mnEmailQuery,
      path: $rrpIds))
  (b2, EmailQuerySnippetChain(
    first: queryHandle, second: snippetHandle))
```

A new `addSearchSnippetGetByRef` helper is introduced to accept a
`ResultReference` for `emailIds` — the existing `addSearchSnippetGet`
(`mail_methods.nim:193-213`) takes a literal `firstEmailId: Id` +
`restEmailIds: seq[Id]` cons-cell, which is fine when the ids are
known at call time but cannot express a back-reference. The two
builders coexist: `addSearchSnippetGet` for direct callers,
`addSearchSnippetGetByRef` for chain builders. H8 below explains why
the cons-cell discipline does NOT propagate into the compound.

### 3.4. Filter handling and invariants

- **`filter` is mandatory**, not `Opt[Filter[EmailFilterCondition]]`.
  RFC 8621 §5.1 ¶2 is explicit: SearchSnippet/get returns snippets
  for the given search criteria. A snippet request without a filter
  is semantically void — the library refuses to construct one at the
  type level. Matches the existing `addSearchSnippetGet` discipline
  (filter is a required argument there too).
- **Filter duplicated literally on the wire**, not shared via a
  second `ResultReference`. RFC 8620 §3.7 permits both: the chain
  builder could emit a single `filter` in the `Email/query`
  invocation and reference it from the snippet invocation. Literal
  duplication is simpler, each invocation stays self-contained, and
  no new `ResultReference` path is invented (H7). If a future
  optimisation materialises a `#filter` reference path, §8.7 covers
  adding it as a `ResultRefPath` variant.
- **Empty-ids back-reference is legal.** If the `Email/query`
  resolves to zero ids, the `SearchSnippet/get` request receives an
  empty `emailIds` array via the back-reference. RFC 8620 §5.1 does
  not forbid this — the snippet request is degenerate-but-valid and
  returns an empty list. The existing `addSearchSnippetGet`'s
  `firstEmailId + restEmailIds` cons-cell enforces non-emptiness at
  compile time for the direct-call case; that discipline does not
  propagate into the back-reference case because the back-reference
  target cannot be statically known (H8). If a caller wants the
  non-empty-by-construction guarantee, they build two invocations
  manually — the library does not provide a back-reference-with-
  non-empty-guarantee variant because the RFC does not describe one.

### 3.5. Compile-time participation gate (`registerChainableMethod`)

Analogue of `registerCompoundMethod`:

```nim
template registerChainableMethod*(Primary: typedesc) =
  ## Compile-checks that ``Primary`` has a registered method name,
  ## so a back-reference to it can be constructed with a typed
  ## ``ResultReference`` rather than stringly-typed parts.
  static:
    doAssert declared(methodName(Primary)),
      $Primary & " not registered via registerMethod"
```

Applied in `src/jmap_client/mail/mail_entities.nim`:

```nim
registerChainableMethod(QueryResponse[Email])
```

Adding a new chain whose first step references an unregistered method
is a static assertion failure at module load.

### 3.6. File impact

- `src/jmap_client/dispatch.nim` — add `ChainedHandles`,
  `ChainedResults`, overloaded `getBoth`, `registerChainableMethod`,
  `ResultRefPath` enum (see §4.4).
- `src/jmap_client/mail/mail_methods.nim` — add
  `addEmailQueryWithSnippets`, `EmailQuerySnippetChain` type alias,
  `addSearchSnippetGetByRef` helper.
- `src/jmap_client/mail/mail_entities.nim` — add
  `registerChainableMethod(QueryResponse[Email])`.

Wire impact: new additive builder; no existing wire shape touched.

### 3.7. Decisions

- **H5. `ChainedHandles[A, B]` as a sibling to `CompoundHandles[A, B]`,
  not a subtype or unified super-generic.** Documented at §3.1. Type-
  level honesty over spurious unification. Same principle that drove
  `769d56a` to keep `ConflictKind` distinct from `ValidationError` —
  two ADTs, one translation boundary, no forced sharing of shape.

- **H6. `filter: Filter[EmailFilterCondition]` is mandatory, not
  `Opt[Filter[...]]`.** Documented at §3.4. RFC 8621 §5.1 ¶2 forbids
  a snippet request without a filter; the library lifts that
  obligation into the type of the builder argument. Parity with the
  existing `addSearchSnippetGet`'s mandatory-filter discipline.

- **H7. Filter duplicated literally on the wire, not shared via a
  second `ResultReference`.** Documented at §3.4. RFC 8620 §3.7
  permits both; the choice is made for simplicity and wire-level
  self-containment. No new `ResultReference` path is invented for
  filter sharing.

- **H8. Cons-cell non-emptiness of `addSearchSnippetGet` does NOT
  propagate into the compound.** Documented at §3.4. A back-reference
  resolves at request-execution time, not at compile time. If the
  back-reference target is empty, the library still emits a valid
  (if degenerate) request per RFC. Callers who need a non-empty
  guarantee assemble two invocations themselves.

- **H9. Compile-time gate via `registerChainableMethod(Primary)`.**
  Documented at §3.5. Mirrors `registerCompoundMethod` and
  `registerSettableEntity`. Emitted at module scope in
  `mail_entities.nim`.

---

## 4. `ChainedHandles4[A, B, C, D]` and `addEmailQueryWithThreads`

### 4.1. The shape at arity 4

RFC 8621 §4.10's canonical "first-login" workflow is a four-invocation
back-reference chain:

1. `Email/query` — find the messages.
2. `Email/get` `{threadId}` — fetch only the thread ids of those messages.
3. `Thread/get` — fetch the threads and the email ids within each.
4. `Email/get` — fetch the full display properties for the emails in
   those threads.

This is a structurally honest arity-4 chain, not a two-step chain
repeated. Each back-reference path is a distinct RFC 6901 JSON Pointer
(`/ids`, `/list/*/threadId`, `/list/*/emailIds`), not one shared path
used twice. A generic at arity 2 cannot express it without ceremony;
H1 introduces the arity-4 sibling generic (H10):

```nim
type ChainedHandles4*[A, B, C, D] {.ruleOff: "objects".} = object
  ## Paired handles for a 4-step RFC 8620 §3.7 back-reference chain.
  ## Each handle binds a distinct ``MethodCallId``.
  first*:  ResponseHandle[A]
  second*: ResponseHandle[B]
  third*:  ResponseHandle[C]
  fourth*: ResponseHandle[D]

type ChainedResults4*[A, B, C, D] {.ruleOff: "objects".} = object
  first*:  A
  second*: B
  third*:  C
  fourth*: D

func getAll*[A, B, C, D](
    resp: Response, handles: ChainedHandles4[A, B, C, D]
): Result[ChainedResults4[A, B, C, D], MethodError] =
  ## Extract all four responses from a §3.7 arity-4 chain.
  mixin fromJson
  let first  = ?resp.get(handles.first)
  let second = ?resp.get(handles.second)
  let third  = ?resp.get(handles.third)
  let fourth = ?resp.get(handles.fourth)
  ok(ChainedResults4[A, B, C, D](
    first: first, second: second, third: third, fourth: fourth))
```

Two type parameters for a two-step chain, four for a four-step chain
(H10). The naming mirrors `be21db0`'s `SetRequest[T, C, U]` — just-
enough-parametricity, no more. Rule-of-Three for a variadic
`ChainedHandlesN` is deferred to §8.5.

### 4.2. `addEmailQueryWithThreads` — spec-verbatim

```nim
type EmailQueryThreadChain* = ChainedHandles4[
  QueryResponse[Email],    # step 1: Email/query
  GetResponse[Email],      # step 2: Email/get {threadId}
  GetResponse[Thread],     # step 3: Thread/get
  GetResponse[Email],      # step 4: Email/get {display props}
]

func addEmailQueryWithThreads*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    sort: seq[EmailComparator],
    queryParams: QueryParams,
    collapseThreads: bool = true,     # RFC §4.10 default
    displayProperties: seq[string] = DefaultDisplayProperties,
): (RequestBuilder, EmailQueryThreadChain) =
  ## RFC 8621 §4.10 first-login workflow encoded in types. Emits the
  ## exact 4-invocation back-reference chain the RFC demonstrates,
  ## with ``ResultReference`` paths from ``ResultRefPath`` — no
  ## stringly-typed JSON Pointers at this site.
  let (b1, queryH) = addEmailQuery(
    b, accountId, filter, Opt.some(sort), queryParams, collapseThreads)

  let (b2, threadIdGetH) = addEmailGetByRef(
    b1, accountId,
    idsRef = ResultReference(
      resultOf: callId(queryH), name: mnEmailQuery,
      path: $rrpIds),
    properties = @["threadId"])

  let (b3, threadGetH) = addThreadGetByRef(
    b2, accountId,
    idsRef = ResultReference(
      resultOf: callId(threadIdGetH), name: mnEmailGet,
      path: $rrpListThreadId))

  let (b4, displayGetH) = addEmailGetByRef(
    b3, accountId,
    idsRef = ResultReference(
      resultOf: callId(threadGetH), name: mnThreadGet,
      path: $rrpListEmailIds),
    properties = displayProperties,
    fetchHtmlBody = true,
    fetchAllBodyValues = true,
    maxBodyValueBytes = UnsignedInt(256))

  (b4, EmailQueryThreadChain(
    first: queryH, second: threadIdGetH,
    third: threadGetH, fourth: displayGetH))
```

Builder-helper dependencies `addEmailGetByRef` and `addThreadGetByRef`
accept a `ResultReference` for `ids` — siblings of the existing
literal-ids overloads (parity with §3's `addSearchSnippetGetByRef`).
Both are introduced in this commit.

### 4.3. `DefaultDisplayProperties`

The RFC 8621 §4.10 example literally enumerates nine display
properties for the fourth invocation. H1 exposes them as a module-
level `const` whose docstring cites the RFC (H12):

```nim
const DefaultDisplayProperties*: seq[string] = @[
  "threadId", "mailboxIds", "keywords", "hasAttachment",
  "from", "subject", "receivedAt", "size", "preview",
]
  ## RFC 8621 §4.10 first-login example display properties. Override
  ## is a normal ``displayProperties`` argument; this const is the
  ## default for a minimally-configured first-login scenario.
```

Callers who want different properties pass their own list. The const
is not magic — it is one named, auditable default, visible at one
site, and the docstring pins its RFC origin.

`collapseThreads` defaults to `true` per RFC §4.10 example (H13).

### 4.4. `ResultRefPath` — path constants

RFC 8621 §4.10 uses three JSON Pointer paths as back-reference
targets: `/ids`, `/list/*/threadId`, `/list/*/emailIds`. H1
centralises these as a string-backed enum in `dispatch.nim` (H16):

```nim
type ResultRefPath* = enum
  ## JSON Pointer paths used in RFC 8620 §3.7 ``ResultReference.path``
  ## values. Enumerated variants ensure that builders never emit
  ## stringly-typed JSON Pointers; new chain builders that need a new
  ## path add a variant here (see §8.7 for scope).
  rrpIds               = "/ids"
  rrpListThreadId      = "/list/*/threadId"
  rrpListEmailIds      = "/list/*/emailIds"
```

Usage at builder sites:

```nim
path: $rrpIds              # "/ids"
path: $rrpListThreadId     # "/list/*/threadId"
path: $rrpListEmailIds     # "/list/*/emailIds"
```

`$` on the string-backed enum returns the backing string verbatim
(per `nim-type-safety.md`). Adding a new back-reference path is a
one-line addition to the enum + one call site — and the enum
discipline catches typos at compile time (no `\\ids` vs `/ids`
regressions). Broader enumeration of every JMAP back-reference path
in the wild is out of scope; see §8.7.

### 4.5. File impact

- `src/jmap_client/dispatch.nim` — add `ChainedHandles4`,
  `ChainedResults4`, `getAll`, `ResultRefPath` enum.
- `src/jmap_client/mail/mail_builders.nim` — add
  `EmailQueryThreadChain` alias, `DefaultDisplayProperties` const,
  `addEmailQueryWithThreads` builder, `addEmailGetByRef` and
  `addThreadGetByRef` helpers.

Wire impact: new additive builder; RFC-§4.10-verbatim output.

### 4.6. Decisions

- **H10. `ChainedHandles4[A, B, C, D]` as a separate named generic,
  not a bespoke 4-field object.** Four type parameters is the honest
  arity; `type EmailQueryThreadChain = ChainedHandles4[...]` hides
  them at the call site. Matches the `SetRequest[T, C, U]` naming
  precedent.

- **H11. Field names `first`/`second`/`third`/`fourth`.** Not
  `query`/`threadIdFetch`/`threads`/`emails`. Consistency with
  `ChainedHandles[A, B]` at the field level; domain vocabulary at the
  type-alias level. Same decision as H2 for compound handles.

- **H12. `DefaultDisplayProperties` as a module-level `const` with
  RFC docstring.** Override is a normal argument. One named
  auditable default, visible at one site.

- **H13. `collapseThreads` defaults to `true`.** RFC §4.10 example
  default.

- **H14. `getAll` is one function, not four partial extractors.**
  Partial extraction is a user concern — `resp.get(handles.first)`
  is already available via field access. No `getFirstTwo`,
  `getLastThree`, or similar combinatorial explosion.

- **H15. Rule-of-Three deferred for `ChainedHandlesN` macro-
  generated variadic.** Today we have `ChainedHandles[A, B]` +
  `ChainedHandles4[A, B, C, D]`. When a 5-step chain materialises,
  or when a third distinct arity is justified by a real builder,
  introduce `template defineChainedHandles(n: static int)` that
  generates arity-N generics. Noted in §8.5.

- **H16. `ResultRefPath` path constants centralised in
  `dispatch.nim`.** No stringly-typed paths at builder call sites.
  New paths added as enum variants.

---

## 5. `ParsedSmtpReply` — retiring `SmtpReply`

### 5.1. Why this is the campaign's thesis in miniature

Today, `DeliveryStatus.smtpReply` is a `distinct string` validated for
the RFC 5321 §4.2 surface grammar but opaque at the Nim level to
everything deeper. Callers who want to branch on the Reply-code, the
enhanced status class, or the subject/detail codes must re-parse the
string — every time, at every call site, with no shared vocabulary.
RFC 3463 §2 decomposition is explicitly deferred at
`submission_status.nim:239` with a `G12` marker. The deferral is the
last major "validated-but-opaque" field in the RFC 8621 surface.

H1 lifts it. `DeliveryStatus.smtpReply` becomes `ParsedSmtpReply`, an
object that carries the fully-decomposed structure *as well as* the
original wire bytes (`raw*: string`) for diagnostic fidelity. Parsing
happens once at the serde boundary; consumers branch on typed fields;
no one re-parses (H23, parse-once invariant).

This is the straight analogue of three campaign commits:

- `a23f39a` lifted `Session.rawCore` from a runtime assertion into a
  type-level split; `SetError` gained five payload-bearing arms that
  replaced stringly-typed "extras" fields at specific `errorType`
  values. "Parse once; trust forever" applied to session and errors.
- `c8f45b3` replaced string error messages in serde with
  `SerdeViolation`, a sealed sum whose RFC 6901 path travels through
  composition and whose single translator projects to
  `ValidationError` at the L3/L4 boundary.
- `515f3bd` introduced `TokenViolation`, a sealed sum built from six
  atomic `detectX` primitives composed via `?` into five composite
  detectors, with one `typeName`-parameterised translator — and
  retired `validateServerAssignedToken` entirely, no compat shim.

H1 §5 copies the `515f3bd` shape beat-for-beat:

- **Atomic detectors** (templates, per `7ecddb8` — see H21).
- **Composite detector** built by `?`-chaining atomics.
- **Single translator** `toValidationError(v: SmtpReplyViolation, raw: string): ValidationError`.
- **No compat shim** — `SmtpReply` is deleted wholesale.

### 5.2. Four distinct newtypes + a string-backed enum

No bare `uint16` or `string` survives carrying domain meaning past the
serde boundary (H18, distinct newtype invariant). The Reply-code, the
status-code class, the subject sub-code, and the detail sub-code each
get their own type:

```nim
type ReplyCode* = distinct uint16
  ## RFC 5321 §4.2.3 three-digit Reply-code. Validated by per-digit
  ## grammar in ``parseReplyCode`` / ``detectReplyCodeGrammar``.
  ## Range 200..599 with first digit in {2, 3, 4, 5}, second in
  ## {0..5}, third in {0..9}. Unrepresentable as a bare number — a
  ## ``uint16 = 550`` is not a ``ReplyCode(550)`` without going
  ## through the smart constructor.

type StatusCodeClass* = enum
  ## RFC 3463 §3.1 status-code class digit. String-backed for
  ## lossless wire round-trip; ``$scc = "2" | "4" | "5"``.
  sccSuccess          = "2"
  sccTransientFailure = "4"
  sccPermanentFailure = "5"

type SubjectCode* = distinct uint16
  ## RFC 3463 §4 subject sub-code. Bounded 0..999 by the grammar;
  ## within that range all values are forward-compatible per the
  ## IANA Enhanced-Status-Codes registry policy — we do not close
  ## the enum to currently-registered values (H19).

type DetailCode* = distinct uint16
  ## RFC 3463 §4 detail sub-code. Same bounds and rationale as
  ## ``SubjectCode`` — forward-compatible within 0..999.
```

Borrow templates for each distinct newtype follow the existing
`nim-type-safety.md` convention — `==`, `$`, `hash` — but NOT `<` /
`<=` on `ReplyCode` / `SubjectCode` / `DetailCode` since ordering
them is not a meaningful domain operation.

`StatusCodeClass` is a string-backed enum (per `nim-type-safety.md`
"Enums"). `$sccSuccess = "2"` lossless; `parseStatusCodeClass` is the
inverse. Three variants cover RFC 3463 §3.1 exhaustively — no
catch-all arm; unknown class digits fail parsing and become a
`SmtpReplyViolation` variant (H19).

### 5.3. `EnhancedStatusCode` and `ParsedSmtpReply`

```nim
type EnhancedStatusCode* {.ruleOff: "objects".} = object
  ## RFC 3463 §2 enhanced status code triple: class.subject.detail.
  klass*:   StatusCodeClass
  subject*: SubjectCode
  detail*:  DetailCode

type ParsedSmtpReply* {.ruleOff: "objects".} = object
  ## RFC 5321 §4.2 multi-line Reply-line structure, optionally
  ## carrying a RFC 3463 §2 enhanced status code on the final line.
  ##
  ## Constructed at the serde boundary from the raw wire string via
  ## ``parseSmtpReply``; carries the fully-decomposed form plus the
  ## original wire bytes. Consumers branch on typed fields — no one
  ## re-parses the text. ``raw*`` exists for diagnostic fidelity
  ## (e.g., mail tracing, log correlation); it is NOT a back-compat
  ## escape hatch (H17).
  replyCode*: ReplyCode
  enhanced*:  Opt[EnhancedStatusCode]
  text*:      string
    ## Concatenated explanation text (all lines joined with LF), with
    ## Reply-code prefix and enhanced-code prefix stripped.
  raw*:       string
    ## Original wire bytes as received. Preserves whitespace, exact
    ## line endings, and any textstring content — ``toJson`` emits
    ## the canonical form, not ``raw`` (H24).
```

Field ordering: discriminators first (`replyCode`), then typed
subcomponent (`enhanced`), then diagnostic strings (`text`, `raw`).
Matches the G1 `ParsedDeliveredState`/`ParsedDisplayedState` shape
at `submission_status.nim:73-80, 89-93` — classification plus raw,
round-trippable.

### 5.4. Extended `SmtpReplyViolation` enum (10 → 15 variants)

The existing module-local `SmtpReplyViolation` enum at
`submission_status.nim:111-127` has ten variants covering the
RFC 5321 §4.2 surface grammar. H1 extends it — **same site, same
prefix (`sr`), new variants appended** (H20). No variant is renamed;
existing serde and detector code sees the enum exactly as today.

The enum becomes exported (no longer module-local) because tests
assert against variants directly for per-variant error coverage
(H25).

```nim
type SmtpReplyViolation* = enum
  ## Structural and enhanced-code grammatical failures of the RFC
  ## 5321 §4.2 Reply-line surface and the RFC 3463 §2 enhanced
  ## status-code triple. Module-public in H1 for test introspection;
  ## the public parser translates these to ``ValidationError`` at
  ## the wire boundary via ``toValidationError`` — every failure
  ## message lives in one place.

  # --- Surface grammar (unchanged from G1; 10 variants) --------------
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

  # --- Enhanced-code grammar (new in H1; 5 variants) -----------------
  srEnhancedMalformedTriple
    ## Did not parse as three dot-separated numeric components.
  srEnhancedClassInvalid
    ## First digit not in {2, 4, 5} per RFC 3463 §3.1.
  srEnhancedSubjectOverflow
    ## Subject sub-code outside 0..999.
  srEnhancedDetailOverflow
    ## Detail sub-code outside 0..999.
  srEnhancedMultilineMismatch
    ## Multi-line reply with inconsistent enhanced codes across
    ## lines; RFC 3463 §2 requires the enhanced code (when present)
    ## to be identical on every line that carries one.
```

Violation-vocabulary alignment — the first 10 variants are
**identical in name, order, and semantics** to the existing enum at
`submission_status.nim:111-127`. Only the 5 `srEnhanced*` variants
are appended.

| Position | Existing (G1) | Extended (H1) | Change |
|---|---|---|---|
| 1 | `srEmpty` | `srEmpty` | unchanged |
| 2 | `srControlChars` | `srControlChars` | unchanged |
| 3 | `srLineTooShort` | `srLineTooShort` | unchanged |
| 4 | `srBadReplyCodeDigit1` | `srBadReplyCodeDigit1` | unchanged |
| 5 | `srBadReplyCodeDigit2` | `srBadReplyCodeDigit2` | unchanged |
| 6 | `srBadReplyCodeDigit3` | `srBadReplyCodeDigit3` | unchanged |
| 7 | `srBadSeparator` | `srBadSeparator` | unchanged |
| 8 | `srMultilineCodeMismatch` | `srMultilineCodeMismatch` | unchanged |
| 9 | `srMultilineContinuation` | `srMultilineContinuation` | unchanged |
| 10 | `srMultilineFinalHyphen` | `srMultilineFinalHyphen` | unchanged |
| 11 | — | `srEnhancedMalformedTriple` | **new** |
| 12 | — | `srEnhancedClassInvalid` | **new** |
| 13 | — | `srEnhancedSubjectOverflow` | **new** |
| 14 | — | `srEnhancedDetailOverflow` | **new** |
| 15 | — | `srEnhancedMultilineMismatch` | **new** |

Accessibility change: `type SmtpReplyViolation = enum` (module-local
in G1) → `type SmtpReplyViolation* = enum` (exported in H1). No other
difference.

### 5.5. Atomic detectors (templates) + composite detector + single translator

Per H21 (template inheritance invariant), atomic detectors are
exported templates, not funcs. `{.push raises: [], noSideEffect.}` is
already pushed at the top of `submission_status.nim`; template
expansion at call sites picks up the pragma automatically. Mirror of
`7ecddb8`'s `validateUniqueByIt` / `duplicatesByIt`.

```nim
template detectReplyCodeGrammar*(line: string):
    Result[ReplyCode, SmtpReplyViolation] =
  ## Three-digit Reply-code grammar (RFC 5321 §4.2.3). Requires
  ## ``line.len >= 3``. Returns the numeric Reply-code as a
  ## ``ReplyCode``; caller inspects the ``StatusCodeClass`` via the
  ## first digit.
  # expansion …

template detectSeparator*(line: string, isFinal: bool):
    Result[void, SmtpReplyViolation] =
  ## Dispatches on the byte after the Reply-code: SP/HT on a final
  ## line, ``'-'`` on a continuation line.

template detectClassDigit*(c: char):
    Result[StatusCodeClass, SmtpReplyViolation] =
  ## Maps an RFC 3463 §3.1 class digit to ``StatusCodeClass``.

template detectSubjectInRange*(n: uint16):
    Result[SubjectCode, SmtpReplyViolation] =
  ## Bounds check for RFC 3463 §4 subject sub-code.

template detectDetailInRange*(n: uint16):
    Result[DetailCode, SmtpReplyViolation] =
  ## Bounds check for RFC 3463 §4 detail sub-code.

template detectEnhancedTriple*(raw: string):
    Result[EnhancedStatusCode, SmtpReplyViolation] =
  ## RFC 3463 §2 ``class "." subject "." detail``. Composes
  ## ``detectClassDigit`` + ``detectSubjectInRange`` +
  ## ``detectDetailInRange`` via ``?``.

template detectMultilineConsistency*[T](
    per: openArray[T],
    pick: proc(x: T): auto {.noSideEffect, raises: [].},
    violation: SmtpReplyViolation): Result[void, SmtpReplyViolation] =
  ## Generalises the multi-line consistency check over a selector.
  ## Used once for Reply-code consistency (existing RFC 5321 §4.2.1
  ## rule) and once for enhanced-code consistency (new RFC 3463 §2
  ## rule). One template, two call sites (H22).
```

The `pick: proc` parameter takes a callback with the pure pragma
already applied — `mixin` + `effectsOf: pick` would be equivalent but
the explicit pragma is clearer and matches the codebase's existing
`noSideEffect, raises: []` callback discipline.

Composite detector and translator:

```nim
func detectParsedSmtpReply(raw: string):
    Result[ParsedSmtpReply, SmtpReplyViolation] =
  ## Parses a multi-line Reply into a ``ParsedSmtpReply``. Composes
  ## the surface-grammar detectors (``detectReplyCodeGrammar``,
  ## ``detectSeparator``, ``detectMultilineConsistency``) with the
  ## enhanced-code detector (``detectEnhancedTriple``) via ``?``.
  # (implementation elided — builds ParsedSmtpReply by chaining ?
  # on the detectors above)

func toValidationError(
    v: SmtpReplyViolation, raw: string): ValidationError =
  ## Single domain-to-wire translator. Adding a variant to
  ## ``SmtpReplyViolation`` forces a compile error here and nowhere
  ## else. (H20, single translator invariant.)
  case v
  of srEmpty:
    validationError("SmtpReply", "must not be empty", raw)
  of srControlChars:
    validationError("SmtpReply", "contains disallowed control characters", raw)
  of srLineTooShort:
    validationError("SmtpReply", "line shorter than 3-digit Reply-code", raw)
  of srBadReplyCodeDigit1:
    validationError("SmtpReply", "first Reply-code digit must be in 2..5", raw)
  of srBadReplyCodeDigit2:
    validationError("SmtpReply", "second Reply-code digit must be in 0..5", raw)
  of srBadReplyCodeDigit3:
    validationError("SmtpReply", "third Reply-code digit must be in 0..9", raw)
  of srBadSeparator:
    validationError("SmtpReply", "character after Reply-code must be SP, HT, or '-'", raw)
  of srMultilineCodeMismatch:
    validationError("SmtpReply", "multi-line reply has inconsistent Reply-codes", raw)
  of srMultilineContinuation:
    validationError("SmtpReply", "non-final reply line must use '-' continuation", raw)
  of srMultilineFinalHyphen:
    validationError("SmtpReply", "final reply line must not use '-' continuation", raw)
  of srEnhancedMalformedTriple:
    validationError("SmtpReply", "enhanced status code not a numeric dot-separated triple", raw)
  of srEnhancedClassInvalid:
    validationError("SmtpReply", "enhanced status-code class must be 2, 4, or 5", raw)
  of srEnhancedSubjectOverflow:
    validationError("SmtpReply", "enhanced status-code subject out of 0..999", raw)
  of srEnhancedDetailOverflow:
    validationError("SmtpReply", "enhanced status-code detail out of 0..999", raw)
  of srEnhancedMultilineMismatch:
    validationError("SmtpReply", "multi-line reply has inconsistent enhanced status codes", raw)

func parseSmtpReply*(raw: string):
    Result[ParsedSmtpReply, ValidationError] =
  ## Public entry point. Retains the name ``parseSmtpReply`` from
  ## G1; return type changes from ``Result[SmtpReply, ValidationError]``
  ## to ``Result[ParsedSmtpReply, ValidationError]``. Old body is
  ## deleted, not kept as a fallback (H17, clean-refactor invariant).
  detectParsedSmtpReply(raw).mapErr(
    proc(v: SmtpReplyViolation): ValidationError {.noSideEffect, raises: [].} =
      toValidationError(v, raw))
```

Renderer for the inverse direction (deterministic; H24):

```nim
func renderSmtpReply*(p: ParsedSmtpReply): string =
  ## Deterministic inverse of ``parseSmtpReply`` for canonical
  ## inputs. Emits the canonical wire form from the parsed
  ## components — Reply-code prefix, optional enhanced-code prefix
  ## on the final line, text. Not equal to ``p.raw`` in general:
  ## ``raw`` preserves the exact ingress bytes (whitespace, line-
  ## ending variant); ``renderSmtpReply`` emits the canonical form.
```

The canonicalisation policy is pinned in §5.8.

### 5.6. `DeliveryStatus` field migration

The field type changes at `submission_status.nim:248-253`:

```nim
# Before (G1):
type DeliveryStatus* {.ruleOff: "objects".} = object
  smtpReply*: SmtpReply
  delivered*: ParsedDeliveredState
  displayed*: ParsedDisplayedState

# After (H1):
type DeliveryStatus* {.ruleOff: "objects".} = object
  smtpReply*: ParsedSmtpReply
  delivered*: ParsedDeliveredState
  displayed*: ParsedDisplayedState
```

The other two fields (`delivered`, `displayed`) are unchanged. Their
`Parsed*` wrappers (`ParsedDeliveredState`, `ParsedDisplayedState`)
were the G1 precedent for the parse-once shape; `ParsedSmtpReply`
extends the same pattern into the `smtpReply` slot. All three fields
now carry the parsed form alongside diagnostic raw bytes.

`DeliveryStatusMap` at `submission_status.nim:255-260` is unchanged
— its value type flows through the rename.

### 5.7. Serde routing

`src/jmap_client/mail/serde_submission_status.nim` routes through
the new parser/renderer. `DeliveryStatus.fromJson` reads the raw
string under the `smtpReply` key and runs `parseSmtpReply`;
`DeliveryStatus.toJson` calls `renderSmtpReply` to reconstruct the
wire string:

```nim
func fromJson(T: type DeliveryStatus, node: JsonNode, path: JsonPath):
    Result[DeliveryStatus, SerdeViolation] =
  ?expectKind(node, JObject, path)
  let rawReply = ?fieldJString(node, "smtpReply", path)
  let parsed = parseSmtpReply(rawReply).valueOr:
    return err(wrapInner(error, "smtpReply", path))
  let delivered = ?parseDeliveredState(
    ?fieldJString(node, "delivered", path),
    path.append("delivered"))
  let displayed = ?parseDisplayedState(
    ?fieldJString(node, "displayed", path),
    path.append("displayed"))
  ok(DeliveryStatus(
    smtpReply: parsed, delivered: delivered, displayed: displayed))

func toJson*(x: DeliveryStatus): JsonNode =
  result = newJObject()
  result["smtpReply"] = %renderSmtpReply(x.smtpReply)
  result["delivered"] = %($x.delivered.rawBacking)
  result["displayed"] = %($x.displayed.rawBacking)
```

The `fromJson` path is rewritten, not layered over the old path.
The old `fromJson` that yielded `SmtpReply` is deleted.

### 5.8. Wire round-trip policy — canonicalisation

`parseSmtpReply` is lenient on input per Postel's law: it accepts
CRLF, bare LF, and bare CR line terminators; accepts optional
trailing empty segments from CRLF-terminated payloads; accepts any
byte in the allowed set `{HT, SP..~}` on textstring lines. The
`ParsedSmtpReply.raw*` field preserves the exact ingress bytes,
including the ingress line-ending variant.

`toJson(ParsedSmtpReply)` (via `renderSmtpReply`) emits the
**canonical form**:

- Line terminator: **LF** (`\n`), never CRLF, never bare CR. JMAP
  wire is JSON-in-HTTP; CRLF is an SMTP wire convention not
  required in the JMAP `smtpReply` string value.
- Final line: ends with `<ReplyCode><SP><text>` (no trailing
  newline).
- Multi-line: each non-final line `<ReplyCode><->...<LF>`.
- No trailing whitespace on any line.

Consequences for wire round-trip:

- **Canonical input → identical output.** `raw` is already canonical;
  `renderSmtpReply(parseSmtpReply(raw).get) == raw`. Existing
  fixtures in `tests/serde/mail/tserde_submission_status.nim` and
  any `DeliveryStatus` fixture in `tests/mfixtures.nim` that use
  canonical LF-terminated replies are byte-identical (H24, wire-
  byte-identical invariant).
- **Non-canonical input → canonicalised output.** CRLF in, LF out.
  Trailing CR in, stripped out. The `raw` field on the parsed object
  still holds the original ingress bytes, so diagnostic paths
  (logging, tracing) see the exact wire as received. This is the
  **sole documented normalisation** in H1; tests pin it.

Fixture expectations:

- `tests/serde/mail/tserde_submission_status.nim` — existing tests
  with canonical LF replies pass unchanged.
- Any existing test with a CRLF reply in its input fixture is
  updated to assert that `toJson` emits the LF canonicalisation.
  If no such test exists today, H1 adds one — the normalisation is
  observable and must be test-pinned.

### 5.9. File impact

- `src/jmap_client/mail/submission_status.nim`:
  - **Retire** `type SmtpReply* = distinct string` at line 99.
  - **Retire** `defineStringDistinctOps(SmtpReply)` at line 109.
  - **Retire** old module-local `SmtpReplyViolation` enum definition
    at lines 111–127 (it is re-introduced as exported with 15 variants
    at the same location).
  - **Retire** existing `parseSmtpReply` body at lines 234–242 (name
    reused, new body).
  - **Retire** deferral docstring line at line 239 ("Deeper parsing
    of the textstring (e.g., enhanced status codes per RFC 3463) is
    deferred (G12).") — deferral is discharged; prose deleted.
  - **Add** `ReplyCode`, `StatusCodeClass`, `SubjectCode`,
    `DetailCode` distinct newtypes + borrow templates.
  - **Add** `EnhancedStatusCode`, `ParsedSmtpReply` objects.
  - **Add** extended `SmtpReplyViolation*` enum (15 variants, same
    `sr` prefix, same order for the existing 10).
  - **Add** atomic-detector templates
    (`detectReplyCodeGrammar`, `detectSeparator`, `detectClassDigit`,
    `detectSubjectInRange`, `detectDetailInRange`,
    `detectEnhancedTriple`, `detectMultilineConsistency`).
  - **Add** composite detector `detectParsedSmtpReply`.
  - **Add** `toValidationError(SmtpReplyViolation, raw)` single
    translator.
  - **Add** new `parseSmtpReply*` entry point returning
    `Result[ParsedSmtpReply, ValidationError]`.
  - **Add** `renderSmtpReply*` deterministic inverse.
  - **Migrate** `DeliveryStatus.smtpReply` field type from
    `SmtpReply` to `ParsedSmtpReply`.

- `src/jmap_client/mail/serde_submission_status.nim`:
  - Rewrite `DeliveryStatus.fromJson` to route through the new
    `parseSmtpReply` (which now returns `ParsedSmtpReply`).
  - Rewrite `DeliveryStatus.toJson` to call `renderSmtpReply`.

- `src/jmap_client/mail/email_submission.nim`:
  - No structural change. `DeliveryStatusMap` retains its shape;
    the keyed value type (`DeliveryStatus`) flows through with the
    migrated `smtpReply` field. Any consumer that reads
    `status.smtpReply.string` (distinct-string style) is migrated
    to read `status.smtpReply.raw` or structural accessors.

- Consumer call sites touching `DeliveryStatus.smtpReply`:
  - grep `rg -n 'smtpReply' src/ tests/` — every hit is audited for
    the field-type change. Sites that used `$smtpReply` to get the
    wire form are migrated to `smtpReply.raw` or
    `renderSmtpReply(smtpReply)`. Sites that compared to a literal
    `SmtpReply("...")` are rewritten as structural assertions or
    `ParsedSmtpReply(...)` literal construction.

Wire impact: canonical inputs byte-identical; non-canonical inputs
canonicalised per §5.8, test-pinned.

### 5.10. Decisions

- **H17. Retire `SmtpReply` distinct string wholesale.**
  `ParsedSmtpReply` subsumes it. `ParsedSmtpReply.raw*` preserves the
  raw wire form for diagnostic identity — **explicitly NOT** as a
  back-compat escape hatch. Forbidden in the diff: `type SmtpReply*
  = ParsedSmtpReply` aliases, `{.deprecated.}` pragma on the retired
  symbol, borrowed ops preserved on a placeholder,
  `parseSmtpReplyV2` / `parseSmtpReplyStructured` parallel entry
  points (`parseSmtpReply` keeps its name; only the return type
  changes). Clean refactor per `515f3bd`
  ("`validateServerAssignedToken` deleted entirely, no compat shim")
  and `c8f45b3`'s wholesale replacement of the legacy serde-error
  enum without transitional arms.

- **H18. Four distinct newtypes + a string-backed enum.** Precedent:
  `HoldForSeconds`, `MtPriority`, `RFC5321Keyword` in G1. No bare
  `uint16` or `string` carries domain meaning past the serde
  boundary.

- **H19. `SubjectCode`/`DetailCode` bounded `0..999` lenient, not a
  sealed enum over currently-registered values.** IANA Enhanced
  Status Codes registry is extensible per RFC 3463 §4; hard-coding
  the currently-registered values would force a library update on
  every IANA extension. Matches the `DeliveredState`/`DisplayedState`
  catch-all-arm idiom for forward compatibility.
  `StatusCodeClass`, by contrast, IS a closed enum — the class digit
  is bound to {2, 4, 5} by RFC 3463 §3.1 and cannot extend.

- **H20. `SmtpReplyViolation` extends in place (10 → 15).** Same
  site, same `sr` prefix, existing variants unchanged in name and
  order, five new `srEnhanced*` variants appended. Single
  `toValidationError` translator — one compile-error site per new
  variant. Enum accessibility changes from module-local to exported
  for test introspection per H25.

- **H21. Atomic detectors as exported templates, not funcs.** They
  must live under the module's `{.push raises: [], noSideEffect.}`,
  and template expansion inherits purity at every caller per
  `7ecddb8`. The `detectMultilineConsistency` template takes a
  `pick: proc` with `{.noSideEffect, raises: [].}` to preserve the
  pragma through the closure.

- **H22. `detectMultilineConsistency` generalises multi-line
  consistency across Reply-code and enhanced-code.** One template,
  two call sites. Matches `c4a2445`'s "stdlib when stdlib is correct"
  applied internally — no stdlib primitive fits this shape, so the
  internal generic is the simplification.

- **H23. `DeliveryStatus.smtpReply` migrated to `ParsedSmtpReply`.**
  Parse-once invariant. The entity carries the rich type; consumers
  get structured access for free; no downstream helper is needed.
  The campaign's thesis applied to the last weakly-typed mail
  surface.

- **H24. `renderSmtpReply` is the deterministic inverse of
  `parseSmtpReply`.** Canonical inputs round-trip byte-identical.
  Non-canonical inputs (whitespace variation, line-ending variation)
  are canonicalised to LF terminators with explicit documented
  policy (§5.8). `ParsedSmtpReply.raw*` preserves the exact ingress
  form for diagnostic purposes; `toJson` emits the canonical form.
  Sole documented normalisation in H1.

- **H25. `parseSmtpReply` is the public entry; atomic detectors are
  exported for test introspection only.** Tests assert against
  `SmtpReplyViolation` variants directly (the translator is tested
  once, not per-parser); atomic detectors are test-visible so that
  failing a specific detector in isolation is a legal test shape.
  No parallel entry points (`parseSmtpReplyStructured`,
  `parseSmtpReplyV2`) exist — the public API has exactly one
  parser, and its name is `parseSmtpReply`.

---

## 6. RFC 8621 §10 IANA traceability matrix

Pure documentation section. Four subsections mirror RFC §10's structure;
every registered item maps to a symbol in the library (or is documented
as intentionally absent). The value is inverse-lookup for future audits
and the compile-time claim that if any row points at a symbol that no
longer exists, `just lint` catches it via the re-export chain in
`src/jmap_client.nim`.

### 6.1. Capabilities (§10.1–10.3)

| RFC § | URI | `CapabilityKind` variant | File:line |
|---|---|---|---|
| §10.1 | `urn:ietf:params:jmap:mail` | `ckMail` | `src/jmap_client/capabilities.nim:25` |
| §10.2 | `urn:ietf:params:jmap:submission` | `ckSubmission` | `src/jmap_client/capabilities.nim:27` |
| §10.3 | `urn:ietf:params:jmap:vacationresponse` | `ckVacationResponse` | `src/jmap_client/capabilities.nim:28` |

`MailCapabilities` (RFC §2) — server-advertised limits for
`urn:ietf:params:jmap:mail`:

| RFC field | Nim field | File:line |
|---|---|---|
| `maxMailboxesPerEmail` | `maxMailboxesPerEmail*: Opt[UnsignedInt]` | `src/jmap_client/mail/mail_capabilities.nim:39` |
| `maxMailboxDepth` | `maxMailboxDepth*: Opt[UnsignedInt]` | `src/jmap_client/mail/mail_capabilities.nim:40` |
| `maxSizeMailboxName` | `maxSizeMailboxName*: UnsignedInt` | `src/jmap_client/mail/mail_capabilities.nim:41` |
| `maxSizeAttachmentsPerEmail` | `maxSizeAttachmentsPerEmail*: UnsignedInt` | `src/jmap_client/mail/mail_capabilities.nim:42` |
| `emailQuerySortOptions` | `emailQuerySortOptions*: HashSet[string]` | `src/jmap_client/mail/mail_capabilities.nim:43` |
| `mayCreateTopLevelMailbox` | `mayCreateTopLevelMailbox*: bool` | `src/jmap_client/mail/mail_capabilities.nim:44` |

`SubmissionCapabilities` (RFC §7) — server-advertised limits for
`urn:ietf:params:jmap:submission`:

| RFC field | Nim field | File:line |
|---|---|---|
| `maxDelayedSend` | `maxDelayedSend*: UnsignedInt` | `src/jmap_client/mail/mail_capabilities.nim:49` |
| `submissionExtensions` | `submissionExtensions*: SubmissionExtensionMap` | `src/jmap_client/mail/mail_capabilities.nim:50` |

`VacationResponseCapabilities` (RFC §8) has no server-advertised
fields per the RFC — the capability is a presence flag only. No Nim
type needed beyond the `ckVacationResponse` variant.

### 6.2. Keywords (§10.4)

RFC §10.4 registers four JMAP-originated keywords and reserves one
(`$recent`) with "Do not use" scope.

| RFC § | Keyword | Nim binding | File:line |
|---|---|---|---|
| §10.4.1 | `$draft` | `const kwDraft* = Keyword("$draft")` | `src/jmap_client/mail/keyword.nim:40` |
| §10.4.2 | `$seen` | `const kwSeen* = Keyword("$seen")` | `src/jmap_client/mail/keyword.nim:41` |
| §10.4.3 | `$flagged` | `const kwFlagged* = Keyword("$flagged")` | `src/jmap_client/mail/keyword.nim:42` |
| §10.4.4 | `$answered` | `const kwAnswered* = Keyword("$answered")` | `src/jmap_client/mail/keyword.nim:43` |
| §10.4.5 | `$recent` | **intentionally absent** — RFC §10.4.5 scope: "reserved"; client libraries MUST NOT set it. | — |

`keyword.nim` also exposes `kwForwarded`, `kwPhishing`, `kwJunk`,
`kwNotJunk` (lines 44–47) — these are **NOT** RFC 8621 §10.4
registrations; they are IANA IMAP and JMAP Keywords registry entries
referenced as informative examples in RFC 8621 §4.1.1. See §8.6.

### 6.3. Mailbox roles (§10.5)

RFC §10.5.1 is the only RFC 8621 registration — `inbox` role. The
other `MailboxRoleKind` arms derive from the IANA IMAP Mailbox Name
Attributes registry (RFC 6154, RFC 5258) that RFC 8621 §2 references.

| RFC § | Role | `MailboxRoleKind` variant | File:line |
|---|---|---|---|
| **§10.5.1** | **`inbox` (RFC 8621 registration)** | **`mrInbox = "inbox"`** | **`src/jmap_client/mail/mailbox.nim:28`** |
| RFC 6154 | `drafts` | `mrDrafts = "drafts"` | `src/jmap_client/mail/mailbox.nim:29` |
| RFC 6154 | `sent` | `mrSent = "sent"` | `src/jmap_client/mail/mailbox.nim:30` |
| RFC 6154 | `trash` | `mrTrash = "trash"` | `src/jmap_client/mail/mailbox.nim:31` |
| RFC 6154 | `junk` | `mrJunk = "junk"` | `src/jmap_client/mail/mailbox.nim:32` |
| RFC 6154 | `archive` | `mrArchive = "archive"` | `src/jmap_client/mail/mailbox.nim:33` |
| RFC 6154 | `important` | `mrImportant = "important"` | `src/jmap_client/mail/mailbox.nim:34` |
| RFC 5258 | `all` | `mrAll = "all"` | `src/jmap_client/mail/mailbox.nim:35` |
| RFC 5258 | `flagged` | `mrFlagged = "flagged"` | `src/jmap_client/mail/mailbox.nim:36` |
| RFC 5465 | `subscriptions` | `mrSubscriptions = "subscriptions"` | `src/jmap_client/mail/mailbox.nim:37` |
| (catch-all) | vendor-extension role | `mrOther` | `src/jmap_client/mail/mailbox.nim:38` |

### 6.4. SetError codes (§10.6)

RFC 8621 §10.6 registers twelve SetError codes across Mailbox/set,
Email/set, EmailSubmission/set, and Identity/set. All twelve are
`SetErrorType` variants in `errors.nim`:

| RFC origin | Code | Variant | File:line |
|---|---|---|---|
| RFC 8621 §2.3 Mailbox/set | `mailboxHasChild` | `setMailboxHasChild = "mailboxHasChild"` | `src/jmap_client/errors.nim:274` |
| RFC 8621 §2.3 Mailbox/set | `mailboxHasEmail` | `setMailboxHasEmail = "mailboxHasEmail"` | `src/jmap_client/errors.nim:275` |
| RFC 8621 §4.6 Email/set | `blobNotFound` | `setBlobNotFound = "blobNotFound"` | `src/jmap_client/errors.nim:277` |
| RFC 8621 §4.6 Email/set | `tooManyKeywords` | `setTooManyKeywords = "tooManyKeywords"` | `src/jmap_client/errors.nim:278` |
| RFC 8621 §4.6 Email/set | `tooManyMailboxes` | `setTooManyMailboxes = "tooManyMailboxes"` | `src/jmap_client/errors.nim:279` |
| RFC 8621 §7.5 EmailSubmission/set | `invalidEmail` | `setInvalidEmail = "invalidEmail"` | `src/jmap_client/errors.nim:281` |
| RFC 8621 §7.5 EmailSubmission/set | `tooManyRecipients` | `setTooManyRecipients = "tooManyRecipients"` | `src/jmap_client/errors.nim:282` |
| RFC 8621 §7.5 EmailSubmission/set | `noRecipients` | `setNoRecipients = "noRecipients"` | `src/jmap_client/errors.nim:283` |
| RFC 8621 §7.5 EmailSubmission/set | `invalidRecipients` | `setInvalidRecipients = "invalidRecipients"` | `src/jmap_client/errors.nim:284` |
| RFC 8621 §7.5 EmailSubmission/set | `forbiddenMailFrom` | `setForbiddenMailFrom = "forbiddenMailFrom"` | `src/jmap_client/errors.nim:285` |
| RFC 8621 §7.5 EmailSubmission/set | `forbiddenFrom` | `setForbiddenFrom = "forbiddenFrom"` | `src/jmap_client/errors.nim:286` |
| RFC 8621 §7.5 EmailSubmission/set | `forbiddenToSend` | `setForbiddenToSend = "forbiddenToSend"` | `src/jmap_client/errors.nim:287` |
| RFC 8621 §7.5 EmailSubmission/set | `cannotUnsend` | `setCannotUnsend = "cannotUnsend"` | `src/jmap_client/errors.nim:288` |

RFC 8620 §5.3 standard SetError codes (`invalidArguments`, `notFound`,
`stateMismatch`, `invalidPatch`, `willDestroy`, `invalidProperties`,
`alreadyExists`, `singleton`, `tooLarge`, `rateLimit`) are also
`SetErrorType` variants (lines 259–272) but are RFC 8620 core, not
RFC 8621 §10.6 — included here for completeness of the error-code
vocabulary only.

---

## 7. Decision Traceability Matrix

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|---|---|---|---|
| H1 | Promotion threshold for `CompoundHandles[A, B]` | (A) keep per-site, (B) Rule-of-Three (defer), (C) Rule-of-Two (promote now) | **C** — promote under Rule-of-Two; structural repetition is exact and §3–§4 confirm the §5.4-vs-§3.7 split is load-bearing | Duplicated appearance IS duplicated knowledge (`c4a2445`); `be21db0` precedent for associated-type widening |
| H2 | Field names on `CompoundHandles` | (A) domain-named (`copy`/`destroy`/`submission`/`emailSet`), (B) spec-verbatim (`primary`/`implicit`), (C) proxy accessors atop domain names | **B** — spec-verbatim, with type-alias names carrying domain meaning; old field names DELETED | RFC vocabulary at field level; domain vocabulary at type-alias level; clean-refactor invariant |
| H3 | Where `CompoundHandles` + `getBoth` lives | (A) `dispatch.nim` (with `ResponseHandle`/`NameBoundHandle`), (B) mail-specific module | **A** — `dispatch.nim`; no mail-specific obligation | One source of truth per generic |
| H4 | Compile-time gate for compound participants | (A) none, (B) per-call-site assertion, (C) module-scope registration template | **C** — `registerCompoundMethod(Primary, Implicit)` | `be21db0` `registerSettableEntity(T)` precedent |
| H5 | `ChainedHandles[A, B]` relative to `CompoundHandles[A, B]` | (A) force into one generic with `Opt[MethodName]`, (B) subtype, (C) sibling generic | **C** — sibling; §3.7 and §5.4 are structurally distinct RFC mechanisms | Type-level honesty over spurious unification; `769d56a` precedent for keeping distinct ADTs |
| H6 | `filter` in `addEmailQueryWithSnippets` | (A) `Opt[Filter[...]]`, (B) mandatory `Filter[...]` | **B** — mandatory; RFC 8621 §5.1 forbids snippets without filter | Make the wrong thing hard; lift RFC invariant to type level |
| H7 | Filter shared via back-reference vs duplicated | (A) second `ResultReference` sharing the filter, (B) literal duplication | **B** — literal duplication | Each invocation self-contained; no new `ResultReference` path invented unless needed |
| H8 | Non-emptiness of `emailIds` back-reference | (A) refuse empty (impossible at back-reference), (B) accept empty | **B** — accept degenerate-but-valid per RFC; cons-cell discipline does not propagate through back-reference | Honest about what the type can enforce |
| H9 | Compile-time gate for chain participants | (A) none, (B) `registerChainableMethod(Primary)` | **B** — mirror of H4 | `be21db0` precedent |
| H10 | Arity-4 chain representation | (A) bespoke 4-field object, (B) named generic `ChainedHandles4[A, B, C, D]` | **B** — named generic; `type EmailQueryThreadChain = ChainedHandles4[...]` hides arity at call site | `SetRequest[T, C, U]` just-enough-parametricity precedent |
| H11 | Field names on `ChainedHandles4` | (A) `first`/`second`/`third`/`fourth`, (B) domain-specific names | **A** — positional; consistency with `ChainedHandles[A, B]`; domain vocabulary at type-alias level | H2 precedent |
| H12 | `DefaultDisplayProperties` location | (A) hard-coded in builder, (B) module-level `const` with docstring, (C) configuration object | **B** — one named auditable default, RFC-cited | One source of truth per fact |
| H13 | `collapseThreads` default | (A) `false`, (B) `true` per RFC §4.10 example | **B** | Match RFC canonical example |
| H14 | Partial-extraction functions | (A) `getAll` only, (B) `getAll` + `getFirstTwo` + `getLastThree` + etc. | **A** — one function; partial extraction via field access | Avoid combinatorial explosion; field access is already available |
| H15 | Variadic `ChainedHandlesN` macro | (A) implement now, (B) Rule-of-Three deferred | **B** — deferred to §8.5 | Not yet justified by a third distinct arity |
| H16 | Back-reference path constants | (A) string literals at call sites, (B) `ResultRefPath` enum in `dispatch.nim` | **B** — centralised, compile-checked | No stringly-typed JSON Pointers |
| H17 | `SmtpReply` distinct string retirement | (A) keep as-is, (B) layer a second parser atop, (C) retire wholesale, migrate `DeliveryStatus.smtpReply` to `ParsedSmtpReply` | **C** — wholesale retirement; no compat shim | `515f3bd` "deleted entirely, no compat shim"; clean-refactor invariant |
| H18 | Typed Reply-code / subject / detail | (A) bare `uint16`, (B) distinct newtypes + string-backed enum for class | **B** — four distinct newtypes + `StatusCodeClass` enum | Distinct-newtype invariant; G1 `HoldForSeconds`/`MtPriority` precedent |
| H19 | Closed enum vs lenient bounds for subject/detail | (A) sealed enum over currently-registered values, (B) bounded 0..999 lenient | **B** — IANA Enhanced Status Codes registry is extensible; lenient accepts future codes | G1 `DeliveredState`/`DisplayedState` catch-all-arm precedent |
| H20 | Extend `SmtpReplyViolation` vs replace | (A) new `EnhancedSmtpReplyViolation` sibling enum, (B) extend existing enum in place with 5 new variants | **B** — same site, same `sr` prefix, existing 10 variants unchanged in name and order | Single ADT per domain; single translator forces one compile-error site |
| H21 | Atomic detectors: `func` vs `template` | (A) `func`, (B) `template` | **B** — template expansion inherits caller's pragma | `7ecddb8` precedent for purity-through-expansion |
| H22 | `detectMultilineConsistency` generic vs duplicated | (A) two per-check detectors, (B) one generic template with `pick` callback | **B** — one template, two call sites | DRY where knowledge is shared; `c4a2445` principle |
| H23 | Parse-once entity-field vs on-demand helper | (A) add `parseSmtpReplyStructured` helper, keep `DeliveryStatus.smtpReply: SmtpReply`; (B) migrate field to `ParsedSmtpReply` | **B** — field migration | Parse-once invariant; `a23f39a` `Session.rawCore` precedent |
| H24 | Wire canonicalisation policy | (A) faithful round-trip of ingress bytes; `toJson == raw`, (B) canonical emission; `raw` preserved for diagnostics | **B** — canonical LF-terminated emission; `raw` holds ingress bytes | One canonical wire form; diagnostic fidelity independent of emission |
| H25 | Detector / translator test surface | (A) test only `parseSmtpReply`, (B) export atomic detectors + `SmtpReplyViolation` for introspection | **B** — atomic detectors exported; enum exported; tests assert per-variant | Translator tested once; atomics tested in isolation |

---

## 8. Appendix: Deliberately Out of Scope

Seven concise subsections, each explaining *why*, not just *that*.
These questions are answered once so future audits do not re-litigate
them.

### 8.1. Push / Subscription / TypeState (RFC §1.5)

RFC 8620 §1.5 describes PushSubscription, state-changed events, and
the typed-state protocol for efficient change notification. These are
**server-directed MUSTs** — a server MUST support the protocol, but
a client is RFC-compliant by polling `/changes` and discovering state
diffs via state strings. The library today implements the correctness
substrate (state strings, `*/changes` methods, `stateMismatch` error
handling) but no push transport. Polling clients are spec-compliant.

The design omission is intentional: push requires a transport-layer
subscription (EventSource or WebSocket), which is an FFI consumer
concern — Layer 5 embedders (C ABI callers) plug push into their own
event loops. Introducing push at the Nim library level would either
(a) ship an opinionated transport choice that doesn't compose with
every embedder's event loop, or (b) introduce a callback-registration
API that complicates the Layer 4/5 boundary for a feature that is
strictly efficiency, not correctness.

The library will remain RFC-compliant without push. Push lands as a
separate architectural deliverable (a future Part I or later), not
bolted onto H1.

### 8.2. EmailDelivery TypeState key

RFC 8621 §1.5 defines the `EmailDelivery` type-state key used by
push subscriptions to signal that new mail has arrived. It carries
no methods and no data — it is purely a push signal. Meaningful only
under §8.1; deferred with push.

### 8.3. C ABI / Layer 5 exports

`src/jmap_client.nim` re-exports the Nim surface only. Layer 5 C ABI
exports (`{.exportc: "jmap_name", dynlib, cdecl, raises: [].}`) are a
separate architectural deliverable per `CLAUDE.md`; they will land in
a future Part I (the C-API specification). H1 is a type-lift entirely
within L1–L3; the C ABI layer does not need to see these changes
until Layer 5 is designed.

### 8.4. G2 EmailSubmission test specification

G1 §1.3 deferred "Part G2 (Test Specification)" as a companion
document handled separately per user direction. H1 does not displace
that deferral. Test references in H1 appear only as regression-pinning
named fixtures (e.g. `tests/serde/mail/tserde_submission_status.nim`),
not as a test-spec deliverable.

### 8.5. Variadic `ChainedHandlesN`

Today we have arity 2 (`ChainedHandles[A, B]`) + arity 4
(`ChainedHandles4[A, B, C, D]`). No builder exists at arity 3 or 5+.
Rule-of-Three applies: when the third distinct arity materialises —
or when a real builder needs arity 5, not a hypothetical one —
introduce `template defineChainedHandles(n: static int)` that
generates arity-N generics. Today the two concrete sites do not
justify the macro, and the macro would displace the direct type
definitions that let the compiler give clear error messages on
mismatch.

This is a deliberate asymmetry with H1 §2 (Rule-of-Two promotion for
`CompoundHandles`). The asymmetry is justified by the precedent:
`be21db0` promoted `SetRequest[T, C, U]` at three `/set` sites, not
two; H1 §2 promotes at two sites because the structural repetition
is exact and the §5.4-vs-§3.7 split is load-bearing. H1 §8.5 defers
the variadic macro because the arity-2 vs arity-4 split is the
full set of shapes the library needs today — a third distinct arity
would be new structural evidence.

### 8.6. `$forwarded` / `$phishing` / `$junk` / `$notjunk` keywords

RFC 8621 §4.1.1 references these as informative examples from the
IANA IMAP and JMAP Keywords registry — they are NOT RFC 8621 §10
registrations. They are already represented in
`src/jmap_client/mail/keyword.nim:44-47` (`kwForwarded`, `kwPhishing`,
`kwJunk`, `kwNotJunk`), so H1 §6.2's audit table (which tracks RFC
§10 specifically) correctly omits them. If the RFC 8621 §10.4
registry expands in a future RFC revision to include these, they
are one-line registry additions at §6.2 — no code change required.

### 8.7. Back-reference path constant generalisation

`ResultRefPath` (H16) enumerates the three paths RFC 8621 §4.10 uses:
`/ids`, `/list/*/threadId`, `/list/*/emailIds`. A broader enumeration
covering every JMAP back-reference path observed in the wild is out
of scope for H1 — we introduce variants only when a new chain builder
needs one. Adding `/list/*/blobId` (for a hypothetical
blob-fetching chain) is a one-line enum extension + a new builder;
scope creep at H1 would introduce variants with no consumer.

---

## 9. Clean-refactor: Deletions inventory + grep gate

H1 encodes the clean-refactor invariant (§1.3, invariant 8) as a
grep-verifiable inventory. Every symbol below is DELETED from the
repository — no alias, no shim, no `{.deprecated.}` pragma, no
bridge. Implementation PRs are verified against the grep gate in
§9.6.

### 9.1. §2 — Compound handles collapse

| Symbol / artefact | Location | Reason retired |
|---|---|---|
| `type EmailCopyHandles* = object ...` body | `src/jmap_client/mail/mail_builders.nim:253-260` | Replaced by `type EmailCopyHandles* = CompoundHandles[...]` type alias |
| `type EmailCopyResults* = object ...` body | `src/jmap_client/mail/mail_builders.nim:262-265` | Replaced by `type EmailCopyResults* = CompoundResults[...]` alias |
| `func getBoth*(resp, handles: EmailCopyHandles): ...` body | `src/jmap_client/mail/mail_builders.nim:310-320` | Subsumed by generic `getBoth[A, B]` in `dispatch.nim` |
| `type EmailSubmissionHandles* {.ruleOff: "objects".} = object ...` body | `src/jmap_client/mail/email_submission.nim:536-545` | Replaced by type alias |
| `type EmailSubmissionResults* {.ruleOff: "objects".} = object ...` body | `src/jmap_client/mail/email_submission.nim:547-553` | Replaced by type alias |
| `func getBoth*(resp, handles: EmailSubmissionHandles): ...` body | `src/jmap_client/mail/submission_builders.nim:127-140` | Subsumed by generic `getBoth[A, B]` |
| Field access `.copy` on compound handles | All call sites in `src/`, `tests/` | Renamed to `.primary` |
| Field access `.destroy` on compound handles | All call sites | Renamed to `.implicit` |
| Field access `.submission` on submission handles | All call sites | Renamed to `.primary` |
| Field access `.emailSet` on submission handles | All call sites | Renamed to `.implicit` |
| Module docstrings / inline comments describing retired per-site `getBoth` shape, old field names, or "hand-rolled compound handle" phrasing | `mail_builders.nim`, `email_submission.nim`, `submission_builders.nim` | Rewritten or removed |

### 9.2. §5 — SmtpReply retirement

| Symbol / artefact | Location | Reason retired |
|---|---|---|
| `type SmtpReply* = distinct string` | `src/jmap_client/mail/submission_status.nim:99` | Subsumed by `ParsedSmtpReply` object |
| `defineStringDistinctOps(SmtpReply)` | `src/jmap_client/mail/submission_status.nim:109` | Dies with the type |
| Old `SmtpReplyViolation` enum body (10 variants, module-local) | `src/jmap_client/mail/submission_status.nim:111-127` | Replaced wholesale by 15-variant exported definition at same site |
| Old `func parseSmtpReply*(raw: string): Result[SmtpReply, ValidationError]` body | `src/jmap_client/mail/submission_status.nim:234-242` | Name reused; new signature `Result[ParsedSmtpReply, ValidationError]`; old body deleted, not kept as a fallback |
| Deferral docstring line `## ... enhanced status codes per RFC 3463) is deferred (G12).` | `src/jmap_client/mail/submission_status.nim:239` (docstring within old `parseSmtpReply`) | Discharged by this refactor; prose deleted |
| Field `smtpReply*: SmtpReply` on `DeliveryStatus` | `src/jmap_client/mail/submission_status.nim:251` | Migrated to `smtpReply*: ParsedSmtpReply` |
| Any `## G12` / `## TBD` / `## deferred` / `## XXX` marker in `src/jmap_client/mail/` referencing RFC 3463 or `SmtpReply` | grep `src/jmap_client/mail/` | Audited; deleted |
| Serde path in `fromJson(DeliveryStatus)` that yields `SmtpReply` | `src/jmap_client/mail/serde_submission_status.nim` | Rewritten to yield `ParsedSmtpReply`; not layered over the old path |

### 9.3. Tests — fixtures and assertions

| Pattern | Action |
|---|---|
| Fixture constructing `EmailCopyHandles(copy: ..., destroy: ...)` | Migrated to `EmailCopyHandles(primary: ..., implicit: ...)`. Not duplicated; the old fixture is deleted |
| Fixture constructing `EmailSubmissionHandles(submission: ..., emailSet: ...)` | Migrated to `primary`/`implicit`. Old form deleted |
| Assertion `check smtp == SmtpReply("...")` | Migrated to structural assertion on `ParsedSmtpReply(...)` fields or `parseSmtpReply("...").get()` equality. Old form deleted |
| Tests reading `$deliveryStatus.smtpReply` to compare against a raw string | Migrated to `deliveryStatus.smtpReply.raw` (diagnostic) or `renderSmtpReply(deliveryStatus.smtpReply)` (canonical) |

### 9.4. Design-doc history

Prior design docs (G1 §1.3, F1 Rule-of-Three, G1 Appendix Roadmap)
are **append-only history** and NOT edited. H1 §1.2's discharge
table is the canonical cross-reference pointing back at the
discharged deferrals. Any future audit looking at G1 sees the
original deferral prose intact; a hyperlink/reference to H1 §1.2 is
the idiomatic way to learn "this deferral is no longer open."

### 9.5. Absolute-forbidden diff patterns

These patterns MUST NOT appear in any commit that claims to
implement H1. They are enforced by CI / human review via the grep
gate in §9.6.

| Forbidden pattern | Why |
|---|---|
| `{.deprecated` on any symbol in the H1 file-impact set | A deprecation is a shim; clean refactor forbids it |
| `type SmtpReply* = ParsedSmtpReply` | Preserves the retired name |
| `type SmtpReply* {.deprecated.} = ...` | Same |
| `proc copy*(h: EmailCopyHandles): auto = h.primary` or any proxy accessor on old field names | Preserves the retired field name |
| `when defined(jmap_legacy_smtp_reply)` or any conditional-compile shim for the retired shape | Branching on a compat flag |
| `TODO.*SmtpReply` / `FIXME.*SmtpReply` / `XXX.*SmtpReply` in the mail subtree | Implies unfinished migration |
| `# old: ` / `# formerly: ` / `# was: ` inline comments on migrated sites | Stale metadata |
| Any commented-out block of the old `EmailCopyHandles` / `SmtpReply` shape | Clean-refactor means deleted, not commented-out |
| Parallel entry points `parseSmtpReplyStructured`, `parseSmtpReplyV2`, `parseSmtpReply2` | `parseSmtpReply` is the sole public parser (H17, H25) |

### 9.6. Post-implementation grep gate

Implementation PRs for H1 are required to pass all of the following
greps. These derive mechanically from §9.1–§9.5; failure on any grep
means the refactor left residue.

**Retired symbols have zero defining occurrences:**

```
rg -n 'type\s+SmtpReply\b' src/ tests/                    # → 0 hits
rg -n 'type\s+EmailCopyHandles\*\s*=\s*object' src/ tests/ # → 0 hits
rg -n 'type\s+EmailSubmissionHandles\*\s*=\s*object' src/ tests/ # → 0 hits
```

(Only the type-alias forms `type EmailCopyHandles* = CompoundHandles[...]`
survive.)

**Retired field accesses have zero occurrences:**

```
rg -n '\bhandles\.copy\b|\bhandles\.destroy\b' src/ tests/     # → 0 hits
rg -n '\bhandles\.submission\b|\bhandles\.emailSet\b' src/ tests/ # → 0 hits
rg -n '\bresults\.copy\b|\bresults\.destroy\b' src/ tests/     # → 0 hits
rg -n '\bresults\.submission\b|\bresults\.emailSet\b' src/ tests/ # → 0 hits
```

**No deprecation or compat shims:**

```
rg -n '\{\.deprecated' src/ tests/                         # → 0 hits
rg -n 'when\s+defined\(jmap_legacy' src/ tests/            # → 0 hits
rg -n 'parseSmtpReplyStructured|parseSmtpReplyV2|parseSmtpReply2' src/ tests/  # → 0 hits
```

(`parseSmtpReply` remains the sole public parser.)

**No stale deferral prose:**

```
rg -ni 'G12|deferred to H1|TBD|XXX' src/jmap_client/mail/ tests/  # → 0 hits
rg -n '# old:|# formerly:|# was:' src/ tests/                      # → 0 hits
```

Pre-existing G1/F1 references in `docs/design/` are permitted
(append-only history).

**No commented-out legacy blocks:**

```
rg -n '# *type SmtpReply|# *type EmailCopyHandles|# *func getBoth' src/ tests/  # → 0 hits
```

**§5 field-migration coverage:**

`rg -n 'smtpReply' src/ tests/` lands only on `ParsedSmtpReply`-typed
contexts: the `DeliveryStatus.smtpReply` field, `ParsedSmtpReply.raw`
access, the `parseSmtpReply` entry point, `renderSmtpReply`, and
structural assertions. No remaining `SmtpReply`-typed (distinct
string) usages.

**Documentation consistency:**

`rg -n 'SmtpReply\b' docs/design/` in files authored **after** H1
references only `ParsedSmtpReply`, the retirement narrative, or
historical citations. H1 itself is the only design doc that mentions
`SmtpReply` in a non-historical frame (it narrates the retirement).

---

## 10. Verification — when this document is complete

The H1 document is complete when:

1. **Every §2–§5 decision maps to a commit pattern** cited by short
   hash (`be21db0`, `7ecddb8`, `c4a2445`, `c8f45b3`, `769d56a`,
   `515f3bd`, `a23f39a`). Decisions that do not map to a campaign
   pattern are flagged as deliberate departures with justification.

2. **Eight design invariants** (single translator, distinct newtype,
   template inheritance, parse-once, wire byte-identical, stdlib
   delegation, compile-time participation, clean-refactor) each
   have at least one enforcement point cited by §. The clean-refactor
   invariant is discharged by the §9 Deletions inventory.

3. **Every Nim type sketch compiles under `{.push raises: [],
   noSideEffect.}`** — the atomic-detector templates carry purity
   through expansion per H21; the `detectMultilineConsistency`
   template's `pick: proc` callback is explicitly `noSideEffect,
   raises: []`.

4. **Every cross-reference to existing code carries file:line.**

5. **Decision Traceability Matrix (§7)** covers every H-identifier
   (H1–H25) with a § anchor and a rationale summary, matching G1's
   formatting.

6. **Appendix §8** answers each deferral with a reason, not just a
   label.

7. **RFC conformance spot-checks:**
   - §1.5 (push) described as server-MUST, not client-MUST (§8.1).
   - §4.10 canonical example reproduced in §3 and §4 builders as
     spec-verbatim output, with `ResultRefPath` constants matching
     the RFC's JSON Pointer paths exactly.
   - §5.1 SearchSnippet/get filter argument is mandatory (H6).
   - §7.5 implicit-Email/set pattern lands on
     `CompoundHandles[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]`.
   - §10 every registered item traced to a symbol (§6) or documented
     as intentionally absent.
   - RFC 3463 class/subject/detail triple reproduced in
     `EnhancedStatusCode` with grammar citations.

8. **Wire-byte-identicality claim** for each type migration includes
   the existing test file that pins it (`tserde_email_copy.nim`,
   `tserde_email_submission.nim`, `tserde_submission_status.nim`).

9. **No G2 test-spec material.** Test references appear only as
   regression-pinning named fixtures per §8.4.

10. **Document length** 1400–1800 lines, consistent with G1's
    weight and the scope here.

11. **Deletions inventory (§9) is exhaustive.** Every §2 and §5
    symbol slated for removal appears in §9.1–§9.3. Every forbidden
    diff pattern (§9.5) is grep-expressible. Implementation PRs pass
    the §9.6 grep gate, derived mechanically from §9.1–§9.5.

---

*End of Design H1. RFC 8621 type-lift campaign complete.*
