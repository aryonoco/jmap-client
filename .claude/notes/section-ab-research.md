# Section A&B research maps (extracted from workflow wf_a8f1f21e-7ef)

Durable copy of the 12 research-agent change-maps. Consult per-item.

## Index
- agent-a0091272cfbbebe37.jsonl (29B): agent-a0091272cfbbebe37.jsonl
- agent-a2f344cec353daf8f.jsonl (21071B): # B3 (P16): `Filter[C]` operator-arm re-encoding — change-map
- agent-a3893859815aec6e9.jsonl (15317B): # B7 Change-Map: `mail_filters.nim` `Opt[bool]` → three-state enums (P18)
- agent-a436a92e3e11e8c83.jsonl (17995B): # B8 (P18): `Identity.mayDelete` three-state → `DeleteAuthority` enum — change-map
- agent-a4e51939488d9df45.jsonl (18209B): # B10 (P12) — `lent` annotation pass on container-returning handle accessors
- agent-a8f4db16a1a52c8de.jsonl (15836B): # A8b — Full-seal `Credential` and `SessionEndpoint` (private `rawScheme`/`rawKind` + read
- agent-a99297f6326dac2b6.jsonl (18771B): # B2 (P18): Sort-direction unification — change-map
- agent-aba0157e700dabcc3.jsonl (16698B): # B11 (P16) Change-Map — `Email.bodyValues` / `bodyStructure` coherence
- agent-aba7b22bfcea82e80.jsonl (16748B): # B5 Change-Map: `registerExtractableEntity(T)` compile-check
- agent-ad146f46e394d5990.jsonl (283B): agent-ad146f46e394d5990.jsonl
- agent-aeaf29ce8730317d4.jsonl (25461B): # Change-Map: A25 / A25b / A26 / A2b — snapshot + property-test infrastructure
- agent-af080343b7d79a5ee.jsonl (16906B): ## ITEM B4 (P16) — VacationResponse `fromDate`/`toDate` window invariant — change-map
- agent-affeebabf076a68b6.jsonl (20813B): ## B9 (P9) — Handle-pair zoo consolidation: change-map



================================================================================
## SOURCE agent-a0091272cfbbebe37.jsonl — agent-a0091272cfbbebe37.jsonl
================================================================================

[Request interrupted by user]

================================================================================
## SOURCE agent-a2f344cec353daf8f.jsonl — # B3 (P16): `Filter[C]` operator-arm re-encoding — change-map
================================================================================

I now have complete empirical and source-level grounding. Here is the change-map.

---

# B3 (P16): `Filter[C]` operator-arm re-encoding — change-map

## Current state

**`src/jmap_client/internal/types/framework.nim:31-57`** — the type and its two convenience constructors:

```nim
type FilterOperator* = enum   # :31
  foAnd = "AND"
  foOr = "OR"
  foNot = "NOT"

type FilterKind* = enum       # :37
  fkCondition
  fkOperator

type Filter*[C] = object      # :42
  case kind*: FilterKind
  of fkCondition:
    condition*: C
  of fkOperator:
    operator*: FilterOperator        # plain field (NOT a discriminator)
    conditions*: seq[Filter[C]]      # ← arbitrary arity, incl. @[]

func filterCondition*[C](cond: C): Filter[C] =                       # :51
  return Filter[C](kind: fkCondition, condition: cond)

func filterOperator*[C](op: FilterOperator, conditions: seq[Filter[C]]): Filter[C] =  # :55
  return Filter[C](kind: fkOperator, operator: op, conditions: conditions)
```

The illegal states this admits (the RFC 8620 §5.5 violations B3 closes): `filterOperator(foNot, @[])`, `filterOperator(foNot, @[a, b])` (NOT must be exactly one child), and `filterOperator(foAnd/foOr, @[])` (AND/OR are "one or more").

**`NonEmptySeq[T]` — `src/jmap_client/internal/types/primitives.nim:328-362`**: sealed Pattern-A object `rawValue: seq[T]` (private). Standalone generic accessors: `parseNonEmptySeq*[T](s): Result[NonEmptySeq[T], ValidationError]` (:336, rejects empty), `head*[T](a): lent T` (:345), `asSeq*[T](a): lent seq[T]` (:352). The richer ops (`==`, `$`, `hash`, `len`, `[]`, `contains`, `items`, `pairs`) live only in `defineSealedNonEmptySeqOps*` (`validation.nim:157-194`), instantiated **per concrete element type** — never for an open generic `Filter[C]`.

**Serde — `src/jmap_client/internal/serialisation/serde_framework.nim`**: `toJson*[C]` (:97) reads `f.conditions` at :110 (`for child in f.conditions`). `fromJsonImpl[C]` (:123) builds `var children: seq[Filter[C]]` and calls `filterOperator(op, children)` at :147 with **no arity validation** — accepts any count for any operator. `fromJson*[C]` (:149) is the public entry; depth-capped at `MaxFilterDepth = 128` (:114).

**Reject test already in place — `tests/unit/ttypesafety.nim:64-67`**: `not compiles(Filter[int](kind: fkCondition, operator: foAnd, conditions: @[]))` (mixed-arm field access; references `conditions`).

## All sites

### src/ — construct/read/serde (must change)
- `src/jmap_client/internal/types/framework.nim:42-57` — type def + `filterCondition` + `filterOperator`.
- `src/jmap_client/internal/serialisation/serde_framework.nim:110` — read `f.conditions` (toJson).
- `src/jmap_client/internal/serialisation/serde_framework.nim:139,147` — `filterCondition`/`filterOperator` construction in fromJson.

### src/ — type-only references (UNAFFECTED — pass `Filter[C]` through, never touch fields)
- `src/jmap_client/convenience.nim:82,103-104,123-124` — `Opt[Filter[...]]` params.
- `src/jmap_client/internal/mail/mail_methods.nim:279,289,307,321,344` — `filter: Filter[EmailFilterCondition]` + `serializeFilter(filter)`.
- `src/jmap_client/internal/mail/mail_builders.nim:90-91,116-117,276,283,298,309,486` — `Opt[Filter[...]]` + `serializeOptFilter`.
- `src/jmap_client/internal/mail/submission_builders.nim:82-83,100-101` — `Opt[Filter[...]]`.
- `src/jmap_client/internal/protocol/builder.nim:532,558,573` — generic `Opt[Filter[C]]` + `serializeOptFilter`.
- `src/jmap_client/internal/protocol/methods.nim:376,386` — `serializeOptFilter[C]`/`serializeFilter[C]` (call `f.toJson()` only).

### tests/ — construct via `filterOperator` (break — signature/return change)
- `tests/mfixtures.nim:479-483` — `makeFilterAnd`/`makeFilterOr` (`filterOperator[int](foAnd/foOr, children)`).
- `tests/mproperty.nim:472-484` — `genFilter` (`filterOperator(op, children)`, childCount `0..4`, op incl. `foNot`).
- `tests/unit/tframework.nim:50,56,57,94,99-107,141` — incl. arity tests `filterOperatorNotEmpty` (:92), `filterOperatorNotMultiple` (:97), `filterOperatorAndSingle` (:105).
- `tests/property/tprop_framework.nim:50,164-174,198,247` — incl. arity `Filter operator arity` (:160), `propFilterOperatorEmpty` (:171).
- `tests/compliance/trfc_8620.nim:777,806-807,819,828,1066` — incl. `filterOperatorArity` (:817), `filterOperatorEmptyConditions` (:1064).
- `tests/stress/tstress.nim:34,42,94,102,172,179,181,232` — deep/wide trees built via `filterOperator`.
- `tests/stress/tadversarial.nim:945,952,961-963` — arity edge cases (foNot×2, foAnd empty).
- `tests/serde/tserde_framework.nim:377-379` — `filterOperator(foNot/foOr/foAnd, …)`.
- `tests/integration/live/temail_query_filter_tree_live.nim:67,90,115,119` — `filterOperator(foAnd/foOr/foNot, …)`.

### tests/ — read `.conditions` / `.operator` (break — accessor change)
- `tests/mfixtures.nim:836-839` — `filterEq` (`a.conditions.len`, `a.conditions[i]`).
- `tests/unit/tframework.nim:52,53,59,60,144-148`.
- `tests/property/tprop_framework.nim:52,53,113-114,144-145,167-168,173-174,188,250-256,265-275`.
- `tests/compliance/trfc_8620.nim:779-780,808-810,820-822,829-831,1067-1068`.
- `tests/serde/tserde_framework.nim:239-240,251-253,257-258,335-345`.
- `tests/serde/tserde_adversarial.nim:232-233,449-450`.
- `tests/stress/tstress.nim:43,173`.
- `tests/stress/tadversarial.nim:946-948,953-954,964-967`.
- `tests/unit/ttypesafety.nim:66` — reject test references `conditions`.

### tests/ — construct leaves via `filterCondition` only (UNAFFECTED — leaf ctor unchanged)
- All `filterCondition(EmailFilterCondition(...))` / `filterCondition(MockFilter())` / `filterCondition(int)` sites: `tests/protocol/tmail_methods.nim:219,231,242,263,336`, `tests/protocol/tmethods.nim:337,366,944,952,980,1027`, `tests/protocol/tbuilder.nim:385`, `tests/serde/mail/tserde_email_integration.nim:229`, `tests/integration/live/*` (`temail_query_*`, `tmailbox_query_filter_sort_live`, `temail_submission_*`, `tresult_reference_deep_paths_live`, `tthread_keyword_filter_*`, `tcombined_adversarial_*`, `mlive.nim:1177,1228`), `tests/compliance/tscenarios.nim:447,457-459`, `tests/serde/tserde_framework.nim:376`, `tests/serde/tserde_*`. These build leaves or AND-of-leaves; only the AND/OR/NOT *operator* sites among them change.

### tests/ — `Filter[C].fromJson` round-trip callers (behaviour change: arity now validated)
- `tests/serde/tserde_framework.nim:57,62,68,228,237,250,257,334,381,402`; `tests/serde/tserde_adversarial.nim:218,231,242,251,256,261`; `tests/serde/tserde_properties.nim:83,159`; `tests/property/tprop_serde.nim:139`; `tests/compliance/tregression.nim:181`; `tests/stress/tstress.nim:236`; `tests/serde/tserde_type_safety.nim:529-547`.
- Fixtures consuming via `Filter[int]`: `tests/mserde_fixtures.nim:15-30` (`fromIntCondition`/`toJson(int)` — unchanged).

## Proposed cut

The TODO's literal sketch — an inner `case operator` **on the same `Filter` object** with `of foNot: child: Filter[C]` — is **infeasible** for two independently-proven reasons (see Hazards): (1) a direct-value recursive `child: Filter[C]` field **segfaults the Nim compiler**, and (2) reading the inner variant field through nested `case f.kind` / `case f.operator` is **rejected by strictCaseObjects** at instantiation. Both are empirically confirmed below.

**Recommended shape (Option C1 — flat, sealed, `NonEmptySeq`), serving P16:**

```nim
type Filter*[C] {.ruleOff: "objects".} = object
  ## Recursive filter tree (RFC 8620 §5.5). The operator arm is sealed:
  ## ``rawOperands`` is module-private and only reachable through the
  ## non-empty smart constructors, so an empty operand list is
  ## unrepresentable. ``foNot`` is held to exactly one operand by
  ## ``filterNot`` (the only constructor that targets it); ``foAnd``/
  ## ``foOr`` accept one or more.
  case kind*: FilterKind
  of fkCondition:
    condition*: C
  of fkOperator:
    operator*: FilterOperator              # plain field — runtime value OK
    rawOperands: NonEmptySeq[Filter[C]]     # private; ≥1 guaranteed by type

func filterCondition*[C](cond: C): Filter[C] =                 # unchanged
  Filter[C](kind: fkCondition, condition: cond)

func filterNot*[C](child: Filter[C]): Filter[C] =
  ## RFC 8620 §5.5: NOT has exactly one child. ``@[child]`` has length 1,
  ## so ``parseNonEmptySeq`` cannot Err here.
  Filter[C](kind: fkOperator, operator: foNot,
            rawOperands: parseNonEmptySeq(@[child]).get())

func filterAnd*[C](operands: seq[Filter[C]]): Result[Filter[C], ValidationError] =
  ## RFC 8620 §5.5: AND is one or more conditions.
  let nes = ?parseNonEmptySeq(operands)
  ok(Filter[C](kind: fkOperator, operator: foAnd, rawOperands: nes))

func filterOr*[C](operands: seq[Filter[C]]): Result[Filter[C], ValidationError] =
  let nes = ?parseNonEmptySeq(operands)
  ok(Filter[C](kind: fkOperator, operator: foOr, rawOperands: nes))

func operands*[C](f: Filter[C]): lent seq[Filter[C]] =
  ## Operand list of an operator node; empty seq for a leaf (callers
  ## should ``case`` on ``kind`` first). Single ``kind`` discriminator —
  ## strict-safe.
  case f.kind
  of fkCondition: (let empty {.global.} = newSeq[Filter[C]](); empty)  # see Hazards for the lent-of-empty note
  of fkOperator: asSeq(f.rawOperands)
```

Why C1 over the alternatives: it is the only shape that is simultaneously **recursion-safe** (`NonEmptySeq` wraps `seq` → heap indirection), **strict-safe** (single `kind` discriminator; `operator` is a plain field), **nil/ref-free** (honours the codebase's "value types in domain core, nil impossible" line and FFI `--panics:on` safety), and **idiomatic** (`NonEmptySeq` is the project's established non-empty primitive). It makes the *actual* RFC violation — empty operand lists for every operator — **unrepresentable at the type level**, and makes 2-child-`foNot` **unconstructable** because `rawOperands` is private and `filterNot` is the only path to an `foNot` node. `filterOperator` is **removed** (replaced by `filterNot`/`filterAnd`/`filterOr`).

**Serde adapts (`serde_framework.nim`):**
- `toJson*[C]` :110 — change `for child in f.conditions` → `for child in operands(f)` (public accessor; serde cannot see private `rawOperands`). The `"operator"` key still reads public `f.operator`. Wire output is **byte-identical** to today (NOT still serialises as `{"operator":"NOT","conditions":[...]}` with one element).
- `fromJsonImpl[C]` :142-147 — after collecting `children`, dispatch on the parsed operator and route through the smart constructors, mapping arity failures to `SerdeViolation`:
  ```nim
  case op
  of foNot:
    ?expectLen(conditionsNode, 1, path / "conditions")   # RFC: exactly one
    ok(filterNot(children[0]))                            # children.len==1 proven by expectLen
  of foAnd, foOr:
    # parseNonEmptySeq Err ⇒ map to svkEmptyRequired via wrapInner-style bridge
    filterAndOr(op, children, path)   # helper returning Result[Filter[C], SerdeViolation]
  ```
  Use `expectLen` (`serde_helpers.nim:100`, `svkArrayLength`) for NOT and an empty-check mapping to `svkEmptyRequired` for AND/OR. This is a **behaviour tightening**: malformed server/test filters (NOT≠1, AND/OR empty) now Err instead of silently constructing — correct per RFC and Postel (structural validity is enforced).

**Callers adapt:**
- `filterCondition` callers: **no change** (leaf ctor identical).
- `filterOperator(foAnd/foOr, xs)` → `filterAnd(xs)` / `filterOr(xs)` and **handle the `Result`** (`.get()` where the literal is provably non-empty, `?`/`valueOr` otherwise). In tests, `.get()` with an adjacent invariant comment is acceptable (functional-core Pattern 8).
- `filterOperator(foNot, @[x])` → `filterNot(x)` (infallible).
- `.conditions` reads → `operands(f)`; `.operator` reads unchanged (still public).
- `tests/mfixtures.nim` helpers: `makeFilterAnd`/`makeFilterOr` change return to wrap `.get()` (test fixtures may keep returning `Filter[int]` with an invariant comment), add `makeFilterNot`.
- `tests/mproperty.nim:genFilter`: pick `foNot ⇒ exactly 1 child`, `foAnd/foOr ⇒ rand(1..4)` children, and build via the new constructors so it only emits **valid** trees.

## Hazards

1. **Direct-value recursion segfaults the compiler (decisive).** `of foNot: child: Filter[C]` (TODO's literal sketch) compiles in isolation but **crashes `nim` with SIGSEGV (exit 139)** the moment an `foNot` node is actually constructed (infinite-size type → codegen stack overflow). Confirmed: `/tmp/filt/b.nim`. Avoidance: any recursive child field needs heap indirection — `NonEmptySeq[Filter[C]]`/`seq` (value semantics) or `ref` (nil-able). C1 uses `NonEmptySeq` → safe.

2. **strictCaseObjects Rule 4 rejects nested-case reads on one object (decisive).** Reading an inner variant field via `case f.kind of fkOperator: case f.operator of foNot: f.rawChild` is rejected at **instantiation**: `field access outside of valid case branch: f.rawChild`. Confirmed: `/tmp/filt/e2.nim` (NIM_EXIT=1). The separate-type design (`OperatorFilter[C]` held as `node*`) compiles (`/tmp/filt/f2.nim`, NIM_EXIT=0) — but C1 sidesteps the issue entirely by having **no inner variant field** (single `kind` discriminator; `operator` is plain). Pitfall: strict errors on generic accessors are **deferred to instantiation**, so a green `nim check` on `framework.nim` alone is insufficient — a test must instantiate `operands[int]`/`operands[EmailFilterCondition]` to surface them. The build/test suite already does (e.g. `tframework`, `tserde_framework`).

3. **Pattern-4 (literal-discriminator) does NOT bite C1.** Because `operator` is a plain field, a single constructor with a runtime operator value is legal — but we still split into `filterNot`/`filterAnd`/`filterOr` to *enforce arity*, not because the compiler requires it. (Contrast: had we made `operator` an inner discriminator, `Filter(kind: fkOperator, operator: runtimeOp, …)` would fail with *"cannot prove that it's safe to initialize 'rawOperands' with the runtime value"* — confirmed `/tmp/filt/g.nim`. C1 avoids this.)

4. **`lent` return of the leaf empty-seq.** `operands*` returns `lent seq[Filter[C]]`; the `fkCondition` arm has no seq to borrow. Options: (a) return `seq[Filter[C]]` by value (a copy; simplest, drop `lent`), or (b) keep `lent` and borrow a module-level empty constant. Recommend **(a) non-`lent` `operands*` returning a copy** for the leaf-safe total accessor, OR make `operands*` a `case`-returning accessor only valid via the discriminator. Simplest total form: drop `lent`, return by value; serde/tests don't need zero-copy here. (`asSeq` itself stays `lent` for the operator arm internally.)

5. **No `==`/`$`/`hash` required, and do NOT instantiate `defineSealedNonEmptySeqOps(Filter[C])`.** That template is per-concrete-type and would force a structural `==` through `Filter[C]` (a case object → *"parallel 'fields' iterator does not work for 'case' objects"*). C1 only needs the **standalone generic** `parseNonEmptySeq[T]`/`asSeq[T]` — both already exist — so no template instantiation, no case-object `==` hazard. Confirmed by `/tmp/filt/h.nim` (NIM_EXIT=0). Tests keep their hand-rolled `filterEq`.

6. **`{.push raises: [], noSideEffect.}` purity.** `filterAnd`/`filterOr` use `?parseNonEmptySeq` (pure) and `ok(...)`; `filterNot` uses `parseNonEmptySeq(@[child]).get()` — a `.get()` requiring the **adjacent invariant comment** ("`@[child]` length 1 ⇒ cannot Err") per functional-core Pattern 8. All total/pure. Serde's `filterAndOr` helper must carry `{.noSideEffect, raises: [].}` implicitly via the module push.

7. **nimalyzer `objects` rule.** Adding `{.ruleOff: "objects".}` to `Filter*[C]` (now sealed with a private field) matches the established sealed-Pattern-A convention (`PropertyName`, `Comparator`, `NonEmptySeq` all do this). Without sealing (keeping `operands*` public `NonEmptySeq`), the `ruleOff` may be unnecessary — but then 2-child-`foNot` is constructable by anyone who can build a `NonEmptySeq` (only via `parseNonEmptySeq`, still ≥1). **Decision point:** seal (private `rawOperands` + accessor, kills 2-child-foNot) vs. public `operands*: NonEmptySeq` (simpler, only kills *empty*). Recommend **seal** to fully close P16.

8. **`StackOverflowDefect`/depth.** Unchanged — `MaxFilterDepth = 128` guard in `fromJsonImpl` stays; the deep-tree stress tests (`tstress.nim` 1000/5000 levels built iteratively) still pass since construction is unchanged structurally.

## Audit/test impact

**Must invert (currently assert the now-illegal states — these are the load-bearing changes):**
- `tests/unit/tframework.nim:92-103` — `filterOperatorNotEmpty` (foNot with `@[]`) and `filterOperatorNotMultiple` (foNot with 3) must become: `filterNot` takes a single child (compile-shape), and there is **no** API to give NOT zero/many. Replace with assertions that `filterAnd(@[])`/`filterOr(@[])` return `isErr`, and that `filterNot(x).operands.len == 1`.
- `tests/property/tprop_framework.nim:160-174` — `Filter operator arity` (foNot×2, foAnd `@[]`) → invert to Result-err assertions.
- `tests/compliance/trfc_8620.nim:813-831,1064-1068` — `filterOperatorArity`, `filterOperatorEmptyConditions` → invert (empty AND/OR ⇒ `isErr`; foNot constructed via `filterNot` is single).
- `tests/stress/tadversarial.nim:943-954` — foNot×2 / foAnd-empty edge cases → invert.

**Must update (mechanical: constructor name + `.get()`/Result + `.conditions`→`operands`):**
- `tests/mfixtures.nim:479-483,836-839` (helpers + `filterEq`); `tests/mproperty.nim:472-484` (`genFilter` arity-correct).
- `tests/unit/tframework.nim` (all operator construct/read), `tests/property/tprop_framework.nim`, `tests/compliance/trfc_8620.nim`, `tests/serde/tserde_framework.nim`, `tests/serde/tserde_adversarial.nim`, `tests/stress/tstress.nim`, `tests/integration/live/temail_query_filter_tree_live.nim`, `tests/unit/ttypesafety.nim:66`.

**Serde round-trip tests gaining arity enforcement:**
- `tests/serde/tserde_framework.nim:256-258` (`filterOperatorEmpty`/empty-conditions round-trip) and any fromJson test feeding `{"operator":"NOT","conditions":[a,b]}` or empty `conditions` must now expect **Err** (`svkArrayLength` for NOT≠1, `svkEmptyRequired` for AND/OR empty). Add: `treject`-style serde cases for `NOT` with 0 and 2 children, and `AND`/`OR` with `[]`.

**New tests to add:**
- `tcompile`/`treject` (`ttypesafety.nim`): `not compiles(filterOperator(...))` (symbol removed); `not compiles(Filter[int](kind: fkOperator, operator: foNot, rawOperands: …))` (private payload — external raw construction blocked, confirmed `/tmp/filt`); `filterAnd`/`filterOr` return `Result`, `filterNot` returns `Filter` (signature compile-checks).
- Unit: `filterNot(x).operands.len == 1`; `filterAnd(@[]).isErr`; `filterAnd(@[a]).get().operands.len == 1`.
- Property (`genFilter`): "every generated tree is RFC-arity-valid" (NOT⇒1, AND/OR⇒≥1) and round-trips.
- Snapshot/captured: the wire fixtures (`tcaptured_email_query_advanced_filter`, `tcaptured_mailbox_query_changes_with_filter`) are unaffected — toJson output is byte-identical (NOT still emits a one-element `conditions`).

## Open questions

1. **`foNot` exactly-one: type-level vs. constructor-level.** The TODO wants `of foNot: child: Filter[C]` to put "exactly one" in the type. This is **provably impossible as written** (compiler segfault on value recursion; strict Rule 4 on nested-case reads). The only way to encode foNot-arity *structurally* is `rawChild: ref Filter[C]` inside a **separate `OperatorFilter[C]` type** — which reintroduces `nil` + an ARC ref + a deref panic surface under `--panics:on`, against the codebase's "value types, nil impossible" principle. **Recommendation: adopt C1 (flat sealed `NonEmptySeq`)** — foNot-exactly-one becomes a sealed-`filterNot` invariant (documented on the type and the constructor), 2-child-foNot is unconstructable via the private payload, and empty-operands is unrepresentable at the type level. This closes the real RFC violation without `ref`/`nil`. If the team prioritises type-level foNot-arity over the no-ref rule, the fallback is the `OperatorFilter[C]` + `ref` design (F2 shape, confirmed compiling).

2. **Seal or leave `operands` public?** Recommend **seal** (`{.ruleOff: "objects".}`, private `rawOperands`, public `operands*` accessor) to make 2-child-`foNot` unconstructable. A public `operands*: NonEmptySeq[Filter[C]]` is simpler and still kills the *empty* case, but leaves 2-child-`foNot` representable. Recommend sealing.

3. **AND/OR arity ≥1 vs ≥2.** RFC 8620 §5.5 literal text is "one or more", so `NonEmptySeq` (≥1) is RFC-correct; the TODO confirms ≥1, not ≥2. **Recommendation: ≥1 (NonEmptySeq), no consumer-tightening to ≥2** — a single-operand AND/OR is RFC-valid and some test trees rely on it (`tserde_framework.nim:125` builds `makeFilterAnd(@[one])`).

4. **`fromJson` arity errors — new `svk` kind or reuse?** Recommend **reuse**: `svkArrayLength` (via `expectLen`) for NOT≠1 and `svkEmptyRequired` for empty AND/OR — both helpers exist (`serde_helpers.nim:100,111`), no new violation variant needed.

================================================================================
## SOURCE agent-a3893859815aec6e9.jsonl — # B7 Change-Map: `mail_filters.nim` `Opt[bool]` → three-state enums (P18)
================================================================================

I have everything needed. Here is the complete change-map.

---

# B7 Change-Map: `mail_filters.nim` `Opt[bool]` → three-state enums (P18)

## Current state

Three filter fields are `Opt[bool]`, encoding three states (absent / true / false) by overloading `Opt`'s present/absent axis with a payload bool. P18 wants the three states named.

**`src/jmap_client/internal/mail/mail_filters.nim`** — field declarations (verbatim):

`MailboxFilterCondition` (plain object, `{.ruleOff: "objects".}`, no smart constructor — Decision B16):
```nim
32	  hasAnyRole*: Opt[bool] ## Filter by whether any role is set.
33	  isSubscribed*: Opt[bool] ## Filter by subscription status.
```
`EmailFilterCondition` (plain object, `{.ruleOff: "objects".}`, no smart constructor):
```nim
91	  hasAttachment*: Opt[bool] ## Match on hasAttachment value.
```

**`src/jmap_client/internal/mail/serde_mail_filters.nim`** — wire emission (toJson-only; filters flow client→server, Decision B11). Each field emits via `Opt` iteration:
```nim
41	  for v in fc.hasAnyRole:
42	    node["hasAnyRole"] = %v
44	  for v in fc.isSubscribed:
45	    node["isSubscribed"] = %v
...
125	  for v in fc.hasAttachment:
126	    node["hasAttachment"] = %v
```
Current rule: `Opt.none` → omit key; `Opt.some(true)` → `true`; `Opt.some(false)` → `false`. RFC 8621 §2.3 (`hasAnyRole`/`isSubscribed`) and §4.4.1 (`hasAttachment`) are plain JSON Booleans.

Note `parentId`/`role` use a *different* three-state shape (`Opt[Opt[T]]` via `emitThreeState`, lines 19–27) and are **out of scope** for B7 — they stay.

## All sites

### src/ (4 lines, 2 files)
- `src/jmap_client/internal/mail/mail_filters.nim:32` — decl `hasAnyRole*: Opt[bool]`
- `src/jmap_client/internal/mail/mail_filters.nim:33` — decl `isSubscribed*: Opt[bool]`
- `src/jmap_client/internal/mail/mail_filters.nim:91` — decl `hasAttachment*: Opt[bool]`
- `src/jmap_client/internal/mail/serde_mail_filters.nim:41-42` — emit `hasAnyRole`
- `src/jmap_client/internal/mail/serde_mail_filters.nim:44-45` — emit `isSubscribed`
- `src/jmap_client/internal/mail/serde_mail_filters.nim:125-126` — emit `hasAttachment`

No other src/ site reads these fields (filters are opaque to builders — wrapped in generic `Filter[C]` and serialised via `c.toJson()`; no FFI/exportc touches them).

### tests/ (construct + read + count)
Unit/serde (construct + assert):
- `tests/serde/mail/tserde_mail_filters.nim:33,45,58,70,82,94` — `hasAnyRole: Opt.none(bool)` (6 MailboxFilterCondition ctors)
- `tests/serde/mail/tserde_mail_filters.nim:106` — `hasAnyRole: Opt.some(true)`
- `tests/serde/mail/tserde_mail_filters.nim:112` — `assertJsonFieldEq node, "hasAnyRole", newJBool(true)`
- `tests/serde/mail/tserde_mail_filters.nim:34,46,59,71,83,95,107` — `isSubscribed: Opt.none(bool)` (7 ctors)
- `tests/serde/mail/tserde_mail_filters.nim:280` — `hasAttachment: Opt.some(true)` (EmailFilterCondition)
- `tests/serde/mail/tserde_mail_filters.nim:287` — `assertJsonFieldEq node, "hasAttachment", %true`
- `tests/serde/mail/tserde_mail_filters.nim:310` — `hasAttachment: Opt.some(true)`
- `tests/serde/mail/tserde_mail_filters.nim:324` — `assertJsonFieldEq node, "hasAttachment", %true`

Property (generate + read + count):
- `tests/mproperty.nim:1982` — `fc.hasAttachment = Opt.some(rng.rand(0 .. 1) == 0)` (inside `genEmailFilterCondition`)
- `tests/property/tprop_mail_d.nim:151` — `if fc.hasAttachment.isSome: inc expectedCount` (field-count invariant)
- (No MailboxFilterCondition property generator/count exists — `hasAnyRole`/`isSubscribed` are not property-tested.)

Live integration (construct):
- `tests/integration/live/tmailbox_query_filter_sort_live.nim:151` — `MailboxFilterCondition(hasAnyRole: Opt.some(true))`
- `tests/integration/live/temail_query_advanced_filter_live.nim:198` — `EmailFilterCondition(hasAttachment: Opt.some(true), before: Opt.some(future))`

Not affected (same identifier, different type — Email/Mailbox **entity** fields, not filters): `tests/mfixtures.nim:597,625,969`; `tests/mproperty.nim:1697,1839,2062,2099`; `tests/serde/mail/tserde_email_adversarial.nim:253,341-351`; `tests/serde/mail/tserde_email_integration.nim:92`; all of `mailbox.nim`/`email.nim`/`serde_mailbox.nim`/`serde_email.nim` `isSubscribed`/`hasAttachment` (those are `bool`/`Opt[bool]` entity read-model / `FieldEcho` fields, governed by other items).

### docs/ (design-spec drift — sync, not compiled)
`docs/design/05-mail-architecture.md:2349,2350,2384,2564`; `docs/design/07-mail-b-design.md:934,935,974,975,1354`; `docs/design/09-mail-d-design.md:579,1012`. These show the old `Opt[bool]` shape; uplift to the enum shape (clean-refactor doc hygiene).

## Proposed cut

### New enums — live in `mail_filters.nim` (L1 mail type module), hub-public
Declared at the top of `mail_filters.nim` (after imports, before `MailboxFilterCondition`). They are filter-builder inputs, so they MUST be hub-reachable — and already are: `mail_filters` is `import`ed and `export`ed by `src/jmap_client/internal/mail/types.nim:19,38`, which `src/jmap_client.nim` re-exports. An exported enum type auto-exports its values, so `*` on the type is sufficient.

```nim
type HasAnyRoleFilter* = enum
  ## Mailbox/query ``hasAnyRole`` predicate (RFC 8621 §2.3).
  hrfRequireAny   ## Match Mailboxes that have a role  → wire ``true``.
  hrfRequireNone  ## Match Mailboxes with no role      → wire ``false``.
  hrfNoConstraint ## Do not filter on role presence    → key omitted.

type SubscriptionFilter* = enum
  ## Mailbox/query ``isSubscribed`` predicate (RFC 8621 §2.3).
  sfSubscribed    ## → wire ``true``.
  sfNotSubscribed ## → wire ``false``.
  sfNoConstraint  ## key omitted.

type HasAttachmentFilter* = enum
  ## Email/query ``hasAttachment`` predicate (RFC 8621 §4.4.1).
  hafYes          ## → wire ``true``.
  hafNo           ## → wire ``false``.
  hafNoConstraint ## key omitted.
```

### Field shape — object-field default `= *NoConstraint` (load-bearing)
```nim
hasAnyRole*: HasAnyRoleFilter = hrfNoConstraint    ## (was Opt[bool])
isSubscribed*: SubscriptionFilter = sfNoConstraint ## (was Opt[bool])
...
hasAttachment*: HasAttachmentFilter = hafNoConstraint ## (was Opt[bool])
```
The `= *NoConstraint` default is **mandatory**, not cosmetic: the spec lists `*NoConstraint` last (ordinal 2), but the field must default to it so omitted-field construction and `default(T)` keep today's "omit key" behaviour. Empirically verified at Nim 2.2.8 (`/tmp/b7probe.nim`): with the field default, both `EFC(inMailbox: …)` (omitting the enum field) and `default(EFC)` yield the ordinal-2 `…NoConstraint`; **without** the field default they yield ordinal-0 (`hafYes`) — silently flipping the wire to `"hasAttachment": true`. (Alternative: reorder each enum to put `*NoConstraint` first; rejected — it fights the spec's named order and the natural true/false/omit reading. Field default keeps both.)

### Serde adaptation — overloaded emit helper (keeps toJson flat; complexity ≤10)
Add three overloads in `serde_mail_filters.nim` and replace the three `for` loops:
```nim
func emitBoolFilter(node: JsonNode, key: string, f: HasAnyRoleFilter) =
  case f
  of hrfNoConstraint: discard
  of hrfRequireAny: node[key] = %true
  of hrfRequireNone: node[key] = %false

func emitBoolFilter(node: JsonNode, key: string, f: SubscriptionFilter) =
  case f
  of sfNoConstraint: discard
  of sfSubscribed: node[key] = %true
  of sfNotSubscribed: node[key] = %false

func emitBoolFilter(node: JsonNode, key: string, f: HasAttachmentFilter) =
  case f
  of hafNoConstraint: discard
  of hafYes: node[key] = %true
  of hafNo: node[key] = %false
```
Call sites: `toJson(MailboxFilterCondition)` lines 41–45 become `node.emitBoolFilter("hasAnyRole", fc.hasAnyRole)` + `node.emitBoolFilter("isSubscribed", fc.isSubscribed)`; `toJson(EmailFilterCondition)` lines 125–126 become `node.emitBoolFilter("hasAttachment", fc.hasAttachment)`. Wire rule unchanged: `*NoConstraint` → omit; others → bool. (Three overloads rather than one generic: each enum's true/false mapping is its own knowledge, not duplicated knowledge — DRY-correct. Inline `case` in `toJson` would also work but pushes `toJson(MailboxFilterCondition)` toward the cyclomatic-complexity-10 ceiling; the helper keeps it flat.)

### Caller adaptation (tests)
- `Opt.none(bool)` → `*NoConstraint`; or simply **delete the line** (field default covers it). Recommended: delete the `hasAnyRole:`/`isSubscribed:` lines from the all-none ctors in `tserde_mail_filters.nim` (they now equal the default), keeping the tests' intent crisp; the `assertLen node, 0/1/2` assertions still hold.
- `Opt.some(true)` → `hrfRequireAny` / `hafYes`; `Opt.some(false)` → `hrfRequireNone` / `hafNo`.
  - `tserde_mail_filters.nim:106` → `hasAnyRole: hrfRequireAny` (line 112 assertion `newJBool(true)` unchanged).
  - `tserde_mail_filters.nim:280,310` → `hasAttachment: hafYes` (lines 287,324 `%true` unchanged).
- `tmailbox_query_filter_sort_live.nim:151` → `MailboxFilterCondition(hasAnyRole: hrfRequireAny)`.
- `temail_query_advanced_filter_live.nim:198` → `EmailFilterCondition(hasAttachment: hafYes, before: Opt.some(future))`.
- `mproperty.nim:1982` → `fc.hasAttachment = (if rng.rand(0 .. 1) == 0: hafYes else: hafNo)`.
- `tprop_mail_d.nim:151` → `if fc.hasAttachment != hafNoConstraint: inc expectedCount`.

Principles served: **P18** (named sum type over bool/flag soup — primary), **make-illegal-states-unrepresentable** (the `Opt[bool]` double-axis collapses to one 3-valued axis; "absent-but-meaningful" can no longer masquerade as "missing"), **one-source-of-truth-per-fact**, and **booleans-are-a-code-smell**.

## Hazards

1. **Ordinal-0 default flip (the big one).** Covered above: without `= *NoConstraint` field defaults, every omitted-field construction (and `default(EmailFilterCondition)` used by `mfixtures.nim:538 makeEmailFilterCondition`) silently emits `…RequireAny`/`hafYes`/`sfSubscribed` → wrong wire. Must add the three field defaults. Verified at Nim 2.2.8.
2. **`{.experimental: "strictCaseObjects".}` is a non-issue here.** `MailboxFilterCondition`/`EmailFilterCondition` are plain objects (`{.ruleOff: "objects".}`), not case objects, and the new `case f of …` blocks are over *plain enums* — strict-case-object proof obligations don't apply. The `case` must still be exhaustive (no `else`) per `nim-functional-core` "never catch-all `else` over a finite enum"; the three 3-arm cases are exhaustive.
3. **`{.push raises: [], noSideEffect.}` purity.** The emit helpers are pure (literal enum match + `JsonNode` mutation of a local-scope node passed by the caller — same pattern as existing `emitThreeState`). No raising calls. `func` mandatory in L1/L2 — both files already are func-only; new helpers are `func`.
4. **nimalyzer complexity ≤10** (`nimalyzer.cfg:22 check complexity all 10`). The overloaded-helper approach keeps `toJson(MailboxFilterCondition)`/`toJson(EmailFilterCondition)` complexity unchanged (still straight-line calls). Each `emitBoolFilter` overload is complexity 3.
5. **styleCheck:error / enum prefix convention.** Prefixes `hrf`/`sf`/`haf` match the type names and are lowercase per convention. Grep confirms **no existing collision** with `hrf*`/`sf*`/`haf*` enum values anywhere in src/ or tests/.
6. **`EnumConv`/`HoleEnumConv` warningAsError.** No int↔enum conversion is introduced (no `{.size.}` / FFI involvement — these enums never cross the C ABI). Safe.
7. **`--mm:arc` / lent / `.get()` copying.** Enums are trivially-copyable value types; none of the uncopyable-`T` `.get()`/`.value` hazards apply. The old `for v in fc.hasAttachment:` Opt-iteration (which copied the bool) is gone.
8. **Property field-count invariant** (`tprop_mail_d.nim`): the `isSome`→`!= …NoConstraint` rewrite must be exact, else the `j.len == expectedCount` assertion fails for the `hafYes`/`hafNo` cases. The generator (`mproperty.nim:1982`) must generate both non-default values (not always `hafYes`) to keep coverage; the `if rng.rand(0..1)==0` mapping does this.

## Audit/test impact

- **Update (mechanical, behaviour-preserving):** `tests/serde/mail/tserde_mail_filters.nim` (the `Opt.none/some` → enum / line-deletion edits above; `assertJsonFieldEq` lines unchanged), `tests/mproperty.nim:1982`, `tests/property/tprop_mail_d.nim:151`, `tests/integration/live/tmailbox_query_filter_sort_live.nim:151`, `tests/integration/live/temail_query_advanced_filter_live.nim:198`.
- **Add (recommended) — reject/compile audit:**
  - A `treject_*` testament `action: reject` test proving the wire-safety invariant in a typed way is *not* directly expressible (no smart constructor / no illegal combination — all three enum values are individually legal). Instead add a **positive `tcompile_*` hub-surface assertion** that the three enums are reachable from `import jmap_client`: extend the mail hub-surface compile test (sibling to `tests/compile/tcompile_a1d_mail_hub_surface.nim` / `tcompile_mail_g_public_surface.nim`) with `doAssert declared(HasAnyRoleFilter)`, `declared(SubscriptionFilter)`, `declared(HasAttachmentFilter)` plus one value each (`doAssert declared(hrfNoConstraint)` …) — locking hub-publicity per the B7 requirement.
  - Add one serde unit case asserting the **`*NoConstraint` = omit** and **`…No`/`…NotSubscribed` = `false`** arms explicitly (the current suite only exercises `Opt.some(true)` for these; the `false`/omit arms of the new enums should each get a `assertJsonFieldEq … %false` / `assertLen 0` case so the case-arm mapping is pinned). This is the regression gate for hazard #1.
- **Snapshot gates:** none. No `tests/wire_contract/` snapshot covers these filters (`module-paths.txt`/`error-messages.txt` only). Captured `tests/testdata/captured/*.json` `hasAttachment`/`isSubscribed` occurrences are all **entity** read-model fields (server→client), not filter emissions, so no fixture changes.
- **Docs:** uplift `docs/design/05-mail-architecture.md` (2349/2350/2384/2564), `07-mail-b-design.md` (934/935/974/975/1354), `09-mail-d-design.md` (579/1012) from `Opt[bool]` to the enum shape — clean-refactor doc hygiene, not compiled.

## Open questions

1. **Field-default vs. enum reorder.** Recommendation: **field-default** (`= *NoConstraint`, enums in spec order `RequireAny/RequireNone/NoConstraint`). It honours the spec's named order, reads naturally, and is verified to make `default(T)`/partial-construction behave. No human decision needed unless the team prefers ordinal-0-`NoConstraint` (then drop the field defaults and reorder each enum) — but that contradicts the B7 code-snippet ordering.
2. **All-none test lines: delete vs. set explicitly.** Recommendation: **delete** the now-redundant `hasAnyRole:`/`isSubscribed:` lines from the six/seven all-none ctors in `tserde_mail_filters.nim` (field default covers them, intent stays clear). If the team prefers explicit `*NoConstraint` for documentation, set them explicitly — purely stylistic; both compile and pass.
3. **Generic emit helper vs. three overloads.** Recommendation: **three overloads** (DRY-correct: each enum's true/false mapping is distinct knowledge; keeps `toJson` flat under the complexity-10 ceiling). A single generic over `enum` would need a uniform "which value → true/false/omit" convention the three enums don't structurally share. No human decision required.

================================================================================
## SOURCE agent-a436a92e3e11e8c83.jsonl — # B8 (P18): `Identity.mayDelete` three-state → `DeleteAuthority` enum — change-m
================================================================================

I have a complete picture. Here is the exhaustive change-map.

---

# B8 (P18): `Identity.mayDelete` three-state → `DeleteAuthority` enum — change-map

> **Factual correction up front (feeds Open Questions).** The task header says "`identity.nim` `Identity.mayDelete: Opt[bool]`". That is not the actual shape. The full read model `Identity.mayDelete` is a plain **`bool`** (always required by the current parser). The genuine three‑state `Opt[bool]` "Stalwart omits the field" encoding lives on **two other types**: `IdentityCreatedItem.mayDelete` and `PartialIdentity.mayDelete`. The concept "delete authority" therefore appears in **three representations today** (`bool`, `Opt[bool]`, `Opt[bool]`). The principled cut collapses all three onto one `DeleteAuthority`.

## Current state — actual type/field definitions

**`src/jmap_client/internal/mail/identity.nim`**

`Identity` (full read model) — `mayDelete` is plain `bool`, line 30:
```nim
type Identity* {.ruleOff: "objects".} = object          # :20
  ...
  mayDelete*: bool ## Whether the client may delete this identity.   # :30
```

`IdentityCreatedItem` (RFC 8620 §5.3 created[cid] subset) — `Opt[bool]`, lines 41–55:
```nim
type IdentityCreatedItem* {.ruleOff: "objects".} = object   # :41
  ## ... (docstring lines 41-53, lines 48-53 justify Opt[bool]):
  ## ``mayDelete`` is ``Opt[bool]`` rather than ``bool`` because Stalwart
  ## 0.15.5 omits it from this payload ... Mirrors the
  ## ``EmailCreatedItem`` design (``email.nim``).
  id*: Id                                                   # :54
  mayDelete*: Opt[bool]                                     # :55
```

`PartialIdentity` (A3.6/A4 sparse echo) — `Opt[bool]`, line 74:
```nim
type PartialIdentity* {.ruleOff: "objects".} = object       # :61
  ...
  mayDelete*: Opt[bool]                                     # :74
```

Note: `replyTo`/`bcc` on `PartialIdentity` are `FieldEcho[seq[EmailAddress]]` (lines 68–71) because they are wire-*nullable*; `mayDelete` is wire-*non-nullable* (a bool) so it is `Opt`, not `FieldEcho` — this resolves the prompt's "FieldEcho/Opt — reconcile": it is `Opt`, parsed two-state via `parsePartialOptField`.

The `igkMayDelete = "mayDelete"` property selector (identity.nim:241), `igpMayDelete*` const (:290) and parse arm (:315) are **the property *name* selector**, unrelated to the field's value type — they stay unchanged.

**`src/jmap_client/internal/mail/serde_identity.nim`** — current serde:

- `Identity.toJson` line 84: `node["mayDelete"] = %ident.mayDelete` (always emits).
- `Identity.fromJson` lines 110–111, 121: `let mayDeleteNode = ?fieldJBool(node, "mayDelete", path)` → **field is REQUIRED** (`fieldJBool` errors on absent/null/wrong-kind); `let mayDelete = mayDeleteNode.getBool(false)`; constructed at :121.
- `IdentityCreatedItem.toJson` lines 161–162: `for v in item.mayDelete: node["mayDelete"] = %v` (omits when none).
- `IdentityCreatedItem.fromJson` lines 177–182: manual three-state — absent/null → `Opt.none`, present non-bool → violation, present bool → `Opt.some`; constructed :182.
- `PartialIdentity.fromJson` line 202: `let mayDelete = ?parsePartialOptField[bool](node, "mayDelete", path)`; constructed :212.
- `PartialIdentity.toJson` lines 232–233: `for v in p.mayDelete: node["mayDelete"] = v.toJson()`.

## All sites — every construct / read / serde / test caller

### src/ (type defs + serde + docstrings)
- `internal/mail/identity.nim:30` — `Identity.mayDelete*: bool` (def)
- `internal/mail/identity.nim:48` — docstring "`mayDelete` is `Opt[bool]`…" (IdentityCreatedItem)
- `internal/mail/identity.nim:55` — `IdentityCreatedItem.mayDelete*: Opt[bool]` (def)
- `internal/mail/identity.nim:74` — `PartialIdentity.mayDelete*: Opt[bool]` (def)
- `internal/mail/serde_identity.nim:84` — Identity.toJson emit (read `ident.mayDelete`)
- `internal/mail/serde_identity.nim:110-111,121` — Identity.fromJson parse+construct
- `internal/mail/serde_identity.nim:130` — comment "no id or mayDelete" (IdentityCreate; no change)
- `internal/mail/serde_identity.nim:157,161-162` — IdentityCreatedItem.toJson emit (read `item.mayDelete`)
- `internal/mail/serde_identity.nim:169,177-182` — IdentityCreatedItem.fromJson parse+construct
- `internal/mail/serde_identity.nim:202,212` — PartialIdentity.fromJson parse+construct
- `internal/mail/serde_identity.nim:232-233` — PartialIdentity.toJson emit (read `p.mayDelete`)
- `internal/mail/mail_entities.nim:119-121` — `setResponseType[Identity]` docstring referencing `Opt[bool]`
- `internal/mail/identity_builders.nim:87,90` — `addIdentitySet` docstring "optional server-set `mayDelete`" / "`mayDelete` is false"

(Out of scope — different field: every `mayDelete` under `mailbox.nim:349` / `serde_mailbox.nim:159,176,187` is the `MailboxRights` ACL bool, the documented P18 exception B6 — **do not touch**.)

### tests/ — Identity-value sites
- `tests/serde/mail/tserde_identity.nim:50` — read: `assertEq ident.mayDelete, true`
- `tests/serde/mail/tserde_identity.nim:111` — construct `mayDelete: true` (roundTripFull)
- `tests/serde/mail/tserde_identity.nim:119` — read: `assertEq roundTripped.mayDelete, ident.mayDelete`
- `tests/serde/mail/tserde_identity.nim:132` — construct `mayDelete: false` (roundTripMinimal)
- `tests/serde/mail/tserde_identity.nim:223,234,249,262` — construct `mayDelete: false` (toJson* cases)
- `tests/serde/mail/tserde_identity.nim:167-169` — `fromJsonMissingMayDelete` → currently `assertErr` (**behaviour change site**)
- `tests/serde/mail/tserde_identity.nim:183-185` — `fromJsonMayDeleteWrongType` (`"mayDelete":"true"`) → stays `assertErr`
- `tests/serde/mail/tserde_identity.nim` (JSON literals at :33,53,64,70,76,82,89-92,150,156,160,176,180,191,195,201,210) — wire `"mayDelete": true/false` literals: **unchanged** (wire stays a JSON bool)

### tests/ — Identity property-selector site (unaffected: it's the *name* not the value)
- `tests/unit/mail/tget_property_selectors.nim:54` — `assertEq igpMayDelete.wireName, "mayDelete"`

### tests/ — structural-only (parse whole SetResponse, never read the field): no change required
- `tests/serde/captured/tcaptured_identity_set_update_stalwart.nim:35-37`
- `tests/serde/captured/tcaptured_identity_changes_with_updates.nim:27-29`
- `tests/serde/captured/tcaptured_patch_object_deep_paths.nim:32-34`
- `tests/integration/live/tpatch_object_deep_paths_live.nim:206-208`
- Captured fixtures `identity-*.json` carry no `mayDelete` value (`updated:{"cy":null}`) — no fixture edits.

### tests/ — confirmed NOT Identity entity (false positives, no change)
- `tests/integration/tpipeline.nim:217` — `"mayDelete": true` is inside a **Mailbox** `mailboxRights` object
- `tests/property/{tprop_algebraic,twire_determinism,tprop_mail_g}.nim` — "Identity" = monad/round-trip *identity law* & submission-param, not the entity
- `tests/compile/tcompile_a1d_mail_hub_surface.nim` (:38,47,110,221-222), `tcompile_mail_f_public_surface.nim` (:108-117), `tcompile_a1_public_surface.nim` (:75-77) — `declared(...)` hub-surface checks; no field reads

### No-impact confirmations
- No FFI/C-ABI accessor reads `Identity.mayDelete` (`src/jmap_client.nim` clean).
- No `convenience.nim` read.
- No `tests/wire_contract/type-shapes.txt` (A25 not yet implemented) to update.
- All in-tree constructors of the three types are inside `serde_identity.nim` only.

## Proposed cut

### New type (identity.nim, L1) — place above `Identity` (after the imports block, ~line 19)
```nim
type DeleteAuthority* = enum
  ## RFC 8621 §6 — the server's statement of whether the client may
  ## delete an Identity (the wire ``mayDelete`` boolean), modelled as a
  ## three-state sum so "the server did not report it" is a named state
  ## rather than an ``Opt[bool]`` smuggling a third value past the type
  ## (P18). Wire rule: ``daYes``/``daNo`` mean the boolean was present
  ## and true/false; ``daUnreported`` means the property was absent.
  ##
  ## **Stalwart workaround.** Stalwart 0.15.5 omits ``mayDelete`` from the
  ## Identity/set ``created[cid]`` acknowledgement (a strict-RFC §5.3 minor
  ## divergence — the ack is just ``{"id": "<id>"}``); that omission lands
  ## as ``daUnreported``. Postel's-law accommodation: be lenient on receive.
  daYes
  daNo
  daUnreported
```

### Field rewrites (identity.nim)
- `:30` `Identity.mayDelete*: bool` → `mayDelete*: DeleteAuthority` (docstring: "Server's delete authority for this identity (RFC 8621 §6); `daUnreported` if the server omitted the field.")
- `:55` `IdentityCreatedItem.mayDelete*: Opt[bool]` → `mayDelete*: DeleteAuthority`; rewrite docstring lines 48–53 to point at `DeleteAuthority` (drop the now-inaccurate "Mirrors EmailCreatedItem" line — `EmailCreatedItem` is strict-no-`Opt`, email.nim:618-622).
- `:74` `PartialIdentity.mayDelete*: Opt[bool]` → `mayDelete*: DeleteAuthority`

### Serde adaptation (serde_identity.nim) — two shared helpers in the "Helpers" block (after line 56)
```nim
func parseDeleteAuthority(
    node: JsonNode, key: string, path: JsonPath
): Result[DeleteAuthority, SerdeViolation] =
  ## Wire rule (RFC 8621 §6): absent or null → ``daUnreported``;
  ## JSON ``true`` → ``daYes``; ``false`` → ``daNo``. Strict on a present
  ## non-boolean value (D4). Stalwart 0.15.5 omits the field → daUnreported.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(daUnreported)
  ?expectKind(field, JBool, path / key)
  return ok(if field.getBool(false): daYes else: daNo)

template emitDeleteAuthority(node: JsonNode, key: string, da: DeleteAuthority) =
  ## ``daUnreported`` omits the key (round-trips the server omission);
  ## ``daYes``/``daNo`` emit the wire boolean. Template (not func) to mutate
  ## the caller's local node under ``noSideEffect`` — mirrors
  ## ``emitPartialFieldEcho``.
  case da
  of daUnreported: discard
  of daYes: node[key] = %true
  of daNo: node[key] = %false
```
(`emit` is a **template**, matching `emitPartialFieldEcho` in `serde_field_echo.nim:84`, to keep node-mutation inside the caller's `func` scope under `{.push raises: [], noSideEffect.}`.)

Then:
- `:84` Identity.toJson → `emitDeleteAuthority(node, "mayDelete", ident.mayDelete)`
- `:110-111` Identity.fromJson → `let mayDelete = ?parseDeleteAuthority(node, "mayDelete", path)` (replaces the `fieldJBool` required-field parse). `:121` construct unchanged in shape.
- `:161-162` IdentityCreatedItem.toJson → `emitDeleteAuthority(node, "mayDelete", item.mayDelete)`
- `:177-182` IdentityCreatedItem.fromJson → `let mayDelete = ?parseDeleteAuthority(node, "mayDelete", path)`; `:182` construct unchanged.
- `:202` PartialIdentity.fromJson → `let mayDelete = ?parseDeleteAuthority(node, "mayDelete", path)` (replaces `parsePartialOptField[bool]`).
- `:232-233` PartialIdentity.toJson → `emitDeleteAuthority(node, "mayDelete", p.mayDelete)`

### Docstrings to uplift
- `mail_entities.nim:119-121` — replace "so `IdentityCreatedItem.mayDelete` is `Opt[bool]`" with "…is `DeleteAuthority` (`daUnreported` when omitted)".
- `identity_builders.nim:87,90` — "optional server-set `mayDelete`" → "the server-set `mayDelete` as `DeleteAuthority`"; "`mayDelete` is false" → "`mayDelete` is `daNo`".

### Caller adaptation (the only true behaviour change)
`Identity.fromJson` becomes **lenient on absent `mayDelete`** (absent → `daUnreported`) instead of erroring. This is the single intentional semantic shift; it unifies all three types onto one rule and aligns with the codebase's established Postel posture (empty `email` accepted at serde_identity.nim:97-102; omitted `newState` at email.nim:646). `present-but-wrong-kind` stays a violation; `present-null` now maps to `daUnreported` (was an error for the full record, was already `none` for the two partials — now uniform).

### Principles served
P18 (sum types over flag-soup / `Opt[bool]`); "Booleans are a code smell"; "one source of truth per fact" (one `DeleteAuthority` for a concept previously spelled three ways); "make state explicit in the type"; Postel (lenient receive, named `daUnreported`).

## Hazards

- **`{.push raises: [], noSideEffect.}` (L1–L3).** `parseDeleteAuthority` only reads `node{key}` (the safe `{}` accessor, not `[]`) and returns `Result` — pure, total. The emit must be a **template**, not a `func`: writing `node[key] = …` through a *parameter* `JsonNode` from a `func` risks a `noSideEffect` violation (existing code only mutates *locally-allocated* nodes inside toJson; the precedent `emitPartialFieldEcho` is a template for exactly this reason).
- **`strictCaseObjects`.** `DeleteAuthority` is a plain enum, **not** a case object — none of the four strict variant-access rules apply. The `case da of daYes/daNo/daUnreported` arms are total; no `else`, no field reads. No `FieldDefect`/panic surface.
- **`--warningAsError:EnumConv` / `HoleEnumConv`.** No integer↔enum conversion anywhere; values are constructed by literal (`daYes` etc.), so these never trip.
- **No catch-all `else`** (H9 lint, nim-functional-core "Hard prohibitions"): both `case` sites enumerate all three arms.
- **nimalyzer `objects` rule.** Enum is not an object → **no** `{.ruleOff: "objects".}` needed (and adding one would be wrong). `complexity` is unaffected — `parseDeleteAuthority` is a trivial if/expectKind/case.
- **Enum-prefix naming (`--styleCheck:error`, nim-conventions).** `da` is the correct initials prefix for `DeleteAuthority` (cf. `cek`/`tek`); matches the TODO's literal `daYes, daNo, daUnreported`.
- **`==`/`$`/`hash` derivation.** Enums get `==`/`$` for free, so `assertEq` (`tests/massertions.nim:83`, uses `==` and `$`) works on `DeleteAuthority`, and any auto/explicit structural `==` over `PartialIdentity`/`Identity` keeps compiling (`DeleteAuthority` substitutes cleanly for the former `Opt[bool]`/`bool`). No `ResultDefect`-copy hazard: `DeleteAuthority` is a trivially copyable value, so `.get()`/`.value` on `Result[Identity,…]`/`Result[…CreatedItem,…]` in tests stays fine.
- **ARC/`lent`.** Value enum; no move/`lent` concerns introduced.
- **Imports.** `serde_identity.nim` already imports everything required (`std/json`, `serde`/`serde_helpers` for `expectKind`, `types`, `identity`); no new import. `%true` uses the already-imported `std/json` `%`.

## Audit / test impact

**Must change (`tests/serde/mail/tserde_identity.nim`):**
- `:111`→`mayDelete: daYes`; `:132,223,234,249,262`→`mayDelete: daNo`.
- `:50` `assertEq ident.mayDelete, true` → `assertEq ident.mayDelete, daYes`.
- `:119` stays (`DeleteAuthority == DeleteAuthority`).
- `:167-169` `fromJsonMissingMayDelete` — **flip from `assertErr` to**: `assertOk` + `assertEq res.get().mayDelete, daUnreported`, and rename to `fromJsonMissingMayDeleteIsUnreported`. (This pins the intentional lenience.)
- `:183-185` `fromJsonMayDeleteWrongType` — **unchanged** (`assertErr` still holds; present non-bool → violation).
- JSON-literal `"mayDelete"` nodes elsewhere — unchanged.

**Must add (new positive coverage for the three-state contract):**
- Full `Identity`: `daYes`/`daNo` round-trip via `toJson∘fromJson`; `daUnreported` → `toJson` **omits** the `mayDelete` key (`assertJsonKeyAbsent`), and absent-on-parse → `daUnreported`.
- `IdentityCreatedItem.fromJson`: `{"id":"x"}` (Stalwart ack) → `daUnreported`; `{"id":"x","mayDelete":true}`→`daYes`; `false`→`daNo`; `"mayDelete":"x"`→violation. Symmetric `toJson` omits on `daUnreported`.
- `PartialIdentity.fromJson`: absent → `daUnreported`; present bool → `daYes`/`daNo`. (Direct `PartialIdentity`/`IdentityCreatedItem` value tests are currently absent — this adds first-ever field-level coverage; they were only exercised structurally via `SetResponse`.)

**Compile-surface (recommend adding, low cost):**
- `tests/compile/tcompile_a1d_mail_hub_surface.nim` — add `doAssert declared(DeleteAuthority)` and `doAssert declared(daUnreported)` alongside the Partial-type block (~:43-49) to pin the new public symbol reaches the root hub (it rides out via `mail/types.nim:32 export identity` → `mail.nim` → `jmap_client.nim:32`).

**No change:** captured replay tests, integration/live tests, fixtures, property tests, `tget_property_selectors.nim:54`, all Mailbox `mayDelete` tests (`tserde_mailbox.nim:91,141`).

## Open questions

1. **Scope of the enum — full `Identity` too, or only the two `Opt[bool]` sites? (primary design decision.)** The header names "`Identity.mayDelete`", but the literal `Opt[bool]` flag-soup is only on `IdentityCreatedItem`/`PartialIdentity`. **Recommendation: unify all three onto `DeleteAuthority`** (the cut above). Rationale: "one source of truth per fact" — three representations (`bool`, `Opt[bool]`, `Opt[bool]`) of one concept is itself the smell; `daUnreported` cleanly names the Postel case for any server (not just Stalwart's ack). *Alternative (minimal):* leave `Identity.mayDelete: bool` strict-required and convert only the two `Opt[bool]` fields — preserves the current "missing `mayDelete` on full /get is malformed" hard error, at the cost of two coexisting representations and not literally satisfying the header. I do **not** recommend this.

2. **`present-null` on full `Identity`.** Under the unified cut, `mayDelete: null` maps to `daUnreported` (was an error via `fieldJBool`; was already `none` for both partials). I recommend this (uniform, matches `parsePartialOptField`'s null-collapse). If a reviewer wants strictness, `parseDeleteAuthority` could reject present-null as `svkWrongKind` — but that would re-introduce an asymmetry between the full and partial parsers. **Recommend: lenient (null → `daUnreported`).**

3. **Naming/placement of `DeleteAuthority`.** It is Identity-specific (Mailbox's `mayDelete` is the independent `MailboxRights` ACL bool, B6 exception — not folded in). I place the enum in `identity.nim` (L1), exported through the existing `identity` re-export. No general/shared home needed unless a future entity grows an omittable delete bool. Flagging only because the name reads generically; **recommend keeping it in `identity.nim`**.

================================================================================
## SOURCE agent-a4e51939488d9df45.jsonl — # B10 (P12) — `lent` annotation pass on container-returning handle accessors
================================================================================

I now have a complete, verified picture. Here is the change-map.

---

# B10 (P12) — `lent` annotation pass on container-returning handle accessors

## Current state

The library already uses `lent` in three places, establishing the exact pattern to mirror (raw-field borrow, read-only, `{.inline.}`):

- `src/jmap_client/internal/types/primitives.nim:345` `func head*[T](a: NonEmptySeq[T]): lent T = a.rawValue[0]`
- `src/jmap_client/internal/types/primitives.nim:352-362` `func asSeq*[T](a: NonEmptySeq[T]): lent seq[T] {.inline.} = a.rawValue` — docstring explicitly documents the borrow contract; this is the model for B10.
- `src/jmap_client/internal/types/validation.nim:177` `func \`[]\`*(a: NonEmptySeq[T], i: Idx): lent T`
- `src/jmap_client/internal/mail/email_submission.nim:292,296` `\`[]\`` / `head` return `lent Id`.

The **named B10 targets**, verbatim:

`src/jmap_client/internal/types/session.nim:154-162`
```nim
func parts*(t: UriTemplate): seq[UriPart] =
  ## Parsed token sequence. ...
  return t.rawParts

func variables*(t: UriTemplate): HashSet[string] =
  ## Set of variable names referenced by the template. ...
  return t.rawVariables
```
`src/jmap_client/internal/types/session.nim:211-231`
```nim
func capabilities*(s: Session): seq[ServerCapability] =
  ## Server-level capabilities, core entry synthesised from ``rawCore`` ...
  let coreCap = parseServerCapability(...).get()
  result = @[coreCap]
  for cap in s.rawAdditional:
    result.add(cap)            # <-- COMPUTED: builds a fresh seq

func accounts*(s: Session): Table[AccountId, Account] =
  return s.rawAccounts          # <-- raw field passthrough

func primaryAccounts*(s: Session): Table[string, AccountId] =
  return s.rawPrimaryAccounts   # <-- raw field passthrough
```
`src/jmap_client/internal/protocol/builder.nim:136-140`
```nim
func capabilities*(b: RequestBuilder): seq[string] =
  ## Snapshot of the deduplicated capability URIs ... Returned as ``seq[string]`` ...
  return b.capabilityUris.mapIt($it)   # <-- COMPUTED: mapIt builds a fresh seq
```
The backing field is `capabilityUris: seq[CapabilityUri]` (private, builder.nim:65). **There is no accessor returning `seq[CapabilityUri]` at all** — B10's "`RequestBuilder.capabilities* — lent seq[CapabilityUri]`" is doubly stale: the public accessor returns `seq[string]`, and it is computed.

**Critical finding:** Two of B10's six named targets — `Session.capabilities*` and `RequestBuilder.capabilities*` — are **computed accessors** that build a fresh `seq` in `result`/via `mapIt`. They **cannot** take `lent` (you cannot borrow a value that is destroyed at function return; it is a compile error). The B10 punch-list is wrong on these two. They must be **skipped**, not annotated.

## All sites

### APPLY `lent` — raw-field passthrough accessors on public/handle types (src)
| file:line | accessor | returns |
|---|---|---|
| `src/jmap_client/internal/types/session.nim:154` | `parts*(t: UriTemplate)` | `seq[UriPart]` → `lent` |
| `src/jmap_client/internal/types/session.nim:159` | `variables*(t: UriTemplate)` | `HashSet[string]` → `lent` |
| `src/jmap_client/internal/types/session.nim:225` | `accounts*(s: Session)` | `Table[AccountId, Account]` → `lent` |
| `src/jmap_client/internal/types/session.nim:229` | `primaryAccounts*(s: Session)` | `Table[string, AccountId]` → `lent` |
| `src/jmap_client/internal/types/session.nim:77` | `accountCapabilities*(a: Account)` | `seq[AccountCapabilityEntry]` → `lent` |
| `src/jmap_client/internal/types/capabilities.nim:95` | `collationAlgorithms*(c: CoreCapabilities)` | `HashSet[CollationAlgorithm]` → `lent` |
| `src/jmap_client/internal/types/account_capability_schemas.nim:59` | `emailQuerySortOptions*(m: MailAccountCapabilities)` | `HashSet[string]` → `lent` |
| `src/jmap_client/internal/mail/thread.nim:30` | `emailIds*(t: Thread)` | `seq[Id]` → `lent` |
| `src/jmap_client/internal/mail/email_blueprint.nim:800` | `extraHeaders*(bp: EmailBlueprint)` | `Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]` → `lent` |

### APPLY `lent` — Pattern-A wire/lifecycle handle accessors (hub-internal/demoted, but P12 deep-copy applies to internal hot paths)
| file:line | accessor | returns | justification |
|---|---|---|---|
| `src/jmap_client/internal/types/envelope.nim:163` | `methodResponses*(r: Response)` | `seq[Invocation]` → `lent` | **strongest case**: `dispatch.findInvocation`/`findInvocationByName` scan this on *every* `get`/`getBoth` extraction (dispatch.nim:189,230) — today copies the whole `seq[Invocation]` per scan |
| `src/jmap_client/internal/types/envelope.nim:112` | `methodCalls*(r: Request)` | `seq[Invocation]` → `lent` | read by `detectMaxCalls`/`detectRequestLimitsTyped` (client.nim:293,315) |
| `src/jmap_client/internal/types/envelope.nim:108` | `` `using`*(r: Request) `` | `seq[string]` → `lent` | raw passthrough |
| `src/jmap_client/internal/protocol/builder.nim:181` | `callLimits*(br: BuiltRequest)` | `seq[CallLimitMeta]` → `lent` | raw passthrough; read in `validateLimits` (client.nim:331) |

### APPLY `lent` — template-generated forwarders (low impact, optional)
| file:line | accessor | returns |
|---|---|---|
| `src/jmap_client/internal/mail/mailbox_changes_response.nim:59,63,67` | `created*/updated*/destroyed*(r: T)` (in `forwardChangesFields`) | `seq[Id]` → `lent` (forwards `r.base.<field>`, a stable nested field path) |

### SKIP — computed accessors (lent would dangle; B10 list is wrong here)
| file:line | accessor | reason |
|---|---|---|
| `src/jmap_client/internal/types/session.nim:211` | `capabilities*(s: Session)` | synthesises core entry, builds `@[coreCap] + rawAdditional` in `result` |
| `src/jmap_client/internal/protocol/builder.nim:136` | `capabilities*(b: RequestBuilder)` | `b.capabilityUris.mapIt($it)` builds a fresh seq |
| `src/jmap_client/internal/mail/email_blueprint.nim:837` | `bodyValues*(bp: EmailBlueprint)` | walks the body tree into a fresh `Table` (derived-not-stored) |

### SKIP — sealed Pattern-A projection accessors (return COPIES by design, A8 §7; `lent` would defeat the defensive-copy contract)
`keyword.nim:67` `toHashSet(KeywordSet)`; `mailbox.nim:298` `toHashSet(MailboxIdSet)`, `:321` `toHashSet(NonEmptyMailboxIdSet)`, `:514` `toSeq(MailboxUpdateSet)`, `:554` `toTable(NonEmptyMailboxUpdates)`; `email.nim:727` `toTable(NonEmptyEmailImportMap)`; `email_submission.nim:306` `toSeq(NonEmptyIdSeq)`, `:237` `toTable(NonEmptyEmailSubmissionUpdates)`, `:615` `toTable(NonEmptyOnSuccessUpdateEmail)`, `:626` `toSeq(NonEmptyOnSuccessDestroyEmail)`; `email_update.nim:135` `toSeq(EmailUpdateSet)`, `:297` `toTable(NonEmptyEmailUpdates)`; `identity.nim:158` `toSeq`, `:198` `toTable`; `vacation.nim:115` `toSeq`; `submission_status.nim:533` `toTable(DeliveryStatusMap)`; `submission_param.nim:556` `toOrderedTable(SubmissionParams)`; `submission_atoms.nim:189` `toOrderedTable(SubmissionExtensionMap)`. Every one is documented "returns a copy of the underlying …".

### SKIP — private internal helpers (not accessors / not on a handle type)
`builder.nim:224` `withCapability`; `session.nim:441` `requiredVariables`; `serde_errors.nim:118` `setErrorKnownKeys`; `serde_helpers.nim:186` `reconcileNotFound`; `validation.nim:228`; `email_blueprint.nim:398/446/457/513/525/558/579/595/606/623/640/660`; `email_update.nim:197/210`; `submission_param.nim:569`; `submission_status.nim:375/405`.

### OUT OF STATED SCOPE (not a bare `Table`/`seq`/`HashSet`) — recommend deferring
- **Public-field read-models** (`Email`, `Mailbox`, `Identity`, `VacationResponse`, `EmailSubmission`): collections are **public fields** (`Email.mailboxIds*: Opt[MailboxIdSet]`, `Email.keywords*: Opt[KeywordSet]`, `Mailbox` is an all-public-field record). No accessor func exists ⇒ `lent` does not apply; direct field reads do not copy.
- **`Opt[seq]` / `Opt[Table]` accessors** (copy the inner container by value): `thread.nim:58` `PartialThread.emailIds`; `email_blueprint.nim:756-798` `fromAddr/to/cc/bcc/replyTo/messageId/inReplyTo/references`; `mail_errors.nim:21/61/74` `notFoundBlobIds/invalidRecipientAddresses/invalidEmailProperties`; `envelope.nim:116/167` `createdIds(Request/Response)`; `dispatch.nim:304` `DispatchedResponse.createdIds`.
- **Sealed-newtype-returning accessors** (object wrapping a container; copy includes the inner container): `email_blueprint.nim:744/748` `mailboxIds/keywords`; `account_capability_schemas.nim:119` `submissionExtensions`; `session.nim:578` `coreCapabilities` (object carries a `HashSet`).

### Caller inventory (read-only; none mutate the result) — grouped
- **src internal callers** (all iteration / index / pass-by-read — all `lent`-compatible): `serde_session.nim:41` `caps.collationAlgorithms()`, `:172` `m.emailQuerySortOptions()`, `:377` `acct.accountCapabilities()`, `:426` `for id, acct in s.accounts`, `:431` `for uri, id in s.primaryAccounts`; `capabilities.nim:376` `algorithm in c.collationAlgorithms()`; `session.nim:261,270` `account.accountCapabilities()`; `dispatch.nim:189,230` `for inv in resp.methodResponses`; `client.nim:293,315,331` `request.methodCalls` / `req.callLimits`; `email_blueprint.nim:535,564` `…extraHeaders.keys` (note: `part.extraHeaders` is the *BlueprintBodyPart* overload, separate from the `EmailBlueprint` accessor).
- **tests callers** (representative; all read-only): `tests/unit/tsession.nim:404` `s.accounts.len`; `tests/serde/tserde_session.nim:44` `s.accounts[parseAccountId("A13824").get()]`; `tests/mfixtures.nim:787-788` `a.accounts == b.accounts and a.primaryAccounts == b.primaryAccounts`; `tests/stress/tadversarial.nim:1370` `let parsedAccounts = r.accounts`; `tests/property/tprop_session.nim:242` `session.accounts.hasKey(acctId)`; `mlive.nim:606,622`, `tvacation_*_live.nim`, `tcaptured_*session.nim` `session.primaryAccounts.withValue(...)`; `compliance/trfc_8620.nim:1275-1291` `resp.methodResponses[i].rawName/arguments`; `serde/mail/tserde_mail_account_capabilities.nim:61` `"receivedAt" in mc.emailQuerySortOptions()`; `serde/tserde_capabilities.nim:376` `r.collationAlgorithms().contains(...)`; `stress/tadversarial_blueprint.nim:217` `runA.get().extraHeaders.len`; `serde/mail/tserde_thread.nim:42` `res.get().emailIds[0]`.
- Note: the many `args.accounts` / `args.primaryAccounts` / `args.capabilities` sites in `compliance/`, `stress/`, `tsession.nim`, `mfixtures.nim` are reads/writes of a **test-local helper struct field**, *not* the Session accessor — unaffected.

## Proposed cut

For each APPLY accessor: insert `lent ` before the container in the return type and refresh the docstring to state the borrow (B10 requires "ownership contracts documented for each"). Bodies are unchanged (`return x.rawField` and bare `x.rawField` both compile with `lent`). Concretely, e.g. session.nim:225-227:
```nim
func accounts*(s: Session): lent Table[AccountId, Account] =
  ## Accounts keyed by AccountId. Borrowed view (`lent`) — no per-call
  ## deep-copy; read-only, so the sealed value is preserved.
  s.rawAccounts
```
and identically for `parts`, `variables`, `primaryAccounts`, `accountCapabilities`, `collationAlgorithms`, `emailQuerySortOptions`, `emailIds`, `extraHeaders`, `methodResponses`, `methodCalls`, `` `using` ``, `callLimits`, and the three `forwardChangesFields` funcs.

**Serde adaptation:** none required. The only L2 reads (`serde_session.nim`, `serde_errors`) iterate (`for … in …`) or `pairs`/`contains` over the accessor; the `pairs`/`items`/`hasKey`/`==`/`len`/`[]` stdlib operations all take a **non-var** `Table`/`HashSet`/`seq` and so accept a `lent` borrow with zero copy.

**Caller adaptation:** none. Verified against std/tables (Nim 2.2.8): `[]`(316, returns `lent B`), `hasKey`(355), `contains`(373), `len`(489), `==`(584) all take `t: Table[A,B]` (non-var). The `withValue` used by callers resolves to the **read-only** overload (tables.nim:679/716, `t: Table[A,B]`, binds `let value {.cursor, inject.}`) — already today, because the current return is an rvalue temporary that cannot bind the `var Table` overload (604/638); behaviour is identical after `lent`. `let parsedAccounts = r.accounts` (tadversarial.nim:1370) materialises an owned copy on the `let` bind (same as today). No caller mutates the result (verified: no `[]=`/`incl`/`excl`/`del`/`add` on any accessor result).

**Principles served:** P12 (memory ownership encoded in the type — the `lent` makes "borrowed, not owned" visible in the signature, removing a deep-copy per call); secondarily P8/Pattern-A (the borrow cannot mutate the sealed handle).

## Hazards

1. **Computed accessors cannot be `lent`** (headline). `Session.capabilities`, `RequestBuilder.capabilities`, `EmailBlueprint.bodyValues` build a fresh local container; annotating `lent` is a compile error ("cannot borrow … it is not a path expression / location"). They MUST stay by-value. This directly contradicts B10's own bullet list for the two `capabilities*` — flag in the PR that the punch-list item is corrected, not fully executed.
2. **Borrow from a temporary receiver.** Chains like `runA.get().extraHeaders.len`, `res.get().emailIds[0]`, `session.coreCapabilities.collationAlgorithms.card` borrow off a temporary returned by `.get()`/`coreCapabilities`. Safe because the temporary lives to the end of the full expression and the borrow is consumed within it. The only way to make it dangle is `let x {.cursor.} = temp.accounts` or `addr` — no caller does this. Do not introduce `{.cursor.}` bindings of these results.
3. **`lent` is orthogonal to `{.push raises: [], noSideEffect.}` and `strictCaseObjects`** — no purity/variant interaction. The accessors are flat field reads; none touch a case-object discriminator.
4. **`BuiltRequest` uncopyability.** `callLimits*(br: BuiltRequest)` takes `br` by non-var value; objects pass by hidden reference, so no `=copy`/`=dup` (`{.error.}`) is triggered — it compiles today and remains fine. The `lent` borrow is consumed inside `validateLimits` before `send` sink-moves the `BuiltRequest`; no aliasing across the move.
5. **nim-results `.get()` copy semantics** are not in play — none of the APPLY accessors call `.get()`/`.value` on an uncopyable `T`; they return whole containers, and `.get()` appears only on the *caller* side (`res.get().emailIds`), where it copies the entity once regardless of `lent` (hazard 2 covers lifetime).
6. **nimalyzer.** `objects`/`complexity`/`params`/`hasDoc` are unaffected by a return-type qualifier; the `asSeq`/`head`/`[]` precedents already pass the same lint with `lent`. Keep the docstrings (hasDoc).
7. **`{.inline.}` is optional.** The `asSeq` precedent pairs `lent` with `{.inline.}`; the B10 accessors currently lack `{.inline.}`. Adding it is harmless and consistent but not required for correctness — recommend matching the precedent.
8. **`return` keyword with `lent`.** `return t.rawParts` compiles under `lent`; no need to rewrite to the bare-expression form, though the bare form matches the `asSeq` style.

## Audit/test impact

- **No snapshot/property/wire tests change.** `lent` is a pure non-behavioural optimisation — wire bytes, round-trips, and `==` semantics are identical. `tests/property/`, `tests/wire_contract/`, captured fixtures, and the A1b/A1c/A1d hub-surface compile tests are unaffected (the accessor *names and types* are unchanged; `lent T` and `T` are the same type to `declared()`/`compiles()`).
- **Add one positive compile test** (suggested `tests/compile/tcompile_b10_lent_accessors.nim`): exercise each `lent` accessor through the read patterns proven above — `.len`, `[]`, `hasKey`, `contains`, `in`, `==`, `for … in`, `.withValue(…): … do: …`, and `let copy = acc` (owned-copy materialisation) — so a future change that breaks borrow-compatibility fails CI. This is the mechanical gate B10 currently lacks (P2).
- **Optional reject test** (`treject_b10_*`): `session.accounts[k] = v` / `session.accounts.del(k)` must not compile. Caveat: this already fails today (the by-value rvalue cannot bind `var Table`), so it locks an existing invariant rather than a new one — include only if you want the explicit anchor.
- **Existing suites** (`tests/unit/tsession.nim`, `tests/serde/tserde_session.nim`, `tserde_capabilities.nim`, `tserde_mail_account_capabilities.nim`, `tserde_thread.nim`, `compliance/trfc_8620.nim`, `stress/tadversarial.nim`, `property/tprop_session.nim`, `mfixtures.nim`) compile unchanged; they double as the regression surface. `just test` is sufficient validation.

## Open questions

1. **Scope of "handle accessor" — include hub-internal wire types?** B10's cross-cutting rule says "any handle accessor whose return value is a container gets `lent`", and the design doc's "Pattern-A wire-data types" note extends P8 to `Request`/`Response`/`Invocation`. The biggest real-world win (the dispatch `methodResponses` scan) lives there. **Recommendation: include** `Response.methodResponses`, `Request.methodCalls`/`using`, `BuiltRequest.callLimits` (they are demoted off the hub but still deep-copy on every internal call). State this explicitly so a reviewer doesn't read the hub-demotion as "out of scope".
2. **Correct the B10 punch-list?** `Session.capabilities*` and `RequestBuilder.capabilities*` are computed and cannot be `lent`; B10 names them anyway. **Recommendation:** mark them "N/A — computed; lent infeasible" in the item body when closing B10, and note that `RequestBuilder.capabilities*` returns `seq[string]` not `seq[CapabilityUri]`. If a zero-copy `seq[CapabilityUri]` view is genuinely wanted, that is a *new* accessor (`capabilityUrisView*(b): lent seq[CapabilityUri]`) and thus new public surface — I recommend **not** adding it (P5 minimum surface; the computed `seq[string]` accessor already matches `Request.using`'s wire shape).
3. **Secondary tier (`Opt[seq]`/`Opt[Table]` and sealed-newtype accessors).** These also deep-copy a container per call but fall outside B10's literal `Table`/`seq`/`HashSet` scope, and `lent Opt[seq[T]]` / `lent KeywordSet` is a heavier ergonomic change (every caller's `for x in acc:` consumption already borrows the Opt). **Recommendation: defer** them to a follow-up and keep B10 to bare containers, matching the item's own wording.

================================================================================
## SOURCE agent-a8f4db16a1a52c8de.jsonl — # A8b — Full-seal `Credential` and `SessionEndpoint` (private `rawScheme`/`rawKi
================================================================================

I have everything I need. Here is the change-map.

---

# A8b — Full-seal `Credential` and `SessionEndpoint` (private `rawScheme`/`rawKind` + read accessor)

**Verdict: full-seal both types, mirroring `SubmissionParam`.** It is feasible, strictly better, and makes `T(scheme:…)` / `T(kind:…)` impossible outside the defining module. The Rule-3 justification for a public discriminator (cited in the TODO) does **not** apply here: it applies to `SetError`, whose *payload arms are public* and which external consumers read via `case se.errorType of setX: se.variantField`. `Credential` and `SessionEndpoint` already have **private payload arms**, so no external variant-field read exists to support — the public discriminator buys nothing and only leaks discriminator-only partial construction.

## Current state

### `src/jmap_client/internal/types/credential.nim`
Discriminator is **public** (`scheme*`), payload arms private:
```nim
27	type Credential* {.ruleOff: "objects".} = object
30	  case scheme*: AuthScheme
31	  of asBearer:
32	    bearerTok: string
33	  of asBasic:
34	    basicUser, basicPass: string
```
Producers (internal): `113  ok(Credential(scheme: asBearer, bearerTok: token))`, `124  ok(Credential(scheme: asBasic, basicUser: username, basicPass: password))`.
Internal discriminator reads: `==` at `129 case a.scheme`, `131 case b.scheme`, `137 case b.scheme`; `$` at `146 case c.scheme`, `148/150 $c.scheme`; `authorizationHeaderValue` at `156 case c.scheme`, `158/160 $c.scheme` (and docstring `154 ## …$c.scheme…`). `AuthScheme` enum at 21-25 is unchanged.

### `src/jmap_client/internal/types/session_endpoint.nim`
Discriminator **public** (`kind*`), payload arms private:
```nim
27	type SessionEndpoint* {.ruleOff: "objects".} = object
31	  case kind*: SessionEndpointKind
32	  of sekDirectUrl:
33	    directUrl: string
34	  of sekDiscoveryDomain:
35	    domain: string
```
Producers (internal): `72  ok(SessionEndpoint(kind: sekDirectUrl, directUrl: url))`, `84  ok(SessionEndpoint(kind: sekDiscoveryDomain, domain: domain))`.
Internal discriminator reads: `==` at `88/91/93/95/97/99`; `$` at `104/105/107`; `asDirectUrl` at `114 case e.kind`; `asDiscoveryDomain` at `124 case e.kind`.

### The seal precedent — `src/jmap_client/internal/mail/submission_param.nim`
```nim
196	  case rawKind: SubmissionParamKind          # PRIVATE discriminator
...
231	func kind*(p: SubmissionParam): SubmissionParamKind =   # public accessor
233	  p.rawKind
```
Internal `==`/`paramKey`/constructors all read `p.rawKind`; external consumers branch on `p.kind` (accessor) and read payload only through `asX` Opt-accessors. H1b/A8 audit accept it via `treject_submissionparam_notify_construction.nim`.

## All sites

### src — discriminator construction/read (all internal to the two modules, except resolveEndpoint)
- `src/jmap_client/internal/types/credential.nim:113` — construct `Credential(scheme: asBearer, …)`
- `src/jmap_client/internal/types/credential.nim:124` — construct `Credential(scheme: asBasic, …)`
- `src/jmap_client/internal/types/credential.nim:129,131,137` — `==` reads `a.scheme`/`b.scheme`
- `src/jmap_client/internal/types/credential.nim:146,148,150` — `$` reads `c.scheme`
- `src/jmap_client/internal/types/credential.nim:154,156,158,160` — `authorizationHeaderValue` reads `c.scheme` (154 is docstring)
- `src/jmap_client/internal/types/session_endpoint.nim:72,84` — construct `SessionEndpoint(kind: …)`
- `src/jmap_client/internal/types/session_endpoint.nim:88,91,93,95,97,99` — `==`
- `src/jmap_client/internal/types/session_endpoint.nim:104,105,107` — `$`
- `src/jmap_client/internal/types/session_endpoint.nim:114,124` — `asDirectUrl`/`asDiscoveryDomain`
- `src/jmap_client/internal/client.nim:357` — `case client.endpoint.kind of sekDirectUrl/sekDiscoveryDomain:` — **reads discriminator only, then routes through `asDirectUrl`/`asDiscoveryDomain` Opt-accessors (NOT a variant field).** This is the sole cross-module discriminator read for either type. **No change required.**
- `src/jmap_client/internal/client.nim:342` — `client.credential.authorizationHeaderValue` — does not touch `.scheme`. No change.
- Hub filters: `src/jmap_client/internal/types.nim:53` (`export credential except authorizationHeaderValue`), `:54` (`export session_endpoint except asDirectUrl, asDiscoveryDomain`). **No change** — accessors `scheme`/`kind` are re-exported by default like `SubmissionParam.kind`.

### tests — discriminator reads (all via what will become the accessor; behaviourally unchanged)
- `tests/unit/tcredential.nim:23` — `doAssert c.scheme == asBearer`
- `tests/unit/tcredential.nim:46` — `doAssert c.scheme == asBasic`
- `tests/unit/tsession_endpoint.nim:18,22,27,52,56` — `e.kind == sek…`
- `tests/compile/tcompile_a20a21_hub_surface.nim:32` — `compiles(bearerCredential("t").get().scheme)`
- `tests/compile/tcompile_a20a21_hub_surface.nim:33` — `compiles(directEndpoint("https://x").get().kind)`
- `tests/integration/live/mlive.nim:1581` — `credential.authorizationHeaderValue` (no `.scheme`); imports the leaf `credential` at `:41`. No change.

### tests — raw construction (the A8b targets; these are the audits that change)
- `tests/compile/treject_a21_sealed_credential_construction.nim:17` — `discard Credential(scheme: asBearer, bearerTok: "x")`
- `tests/compile/treject_a20_sealed_endpoint_construction.nim:17` — `discard SessionEndpoint(kind: sekDirectUrl, directUrl: "x")`

### tests — smart-constructor callers (unaffected; listed for completeness)
- `tests/unit/tclient.nim:47-48,62-63,78-79,94-95,99,110-111,123-124,136-137,550-551`; `tests/mtransport.nim:120-121`; `tests/unit/tdebug_callback.nim:45-46`; `tests/integration/live/mconfig.nim:60,62,64`; `tests/compile/treject_a7c_send_consumes_builtrequest.nim:20` — all use `bearerCredential`/`basicCredential`/`directEndpoint`/`discoveryEndpoint`. No change.

## Proposed cut

### `credential.nim`
1. Rename discriminator → private: line 30 `case scheme*: AuthScheme` → `case rawScheme: AuthScheme`.
2. Add accessor immediately after the type (mirror `SubmissionParam.kind`):
```nim
func scheme*(c: Credential): AuthScheme =
  ## The authentication scheme. The discriminator is a module-private
  ## ``rawScheme`` field surfaced read-only here, so ``Credential(scheme: …)``
  ## cannot be raw-constructed outside this module (A8b); the only producers
  ## are ``bearerCredential`` / ``basicCredential``.
  c.rawScheme
```
3. Producers: `113` → `Credential(rawScheme: asBearer, bearerTok: token)`; `124` → `Credential(rawScheme: asBasic, …)`.
4. Internal discriminator reads → `rawScheme`: `==` (129/131/137), `$` (146; `$c.scheme`→`$c.rawScheme` at 148/150), `authorizationHeaderValue` (156; `$c.scheme`→`$c.rawScheme` at 158/160). **All variant-field reads (`c.bearerTok`, `c.basicUser/basicPass`) live inside `case c.rawScheme of …:` branches — strict traces the private field directly.**
5. Docstring uplift: module header (4-9), type docstring (28-29), `authorizationHeaderValue` docstring (154) — replace "the scheme is the discriminator" framing with "private `rawScheme` discriminator surfaced read-only via `scheme`; `Credential(scheme:…)` no longer compiles externally".

### `session_endpoint.nim`
1. Line 31 `case kind*: SessionEndpointKind` → `case rawKind: SessionEndpointKind`.
2. Add accessor after the type:
```nim
func kind*(e: SessionEndpoint): SessionEndpointKind =
  ## How the session resource is located. The discriminator is a module-
  ## private ``rawKind`` field surfaced read-only here, so
  ## ``SessionEndpoint(kind: …)`` cannot be raw-constructed outside this
  ## module (A8b); the only producers are ``directEndpoint`` /
  ## ``discoveryEndpoint``.
  e.rawKind
```
3. Producers: `72`→`SessionEndpoint(rawKind: sekDirectUrl, directUrl: url)`; `84`→`SessionEndpoint(rawKind: sekDiscoveryDomain, domain: domain)`.
4. Internal reads → `rawKind`: `==` (88/91/93/95/97/99), `$` (104/105/107), `asDirectUrl` (114), `asDiscoveryDomain` (124).
5. Docstring uplift: module header (4-8), type docstring (27-30).

### Serde adaptation
**None.** Neither type has a `toJson`/`fromJson` (auth is client→server header material; the endpoint is construction-time intent resolved at L4). The accessor name `scheme`/`kind` is chosen to equal the old field name, so every existing read site (`c.scheme`, `e.kind`) compiles **verbatim** through the accessor.

### Caller adaptation
- `client.nim:357 resolveEndpoint` — **unchanged**: `case client.endpoint.kind` now calls the accessor; the branch bodies read `asDirectUrl`/`asDiscoveryDomain`, not variant fields, so no Rule-3 obligation arises.
- All unit/compile read sites (tcredential:23,46; tsession_endpoint:18,22,27,52,56; tcompile_a20a21:32,33) — **unchanged**, accessor preserves syntax.

### Principles served
- **P15** (raw constructors private): closes the last raw-construction channel — discriminator-only `T(kind:k)` now fails.
- **P16** (make illegal states unrepresentable): an empty-payload `Credential`/`SessionEndpoint` becomes structurally unrepresentable, not merely inert-until-connect.
- **P19** (one read surface): one accessor, no public field; matches `SubmissionParam`/`MailboxRole`/`CollationAlgorithm` seal convention.

## Hazards

- **strictCaseObjects Rule 3 (the central hazard).** After the discriminator becomes a `func`, any `case x.kind of …: x.variantField` would be **rejected** (strict cannot trace variant access through a func body). This is why **every internal `case c.scheme`/`case e.kind` that reads a payload arm MUST switch to `case c.rawScheme`/`case e.rawKind`** (the private field). Enumerated above. The external `case client.endpoint.kind` in `resolveEndpoint` is safe *only because* its branches use Opt-accessors, never `client.endpoint.directUrl`. Do not "tidy" it into a raw field read.
- **`$c.scheme` inside arm bodies (158/160).** These sit inside `case c.rawScheme of asBearer:` and also read `c.bearerTok` (a variant field) — so the enclosing case **must** be `rawScheme`. Render the discriminator as `$c.rawScheme` for consistency (calling the `scheme` accessor there also compiles but is a redundant indirection).
- **Construction literal-discriminator rule.** `Credential(rawScheme: asBearer, …)` keeps the literal `asBearer`/`asBasic` per branch (functional-core pattern 4) — unchanged shape, just renamed key.
- **nimalyzer `hasDoc`.** The new `scheme`/`kind` accessors are public funcs → must carry a docstring (shown above), else CI `just analyse` fails.
- **nimalyzer `objects` / `complexity`.** `{.ruleOff: "objects".}` already on both types; the accessor adds no branching, so `complexity` is unaffected. Do not add new `ruleOff`s.
- **styleCheck / overload.** `scheme`/`kind` are camelCase (OK). `kind` overloads the existing `SubmissionParam.kind`/`Referencable.kind`/etc.; UFCS resolves by receiver type — no ambiguity, no collision with any free `scheme` symbol (grep: none).
- **Purity / ARC / lent.** Accessors return an enum (trivially copyable value) — no `lent`, no move, no uncopyable-`T` `.get()` concern. They satisfy `{.push raises: [], noSideEffect.}` trivially.
- **H1b lint (`tests/lint/h1b_fallible_ctor_public_arm.nim`).** It flags *public payload arms* on fallible-ctor case objects; the discriminator line is explicitly excluded (`hasUnsafePublicArm`). Both types already pass at 0 violations (arms private) and continue to pass — **no H1b interaction.**

## Audit/test impact

**Must change (the two existing reject audits — repurpose to assert the discriminator itself is now sealed, the exact A8b win):**
- `tests/compile/treject_a21_sealed_credential_construction.nim` — line 17 → `discard Credential(rawScheme: asBearer)`; header `errormsg:` → `"the field 'rawScheme' is not accessible."`; uplift docstring ("the scheme discriminator is now module-private…").
- `tests/compile/treject_a20_sealed_endpoint_construction.nim` — line 17 → `discard SessionEndpoint(rawKind: sekDirectUrl)`; header `errormsg:` → `"the field 'rawKind' is not accessible."`; uplift docstring. (Keeping the discriminator-only form is the strongest assertion: if even `rawKind`/`rawScheme` is inaccessible, every raw-construction path is closed. Rationale: testament reject files stop at the first error, and the discriminator key is now evaluated first — asserting on it proves the A8b residue is gone.)

**Must change (surface audit):**
- `tests/compile/tcompile_a20a21_hub_surface.nim` — lines 32-33 keep compiling unchanged, but the comment at **line 31** ("The discriminators are public fields (strict-objects Rule 3).") is now false → uplift to: "The discriminators are exposed read-only via the `scheme` / `kind` accessors; the underlying `rawScheme` / `rawKind` fields are sealed (A8b)." Recommend **adding** two positive seal assertions here so the seal is verified in both the hub-surface file and the reject files:
  ```nim
  doAssert not compiles(Credential(rawScheme: asBearer))
  doAssert not compiles(SessionEndpoint(rawKind: sekDirectUrl))
  ```

**No change required:** `tests/unit/tcredential.nim`, `tests/unit/tsession_endpoint.nim` (reads go through the same-named accessor); `tests/unit/tclient.nim`, `tests/mtransport.nim`, `tests/unit/tdebug_callback.nim`, `tests/integration/live/*` (smart-constructor callers). **No property tests** reference these types; **no snapshot/fixture impact** (no wire-format change).

**Doc uplift (clean-refactor requirement):**
- `docs/TODO/pre-1.0-api-alignment.md`: mark **A8b** (2182-2201) ✅ DONE and rewrite to describe the seal; delete/adjust the **Residue** paragraph (2176-2180) — there is no longer a public-discriminator residue class; update the A8 inventory (848-852) `SessionEndpoint … exposes kind*` → "exposes a `kind` accessor (private `rawKind`)" and `Credential … exposes scheme*` → "exposes a `scheme` accessor (private `rawScheme`)"; update the **A20** snippet (1398-1402: `case kind*` → `case rawKind` + accessor) and **A21** snippet (1432-1435: `case scheme*` → `case rawScheme` + accessor).
- `docs/design/01-layer-1-design.md`: audit the per-module symbol inventory for `credential`/`session_endpoint`; if it lists `scheme*`/`kind*` as public fields, change to accessor funcs. (The §2548 "Public discriminator decision" text is about `SetError` and stays — it is the genuine Rule-3 case and the contrast that explains why Credential/SessionEndpoint can seal but SetError cannot.)

## Open questions

1. **Reject-file form: discriminator-only vs full-payload.** Recommend the discriminator-only form (`Credential(rawScheme: asBearer)` / `SessionEndpoint(rawKind: sekDirectUrl)`) because it asserts exactly what A8b closes. No human decision needed unless you want a second reject file per type also asserting `bearerTok`/`directUrl` inaccessibility — I judge that redundant (the seal on the discriminator already blocks every path).
2. **Accessor naming.** Recommend `scheme` for `Credential` (matches the domain term and every existing read site) and `kind` for `SessionEndpoint` (matches its discriminator name and the `SubmissionParam` precedent). This keeps all read call sites byte-identical. The alternative (`kind` for both, for cross-type uniformity) would needlessly churn `c.scheme` sites and read worse ("scheme" is the RFC term). No blocker.
3. The TODO's stated recommendation for A8b was option (b) *boundary-reject for Credential only*. **Full-seal supersedes both options for both types** — it is strictly stronger than (a) accept-inert and cheaper than (b) (no `ValidationError` plumbing at `initJmapClient`/`resolveEndpoint`, no new error variant), and it unifies these two with the already-sealed `SubmissionParam`. I recommend proceeding with full-seal and noting in the A8b write-up that (b) is rendered unnecessary because the empty-payload state is now unconstructable rather than rejected-on-use.

================================================================================
## SOURCE agent-a99297f6326dac2b6.jsonl — # B2 (P18): Sort-direction unification — change-map
================================================================================

I now have a complete picture. Here is the exhaustive change-map.

---

# B2 (P18): Sort-direction unification — change-map

## Current state

Three comparator types encode sort direction three different ways, and their serde diverges on the wire-emission rule.

**1. `Comparator` — `src/jmap_client/internal/types/framework.nim:59-81`** (L1 hub type)
```nim
type Comparator* {.ruleOff: "objects".} = object
  rawProperty: PropertyName ## module-private; validated PropertyName
  isAscending*: bool ## true = ascending (RFC default)          # line 67
  collation*: Opt[CollationAlgorithm] ## RFC 4790 collation algorithm identifier

func parseComparator*(
    property: PropertyName,
    isAscending: bool = true,                                    # line 76
    collation: Opt[CollationAlgorithm] = Opt.none(CollationAlgorithm),
): Comparator =
  return
    Comparator(rawProperty: property, isAscending: isAscending, collation: collation)  # line 81
```

**2. `EmailComparator` — `src/jmap_client/internal/mail/email.nim:64-102`** (L1 mail, case object)
```nim
type EmailComparator* {.ruleOff: "objects".} = object
  isAscending*: Opt[bool] ## Absent = server default (RFC: true).   # line 68
  collation*: Opt[CollationAlgorithm]
  case kind*: EmailComparatorKind
  of eckPlain:
    property*: PlainSortProperty
  of eckKeyword:
    keywordProperty*: KeywordSortProperty
    keyword*: Keyword
# plainComparator (isAscending param :79, construct :85)
# keywordComparator (isAscending param :91, construct :100)
```

**3. `EmailSubmissionComparator` — `src/jmap_client/internal/mail/email_submission.nim:366-405`** (L1 mail)
```nim
type EmailSubmissionComparator* {.ruleOff: "objects".} = object
  property*: EmailSubmissionSortProperty
  rawProperty*: string
  isAscending*: bool                                             # line 375
  collation*: Opt[CollationAlgorithm]
# parseEmailSubmissionComparator (isAscending param :380, construct :402)
```

**Serde — current wire-emission rules** (the heart of the inconsistency):

- `Comparator.toJson` — **always emits** `isAscending` (`serde_framework.nim:58`: `%*{"property": $c.property, "isAscending": c.isAscending}`).
- `Comparator.fromJson` — `serde_framework.nim:71-91`: strict — absent → `true` (`getBool(true)`); present-and-`JBool` → value; present-and-non-`JBool` → `err(svkWrongKind)` at `/isAscending`. Constructs at `:91`.
- `EmailComparator.toJson` — **omits when `Opt.none`** (`serde_email.nim:892-893`: `for v in c.isAscending: node["isAscending"] = %v`).
- `emailComparatorFromJson` — `serde_email.nim:842-847`: lenient via `optJsonField(node,"isAscending",JBool)` (absent/null/wrong-kind → `Opt.none`); constructs at `:866`/`:871`.
- `EmailSubmissionComparator.toJson` — **always emits** (`serde_email_submission.nim:341`: `node["isAscending"] = %c.isAscending`); docstring at `:337` says "always explicit for debuggability". **No `fromJson`** (toJson-only; server never echoes sort clauses).

RFC 8620 §5.5 (`docs/rfcs/...8620...:2419`): `isAscending: "Boolean" (optional; default: true)`. Absent ≡ ascending. So omitting `isAscending: true` is semantically identical to emitting it.

## All sites

### src/ — type/constructor definitions
- `src/jmap_client/internal/types/framework.nim:67` — `Comparator.isAscending: bool` field
- `src/jmap_client/internal/types/framework.nim:76,81` — `parseComparator` param + construct
- `src/jmap_client/internal/mail/email.nim:68` — `EmailComparator.isAscending: Opt[bool]` field
- `src/jmap_client/internal/mail/email.nim:79,85` — `plainComparator` param + construct
- `src/jmap_client/internal/mail/email.nim:91,100` — `keywordComparator` param + construct
- `src/jmap_client/internal/mail/email_submission.nim:367` (docstring), `:375` field, `:380` param, `:402` construct

### src/ — serde (the rule changes here)
- `src/jmap_client/internal/serialisation/serde_framework.nim:58` — `Comparator.toJson` emit
- `src/jmap_client/internal/serialisation/serde_framework.nim:71-91` — `Comparator.fromJson` read+construct
- `src/jmap_client/internal/mail/serde_email.nim:842-847` — `emailComparatorFromJson` read
- `src/jmap_client/internal/mail/serde_email.nim:866,871` — construct (keyword/plain)
- `src/jmap_client/internal/mail/serde_email.nim:884,892-893` — `EmailComparator.toJson` docstring + emit
- `src/jmap_client/internal/mail/serde_email_submission.nim:337,341` — `EmailSubmissionComparator.toJson` docstring + emit

### src/ — type-level only (sort params; carry the comparator type, never read `.isAscending`; **unaffected by field rename**)
- `src/jmap_client/internal/mail/mail_builders.nim:92,118,124,277,299,487,509` (`sort: …[Comparator]/[EmailComparator]`)
- `src/jmap_client/internal/mail/submission_builders.nim:84,89,102,109`
- `src/jmap_client/internal/protocol/builder.nim:599,605` (`addQuery[T,…,Comparator]`)
- `src/jmap_client/internal/protocol/methods.nim:364-374` (`serializeOptSort` — generic `c.toJson()`, no field touch)
- `src/jmap_client/convenience.nim` (per-entity query wrappers — type aliases only)

### tests/ — construction (pass `isAscending`, must become `direction`)
- `tests/mfixtures.nim:458` (param), `:460` (call), `:464` (param), `:467` (call)
- `tests/mfixtures.nim:1016` — `emailComparatorEq` reads `a.isAscending`/`b.isAscending`
- `tests/mproperty.nim:861,867` — `genComparator` (`asc: bool`)
- `tests/mproperty.nim:1862-1869,1878,1882` — `genEmailComparator` (`Opt[bool]`)
- `tests/compliance/trfc_8620.nim:786,791,792,839,847,850`
- `tests/unit/tframework.nim:67,78,79`
- `tests/unit/ttypes.nim:59`
- `tests/property/tprop_framework.nim:73`
- `tests/property/tprop_serde.nim:61`
- `tests/serde/tserde_properties.nim:90`
- `tests/serde/tserde_framework.nim:39,46,51,53,102-103,183,190,193,197,201-202,217,348-354,397,417,423`
- `tests/serde/mail/tserde_email.nim:404,410,412,416-417,423,463,465`
- `tests/serde/mail/tserde_email_adversarial.nim:136`
- `tests/serde/mail/tserde_email_submission.nim:257,259,265(doc),274`
- `tests/serde/tserde_adversarial.nim:837`
- `tests/protocol/tmethods.nim:927,934`
- `tests/protocol/tmail_builders.nim:365,376`
- `tests/integration/live/temail_query_advanced_sort_live.nim:140,164,211` (+ comment block 14-25)
- `tests/integration/live/temail_query_sort_live.nim:76,108,142` (+ comment block 7-21)
- `tests/integration/live/temail_submission_filter_completeness_live.nim:213,232`
- `tests/integration/live/temail_submission_filter_sort_live.nim:217`
- `tests/integration/live/tmailbox_query_filter_sort_live.nim:107,153`

### tests/ — compile-surface (assert type/proc existence; no `isAscending`, but should add `SortDirection`)
- `tests/compile/tcompile_a1_public_surface.nim:39` (`declared(Comparator)`)
- `tests/compile/tcompile_mail_g_public_surface.nim:73,95` (`EmailSubmissionComparator`, `parseEmailSubmissionComparator`)
- `tests/compile/tcompile_a1d_mail_hub_surface.nim:243-244` (`emailComparatorFromJson` hub-invisible)

### tests/ — captured fixtures (fromJson **inputs**, not pinned outputs)
- `tests/testdata/captured/email-query-advanced-sort-cyrus.json:13`, `mailbox-query-filter-sort-cyrus.json:12`, `email-query-advanced-sort-stalwart.json` — `isAscending` appears inside captured request/response bodies. `tests/serde/captured/tcaptured_email_query_advanced_sort.nim` parses a `Response` and only asserts ids; **no toJson byte-comparison**, so the emit-rule change does not break replay. Low risk; verify no other captured test round-trips a sort clause back through `toJson`.

## Proposed cut

### New type — `src/jmap_client/internal/types/framework.nim` (next to `Comparator`)
```nim
type SortDirection* = enum
  ## Sort direction for a /query Comparator (RFC 8620 §5.5). Three states
  ## map to the wire's three observable states for the optional
  ## ``isAscending`` key: ``sdServerDefault`` omits the key (server applies
  ## its RFC default, ascending); ``sdAscending`` emits ``true``;
  ## ``sdDescending`` emits ``false``. ``sdServerDefault`` MUST stay first
  ## (ordinal 0) so zero-initialisation yields the RFC default.
  sdServerDefault
  sdAscending
  sdDescending
```
Lives in **`framework.nim`** because (a) `Comparator` already lives there, (b) both `email.nim` and `email_submission.nim` already `import ../types/framework`, (c) the hub already blanket-re-exports framework (`internal/types.nim:46 export framework`), so `SortDirection` + the three values reach `import jmap_client` automatically — no `internal/types.nim` edit needed.

### New field shape (rename `isAscending` → `direction`; the `is*` name is a lie on a 3-valued enum)
- `Comparator.isAscending*: bool` → `direction*: SortDirection`
- `EmailComparator.isAscending*: Opt[bool]` → `direction*: SortDirection` (shared field, before the `case`)
- `EmailSubmissionComparator.isAscending*: bool` → `direction*: SortDirection`
- All three constructors: param `isAscending: … = …` → `direction: SortDirection = sdServerDefault`.

### Wire mapping — two L2 helpers in `src/jmap_client/internal/serialisation/serde_helpers.nim`
`serde_helpers.nim` already `import ../types` (sees `SortDirection`) and is already imported by all three serde files (`serde_framework`, `serde_email`, `serde_email_submission`); it is L2/hub-invisible (A1c), so the mapping stays off the public surface while remaining DRY (functional-core "translation at the boundary"):
```nim
func emitSortDirection*(node: var JsonNode, dir: SortDirection) =
  ## Map SortDirection onto the optional RFC 8620 §5.5 ``isAscending`` key.
  case dir
  of sdServerDefault: discard
  of sdAscending: node["isAscending"] = %true
  of sdDescending: node["isAscending"] = %false

func sortDirectionFromWire*(ascending: Opt[bool]): SortDirection =
  ## Inverse: absent → server default; true → ascending; false → descending.
  ## Strictness of the JBool extraction stays at the call site.
  case ascending.isSome
  of false: sdServerDefault
  of true:
    if ascending.unsafeGet: sdAscending else: sdDescending
```
(`case ascending.isSome of true: ascending.unsafeGet` is strict-safe + panic-free per nim-type-safety; `for v in ascending:`/`valueOr:` is the alternative.)

### Serde adaptation per site (uniform emit rule)
- `serde_framework.nim` `Comparator.toJson`: drop the literal `"isAscending"` from the `%*{…}` object; after building `{"property": …}`, call `emitSortDirection(node, c.direction)`.
- `serde_framework.nim` `Comparator.fromJson`: keep the existing strict `JBool` wrong-kind check (lines 72-80, preserves `svkWrongKind` at `/isAscending`); replace `let isAscending = ascNode.getBool(true)` + the `parseComparator(property, isAscending, …)` with: extract `Opt[bool]` (none when `ascNode.isNil`, else `Opt.some(ascNode.getBool(...))`), `let direction = sortDirectionFromWire(asc)`, `parseComparator(property, direction, collation)`.
- `serde_email.nim` `emailComparatorFromJson`: the `block` at `:842-847` already yields `Opt[bool]` via the lenient `optJsonField`; change its result to `sortDirectionFromWire(thatOpt)` and pass `direction` to `keywordComparator`/`plainComparator`.
- `serde_email.nim` `EmailComparator.toJson:892-893`: replace `for v in c.isAscending: node["isAscending"] = %v` with `emitSortDirection(node, c.direction)`.
- `serde_email_submission.nim` `EmailSubmissionComparator.toJson:341`: replace `node["isAscending"] = %c.isAscending` with `emitSortDirection(node, c.direction)`; update docstring at `:337` (drop "always explicit for debuggability").

### Caller adaptation (test churn — accommodated, not protected)
- Boolean literals: `isAscending = true` → `direction = sdAscending`; `isAscending = false` → `direction = sdDescending`; positional `, true,` → `, sdAscending,`; `, false,` → `, sdDescending,`.
- `Opt[bool]` (EmailComparator): `Opt.some(true)` → `sdAscending`; `Opt.some(false)` → `sdDescending`; `Opt.none(bool)` → `sdServerDefault`.
- Field reads: `c.isAscending` (bool) → compare against `sdAscending`/`sdDescending`; `res.get().isAscending` (`Opt[bool]`, e.g. `tserde_email.nim:465 assertSomeEq …, false`) → `assertEq res.get().direction, sdDescending`.
- `mfixtures.nim` `makeComparator`/`makeComparatorWithCollation`: default `direction = sdAscending` (so the `comparatorToJsonFieldNames` test that asserts the `isAscending` key is *present* keeps a meaningful subject); `emailComparatorEq:1016` reads `a.direction != b.direction`.
- Generators: `mproperty.nim:genComparator` pick `rng.oneOf([sdServerDefault, sdAscending, sdDescending])`; `genEmailComparator` likewise (replaces the 3-way `Opt[bool]`).

**Principles served:** P18 (sum type over Bool/Opt[bool] soup; the inconsistency *between* the three sites is itself the smell B2 names); "booleans are a code smell"; "one source of truth per fact" (one direction type, one wire-mapping function); "make illegal states unrepresentable" (the enum's three states are exactly the wire's three states — no `Opt[bool]` redundant encoding where `none` and a hypothetical fourth state could disagree).

## Hazards

- **Wire-shape change (intended).** `Comparator` and `EmailSubmissionComparator` previously *always* emitted `isAscending: true`; with default `sdServerDefault` they now *omit* it. Semantically identical per RFC 8620 §5.5 (absent ≡ true), but byte-different. Breaks: `tserde_email_submission.nim:259,274` (`assertLen node, 2` + `assertJsonFieldEq node,"isAscending",%true`) and `tserde_framework.nim:102-103` (`j{"isAscending"} != nil`). Fix per the caller-adaptation rule (the submission tests with no explicit direction must expect `assertJsonKeyAbsent node,"isAscending"` + `assertLen node,1`).
- **L1 purity** (`framework.nim` is `{.push raises: [], noSideEffect.}`): `SortDirection` is a plain enum, no routine added there. The two helpers go in L2 `serde_helpers.nim` (also `noSideEffect`); `emitSortDirection` mutates a local `var JsonNode` parameter only — not observable, pure.
- **strictCaseObjects**: `EmailComparator` is a case object, but `direction` is a *shared* field (declared before `case kind`), readable in every arm — same as `isAscending` was. No variant-access obligation. Every new `case dir:`/`case ascending.isSome:` is exhaustive with no `else` (enum-exhaustiveness rule).
- **`HoleEnumConv`/`EnumConv`**: `SortDirection` is contiguous (ordinals 0,1,2), no holes — safe.
- **`$` trap**: `SortDirection` has no string backing, so `$sdAscending == "sdAscending"`. Never stringify it to the wire — serde must route through `emitSortDirection`, never `$direction`. (No current serde does `$isAscending`, so no accidental carry-over.)
- **`default()` correctness**: `sdServerDefault` must be ordinal 0 (matches the `BodyValueScope.bvsNone` / `QueryParams` zero-init convention) so `default(Comparator).direction` is the RFC default.
- **`.unsafeGet` under `--panics:on`**: only used inside `case ascending.isSome of true:` (proven Some), strict-safe and panic-free.
- **nimalyzer**: no new `object` (enum needs no `ruleOff:"objects"`); helper bodies are trivial `case` — no `complexity`/`params` trigger. `emitSortDirection`'s `node` is consumed (the `params` rule wants the param used — it is).
- **ARC/lent**: `SortDirection` is a trivially-copyable value enum; no move/`lent` concerns; comparator equality (`mfixtures.emailComparatorEq`) compares enums by value.
- **No L5/FFI impact**: no comparator field is exported through `src/jmap_client.nim` C ABI.

## Audit / test impact

- **Update (rename + value mapping)**: every tests/ site in the "All sites → tests/ construction" list above (~25 files). Mechanical: `isAscending = true/false` → `direction = sdAscending/sdDescending`, `Opt.some/none` → enum values, field reads → enum compares.
- **Update (wire-rule assertions)**: `tserde_email_submission.nim:257-262,272-277` (default now omits `isAscending`); `tserde_framework.nim:96-104` (`comparatorToJsonFieldNames` — keep meaningful only if `makeComparator` defaults to `sdAscending`); `tserde_framework.nim:187-190` (`comparatorDeserMissingIsAscending` "must default to true" → assert `direction == sdServerDefault`); `tserde_email.nim:409-413` (already expects omit; still passes for `sdServerDefault`).
- **Preserve (adversarial/strict)**: `tserde_framework.nim:200-202` (`comparatorDeserIsAscendingWrongKind`) — must still `err` at `/isAscending`; keep the strict `JBool` check in `Comparator.fromJson`. `tserde_email_adversarial.nim:136` unaffected (missing-property path).
- **Property round-trips**: `tprop_serde.nim:61`, `tserde_properties.nim:90`, `tserde_framework.nim:397` change `v.isAscending == c.isAscending` → `v.direction == c.direction`. Round-trip is now lossless and idempotent (`sdServerDefault`↔absent, `sdAscending`↔true, `sdDescending`↔false), strengthening these tests.
- **Add (recommended)**: a `tcompile_*` assertion that `SortDirection`, `sdServerDefault`, `sdAscending`, `sdDescending` are `declared` via `import jmap_client` (extend `tcompile_a1_public_surface.nim` near `:39`); a `treject_*` is **not** needed (the enum carries no construction invariant to seal).
- **Docs uplift**: flip `docs/TODO/pre-1.0-api-alignment.md:2218` B2 to `✅ DONE` and adjust the dashboard counts (`:71-72` DONE 50→51, TODO 58→57). The "Documented exceptions" section needs no entry (B2 is a fix, not an exception). Update the three type docstrings (`framework.nim:67`, `email.nim:68`, `email_submission.nim:337`).

## Open questions

1. **Default constructor argument — `sdServerDefault` vs `sdAscending`.** I recommend **`sdServerDefault`** (matches enum ordinal 0, matches `EmailComparator`'s existing omit-default, makes round-trip idempotent, and is the only choice that doesn't defeat the three-state enum's purpose). The cost is the intended wire change for `Comparator`/`EmailSubmissionComparator` (omit instead of emit `true`), which is RFC-equivalent. The only reason to instead pick `sdAscending` would be to preserve byte-identical wire for those two — but that re-introduces the inconsistency B2 exists to remove. **Recommendation: `sdServerDefault`.**
2. **Field name — `direction` vs keep `isAscending`.** Recommend **`direction`**: an `is*`-prefixed name asserting a boolean is misleading on a 3-valued enum, and the rename is the forcing function that surfaces every caller. (Accepts ~25 files of mechanical churn.) **Recommendation: rename to `direction`.**
3. **Helper location — `serde_helpers.nim` (L2, hub-invisible) vs `framework.nim` (L1, on the hub).** Recommend **`serde_helpers.nim`** so the wire-mapping stays off the public surface (consistent with A1c keeping all L2 serde hub-private) while remaining a single source of truth. No human decision strictly required; flagging only because the alternative (pure L1 helpers) would add two public functions to `import jmap_client`. **Recommendation: `serde_helpers.nim`.**

================================================================================
## SOURCE agent-aba0157e700dabcc3.jsonl — # B11 (P16) Change-Map — `Email.bodyValues` / `bodyStructure` coherence
================================================================================

I now have a complete, exhaustive picture. Here is the change-map.

---

# B11 (P16) Change-Map — `Email.bodyValues` / `bodyStructure` coherence

## Headline finding (read first)

**The B11 premise is factually wrong against RFC 8621.** The TODO states *"`Email.bodyValues` is populated only when a `bodyStructure` is requested … 'bodyValues populated + bodyStructure absent' is structurally allowed but server-incoherent."* RFC 8621 §4.2 (`docs/rfcs/rfc8621-jmap-mail.txt:2359-2365`) defines the Email/get default property set as:

```
[ "id", "blobId", "threadId", "mailboxIds", "keywords", "size",
"receivedAt", "messageId", "inReplyTo", "references", "sender", "from",
"to", "cc", "bcc", "replyTo", "subject", "sentAt", "hasAttachment",
"preview", "bodyValues", "textBody", "htmlBody", "attachments" ]
```

`bodyValues` **is** a default property; `bodyStructure` **is not**. `bodyValues` content is gated by `fetchTextBodyValues`/`fetchHTMLBodyValues`/`fetchAllBodyValues` (`…:2322-2335`), *not* by whether `bodyStructure` is in the property set. Per RFC §4.1.4 (`…:1295-1301`), `bodyValues` keys (`PartId`) reference parts from **any** of `bodyStructure`, `textBody`, `htmlBody` — and `textBody`/`htmlBody` are defaults. So "bodyValues populated + bodyStructure absent" is the **normal, RFC-mandated default shape** for the single most common fetch (read an email's text content).

This is reinforced structurally by the library's own typed API: `addEmailGet` (`src/jmap_client/internal/mail/mail_builders.nim:172-187`) sends **no** `properties` filter — only `bodyFetchOptions`. A conformant server therefore returns the default set (no `bodyStructure`) for every full-record `Email`. Consequently `Email.bodyStructure` is `Opt.none` for essentially *every* `addEmailGet` result, and `Opt.some` only when a server volunteers a non-default property. The "incoherent" state is not an edge case from server bugs — it is the steady state of the full-record `Email` path.

**Recommendation: resolve B11 as ❌ DROPPED (premise invalid). Implement neither (a) phantom nor (b) reject/drop.** A `parseEmail` enforcing `bodyValues.len>0 ⇒ bodyStructure.isSome` would reject the most common real response and fail an entire `Email/get` batch (see Hazards). Instead apply a small corrective: tighten one docstring, and add positive gates that *lock in* acceptance of the coherent-without-`bodyStructure` shape so a future contributor cannot "reintroduce" the false invariant. Details below.

---

## Current state — actual type/field definitions

`Email` read model — `src/jmap_client/internal/mail/email.nim:452-505`. Relevant pair:
```nim
496  bodyStructure*: Opt[EmailBodyPart]
497    ## Full MIME tree; ``Opt.none`` when ``bodyStructure`` was not
498    ## requested under a property filter.
499  bodyValues*: Table[PartId, EmailBodyValue]
500    ## Text part contents; empty if none fetched.
```
Note: the source docstrings are already correct and do **not** assert the false coupling — the false claim lives only in the TODO. There is **no** smart constructor for `Email`: `grep` for `func parseEmail`/`initEmail`/`makeEmail` under `src/` returns only `parseEmailGetProperty`, `parseEmailBodyProperty`, `parseEmailHeader`, `parseEmailBlueprint`, etc. — none constructs an `Email`. `Email` is **raw-constructed** in serde (`serde_email.nim:371`).

`ParsedEmail` — `email.nim:571-612`, same pair at `603` (`bodyStructure*: Opt[EmailBodyPart]`) and `606` (`bodyValues*: Table[PartId, EmailBodyValue]`). Also raw-constructed (`serde_email.nim:638`).

`PartialEmail` (sparse, A3.6/A4) — `email.nim:517-565`, pair at `559` (`bodyStructure*: FieldEcho[EmailBodyPart]` — three-state) and `560` (`bodyValues*: Opt[Table[PartId, EmailBodyValue]]` — two-state). The two fields are *independently* optional by design; the partial type already models absence of each with no cross-field coupling.

`EmailBodyValue` — `src/jmap_client/internal/mail/body.nim:204-209`: plain copyable `object` (`value: string`, `isEncodingProblem: bool`, `isTruncated: bool`). No move/copy/`lent` hazard.

Parser is lenient-by-design (A3.6 / Postel) — `emailFromJson` `serde_email.nim:328-401`; docstring at `334-336`: *"every field is `Opt` so property-filtered `Email/get` responses (sparse JSON) parse without error."* `parseBodyFields` (`serde_email.nim:268-311`) reads `bodyStructure` and `bodyValues` independently with no coherence check.

Dispatch wiring (decisive for the "reject" semantics): `GetResponse[T].fromJson` (`src/jmap_client/internal/protocol/methods.nim:726-751`) parses each `list` entry with `?T.fromJson(...)` inside a `collect` (line 744-746) — **any** per-entry `err` aborts the whole `GetResponse`. The `SerdeViolation` then becomes a `MethodError(serverFail)` via `serdeToMethodError` (`src/jmap_client/internal/protocol/dispatch.nim:166-181`, `339`/`362`). So a per-Email reject = whole-batch `Email/get` failure.

## All sites — every construct / read / serde / test caller

### src/ — read-model construct + serde (B11 scope)
- `src/jmap_client/internal/mail/email.nim:496,499` — `Email.bodyStructure` / `bodyValues` field decls.
- `src/jmap_client/internal/mail/email.nim:603,606` — `ParsedEmail` field decls.
- `src/jmap_client/internal/mail/email.nim:559,560` — `PartialEmail` field decls.
- `src/jmap_client/internal/mail/serde_email.nim:73,74` — internal `BodyFields` carrier decls.
- `src/jmap_client/internal/mail/serde_email.nim:242-255` — `parseBodyValues` (Table parse).
- `src/jmap_client/internal/mail/serde_email.nim:268-311` — `parseBodyFields` (reads `bodyStructure` 274, `bodyValues` 275; constructs `BodyFields` 303-304). **The natural coherence-check site if one were ever wanted.**
- `src/jmap_client/internal/mail/serde_email.nim:371,393-394` — `Email(...)` raw construction (`bodyStructure: bf.bodyStructure`, `bodyValues: bf.bodyValues`). **Sole `Email` construction site.**
- `src/jmap_client/internal/mail/serde_email.nim:417-520` — `PartialEmail.fromJson`; body block `480-487`, construct `512-513`.
- `src/jmap_client/internal/mail/serde_email.nim:572-586` — `emitPartialEmailBody` (`bodyStructure` 574, `bodyValues` 575-576).
- `src/jmap_client/internal/mail/serde_email.nim:638,654-655` — `ParsedEmail(...)` raw construction.
- `src/jmap_client/internal/mail/serde_email.nim:730-734` — `Email.toJson` body emit.
- `src/jmap_client/internal/mail/serde_email.nim:793-797` — `ParsedEmail.toJson` body emit.
- `src/jmap_client/internal/mail/serde_email.nim:403-411` — `fromJson(typedesc[Email])` mixin wrapper (the parser GetResponse[Email] resolves).
- `src/jmap_client/internal/mail/mail_builders.nim:172-187` — `addEmailGet` (no `properties` filter → server default → `bodyStructure` absent).
- `src/jmap_client/internal/mail/mail_builders.nim:208-227` — `addPartialEmailGet` (sends `properties`, returns `GetResponse[PartialEmail]`).
- `src/jmap_client/internal/mail/mail_methods.nim:171-172` — `parsedEmailFromJson` wired into `EmailParseResponse`.

### src/ — OUT OF SCOPE (do not touch): `EmailBlueprint` creation-side family
Separate creation model with its own `bodyStructure`/derived `bodyValues` accessor — not the `Email` read model: `email_blueprint.nim:344,361-365,815-844`, `serde_email_blueprint.nim:80-84,114-128,171-175`. The B11 premise is about the read model only.

### tests/ — read-model callers that PROVE the premise false / would break under reject
- `tests/serde/mail/tserde_email.nim:215-230` (`fromJsonBodyOnlyPartialShape`) — full `Email`, `properties=["id","textBody","bodyValues"]`; asserts `e.bodyValues.len==1` **and** `assertNone e.bodyStructure`, `assertOk`. **Directly contradicts a reject.**
- `tests/serde/captured/tcaptured_email_multipart_alternative.nim:28-41` — real captured Stalwart `Email/get`; `GetResponse[Email].fromJson`; `email.bodyValues.len==2` with **no** `bodyStructure` in the property set. **Live-wire proof.**
- `tests/mproperty.nim:2103-2123` (`genPartialEmail`) — generates full `Email` with `bodyStructure=Opt.none` (2123) while `bodyValues` may be non-empty (2058) → drives the round-trip property test through the "incoherent" state.
- `tests/property/tprop_mail_d.nim:36-50` — `emailFromJson(toJson(e))==e` round-trips both `genEmail`/`genPartialEmail`; would fail if parser rejected.
- `tests/serde/mail/tserde_email.nim:117-130` — `bodyValues` populated case.

### tests/ — other read-model `bodyValues`/`bodyStructure` callers
- `tests/serde/mail/tserde_email.nim:202-213` (`assertNone e.bodyStructure`), `247-253`, `310-311`, `318-392` (ParsedEmail).
- `tests/serde/mail/tserde_email_integration.nim:82-111` (parity), `137`.
- `tests/serde/mail/tserde_email_adversarial.nim:173-189` (`bodyValuesDuplicatePartId`/`EmptyPartId`), `248-249`, `282-327`.
- `tests/mfixtures.nim:592-593,620-621` (`makeEmail`/`makeParsedEmail`: `bodyStructure: Opt.some(leaf)`, `bodyValues: empty` — coherent, unaffected), `958-967` (`emailEq` reads both), `1306`.
- `tests/mproperty.nim:1692-1693,1821-1835` (`genBodyFields`), `2057-2063` (`genEmail`), `2094-2095` (`genParsedEmail`).
- Live (require servers, not in `just test`): `tests/integration/live/temail_get_text_body_live.nim:95-98`, `temail_get_html_body_live.nim:91-102`, `temail_get_body_properties_all_live.nim:96-111`, `temail_get_max_body_value_bytes_live.nim:121-126` — all read `email.bodyValues.valueOr(...)` ⇒ these are `PartialEmail` (Opt) paths.
- Captured: `tests/serde/captured/tcaptured_email_get_body_properties_all.nim:32-41` (bodyStructure `isSome` because explicitly requested + bodyValues), `tcaptured_email_get_max_body_value_bytes_truncated.nim:32-35`.
- Selector/blueprint tests touching the *names* only (no read-model coherence): `tests/unit/mail/tget_property_selectors.nim:89`, `tests/property/tprop_mail_e.nim:*`, `tests/serde/mail/tserde_email_blueprint*.nim:*`, `tests/unit/mail/temail_blueprint.nim:*`, `tests/compliance/tmail_e_reexport.nim:77`, `tests/unit/mail/tblueprint_compile_time.nim:111,137,147,227`.

## Proposed cut

**No type change. No serde signature change. No smart constructor.** Concretely:

1. **Reclassify B11 in `docs/TODO/pre-1.0-api-alignment.md:2346-2369`** from `⬜ TODO (FREEZE-BLOCKING)` to `❌ DROPPED`, body rewritten to: the claimed invariant `bodyValues.len>0 ⇒ bodyStructure.isSome` is false per RFC 8621 §4.2 default-property set (`bodyStructure` non-default, `bodyValues` default; `bodyValues` partIds reference `textBody`/`htmlBody`/`bodyStructure`, RFC §4.1.4). Both option (a) phantom and option (b) reject/drop are rejected because they would break the default text-fetch path. Update the dashboard (`:70-75`) and freeze-blocking list (`:77-84`) to remove B11; update the P16 tracker row (`:3616`) and the "Decision gates" line (`:3053`). Serves **P16** correctly: a precondition that does not exist must not be encoded; and **Postel/A3.6** (lenient receive) which the parser already embodies.

2. **Tighten the `Email.bodyValues` docstring** at `src/jmap_client/internal/mail/email.nim:499-500` to state the *actual* referential relationship and explicitly that it is independent of `bodyStructure`. Suggested:
   ```nim
   bodyValues*: Table[PartId, EmailBodyValue]
     ## Decoded text-part contents keyed by PartId; empty if no
     ## fetch*BodyValues flag was set. Keys reference parts in any of
     ## textBody / htmlBody / bodyStructure (RFC 8621 §4.1.4); because
     ## textBody and htmlBody are default Email/get properties and
     ## bodyStructure is not (§4.2), a populated bodyValues with absent
     ## bodyStructure is the normal default shape, not an incoherence.
   ```
   Mirror the same note on `ParsedEmail.bodyValues` (`email.nim:606`). Serves **"comments explain why"** + prevents re-litigation.

3. **Serde adapts: unchanged.** `parseBodyFields` (`serde_email.nim:268-311`) stays as-is. **Each caller adapts: unchanged** — no construction site changes.

4. **(Optional, recommended) If a human still wants a gate**, the only defensible coherence rule is *referential* and **lenient, never reject**: bodyValues keys SHOULD resolve to a fetched part. But it is violated legitimately by `fetchAllBodyValues=true` without `bodyStructure`/flat-lists, and lenient-dropping orphan entries would discard the server's decoded text (the payload the user asked for). So **do not implement even this.** State it as the rationale for DROP.

## Hazards

- **Whole-batch poisoning (the killer argument against b-reject).** `GetResponse[Email].fromJson` uses `?T.fromJson` in a `collect` (`methods.nim:744-746`); one rejected `Email` aborts the entire list → `MethodError(serverFail)` (`dispatch.nim:339`). A reject does not "drop one bad email" — it fails the whole `Email/get`. Combined with finding (1) that the rejected shape is the *default*, b-reject would make `addEmailGet(..., fetchBodyValues=bvsText)` fail on conformant servers.
- **`{.push raises: [], noSideEffect.}` purity (L1-L3).** If any check were added, it must live in serde (`serde_email.nim`, L2) as a `Result[..., SerdeViolation]` rail, not throw. A `parseEmail` returning `Result` is purity-compatible but pulls `Email` construction out of the raw-init pattern at `serde_email.nim:371` — a large, needless blast radius. Avoid.
- **`strictCaseObjects`.** `EmailBodyPart` is a case object (`isMultipart`); any predicate touching `bodyStructure.value.isMultipart` inside a check must go through `for v in opt:` / `case`, not `if isSome`. Another reason to add nothing.
- **`Opt[...].get()` copying.** `EmailBodyValue`/`Table` are copyable; no `lent`/uncopyable hazard. Not a blocker, just noted.
- **A3 scope text drift.** `pre-1.0-api-alignment.md:533-547` (A3) already asserts the full-record `Email` parser is lenient and "a sparse fetch cannot drive … to MethodError". Encoding a reject would directly contradict A3 — a documented, shipped decision. The DROP keeps A3 and B11 consistent.

## Audit / test impact

Because the cut is "no behaviour change + lock the correct behaviour", the impact is additive gates, not protective rewrites:

- **No test breaks** under the DROP — all sites in "All sites" already pass with the lenient parser. (Under the rejected b-reject, `tserde_email.nim:215-230`, `tcaptured_email_multipart_alternative.nim:36`, `mproperty.nim:2103-2123`, `tprop_mail_d.nim:36-50` would all break — evidence the cut should not happen.)
- **Add a positive serde gate** in `tests/serde/mail/tserde_email.nim` (a `testCase`, e.g. `fromJsonBodyValuesWithoutBodyStructureIsCoherent`): feed `{"id","textBody","bodyValues"}` (no `bodyStructure`), assert `emailFromJson` is `Ok`, `bodyValues.len>0`, `bodyStructure.isNone`. This is the mechanical regression gate that B11's DROP rationale relies on (prevents a future contributor adding the false invariant). `fromJsonBodyOnlyPartialShape` (`:215-230`) already nearly does this — extend/rename it and cite RFC 8621 §4.2 in the docstring.
- **Property gate already present:** `tprop_mail_d.nim:36-50` over `genPartialEmail` already exercises round-trip through the bodyValues-without-bodyStructure state — keep, add an inline comment tying it to B11's resolution.
- **No `treject_*` / `tcompile_*` needed** (there is no new compile-time invariant). Explicitly do **not** add a `treject_b11_*` — there is nothing to reject.
- **Snapshot gates** (`tests/wire_contract/type-shapes.txt`, A25): untouched — no type shape changes.

## Open questions

1. **Does the maintainer accept the DROP?** This is the one genuine human decision: B11 is a labelled FREEZE-BLOCKING item with a "default recommendation: (b)". My research shows (b) is actively harmful and (a) is unnecessary. Recommendation: **DROP**, with the docstring fix + positive gate above. I'm confident on the RFC reading (§4.2 default set excludes `bodyStructure`; §4.1.4 ties `bodyValues` to `textBody`/`htmlBody`/`bodyStructure`) and on the live evidence (captured Stalwart fixture already exhibits the state).
2. **Where to record the DROP rationale?** The api-alignment doc B11 body is the natural home; the referenced `docs/TODO/pre-1.0-freeze-checklist.md` (D18) **does not yet exist** (`ls docs/TODO/` shows only `pre-1.0-api-alignment.md`, `macro-tests-ffi.md`, `mixin-and-json-combinators.md`, `refactor-case-discard.txt`). So the dashboard at `pre-1.0-api-alignment.md:68-84` is the only freeze tally to update. Flag this missing-checklist gap separately.
3. **`PartialEmail` cross-field coupling?** None proposed — `PartialEmail` already models `bodyStructure: FieldEcho` and `bodyValues: Opt[Table]` independently, which is correct under the same RFC reading. No change. (Recommendation: confirm in the B11 DROP body that the partial type needs no coupling either, to forestall a follow-up.)

================================================================================
## SOURCE agent-aba7b22bfcea82e80.jsonl — # B5 Change-Map: `registerExtractableEntity(T)` compile-check
================================================================================

I now have a complete and verified picture. Here is the change-map.

---

# B5 Change-Map: `registerExtractableEntity(T)` compile-check

## Current state — actual type/field definitions

### The registration framework (`src/jmap_client/internal/protocol/entity.nim`)
Three sibling templates, all hub-public (re-exported via `protocol.nim:33 export entity`, no `except`). The module has **zero imports** — every symbol the templates reference (`methodEntity`, `capabilityUri`, `filterType`, `toJson`, `setMethodName`, `createType`, `updateType`, `setResponseType`) is left *open* in the template body and resolved at the call site (`mail_entities.nim`).

`entity.nim:129-163` — the closest sibling to mirror:
```nim
template registerSettableEntity*(T: typedesc) =
  static:
    when not compiles(setMethodName(T)):
      {.error: "registerSettableEntity: " & $T & " is missing `func setMethodName*...".}
    when not compiles(createType(T)):     ...
    when not compiles(updateType(T)):     ...
    when not compiles(setResponseType(T)): ...
```
Note: `registerSettableEntity` checks only that the *typedesc resolvers* exist — it does **not** check `createType(T).toJson`/`updateType(T).toJson`/`setResponseType(T).fromJson`. The true precedent for checking a *serde overload* is `registerQueryableEntity` (`entity.nim:122`): `when not compiles(toJson(default(filterType(T))))`. B5 mirrors *that* shape, for `fromJson`.

### Post-A1c dispatch (`src/jmap_client/internal/protocol/dispatch.nim`)
`ParseProc[T]` (`dispatch.nim:40-41`) and the handle's `rawParseProc: ParseProc[T]` field (`dispatch.nim:54-56`, `113-116`). The closure is captured in the template `initResponseHandle` (`dispatch.nim:58-71`):
```nim
template initResponseHandle*[T](callId, builderId): ResponseHandle[T] =
  mixin fromJson
  block:
    proc parse(args: JsonNode): Result[T, SerdeViolation] {.noSideEffect, raises: [].} =
      T.fromJson(args)                       # <-- the checkpoint
    ResponseHandle[T](rawCallId: callId, rawBuilderId: builderId, rawParseProc: parse)
```
`dispatch.get` (`dispatch.nim:312-341`) now invokes `handle.rawParseProc(inv.arguments)` (line 339) — it does **no** `mixin fromJson`. So the `fromJson`-resolution checkpoint moved off `dispatch.get[T]` and onto `initResponseHandle[T]`/`initNameBoundHandle[T]`, which expand inside the builders.

### The entity `fromJson` overloads (all uniform shape)
`func fromJson*(T: typedesc[X], node: JsonNode, path: JsonPath = emptyJsonPath()): Result[X, SerdeViolation]` for:
- `serde_thread.nim:34` `Thread`, `:56` `PartialThread`
- `serde_identity.nim:88` `Identity`, `:166` `IdentityCreatedItem`, `:189` `PartialIdentity`
- `serde_mailbox.nim:219` `Mailbox`, `:297` `MailboxCreatedItem`, `:399` `PartialMailbox`
- `serde_email.nim:403/417/967/1057` `Email`/`PartialEmail`/`EmailCreatedItem`/etc.
- `serde_email_submission.nim:131` `AnyEmailSubmission`, `:158` `EmailSubmissionCreatedItem`, `:350` `PartialEmailSubmission`
- `serde_vacation.nim:78` `VacationResponse`, `:149` `PartialVacationResponse`

Confirmed there is **no catch-all** `fromJson(typedesc[T], JsonNode)`: the only generic overloads are constrained `seq[T]` (`serde_primitives.nim:60`), `Table[K,V]` (`:93`), and the `GetResponse[T]`/`ChangesResponse[T]`/`SetResponse[T,U]`/`CopyResponse[T]`/`QueryResponse[T]`/`QueryChangesResponse[T]` families (`methods.nim:726/753/786/815/844/877`). So `compiles(fromJson(Mailbox, …))` resolves unambiguously to the concrete overload.

## All sites

### `register*` call sites (src) — all in `mail_entities.nim`
- `:68` `registerJmapEntity(thread.Thread)`
- `:126` `registerJmapEntity(Identity)`; `:127` `registerSettableEntity(Identity)`
- `:203` `registerJmapEntity(Mailbox)`; `:204` `registerQueryableEntity`; `:205` `registerSettableEntity`
- `:297-299` `registerJmapEntity/registerQueryableEntity/registerSettableEntity(Email)`
- `:371-373` same trio for `AnyEmailSubmission`
- `:379/382` `registerCompoundMethod(...)`; `:390/393/396` `registerChainableMethod(...)`
- Partials (getter-only): `:424` `PartialThread`, `:443` `PartialIdentity`, `:462` `PartialMailbox`, `:481` `PartialEmail`, `:501` `PartialEmailSubmission`, `:524` `PartialVacationResponse`

### Template definitions
- `entity.nim:77` `registerJmapEntity`, `:107` `registerQueryableEntity`, `:129` `registerSettableEntity`
- `dispatch.nim:397` `registerCompoundMethod`, `:446` `registerChainableMethod`

### "Distant instantiation" sites B5 protects (the `fromJson`-resolution points)
Generic builders (`builder.nim`) — response `fromJson` resolves at each *instantiation* in a per-entity wrapper:
- `:280` `addMethodImpl`→`initResponseHandle[RespType]` (used by `addChanges`)
- `:398` `addGet`→`initResponseHandle[GetResponse[T]]`; `:420` `addGetSelected`
- `:487` `addSet`→`initResponseHandle[R]`; `:523` `addCopy`; `:548` `addQuery`; `:582` `addQueryChanges`

Per-entity wrappers that *trigger* those instantiations (the sites where a missing entity `fromJson` currently errors confusingly):
- `mail_builders.nim:54,69,81,201,241,251,265` (Mailbox/Email/Thread get+changes via generic `addGet`/`addChanges`); plus local `initResponseHandle` at `:106,165,187,227,288,318,419`
- `identity_builders.nim:43,53,67,93` (Identity)
- `submission_builders.nim:48,58,73,88,108,131` (AnyEmailSubmission); local handles `:241,242`
- `mail_methods.nim:65,93,131,270,297,331,386` (VacationResponse, EmailParse, SearchSnippet, EmailImport — all *local* `initResponseHandle`, low risk)

### `dispatch.get`/`getBoth` extraction sites (post-A1c, no `fromJson` here)
- `dispatch.nim:312,347` `get`; `:382,433` `getBoth`
- `convenience.nim:229,240` `getBoth`; `:236,237,246` `dr.get`
- `mail_builders.nim:464-481` `getAll`

### Tests touching the registration surface
- `tests/protocol/tentity.nim` (entity-framework positive/negative; `:36,48,56,85` registrations; `:121-139` `assertNotCompiles`)
- `tests/protocol/tmail_entities.nim:42,46,65,154,158,242,246` (incl. `:65` `assertNotCompiles(registerJmapEntity(VacationResponse))`)
- `tests/compile/tcompile_a1b_protocol_hub_surface.nim:24-26` (`declared(registerJmapEntity/Queryable/Settable)`)
- `tests/compile/tcompile_mail_f_public_surface.nim:73` (`declared(registerSettableEntity)`)
- `tests/mtest_entity.nim:84-85`, `tests/protocol/{tmethods,tbuilder,tdispatch}.nim` (mock registrations)
- `tests/m_l2_serde.nim` (H10 test-side L2 aggregator — gives tests the serde surface)

## Proposed cut

### 1. New template in `entity.nim` (after `registerSettableEntity`, ~line 164)
```nim
template registerExtractableEntity*(T: typedesc) =
  ## Compile-time check: verifies T provides the ``fromJson`` parser that
  ## ``dispatch.get[T]`` ultimately relies on. Call after ``registerJmapEntity``
  ## for every entity that supports /get (i.e. every readable entity and every
  ## getter-only ``Partial*``).
  ##
  ## Post-A1c, ``dispatch.get`` invokes the resolver closure captured on the
  ## handle by ``initResponseHandle``; the resolver body is ``T.fromJson(args)``.
  ## So ``fromJson`` is still the checkpoint — this template moves the
  ## resolution failure from the builder's ``initResponseHandle[Resp[T]]``
  ## expansion (a distant generic-instantiation site inside ``addGet``/``addSet``
  ## etc.) to the registration call, with a domain-specific message.
  ##
  ## Mirrors ``registerQueryableEntity``'s ``toJson(default(filterType(T)))``
  ## probe: ``fromJson`` and ``JsonNode`` resolve at the caller's scope.
  static:
    when not compiles(fromJson(T, default(JsonNode))):
      {.
        error:
          "registerExtractableEntity: " & $T &
          " is missing `func fromJson*(_: typedesc[" & $T &
          "], JsonNode): Result[" & $T & ", SerdeViolation]`"
      .}
```
No imports added to `entity.nim`: `fromJson` is open (resolves at `mail_entities.nim`); `JsonNode` is open (resolves to `std/json`, imported at `mail_entities.nim:18`); `default` is a `system` builtin. **Empirically verified in /tmp** that `compiles(fromJson(T, default(JsonNode)))` (a) resolves `JsonNode` open at the call site and (b) marks the providing serde module as *used* for `UnusedImport`.

### 2. `mail_entities.nim` — add serde-leaf imports + registration calls
Add imports (after line 35) so the entity/partial `fromJson` overloads are in scope at registration:
```nim
import ./serde_thread
import ./serde_identity
import ./serde_mailbox
import ./serde_email
import ./serde_vacation
```
(`serde_email_submission` is already imported at `:31`.) These are *used* by the new `compiles` probes, so no `UnusedImport`.

Insert one `registerExtractableEntity` after each `registerJmapEntity`:
- `:68` → `registerExtractableEntity(thread.Thread)`
- `:126` → `registerExtractableEntity(Identity)` (before `registerSettableEntity`)
- `:203` → `registerExtractableEntity(Mailbox)`
- `:297` → `registerExtractableEntity(Email)`
- `:371` → `registerExtractableEntity(AnyEmailSubmission)`
- `:424/443/462/481/501/524` → `registerExtractableEntity(PartialThread/PartialIdentity/PartialMailbox/PartialEmail/PartialEmailSubmission/PartialVacationResponse)`

### How serde adapts
No serde change. The entity `fromJson` overloads already exist with the exact `Result[X, SerdeViolation]` shape the probe expects. `mail_entities.nim` (hub-private — `mail.nim` re-exports only `types`/`mail_methods`/`mail_builders`/`identity_builders`/`submission_builders`, never `mail_entities`) gains serde imports without leaking serde to the `import jmap_client` surface (A1c/A1d preserved).

### How each caller adapts
No builder, no test caller changes shape. The new calls are additive at module scope. The only behavioural change: an entity registered without a valid `fromJson` now fails at its `registerExtractableEntity` line instead of inside `addGet[T]`/`initResponseHandle`.

### A1c reconciliation (explicit)
`fromJson` **is still the checkpoint**. A1c moved the *resolution site* from `dispatch.get[T]` to `initResponseHandle[T]` (captured into `rawParseProc`), but the captured body is `T.fromJson(args)`. B5 checks that exact `fromJson`. The B5 docstring/TODO wording "dispatch.get[T] fails at instantiation" should be updated to "the builder's `initResponseHandle[Resp[T]]` expansion fails at instantiation" — same `fromJson`, new (post-A1c) failure locus.

### Principles served
- **P19** (schema-driven, no stringly-typed escapes): every readable entity proves it has a typed parser at registration.
- **P5/P20** (single public layer; additive variants): additive registration call, no new module entry point; framework stays in `entity.nim`.
- **"Make illegal states unrepresentable" / domain-modelling**: "registered-but-unparseable entity" becomes a compile error at the registration site.
- **P2** (stability bought with tests): the compile-audit + `assertNotCompiles` tests lock it.

## Hazards

- **`UnusedImport` is `warningAsError`** (`config.nims`). Adding 5 serde imports to `mail_entities.nim` is safe *only because* the `compiles(fromJson(T, …))` probe counts as a use — **empirically confirmed** (probe present → EXIT 0; probe removed → `Error: imported and not used: 'serdemod' [UnusedImport]`). If any registered entity's serde leaf had *no* corresponding `registerExtractableEntity` call, its import would be flagged — so every added import must be paired with at least one probe that references it.
- **Open-symbol resolution in templates**: `JsonNode`/`fromJson` must NOT be added to `entity.nim` as a definition-site binding, or they'd bind at `entity.nim` scope (where serde isn't imported) and break. Keep `entity.nim` import-free (consistent with current design); rely on call-site resolution (verified working in /tmp with an import-free `reg.nim`).
- **`{.push raises: [], noSideEffect.}`** (L1–L3 purity): the template emits only `static:`/`when`/`{.error.}` — no runtime code, no raises, no side effects. `default(JsonNode)` is nil but never executed (`compiles` is non-evaluating). Safe.
- **strictCaseObjects**: no variant access; N/A.
- **nimalyzer `params` rule**: the template consumes `T` via `$T` in the error strings (same as siblings) — compliant, no `ruleOff` needed.
- **nimalyzer `complexity`**: single `when` — trivial; no decomposition needed.
- **Overload ambiguity**: none — `fromJson(Mailbox, JsonNode)` matches only the concrete `typedesc[Mailbox]` overload (generic overloads are constrained to `seq`/`Table`/`*Response`).
- **No import cycle**: verified no `serde_*` leaf imports `mail_entities`.
- **Return-type precision**: the simple probe checks *existence/argument-shape*, not that the result is exactly `Result[T, SerdeViolation]` (matching `registerQueryableEntity`'s precedent). A stricter probe (`when not compiles((let r: Result[T, SerdeViolation] = fromJson(T, default(JsonNode)); r))`) would require `SerdeViolation`+`Result` in scope at `mail_entities.nim` (and arguably in `entity.nim`), breaking the import-free design. Recommend the simple form; it's sufficient because the only matching overloads in-tree return `Result[T, SerdeViolation]`.

## Audit/test impact

**Must change:**
- `tests/compile/tcompile_a1b_protocol_hub_surface.nim:26` — add `doAssert declared(registerExtractableEntity)` (it auto-re-exports via `export entity`).
- `tests/protocol/tentity.nim` — add:
  - Positive: a mock with a valid `fromJson` (e.g. `MockExtractable` + `func fromJson*(T: typedesc[MockExtractable], n: JsonNode): Result[MockExtractable, SerdeViolation]`) then `registerExtractableEntity(MockExtractable)`; a `testCase` asserting compile success. (Realistic return type means `import .../serialisation/serde` for `SerdeViolation`; the minimal alternative — `fromJson` returning `int` — also passes the probe but is less faithful. Recommend the realistic form.)
  - Negative: `assertNotCompiles(registerExtractableEntity(MockFoo))` — `MockFoo` (already defined, no `fromJson`) must fail. Add a dedicated `NoFromJson` mock if cleaner.
- `tests/protocol/tmail_entities.nim` — add a positive `testCase` that the five entities + six partials satisfy extractability (implicit pass), and optionally a negative noting `registerExtractableEntity(VacationResponse)` *passes* (it has `fromJson`) while `registerJmapEntity(VacationResponse)` *fails* (`:65`) — documents that the two checks are orthogonal.

**Optionally add:** `tests/compile/tcompile_mail_f_public_surface.nim` — `doAssert declared(registerExtractableEntity)` alongside `:73`.

**Snapshot/wire/property:** none. No wire shape, no type-shape (`tests/wire_contract/type-shapes.txt`) change — `registerExtractableEntity` introduces no new runtime type or field.

## Open questions

1. **`/set`+`/copy` `createResults` item types are not covered.** `registerExtractableEntity(<entity>)` checks the bare-entity `fromJson` (covers full `/get`) and `registerExtractableEntity(Partial*)` covers `SetResponse`'s `U` (updateResults). But the `T` in `SetResponse[T,U]`/`CopyResponse[T]` is a *created-item* type (`MailboxCreatedItem`, `EmailCreatedItem`, `IdentityCreatedItem`, `EmailSubmissionCreatedItem`, `NoCreate`), which is **not** an entity and not registered — so its `fromJson` still resolves only at the distant `addSet`/`addCopy` instantiation. **Recommendation:** close this with one extra probe inside `registerSettableEntity` — `when not compiles(fromJson(setResponseType(T), default(JsonNode)))` — which transitively verifies the created-item *and* partial *and* the `SetResponse`/`EmailSubmissionSetResponse` wrapper in a single check. This is a small, principled extension of an existing template (not scope-creep into a new one) and reuses the same serde imports. If preferred to keep B5 minimal, leave it and file as a follow-up; the `/get` path (the most-used generic builder) is fully closed by B5 as specified.

2. **Bespoke responses (`EmailParseResponse`, `SearchSnippetGetResponse`, `EmailImportResponse`) and full `VacationResponse`** are extractable but *not* registered entities; their `fromJson`/`initResponseHandle` are co-located in `mail_methods.nim`, so the failure locus is already local (not distant). **Recommendation:** do **not** force these through `registerExtractableEntity` — it would require either registering non-entities or scattering the call into `mail_methods.nim`. Leave them as locally-checked. (State explicitly in the new template's docstring that it targets the *registered-entity* `/get` path.)

3. **Insertion order relative to `registerSettableEntity`.** Recommend `registerJmapEntity` → `registerExtractableEntity` → `registerQueryableEntity` → `registerSettableEntity`, so the docstring "checklist" in `entity.nim:45-72` (items 7–12) gains "register extractable" as the step immediately after item 7. Update that checklist docstring accordingly.

================================================================================
## SOURCE agent-ad146f46e394d5990.jsonl — agent-ad146f46e394d5990.jsonl
================================================================================

These tests only check `assertOk`/`assertErr` + read `.error()` — they don't unwrap the Ok tuple, so they're unaffected. But the live tests use `.expect(...)`. Let me examine nim-results' extraction procs to know which copy vs move, and read the src definitions plus live-test usage.

================================================================================
## SOURCE agent-aeaf29ce8730317d4.jsonl — # Change-Map: A25 / A25b / A26 / A2b — snapshot + property-test infrastructure
================================================================================

I now have a complete, verified picture. Here is the change-map.

---

# Change-Map: A25 / A25b / A26 / A2b — snapshot + property-test infrastructure

Research-only. No files edited. All paths absolute. This maps the *new* infrastructure (freeze recipes, generator scripts, snapshot files, lints, property test) onto the existing freeze conventions, with the `nim doc` investigation resolved.

## Current state

### Existing freeze infrastructure (the conventions to mirror)

**justfile recipes** (`/workspaces/jmap-client/justfile`):

- `freeze-module-paths` (justfile:419-427) — shell-only; regenerates `tests/wire_contract/module-paths.txt` by listing `src/jmap_client/*.nim`, prefixing `jmap_client`, `sort -u`. No `nim` invocation. Comment header (415-418) states "CI does not run this recipe" and tags `[MODULE-PATH-CHANGE]`.
- `lint-module-paths` (justfile:432-435) — `nim r --hints:off --warnings:off tests/lint/h13_module_path_lock.nim`.
- `freeze-error-messages` (justfile:440-446) — runs the Nim generator: `nim r ... scripts/freeze_error_messages.nim > …/error-messages.txt.new` then `mv`. Tags `[ERR-MSG-CHANGE]`.
- `lint-error-messages` (justfile:451-454) — `nim r ... tests/lint/h15_error_message_snapshot.nim`.
- `check` (justfile:466) and `ci` (justfile:480) both end the lint chain with `… lint-module-paths lint-error-messages analyse [test]`.
- `docs` (justfile:491-494) — `nim doc --project --index:on --outdir:htmldocs src/jmap_client.nim` (HTML, not JSON).

**Generator script** (`/workspaces/jmap-client/scripts/freeze_error_messages.nim:1-186`): `{.push raises: [].}`, imports the library, declares `proc emit` + `proc main`, `echo`s a snapshot with a 3-line header (`# … locked by …`, `# Regenerate with: just …`, `# Update PR label: [ERR-MSG-CHANGE]`), then `## Section` headings and `[label]` / two-space-indented-value pairs. Determinism is explicit (no Tables iteration, no Rand). Other `scripts/` contents: `strip_comments.nims` (nimscript), `output/` (dir).

**Snapshot-lint pattern** (`/workspaces/jmap-client/tests/lint/h13_module_path_lock.nim:1-103` and `h15_error_message_snapshot.nim:1-366`): both compute `RepoRoot = currentSourcePath().parentDir.parentDir.parentDir`, `loadSnapshot()` reads the committed `.txt`, recompute the live set (h13 walks the filesystem; h15 inlines the same 38 samples as the generator, verbatim — they duplicate, not share), three-way diff (MISSING / EXTRA / CHANGED), `quit(1)` with a fix-it block pointing at the freeze recipe + PR label. h13 docstring (lines 4-25) documents the bidirectional contract.

**Snapshot files** (`/workspaces/jmap-client/tests/wire_contract/`): `module-paths.txt` (2 lines: `jmap_client`, `jmap_client/convenience`), `error-messages.txt` (94 lines, 3-line header + `## Section`/`[label]`/`  value`), `tsnapshot_well_formed.nim:1-23` — the testament anchor that keeps `tests/wire_contract/` a valid testament `cat` (asserts `module-paths.txt` non-empty). `type-shapes.txt` and `public-api.txt` do **not** exist.

### Property-test infrastructure (A2b)

**Generators** (`/workspaces/jmap-client/tests/mproperty.nim`): trial tiers `QuickTrials=200`/`DefaultTrials=500`/`ThoroughTrials=2000` (55-67); `checkProperty`/`checkPropertyN` templates injecting `rng = initRand(42)`, `trial`, `lastInput` (73-90); `oneOf` (96-98). `genInvocation` (486-495):

```nim
proc genInvocation*(rng: var Rand): Invocation =
  const methods = [mnMailboxGet, mnEmailGet, mnEmailQuery, mnEmailSet, mnThreadGet]
  let name = rng.oneOf(methods)
  let mcidStr = "c" & $rng.rand(0 .. 99)
  let mcid = parseMethodCallId(mcidStr).get()
  initInvocation(name, newJObject(), mcid)
```

`genInvocationWithArgs` (1052-1078) produces richer JObject args over 7 methods; `genRequest`/`genBuiltRequest`/`genResponse` (1080-1137). Direct H10 import already present: `import jmap_client/internal/protocol/builder` (46).

**Existing partial** (`/workspaces/jmap-client/tests/property/tprop_envelope.nim:84-91`):

```nim
testCase propInvocationPreservesFields:
  checkProperty "propInvocationPreservesFields":
    ## Invocation construction preserves all three fields.
    let inv = genInvocation(rng)
    lastInput = inv.rawName
    doAssert inv.rawName.len > 0
    doAssert inv.arguments.kind == JObject
```

Imports (7-15): `primitives`, `identifiers`, `envelope`, `methods_enum`, `validation`, plus `../mproperty`, `../mtestblock`. It does **not** import `serde_envelope`. `testCase` is from `/workspaces/jmap-client/tests/mtestblock.nim` (wraps body in an IIFE proc for move analysis).

**The types A2b round-trips** — `/workspaces/jmap-client/src/jmap_client/internal/types/envelope.nim`:
- `Invocation` (31-36): flat `object` with private `arguments`, `rawMethodCallId`, `rawName`. **No explicit `==`** anywhere in `src/` (verified). Being a flat (non-case) object, Nim auto-generates structural `==`.
- `initInvocation` (64-71) stores `rawName: $name`; `parseInvocation` (73-82) stores `rawName: rawName` verbatim, rejects empty.
- `MethodName` (`/workspaces/jmap-client/src/jmap_client/internal/types/methods_enum.nim:19-53`): 27 backed variants + `mnUnknown` (no backing string). `parseMethodName` (93-101) is total → `mnUnknown` for unrecognised wire strings.
- serde: `toJson(inv)` = `%*[inv.rawName, inv.arguments, $inv.methodCallId]` and `Invocation.fromJson` at `/workspaces/jmap-client/src/jmap_client/internal/serialisation/serde_envelope.nim:31-86`.

## All sites

**Existing infra sites (templates to copy), src/build:**
- justfile:419-427 freeze-module-paths · 432-435 lint-module-paths · 440-446 freeze-error-messages · 451-454 lint-error-messages · 466 check · 480 ci · 491-494 docs
- /workspaces/jmap-client/scripts/freeze_error_messages.nim:1-186 (generator template)
- /workspaces/jmap-client/tests/lint/h13_module_path_lock.nim:1-103 (filesystem-walk lint template)
- /workspaces/jmap-client/tests/lint/h15_error_message_snapshot.nim:1-366 (recompute-and-diff lint template)
- /workspaces/jmap-client/tests/lint/h12_no_test_backdoor_symbols.nim:31-126 (`extractExportedName` text-scraper to generalise for public-api)
- /workspaces/jmap-client/tests/wire_contract/module-paths.txt · error-messages.txt · tsnapshot_well_formed.nim:1-23 (anchor)

**Export-graph sites that define hub reachability (the A26 input), src:**
- /workspaces/jmap-client/src/jmap_client.nim:20-33 — root exports `types protocol transport client mail push websocket` (no filters)
- /workspaces/jmap-client/src/jmap_client/internal/types.nim:20-58 — `export results` + 15 L1 leaves with multi-line `except` clauses (envelope except spans 49-53; errors except 55-58); defines `JmapResult`
- /workspaces/jmap-client/src/jmap_client/internal/protocol.nim:27-37 — exports `entity methods dispatch builder` with `except` filters
- /workspaces/jmap-client/src/jmap_client/internal/mail.nim:12-22 — exports `types(except fromJson) mail_methods mail_builders identity_builders submission_builders`
- /workspaces/jmap-client/src/jmap_client/internal/mail/types.nim:11-47 — sub-hub: 18 mail leaves (`headers`/`body except parseFromString`)
- /workspaces/jmap-client/src/jmap_client/internal/transport.nim, client.nim, push.nim, websocket.nim — leaves, **no** `export` lines (own `*` symbols only)
- /workspaces/jmap-client/src/jmap_client/convenience.nim:31 — `import jmap_client` only, **no** `export`; adds 17 own symbols (6 types + 11 procs incl 3 `getBoth` overloads)
- **Not reachable:** everything under `src/jmap_client/internal/serialisation/` (no hub re-exports it).

**A2b construct/read/serde/test sites:**
- src: envelope.nim:31-82 (Invocation type + ctors), methods_enum.nim:19-101 (MethodName + parseMethodName), serde_envelope.nim:31-38 toJson, :67-86 fromJson
- tests: mproperty.nim:486-495 genInvocation, :1052-1078 genInvocationWithArgs; tprop_envelope.nim:84-91 propInvocationPreservesFields (the partial to extend); mtestblock.nim testCase

**Existing hub-surface audits (cross-check oracle for the generators):** /workspaces/jmap-client/tests/compile/ — `tcompile_a1_public_surface.nim`, `tcompile_a1b_protocol_hub_surface.nim`, `tcompile_a1c_serialisation_hub_surface.nim`, `tcompile_a1d_mail_hub_surface.nim`, `tcompile_a2_invocation_hub_surface.nim`, `tcompile_a30_envelope_hub_surface.nim`, `tcompile_a11_request_context_hub_surface.nim`, `tcompile_a20a21_hub_surface.nim`, `tcompile_mail_f_public_surface.nim`, `tcompile_mail_g_public_surface.nim`.

## Investigation results (the `nim doc` question, resolved)

1. **`nim jsondoc <module>` works per-module**, RC=0, complete JSON, for all 82 source modules (swept). Output shape: top keys `{orig, nimble, moduleDescription, entries}`; each entry `{name, type, line, col, code, description}`. `type` ∈ `{skType, skProc (func reported as skProc), skConst, skIterator, skTemplate}` — no skMacro/skConverter (project forbids converters).
2. **`code` for `skType` = public-field-only signature** (private fields stripped) plus field docstrings. Verified: `Invocation` (all-private fields) renders as `Invocation {.ruleOff: "objects".} = object` with no fields; `TransportError`/`SetError` render full `field*: Type ## doc` lines incl `case kind*:` arms. **This is exactly what A25 wants** and it auto-ignores internal `raw*` field renames.
3. **`code` for `skProc` = full normalized signature** with params, return type, generics, AND inferred `{.raises: [], noSideEffect, tags: [], forbids: [].}`. Overloads appear as distinct entries (two `name`, three `getBoth`). The inferred-pragma tail is a toolchain-version churn risk.
4. **`nim jsondoc src/jmap_client.nim` (the hub) = 0 entries** — jsondoc does **not** follow `export` re-exports. So you cannot jsondoc the hub to get the public surface.
5. **`nim jsondoc --project` is fragile**: it does cross-module semantic work and errored on `email.nim(508,49) '*' expected` (the `multipart/*` token in the line-508 docstring). It still wrote `theindex.json` `{documents, modules, symbols}`, but the project doc is incomplete and it over-captures (lists every documented module incl `serialisation/*`, ignoring `export … except` filtering). **Do not use `--project`.**
6. Per-module `nim jsondoc` on `email.nim` prints the same cosmetic `Error: '*' expected` to stderr **but returns RC=0 with complete JSON** (93 entries). Cosmetic only; optionally silenced by rewording the `multipart/*` docstring (a clean-refactor comment uplift).
7. **The `compiler` AST package is unavailable** (`import compiler/ast` → cannot open). AST scraping must be text-based (h12/h13 style) or via jsondoc JSON. There is no compile-time facility to enumerate in-scope symbols by name.
8. **A2b proof-of-concept compiled and passed**: `Invocation.fromJson(toJson(inv)).get() == inv` for all 28 `MethodName` variants (27 named + `mnUnknown` via `parseInvocation("Vendor/customThing", …)`). Requires the vendored results on the path (config.nims:10) — the unpatched nimble `results-0.5.1` fails strictCaseObjects `==`.

**Conclusion on reliable enumeration:** the only faithful way to enumerate "reachable through the hub" is to **resolve the `export` / `export … except` graph** from the two entry points (`src/jmap_client.nim`, `src/jmap_client/convenience.nim`). jsondoc-of-hub yields nothing, jsondoc-`--project` over-captures and is fragile, the compiler AST is unavailable, and there is no symbol-table reflection.

## Proposed cut

Four deliverables, all mirroring existing conventions. New files only; nothing in `src/` changes (except an optional one-line `email.nim:508` docstring uplift to silence the cosmetic jsondoc stderr).

### Shared reachability resolver (foundation for A25b + A26)

`/workspaces/jmap-client/scripts/api_surface.nim` — a pure-Nim module (under `scripts/`, exempt from `src/` L1-L3 pragmas) providing:
- `func reachableModules(): seq[ReachableModule]` where `ReachableModule = (path: string, exceptSet: HashSet[string])`. Algorithm: BFS from `src/jmap_client.nim` and `src/jmap_client/convenience.nim`; for each module read its source, **join logical lines** (a physical line continues while it ends in `,` or bare `except`), parse `export <ident>[ except a, b, …]`, resolve `<ident>` to a file via the module's `import ./…` lines, recurse, accumulating `exceptSet`. Modules with no further `export <localmodule>` are leaves. `export results` and `export <std>` handled by an explicit allow/skip policy (see Open Questions).
- `func exportedDecls(modPath): seq[Decl]` where `Decl = (kind, name, signature)` — generalise `h12`'s `extractExportedName` (h12_no_test_backdoor_symbols.nim:40-57) to all `DeclarationKinds = ["type ","func ","proc ","template ","iterator ","const ","macro "]` and to capture the declared signature substring up to `=`/pragma. Text-scrape (toolchain-stable, no inferred pragmas).

Both `freeze_public_api.nim` and the public-api lint import this so they cannot drift (improving on the h15 verbatim-duplication convention).

### A26 + F6 — `public-api.txt` + `freeze-api` + lint

- **Snapshot** `/workspaces/jmap-client/tests/wire_contract/public-api.txt`: 3-line header (`# … locked by tests/lint/h16_public_api_snapshot.nim`, `# Regenerate with: just freeze-api`, `# Update PR label: [API-CHANGE]`), then `## section per source module` (mirroring error-messages.txt grouping), each symbol one line: `<kind> <name><declared-signature>`, sorted. Includes the declared signature (text-scraped) so it catches accessor return-type drift (the `using: seq[string] → seq[CapabilityUri]` case A25 worried about) — closing the A25/A26 gap without jsondoc's pragma churn. Union = hub-reachable ∪ convenience's 17 own symbols.
- **Generator** `/workspaces/jmap-client/scripts/freeze_public_api.nim` — `{.push raises: [].}`, imports `./api_surface`, walks `reachableModules()`, emits filtered `exportedDecls`. `echo` to stdout.
- **Recipe** `freeze-api` (after justfile:446, mirroring freeze-error-messages exactly):
  ```
  freeze-api:
      @echo "Regenerating tests/wire_contract/public-api.txt..."
      @mkdir -p tests/wire_contract
      nim r --hints:off --warnings:off scripts/freeze_public_api.nim \
        > tests/wire_contract/public-api.txt.new
      @mv tests/wire_contract/public-api.txt.new tests/wire_contract/public-api.txt
      @echo "Snapshot regenerated. Review the diff before committing."
  ```
- **Lint** `/workspaces/jmap-client/tests/lint/h16_public_api_snapshot.nim` — copy h15 structure (loadSnapshot / recompute via `api_surface` / 3-way diff / fix-it pointing at `just freeze-api` + `[API-CHANGE]`).
- **Recipe** `lint-public-api` (mirror lint-error-messages) + add `lint-public-api` to `check` (justfile:466) and `ci` (justfile:480).
- F6's GitHub-Actions step (TODO §F6, lines 3221-3230) is the CI-workflow layer: `just freeze-api` + `git diff --quiet`. Recommend **both** the h16 lint (clear local error message) and the F6 git-diff CI gate.
- Serves: **P1** (lock the contract), **P5** (single public layer — the snapshot makes the export-graph filter auditable), **P2** (stability bought with tests).

### A25 + A25b — `type-shapes.txt` + `freeze-type-shapes`

- **Snapshot** `/workspaces/jmap-client/tests/wire_contract/type-shapes.txt`: 3-line header (`# … locked by … `, `# Regenerate with: just freeze-type-shapes`, `# Update PR label: [TYPE-SHAPE-CHANGE]`), then one section per reachable public type, **alphabetical by type name**, body = the jsondoc `skType` `code` (public-field-only), field docstrings stripped, whitespace-normalized. Captures every public type's field signature incl enum members and `case` arms.
- **Generator** `/workspaces/jmap-client/scripts/freeze_type_shapes.nim` — imports `./api_surface` for `reachableModules()`; for each reachable leaf, `osproc.execProcess "nim jsondoc --hints:off --warnings:off --outdir:<tmp> <leaf>"` (tolerate cosmetic stderr; RC is 0), parse JSON, select `skType` entries whose `name ∉ exceptSet`, take `code`, strip per-field `## …` docstrings, emit. Uses jsondoc (not text-scrape) because its `code` already strips private `raw*` fields — exactly A25's "public field signature" semantic.
- **Recipe** `freeze-type-shapes` (mirror freeze-error-messages; the generator shells jsondoc internally, so the recipe is just `nim r … scripts/freeze_type_shapes.nim > …txt.new && mv`).
- **CI gate**: A25b text (TODO:2025-2031) specifies regenerate-and-git-diff with `[TYPE-SHAPE-CHANGE]`. Recommend a thin `lint-type-shapes` (regenerate to temp, diff committed) OR the F6-style git-diff. Add to `check`/`ci`.
- Serves: **P1** (field-set drift is a contract break), **P2**, **P21** (lifecycle/handle types — `HandlePairKind` etc. cited at TODO:2331).

### A2b — Invocation round-trip property

- **Extend** `/workspaces/jmap-client/tests/property/tprop_envelope.nim` (it is **not** in `testament_skip.txt` → stays in the fast `just test` suite). Add `import jmap_client/internal/serialisation/serde_envelope` (direct H10 import; tests are exempt from the H10 boundary lint, and `mproperty.nim:46` already imports an internal protocol leaf).
- New `testCase propInvocationRoundTrip` covering both axes:
  - **Exhaustive variant loop** (deterministic): `for m in MethodName:` build `inv` — for `mnUnknown` use `parseInvocation("Vendor/" & synthesised, args, mcid).get()` (a realistic unknown wire name that `parseMethodName` maps to `mnUnknown`), else `initInvocation(m, args, mcid)`; assert `Invocation.fromJson(toJson(inv)).get() == inv`.
  - **Randomised** (`checkProperty`): random JObject args + random `MethodCallId` per trial, asserting the same identity.
- Add a generator `genInvocationForMethod*(rng, m: MethodName): Invocation` to `mproperty.nim` (alongside genInvocation:486) so other suites can reuse it; args must be `JObject` (fromJson requires `path/1` JObject).
- The auto-generated structural `==` on the flat `Invocation` object is the comparison (no new `==` needed; proof-of-concept passed for all 28 variants).
- F1 wiring (`just test-wire-contract`, `tests/property/coverage.txt`) does **not** exist yet; A2b lands independently in the property category and is picked up by `testament cat property` / `just test`. Note F1 as a follow-up, not a blocker.
- Serves: **P19** (schema-driven, lossless round-trip incl forward-compat `mnUnknown`), **P2**.

## Hazards

- **jsondoc does not follow re-exports** (hub → 0 entries) and **`--project` is fragile** (email.nim semantic error, over-capture). The generators MUST resolve the export graph and call jsondoc **per leaf**. Do not jsondoc the hub or `--project`.
- **jsondoc cosmetic stderr + exit code**: `email.nim` prints `Error: '*' expected` but exits 0 with full JSON. The justfile shell is `set -euo pipefail` (justfile:10). The freeze recipe must not let a piped/grepped jsondoc stderr abort it; the Nim generator calling `execProcess` should ignore stderr and validate `entries.len > 0` rather than the exit code. (Optionally reword `email.nim:508` `multipart/*` to kill the noise — allowed clean-refactor uplift.)
- **jsondoc `skProc` inferred-pragma tail** (`{.raises:[],noSideEffect,tags:[],forbids:[].}`) is toolchain-version-sensitive → public-api snapshot churn on Nim upgrades. Mitigation: build public-api from **text-scraped declared signatures** (no inferred pragmas), not jsondoc. type-shapes uses jsondoc `code` for *types* only (no effect pragmas on type decls), so it is unaffected.
- **Multi-line `export … except`** (types.nim:49-53, 55-58) and **two-level filters** (`headers`/`body except parseFromString` at mail/types.nim:39-40) require logical-line joining in the resolver. A naive per-line scrape (h12/h13 style) is insufficient — this is the one place the new tooling must exceed the existing lints.
- **`export results`** (types.nim:20) re-exports the external nim-results surface (`Result`, `Opt`, `?`, …) into the hub. Decide whether public-api.txt enumerates them (they ARE reachable) or treats `results` as an opaque external boundary. Recommendation: list `export results` as a single boundary line, not its member symbols, to avoid snapshotting a vendored dependency (ties to D4).
- **Vendored results / strictCaseObjects**: any helper that compiles against the library (the A2b test, and the type-shapes generator if it imports the lib) must use the vendored copy via config.nims:10. The A2b property test compiles inside the project so this is automatic; a standalone generator that only shells jsondoc and reads JSON avoids the issue entirely.
- **`Invocation` has no explicit `==`** — it relies on Nim's auto structural `==` for flat objects. If `Invocation` ever gains a `case` (it won't per A30), auto-`==` breaks (nim-type-safety.md "parallel fields iterator"). The A2b assertion silently depends on flatness; note it in the test docstring.
- **strictCaseObjects in tests is exempt**, but the generators live in `scripts/` (also exempt from the `src/` `{.experimental: "strictCaseObjects".}` mandate). They still need `{.push raises: [].}` + `osproc`/`json` exception handling to satisfy their own `raises`.
- **nimalyzer / fmt / reuse**: new `scripts/*.nim` and `tests/lint/*.nim` must carry the SPDX header (reuse), pass `nph` (`just fmt-check`), and satisfy nimalyzer if `scripts/` is in scope (freeze_error_messages.nim passes today — mirror its `{.push ruleOff.}` usage only if needed; never relax rules).
- **Slowness**: type-shapes freeze shells `nim jsondoc` for ~40 leaves (each a compile) → tens of seconds. Acceptable for a dev-only freeze recipe; keep it out of the per-PR fast path (use the git-diff gate, not an in-process recompute, for type-shapes CI).

## Audit/test impact

- **New snapshot data**: `tests/wire_contract/public-api.txt`, `tests/wire_contract/type-shapes.txt`. The existing anchor `tsnapshot_well_formed.nim:1-23` keeps the category valid; optionally extend it (or add `tsnapshot_public_api_well_formed.nim` / `tsnapshot_type_shapes_well_formed.nim`) to assert the two new files are non-empty, matching the existing anchor's sole purpose.
- **New lints**: `tests/lint/h16_public_api_snapshot.nim` (recompute-and-diff, mirror h15). Optional `tests/lint/h17_type_shapes_snapshot.nim` or rely on the git-diff gate. Both run via new `lint-public-api` / `lint-type-shapes` recipes and must be appended to `check` (justfile:466) and `ci` (justfile:480).
- **New scripts**: `scripts/api_surface.nim` (shared resolver), `scripts/freeze_public_api.nim`, `scripts/freeze_type_shapes.nim`.
- **New recipes**: `freeze-api`, `lint-public-api`, `freeze-type-shapes`, `lint-type-shapes`.
- **Property test (A2b)**: extend `tests/property/tprop_envelope.nim` with `propInvocationRoundTrip` (+ `serde_envelope` import); add `genInvocationForMethod` to `tests/mproperty.nim`. No skip-list change (tprop_envelope runs in the fast suite). The randomised variant can use `DefaultTrials`; the exhaustive `for m in MethodName` loop is O(28) per trial — cheap.
- **Cross-check (reliability)**: the generated `public-api.txt` should be reconciled against the hand-curated `tcompile_*_hub_surface.nim` audits — every `doAssert not declared(X)` in those audits must correspond to X being absent from public-api.txt, and every `doAssert declared(Y)` to Y present. This is the belt-and-suspenders argument that the export-graph resolver is correct; consider a one-off reconciliation during implementation (not necessarily a permanent test).
- **No `treject_*` needed** — these items add snapshots/properties, not new rejection-surface constructors.

## Open questions

1. **public-api.txt: names-only vs names+signatures.** A26/D2 literally say "exported symbol list"; F6 says "symbols reachable." Recommendation: **include declared signatures** (text-scraped, pragma-free) — it subsumes the names contract AND catches the accessor return-type drift A25 explicitly flags as the gap D2 misses. If reviewers want minimal churn, fall back to `<kind> <name>` only and rely on type-shapes for field drift (but accessor-return drift then escapes both). I recommend signatures.
2. **`export results` handling.** List as one boundary line vs enumerate the nim-results surface. Recommendation: single boundary line (`export results  # external boundary, see D4`) — snapshotting a vendored third-party API surface is out of scope and couples to D4.
3. **type-shapes: keep or strip field docstrings.** jsondoc `code` includes them; they churn on comment edits. Recommendation: **strip** (the snapshot locks shape, not prose; `just docs` already owns rendered docs).
4. **CI gate style: in-process Nim lint (h15-style) vs regenerate-and-git-diff (F6-style).** The codebase uses the former for module-paths/error-messages; F6/A25b text specifies the latter. Recommendation: **public-api → h16 lint** (clear local message, fast text-scrape recompute) **plus** the F6 git-diff CI step; **type-shapes → git-diff only** (jsondoc recompute is too slow for an in-process lint). This honours both conventions where each is cheap.
5. **One combined freeze recipe vs two.** A25b and A26/F6 name distinct files and PR labels (`[TYPE-SHAPE-CHANGE]` vs `[API-CHANGE]`). Keep them as **two recipes / two scripts** sharing `scripts/api_surface.nim`. (No human decision strictly required; stated for completeness.)
6. **Silence the `email.nim:508` jsondoc stderr** by rewording the `multipart/*` docstring? Recommendation: yes (trivial, clean-refactor-legal, removes confusing CI log noise) — but the generators must be robust to it regardless, since other future docstrings could re-introduce it.

================================================================================
## SOURCE agent-af080343b7d79a5ee.jsonl — ## ITEM B4 (P16) — VacationResponse `fromDate`/`toDate` window invariant — chang
================================================================================

I now have a complete picture. Here is the change-map.

---

## ITEM B4 (P16) — VacationResponse `fromDate`/`toDate` window invariant — change-map

### Summary verdict (read first)
The invariant "`from > to` is forbidden" is a **temporal** invariant, but `UTCDate` is deliberately modelled as a structurally-validated opaque string with **no calendar semantics and no ordering operator** (`primitives.nim:62-67`, `defineSealedStringOps` gives only `==`/`$`/`hash`/`len`). RFC 8620 §1.4 (`rfc8620-jmap-core.txt:343-353`) normalises only "zero `time-secfrac` omitted + letters uppercase" — fractional-second precision is **not** fixed, so lexicographic comparison of two valid `UTCDate` strings is temporally **unsound** (e.g. `"…01Z"` vs `"…01.5Z"`: `'.'`=0x2E < `'Z'`=0x5A, so the later instant sorts first). Both literal options in the TODO are therefore wrong as stated — see Proposed cut. My recommendation is a **third shape**: leave the receive types lenient (Postel), add a sound module-private structural comparator, and enforce the locally-checkable subset of the invariant inside the send-side batch constructor `initVacationResponseUpdateSet`.

---

## Current state

**`src/jmap_client/internal/mail/vacation.nim`**

Full receive record (constructed only by serde from the wire):
```nim
21  type VacationResponse* {.ruleOff: "objects".} = object
24    isEnabled*: bool
25    fromDate*: Opt[UTCDate] ## Start of the vacation window, or none.
26    toDate*: Opt[UTCDate]   ## End of the vacation window, or none.
27    subject*: Opt[string]
28    textBody*: Opt[string]
29    htmlBody*: Opt[string]
```
Partial echo (receive-only; sparse `/get` + `/set` echo):
```nim
35  type PartialVacationResponse* {.ruleOff: "objects".} = object
41    isEnabled*: Opt[bool]
42    fromDate*: FieldEcho[UTCDate]
43    toDate*: FieldEcho[UTCDate]
44    subject*: FieldEcho[string]
45    textBody*: FieldEcho[string]
46    htmlBody*: FieldEcho[string]
```
Send-path update algebra (independent single-property replace ops):
```nim
70    case kind*: VacationResponseUpdateVariantKind
73    of vruSetFromDate:
74      fromDate*: Opt[UTCDate]  ## Opt.none clears the start date.
75    of vruSetToDate:
76      toDate*: Opt[UTCDate]    ## Opt.none clears the end date.
88  func setFromDate*(fromDate: Opt[UTCDate]): VacationResponseUpdate = ...
92  func setToDate*(toDate: Opt[UTCDate]): VacationResponseUpdate = ...
119 func initVacationResponseUpdateSet*(updates): Result[VacationResponseUpdateSet, seq[ValidationError]]
      # currently validates ONLY: non-empty + unique-by-kind (lines 129-138)
```

`UTCDate` (`src/jmap_client/internal/types/primitives.nim:62-67`): sealed `rawValue: string`, `defineSealedStringOps` → **no `<`/`<=`**. `parseUtcDate` (`primitives.nim:315-322`) is purely structural; fractional seconds optional (`detectFractionalSeconds`, `primitives.nim:190-208`).

`VacationResponse` is **never** constructed by application code — the only `src/` construction site is `serde_vacation.nim:103` (the `fromJson` wire boundary). There is no `/set` create rail (singleton, `NoCreate`; `mail_methods.nim:100-132`). Therefore client-supplied dates flow out **only** through `setFromDate`/`setToDate` → `initVacationResponseUpdateSet` → `mail_methods.nim:120 update.toJson()`.

Note: comments in `vacation.nim` cite "RFC 8621 §7" (lines 5, 19, 40, 42-43) but the VacationResponse object is **§8** of `rfc8621-jmap-mail.txt` (heading at line 4787; properties 4797-4858). Inconsistent even within the file (lines 53, 65, 74-82 say §8). A clean refactor touching these comments should normalise to §8.

---

## All sites

### src — `fromDate`/`toDate` reads, emits, parses
- `src/jmap_client/internal/mail/vacation.nim:25-26` — full-record field decls (Opt)
- `src/jmap_client/internal/mail/vacation.nim:42-43` — partial field decls (FieldEcho)
- `src/jmap_client/internal/mail/vacation.nim:59-60` — update kind enum `vruSetFromDate`/`vruSetToDate`
- `src/jmap_client/internal/mail/vacation.nim:74,76` — update variant fields
- `src/jmap_client/internal/mail/vacation.nim:88-90,92-94` — `setFromDate`/`setToDate` constructors
- `src/jmap_client/internal/mail/vacation.nim:119-138` — `initVacationResponseUpdateSet` (**target of change**)
- `src/jmap_client/internal/mail/vacation.nim:151-152,198-200,221-224` — GetProperty selectors `vrgkFromDate`/`vrgkToDate`/`vrgpFromDate`/`vrgpToDate`
- `src/jmap_client/internal/mail/serde_vacation.nim:70-71` — `emitOptUtcDate` for full record
- `src/jmap_client/internal/mail/serde_vacation.nim:97-98,105-106` — parse + construct full record
- `src/jmap_client/internal/mail/serde_vacation.nim:124,126` — update `toJson` (`u.fromDate`/`u.toDate`)
- `src/jmap_client/internal/mail/serde_vacation.nim:158-159,166-167,180-181` — partial parse/construct/emit (FieldEcho)
- `src/jmap_client/internal/mail/mail_methods.nim:100-132` — `addVacationResponseSet` (passes `update.toJson()`; unaffected)

### tests — construction / read / serde / fixtures
- `tests/serde/mail/tserde_vacation.nim:71-78,87-94,135-142` — direct `VacationResponse(...)` construction
- `tests/serde/mail/tserde_vacation.nim:34-37,56-57,97-100,145-146` — `vr.fromDate`/`vr.toDate` reads & null-emit asserts
- `tests/serde/mail/tserde_vacation.nim:158-178,210-226` — update-arm serde (`makeSetFromDate`/`makeSetToDate`, update-set flatten)
- `tests/unit/mail/tvacation.nim:25-29,93-97` — `setFromDate`/`setToDate` arm tests
- `tests/unit/mail/tvacation.nim:38-89` — `initVacationResponseUpdateSet` empty/dup tests (**must extend**)
- `tests/mfixtures.nim:1846-1852` — `makeSetFromDate`/`makeSetToDate`
- `tests/mfixtures.nim:1882-1885` — `makeVacationResponseUpdateSet` (`.get()` — would crash if a fixture ever builds a backwards window)
- `tests/unit/mail/tget_property_selectors.nim:75` — `vrgpFromDate.wireName`
- `tests/protocol/tmail_methods.nim:32,153` — `initVacationResponseUpdateSet(@[setIsEnabled(true)])`
- `tests/protocol/tmail_entities.nim:63-75` — VacationResponse registration-blocked compile tests (unaffected)
- `tests/serde/captured/tcaptured_vacation_get.nim`, `tcaptured_vacation_set_all_arms.nim` — receive replay (unaffected; no from/to comparison)
- `tests/integration/live/tvacation_set_all_arms_live.nim:68-73,84-85,157-161,170-171` — from=`2026-06-01…`, to=`2026-06-30…` (from<to → unaffected); reads `vr.fromDate`/`vr.toDate`
- `tests/integration/live/tvacation_get_set_live.nim:61-68,145-146` — `initVacationResponseUpdateSet` (no dates)
- `tests/compile/tcompile_mail_f_public_surface.nim:64` — `declared(initVacationResponseUpdateSet)` surface lock (signature returns same type → unaffected)
- `tests/testdata/captured/vacation-get-singleton-stalwart.json:1` — fixture has `fromDate:null,toDate:null` (unaffected)

---

## Proposed cut

### Why neither (a) nor (b) as literally written
- **(a) `parseVacationResponse: Result` enforcing order on the receive record** — *rejected.* `VacationResponse`/`PartialVacationResponse` are receive-only (server→client). Postel's law (CLAUDE.md "be lenient on receive"; nim-conventions "Lenient fromJson for server data") forbids failing `/get` parsing because a server emitted a pathological window. The library must faithfully represent whatever the server sends. Enforcing here would also break `tserde_vacation` round-trips and captured replay.
- **(b) single `Opt[VacationWindow] = (UTCDate, UTCDate)`** — *rejected.* `fromDate` and `toDate` are **independently nullable** per RFC 8621 §8 (`rfc8621-jmap-mail.txt:4823-4835`): from-only ("effective from X indefinitely"), to-only ("effective immediately until Y"), and neither are all legal, meaningful states the server sends and the client may set. A required `(UTCDate, UTCDate)` pair makes the three mixed states unrepresentable — it destroys RFC fidelity on both the receive record and the update algebra. It also clashes with the single-property replace structure of `VacationResponseUpdate` (you can clear just one endpoint).

### Does the invariant apply to `PartialVacationResponse`?
**No.** It is receive-only and three-state (`FieldEcho`): a partial echo may carry only `fromDate`, only `toDate`, null, or absent for either. The cross-field invariant is neither expressible nor enforceable there, and Postel forbids enforcement on receive. Leave it untouched.

### Recommended shape (variant of (a), relocated to the send-side batch constructor)
The only place client-originated dates are validated *with both endpoints visible* is `initVacationResponseUpdateSet` (it already sees the whole batch). Enforce the locally-checkable subset there; leave all receive types and all serde untouched.

1. **Add a sound, module-private structural comparator in `vacation.nim`** (no change to `primitives.nim`, no new public `UTCDate` ordering, no `std/times`):
   ```nim
   func utcInstantLeq(a, b: UTCDate): bool =
     ## True iff `a` is at or before `b` on the UTC timeline. Sound for
     ## RFC 8620 §1.4 UTCDate: the 19-char "YYYY-MM-DDTHH:MM:SS" prefix is
     ## fixed-width zero-padded numerics with fixed separators (lexical ==
     ## chronological); the optional fractional part is compared as a
     ## right-zero-padded digit string. Both values end in 'Z' (UTCDate
     ## invariant), so no offset normalisation is needed.
   ```
   Uses only `$a` / `$b` (the sealed `defineSealedStringOps` `$` returns `rawValue` verbatim), so it needs no access to the private field and lives entirely in `vacation.nim` under `{.push raises: [], noSideEffect.}`.

2. **Extend `initVacationResponseUpdateSet`** with a second accumulating pass after the existing `validateUniqueByIt` pass: scan the batch for `vruSetFromDate(Opt.some f)` **and** `vruSetToDate(Opt.some t)`; if both present and `not utcInstantLeq(f, t)` (i.e. `f > t`), append one `ValidationError(typeName="VacationResponseUpdateSet", reason="window start is after window end", value=...)`. Concatenate with the uniqueness errors so all violations surface in one `Err` pass (mirrors the existing contract). Extract the scan into a helper `func windowOrderConflict(updates): seq[ValidationError]` to keep cyclomatic complexity under the nimalyzer `complexity` ceiling.

3. **No change to**: `VacationResponse`, `PartialVacationResponse`, `VacationResponseUpdate`, the six `setX` constructors, all of `serde_vacation.nim`, `mail_methods.nim`, the GetProperty selectors.

### Serde adaptation
**None.** Receive parsing/emitting and update `toJson` are unchanged. This is the chief advantage: every existing serde, captured-replay, and live test passes unchanged; the wire contract is byte-identical.

### Caller adaptation
- All existing `initVacationResponseUpdateSet` callers (`mfixtures.nim:1885`, `tvacation.nim`, `tmail_methods.nim:32,153`, both live tests, `tserde_vacation.nim:214`) pass either single-property batches or `from<to` — **none break**.
- Only new tests exercising a deliberately backwards window need adding (see Audit/test impact).

### Principles served
P16 (encode preconditions — the locally-checkable subset), "make illegal states unrepresentable" — *partially*, honestly scoped; while **respecting** Postel (receive leniency) and **preserving** independent-nullability fidelity. The honest scoping (server remains authoritative for windows that span an unseen server-held endpoint) is itself a P16/P13 stance: don't pretend a guarantee you can't make.

---

## Hazards

- **Lexical `<` is wrong.** Do **not** add `<`/`<=` to `UTCDate` via `defineSealedStringOps` or borrow `string`'s `<`. Fractional-second precision varies under RFC 8620 §1.4 normalisation, so naive string compare misorders (`"…01.5Z"` < `"…01Z"`). The comparator must split prefix (lexical) from fractional (right-zero-padded digit compare).
- **L1 purity (`{.push raises: [], noSideEffect.}`).** `std/times.parse` raises `TimeParseError` and is impure → forbidden in `vacation.nim`. The structural comparator must stay string-only, total, allocation-free where possible (substring slices of already-validated input; no `parseInt`). Keep it `func`.
- **`strictCaseObjects`.** Reading `u.fromDate`/`u.toDate` from `VacationResponseUpdate` requires `case u.kind of vruSetFromDate: u.fromDate` (Rule 1 — not `if`). The arms are individually declared (`vruSetFromDate`/`vruSetToDate` are separate `of` arms, lines 73-76), so per-arm reads are strict-safe. The batch scan must `case` on each update's `kind`, never `if u.kind == …`.
- **nimalyzer `complexity`.** Folding the new cross-field pass into the existing constructor body risks tripping the complexity rule (already has the uniqueness pass). Extract `windowOrderConflict` (and keep `utcInstantLeq` separate). Do not `ruleOff`.
- **nimalyzer `params`.** `utcInstantLeq` consumes both params naturally — fine.
- **`.get()` discipline.** `mfixtures.nim:1885 initVacationResponseUpdateSet(updates).get()` will now `ResultDefect`-crash if any future fixture builds a backwards window. Acceptable (fixtures are trusted), but if a fixture is ever added with `from>to` it must use `.expect`/error-aware handling. No current fixture does this.
- **ARC/`lent`/copy.** Comparator takes `UTCDate` by value (small sealed string wrapper) and reads via `$`; no move/lent concerns. The accumulating `seq[ValidationError]` is a local `var` (pattern 7) — pure.
- **`from == to`.** Degenerate empty window; structurally not a contradiction. Recommend permitting `from == to` (reject only strict `f > t`) — see Open questions.

---

## Audit/test impact

**Must add** (`tests/unit/mail/tvacation.nim`, section B — runtime `Result` errors, so plain `testCase`, **not** `treject_*`):
- `initVacationResponseUpdateSet` with `setFromDate(Opt.some f)` + `setToDate(Opt.some t)`, `f > t` → `assertErr`, one error, `typeName == "VacationResponseUpdateSet"`, reason `"window start is after window end"`.
- Accept cases: `f < t`; `f == t` (per recommendation); from-only (`setFromDate(some)` no toDate); to-only; both-cleared (`Opt.none`); from-some + to-cleared; from-cleared + to-some.
- Co-occurrence with the existing uniqueness pass: a batch that is both backwards-windowed and has a duplicate kind surfaces **both** error classes in one `Err` (defends the accumulating contract).

**Comparator unit tests** (new, e.g. in `tvacation.nim` or a primitives test): fractional-second soundness — `utcInstantLeq(parseUtcDate("…01Z"), parseUtcDate("…01.5Z"))` is true and the reverse is false; equal-prefix equal-fraction is reflexive; differing-precision equal-instant edge (`"…00Z"` vs nonzero fraction).

**Should add** (property test, `tests/property/tprop_mail_f.nim` or sibling): generate random `(from, to)` UTCDate pairs (varying fractional precision); assert `initVacationResponseUpdateSet(@[setFromDate(some from), setToDate(some to)])` is `Err` **iff** `from` is strictly after `to` on the timeline — pins comparator soundness against the constructor.

**Unchanged / must still pass** (regression evidence the receive path is untouched): `tests/serde/mail/tserde_vacation.nim` (all), `tcaptured_vacation_get.nim`, `tcaptured_vacation_set_all_arms.nim`, `tcaptured_round_trip_integrity.nim`, `tcompile_mail_f_public_surface.nim:64`, both live tests. No snapshot/wire-fixture changes (serde output byte-identical).

---

## Open questions

1. **Enforcement scope — is the partial guarantee worth it?** My recommendation enforces only the both-endpoints-in-one-batch case; the common pattern "set one date, leave the other server-side" is unprotected because the library cannot see the server's current value, and the server is authoritative (returns an `invalidProperties` `SetError`). *Recommendation:* implement the send-batch check anyway (real elimination of the obvious client mistake, honest about coverage). A defensible alternative the human may prefer is to **close B4 as "won't-fix / server-authoritative"** — leave the types lenient and document the trade-off, since the invariant is fundamentally not fully client-enforceable and the design intentionally keeps `UTCDate` calendar-free. Needs a human ruling on appetite for a partial P16 win vs. zero new comparison machinery.
2. **`from == to`:** allow (recommended — empty window, not a structural contradiction) or reject as useless? 
3. **Comparator placement/visibility:** keep `utcInstantLeq` **private to `vacation.nim`** (recommended — avoids implying a general public `UTCDate` ordering that the "no calendar semantics" design avoids), or promote a public sound comparator to `primitives.nim` for reuse (e.g. future `ReceivedAtFilter` date logic)? Recommend private until a second consumer exists (DRY = duplicated *knowledge*, not appearance).
4. **Comment hygiene (in-scope for clean refactor):** correct the erroneous "§7" references in `vacation.nim:5,19,40,42-43` (and `serde_vacation.nim:4`, `mail_methods.nim:6,51,106,110`) to **§8** while the files are open, per comment-base (RFC-section-only, accurate).

================================================================================
## SOURCE agent-affeebabf076a68b6.jsonl — ## B9 (P9) — Handle-pair zoo consolidation: change-map
================================================================================

I have everything needed. Let me produce the change-map.

## B9 (P9) — Handle-pair zoo consolidation: change-map

### Summary verdict

**Recommend (b): demote `Chained*` off the public hub.** Reject (a). Within (b) I give two execution variants — **(b-minimal)** (except-filter demotion, lowest risk, the TODO-sanctioned move) and **(b-clean)** (delete the single-use generic entirely and replace its one consumer with a bespoke record, which the codebase already does for the 4-step chain). Under the clean-refactor mandate (no dead/legacy plumbing) **(b-clean)** is the principled end-state; (b-minimal) is the safe fallback if churn budget is tight. The decisive fact: **`Chained*` is reducible to two independent `dr.get` calls** (distinct call-ids, no disambiguation), so the generic earns nothing; **`Compound*` is NOT reducible** (its `implicit` is a `NameBoundHandle` whose method-name filter only a builder can mint via the hub-private `initNameBoundHandle`).

---

## Current state

The four context types, two register templates, and two `getBoth` overloads all live in `src/jmap_client/internal/protocol/dispatch.nim`.

**Compound (RFC 8620 §5.4 — one wire call-id, two responses, disambiguated by method-name)** — `dispatch.nim:368-413`:
```nim
type CompoundHandles*[A, B] {.ruleOff: "objects".} = object   # :368
  primary*: ResponseHandle[A]
  implicit*: NameBoundHandle[B]
type CompoundResults*[A, B] {.ruleOff: "objects".} = object   # :377
  primary*: A
  implicit*: B
func getBoth*[A, B](dr: DispatchedResponse, handles: CompoundHandles[A, B]):  # :382
    Result[CompoundResults[A, B], GetError] =
  let primary = ?dr.get(handles.primary)        # default ResponseHandle overload
  let implicit = ?dr.get(handles.implicit)      # NameBoundHandle overload (name filter)
  ok(CompoundResults[A, B](primary: primary, implicit: implicit))
template registerCompoundMethod*(Primary, Implicit: typedesc) = ...   # :397
```

**Chained (RFC 8620 §3.7 — two distinct wire call-ids, back-reference)** — `dispatch.nim:419-455`:
```nim
type ChainedHandles*[A, B] {.ruleOff: "objects".} = object    # :419
  first*: ResponseHandle[A]
  second*: ResponseHandle[B]
type ChainedResults*[A, B] {.ruleOff: "objects".} = object    # :428
  first*: A
  second*: B
func getBoth*[A, B](dr: DispatchedResponse, handles: ChainedHandles[A, B]):  # :433
    Result[ChainedResults[A, B], GetError] =
  let first = ?dr.get(handles.first)     # both via default ResponseHandle overload —
  let second = ?dr.get(handles.second)   # call-ids are unique, no name filter
  ok(ChainedResults[A, B](first: first, second: second))
template registerChainableMethod*(Primary: typedesc) = ...    # :446
```

**Semantic difference (definitive).** Compound = *one* invocation that the server expands into *two* responses sharing a call-id (`Email/copy` + implicit `Email/set` destroy; `EmailSubmission/set` + implicit `Email/set`); the second response is found by `findInvocationByName` (`dispatch.nim:224`) filtering on both call-id AND method-name, because the call-ids collide. Chained = *two* separate invocations with *distinct* call-ids wired by a `#`-back-reference (`Email/query` → `SearchSnippet/get`); both responses are found by plain `findInvocation` (`dispatch.nim:187`) on call-id alone. `getBoth(Chained)` is therefore pure sugar over two `dr.get` calls; `getBoth(Compound)` is not (the `implicit` `NameBoundHandle` cannot be re-minted by application code — `initNameBoundHandle` is hub-private per `protocol.nim:38`).

**Hub exposure** — `src/jmap_client/internal/protocol.nim:37-38`:
```nim
export dispatch except
  initResponseHandle, initNameBoundHandle, initDispatchedResponse, response, builderId
```
All four types + both register templates + both `getBoth` overloads are currently hub-public (none in the `except` filter).

---

## All sites

### Generic definitions (src)
- `src/jmap_client/internal/protocol/dispatch.nim:368` — `CompoundHandles*[A,B]`
- `src/jmap_client/internal/protocol/dispatch.nim:377` — `CompoundResults*[A,B]`
- `src/jmap_client/internal/protocol/dispatch.nim:382-395` — `getBoth(CompoundHandles)`; reads `.primary`/`.implicit` at :393-394
- `src/jmap_client/internal/protocol/dispatch.nim:397-413` — `registerCompoundMethod`
- `src/jmap_client/internal/protocol/dispatch.nim:419` — `ChainedHandles*[A,B]`
- `src/jmap_client/internal/protocol/dispatch.nim:428` — `ChainedResults*[A,B]`
- `src/jmap_client/internal/protocol/dispatch.nim:433-444` — `getBoth(ChainedHandles)`; reads `.first`/`.second` at :442-443
- `src/jmap_client/internal/protocol/dispatch.nim:446-455` — `registerChainableMethod`

### Compound consumers (src) — UNAFFECTED by (b)
- `src/jmap_client/internal/mail/mail_builders.nim:371` — `EmailCopyHandles* = CompoundHandles[...]`
- `src/jmap_client/internal/mail/mail_builders.nim:381` — `EmailCopyResults* = CompoundResults[...]`
- `src/jmap_client/internal/mail/mail_builders.nim:417-422` — constructs `EmailCopyHandles(primary:…, implicit:…)`
- `src/jmap_client/internal/mail/email_submission.nim:679` — `EmailSubmissionHandles* = CompoundHandles[...]`
- `src/jmap_client/internal/mail/email_submission.nim:689` — `EmailSubmissionResults* = CompoundResults[...]`
- `src/jmap_client/internal/mail/submission_builders.nim:199,240` — returns/constructs `EmailSubmissionHandles`
- `src/jmap_client/internal/mail/mail_entities.nim:379,382` — `registerCompoundMethod(...)` ×2

### Chained consumers (src) — the ONLY ones, AFFECTED by (b)
- `src/jmap_client/internal/mail/mail_methods.nim:333-339` — `EmailQuerySnippetChain* = ChainedHandles[QueryResponse[Email], SearchSnippetGetResponse]` (sole `ChainedHandles` instantiation in the whole tree)
- `src/jmap_client/internal/mail/mail_methods.nim:364` — constructs `EmailQuerySnippetChain(first:…, second:…)`
- `src/jmap_client/internal/mail/mail_entities.nim:390,393,396` — `registerChainableMethod(...)` ×3 (gates only; do not instantiate `ChainedHandles`)

### Hub filter (src)
- `src/jmap_client/internal/protocol.nim:37-38` — `export dispatch except …` (must gain `Chained*` names under b)
- `src/jmap_client/internal/mail.nim:18` — `export mail_methods` (re-exports `EmailQuerySnippetChain` alias — keeps working under b)

### NOT related but adjacent (the parallel/precedent patterns)
- `src/jmap_client/convenience.nim:37,43,48,60,65,70` — `QueryGetHandles[T]`, `ChangesGetHandles[T]`, `MailboxChangesGetHandles` + their `*Results`; `getBoth` overloads at :229,240,250. **These are a parallel, independent implementation of the same "paired handles" concept built directly on `ResponseHandle[T]` + `dr.get` — they do NOT use `ChainedHandles` at all.** They live in the P6-quarantined `convenience` module (separate public path), so they don't count against the headline-layer P9 cap, and they are untouched by B9.
- `src/jmap_client/internal/mail/mail_builders.nim:444-481` — `EmailQueryThreadChain` (bespoke 4-handle `object`) + `EmailQueryThreadResults` + monomorphic `getAll` (`:464`). **This is the codebase's existing precedent for a back-reference chain implemented as a bespoke record co-located with its builder, with the comment "there is no generic above this record to carry it" / "Co-located with the builder … because there is no parametric shape to share with the dispatch layer." It already proves Chained chains don't need the dispatch.nim generic.**

### Tests
- `tests/compile/tcompile_a1b_protocol_hub_surface.nim:52,53` — `doAssert declared(CompoundHandles/CompoundResults)` (keep)
- `tests/compile/tcompile_a1b_protocol_hub_surface.nim:54,55` — `doAssert declared(ChainedHandles/ChainedResults)` (**flip to negative under b**)
- `tests/compile/tcompile_a1b_protocol_hub_surface.nim:63,64` — `doAssert declared(registerCompoundMethod/registerChainableMethod)` (:64 **flip to negative under b**)
- `tests/compile/tcompile_a1d_mail_hub_surface.nim:136-139,261-262` — `getBoth`, `QueryGetHandles`, `ChangesGetHandles`, `MailboxChangesGetHandles` (convenience; unaffected)
- `tests/compile/tcompile_mail_f_public_surface.nim:40,41,103` — `EmailCopyHandles/Results`, `getBoth` (compound; unaffected)
- `tests/compile/tcompile_mail_g_public_surface.nim:78,79` — `EmailSubmissionHandles/Results` (compound; unaffected)
- `tests/compliance/trfc_8620.nim:1837` — `EmailSubmissionHandles` (compound; unaffected)
- `tests/integration/live/temail_query_with_snippets_live.nim:5,21,77` (comments naming `ChainedHandles`), `:80,90,92,99` (code: builds via `addEmailQueryWithSnippets`, extracts via `getBoth`, reads `pair.first`/`pair.second`) — **code compiles unchanged under b** (uses the `EmailQuerySnippetChain` alias + `getBoth` symbol + exported fields, never the bare `ChainedHandles` name); comments to uplift.
- `tests/protocol/tmail_builders.nim:550,561-562,639-640,806-808,928-930` etc. — compound `EmailCopy`/`EmailSubmission` `getBoth` + `.primary`/`.implicit` reads (unaffected by b)
- `tests/protocol/tconvenience.nim:104-183` — convenience `getBoth` (unaffected)
- `tests/stress/tadversarial_mail_f.nim`, `tests/stress/tadversarial_mail_g.nim` — compound adversarial `getBoth` (unaffected)
- `tests/mfixtures.nim:2008-2018,2376-2387` — `makeEmailCopyHandles`/`makeEmailSubmissionHandles` (compound; unaffected)

### Docs (uplift, not compile)
- `docs/design/00-architecture.md:553-554,2089-2105,3198-3212,3418,3487-3488`
- `docs/TODO/pre-1.0-api-alignment.md:201-209,338,1570-1571,2308-2331,3609`

---

## Proposed cut

### Recommended: (b) demote `Chained*`

**(b-minimal)** — pure visibility demotion, zero behaviour change:

1. `src/jmap_client/internal/protocol.nim:37-38` — extend the filter:
```nim
export dispatch except
  initResponseHandle, initNameBoundHandle, initDispatchedResponse, response, builderId,
  ChainedHandles, ChainedResults, registerChainableMethod
```
2. Everything else in `dispatch.nim` stays as-is: `ChainedHandles`/`ChainedResults`/`getBoth(ChainedHandles)`/`registerChainableMethod` remain `*`-exported for cross-internal reach. `mail_methods.nim` and `mail_entities.nim` import `dispatch` directly, so they still see them.
3. `EmailQuerySnippetChain` (alias, `mail_methods.nim:333`) stays hub-public via `mail.nim:18 export mail_methods`. Application code names `EmailQuerySnippetChain`, never `ChainedHandles`.

**Serde adapts:** none. No wire types, no `fromJson`/`toJson` touched. The handle types carry a captured `ParseProc[T]` closure only; serde is unchanged.

**Callers adapt:**
- Hub consumers (`import jmap_client`): can no longer name `ChainedHandles`/`ChainedResults`/`registerChainableMethod`. They never did — only `addEmailQueryWithSnippets` + `EmailQuerySnippetChain` + `getBoth` + `.first`/`.second` field reads, all of which keep working (field visibility is governed by the `*` on the field at `dispatch.nim:425-426,430-431`, not by hub re-export; the `getBoth(ChainedHandles)` overload resolves through the un-filtered `getBoth` symbol).
- Internal consumers (`mail_methods.nim`, `mail_entities.nim`): unchanged (direct `import ./…/dispatch`).

**Principles served:** P9 (two context types per concept — the hub now exposes exactly `CompoundHandles`/`CompoundResults` as the generic paired-handle surface); P5 (single public layer — the generic chain plumbing becomes internal); P7 (minimum surface).

**(b-clean)** [preferred under the no-dead-code mandate] — also delete the single-use generic:

1. Delete `ChainedHandles` (`dispatch.nim:419`), `ChainedResults` (`:428`), `getBoth(ChainedHandles)` (`:433-444`), `registerChainableMethod` (`:446-455`) from `dispatch.nim`.
2. Delete the three `registerChainableMethod(...)` calls at `mail_entities.nim:390,393,396` (and the two explanatory comments at :391-392,394-395).
3. In `mail_methods.nim`, replace the `EmailQuerySnippetChain` *alias* (`:333-339`) with a bespoke record + extractor mirroring `EmailQueryThreadChain`/`EmailQueryThreadResults`/`getAll` (`mail_builders.nim:444-481`):
```nim
type EmailQuerySnippetChain* {.ruleOff: "objects".} = object
  query*: ResponseHandle[QueryResponse[Email]]
  snippets*: ResponseHandle[SearchSnippetGetResponse]
type EmailQuerySnippetResults* {.ruleOff: "objects".} = object
  query*: QueryResponse[Email]
  snippets*: SearchSnippetGetResponse
func getBoth*(dr: DispatchedResponse, handles: EmailQuerySnippetChain):
    Result[EmailQuerySnippetResults, GetError] =
  let query = ?dr.get(handles.query)
  let snippets = ?dr.get(handles.snippets)
  ok(EmailQuerySnippetResults(query: query, snippets: snippets))
```
   and update the constructor at `:364` to `EmailQuerySnippetChain(query: queryHandle, snippets: snippetHandle)`.
4. Then `dispatch.nim` carries exactly the two compound context types and nothing chain-shaped; no hub-filter line is even needed for `Chained*` (they no longer exist). `protocol.nim:37-38` stays unchanged.

**(b-clean) caller adaptation:** `temail_query_with_snippets_live.nim:92,99` reads `pair.first`/`pair.second` → become `pair.query`/`pair.snippets` (2 lines + 3 comment lines). No other code site touches these.

**Principles served (b-clean):** all of (b-minimal), plus the clean-refactor invariant (no generic kept alive for a single instantiation) and consistency with the `EmailQueryThreadChain` precedent (chains are bespoke records co-located with their builder).

### Rejected: (a) merge to `HandlePair[A,B]` + `HandlePairKind`

A merged type must hold *either* `(primary: ResponseHandle[A], implicit: NameBoundHandle[B])` *or* `(first: ResponseHandle[A], second: ResponseHandle[B])` — the second handle has a **different type** per mode (`NameBoundHandle[B]` vs `ResponseHandle[B]`), forcing a **generic case object**:
```nim
type HandlePairKind* = enum hpkCompound, hpkChained
type HandlePair*[A, B] {.ruleOff: "objects".} = object
  head*: ResponseHandle[A]
  case kind*: HandlePairKind
  of hpkCompound: implicit*: NameBoundHandle[B]
  of hpkChained: tail*: ResponseHandle[B]
```
This is rejected because:
- It introduces a **generic case object under `{.experimental: "strictCaseObjects".}`** — every variant-field read (`handles.implicit`, `handles.tail`) must be inside a `case handles.kind of …` arm, including inside `getBoth`; and a case object needs hand-written `==`/`$`/`hash` if any equality is ever forced (per `nim-type-safety.md`).
- It **renames `CompoundResults.primary/implicit` → `first/second`** (or `head/tail`), churning ~14 read sites: `dispatch.nim:393-394`, `submission_builders.nim:203`(doc), `temail_submission_on_success_destroy_live.nim:101,107`, `temail_submission_on_success_update_live.nim:118,124`, `tmail_builders.nim:561-562,639-640,806-808,928-930`, `tadversarial_mail_f.nim:1232-1233` — plus the 4 chained reads.
- The domain aliases lose type-level meaning: `EmailCopyHandles`/`EmailSubmissionHandles`/`EmailQuerySnippetChain` can no longer be plain `= HandlePair[A,B]` aliases (an alias cannot pin `kind`), so each construction site must pass a runtime `kind: hpkCompound`/`hpkChained` literal.
- A25 cost: `tests/wire_contract/type-shapes.txt` **does not exist** (the dir holds only `error-messages.txt`, `module-paths.txt`, `tsnapshot_well_formed.nim`), so (a)'s mandate to "record the `HandlePairKind` enum in type-shapes.txt" means standing up new snapshot infrastructure.

Net: (a) maximises churn and adds a hazardous generic case object to buy nothing the two flat types didn't already give.

---

## Hazards

- **strictCaseObjects / generic case object** — *only a hazard for (a).* (b) introduces no case object. If (a) were taken, every `handles.implicit`/`handles.tail` read must be `case`-guarded, and `==`/`$`/`hash` become mandatory hand-written arm-dispatch funcs.
- **nimalyzer `objects` rule** — the existing four types already carry `{.ruleOff: "objects".}` (`dispatch.nim:368,377,419,428`). Under (b-clean) the new bespoke `EmailQuerySnippetChain`/`EmailQuerySnippetResults` must carry `{.ruleOff: "objects".}` exactly like `EmailQueryThreadChain` (`mail_builders.nim:444,455`). Do not relax the rule.
- **`export … except` filtering granularity** — `getBoth` is one overloaded symbol; you cannot filter only the `ChainedHandles` overload. (b-minimal) deliberately leaves `getBoth` un-filtered so the overload stays callable for `EmailQuerySnippetChain`; only the *type names* and `registerChainableMethod` go in the `except` list. This is correct and intended — an un-feedable overload is invisible without a `ChainedHandles`-typed value in scope.
- **Alias vs hub re-export** — under (b-minimal), `EmailQuerySnippetChain = ChainedHandles[...]` is re-exported through `mail.nim` while `ChainedHandles` is filtered from `protocol.nim`. This is sound: Nim type aliases are transparent, and field visibility (`first*`/`second*`) is fixed at the field definition, independent of which hub re-exports the type. No `UnusedImport`/`declared` conflict arises.
- **`{.push raises: [], noSideEffect.}` (L3 func-only)** — both variants stay pure; no new `proc`, no IO. (b-clean)'s new `getBoth` is a `func` with `?`-propagation, matching `getAll` at `mail_builders.nim:464`.
- **ARC / copy semantics** — the handle types embed `ParseProc[T]` closures (ref-counted); they are freely copyable (unlike `BuiltRequest`). `getBoth` takes `handles` by value — fine; no `sink`/`lent` concern.
- **`mixin fromJson`** — (b-clean)'s co-located `getBoth` in `mail_methods.nim` resolves `Email`/`SearchSnippetGetResponse` `fromJson` through the handle's captured closure (set at `initResponseHandle`), so no `mixin` is needed at the new extraction site (same as `dispatch.get`); `getAll` at `mail_builders.nim:472` still writes a defensive `mixin fromJson` — harmless to mirror or omit.

---

## Audit / test impact

**Required (b-minimal):**
- `tests/compile/tcompile_a1b_protocol_hub_surface.nim`: move `:54` `declared(ChainedHandles)`, `:55` `declared(ChainedResults)`, and `:64` `declared(registerChainableMethod)` from the POSITIVE block into the NEGATIVE block (`:131+`) as `doAssert not declared(ChainedHandles)` / `…ChainedResults` / `…registerChainableMethod`. Add a one-line comment citing B9. This is the freeze gate that mechanically pins the demotion.
- No other compile/property/snapshot test changes required: `tcompile_a1d`, `tcompile_mail_f`, `tcompile_mail_g`, `trfc_8620` all assert only Compound/convenience symbols. `tests/wire_contract/` snapshots contain none of these names (no `type-shapes.txt`), so no snapshot relabelling.

**Additional for (b-clean):**
- Same `tcompile_a1b` flips, plus assert `not declared(ChainedHandles/ChainedResults)` reflect *deletion* (still passes).
- `temail_query_with_snippets_live.nim:92,99` field reads `pair.first`/`pair.second` → `pair.query`/`pair.snippets`; comments `:5,21,77` uplifted off `ChainedHandles`.
- Optionally add a positive `tcompile_a1d`/`tcompile_mail_*` assertion for `EmailQuerySnippetChain`/`EmailQuerySnippetResults` + their `getBoth` to pin the new bespoke surface (parity with the existing `EmailQueryThreadChain` coverage at `tmail_methods.nim:329-338`).
- No unit/serde/property test depends on the generic `Chained*`; the compound-side adversarial suites (`tadversarial_mail_f/g`, `tmail_builders`) are entirely Compound and stay green.

---

## Open questions

1. **registerCompoundMethod also hub-private?** `registerCompoundMethod` (kept public under b) and the demoted `registerChainableMethod` are both only ever called at module scope in the hub-private `mail_entities.nim`; application code has no call site for either. Strictly, B9 only mandates moving the `Chained*` family. **Recommendation:** keep `registerCompoundMethod` public for now (it is the documented A1b surface and out of B9's stated scope); if a follow-up tightens it, demote both together. Not freeze-blocking.
2. **(b-minimal) vs (b-clean).** Both satisfy P9 at the surface. **Recommendation: (b-clean)** — the clean-refactor ground rule forbids keeping a generic alive for exactly one instantiation, and the `EmailQueryThreadChain` precedent already establishes "bespoke chain record co-located with its builder" as the house style. Take (b-minimal) only if the execution window cannot absorb the `mail_methods.nim` rewrite + the 2 live-test field renames. Either way the public commitment is identical: `Compound*` is the only generic paired-handle surface; chains are reached through named per-method records.
3. **`getBoth` overload sprawl.** After (b-clean), `getBoth` overloads are: 1 in `dispatch.nim` (Compound), 3 in `convenience.nim`, 1 in `mail_methods.nim` (EmailQuerySnippet), plus `getAll` in `mail_builders.nim`. This is consistent (each monomorphic overload co-located with its result type) and does not breach P9 (P9 caps *context types*, not *function overloads*). No action needed; just update the `docs/design/00-architecture.md:3418` "four getBoth overloads" tally during doc uplift.