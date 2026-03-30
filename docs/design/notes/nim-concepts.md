# Nim Concepts Reference Note

A reference on Nim's `concept` feature: what it is, how both syntax generations
work, what the compiler actually implements, and where the sharp edges are.

Sources: Nim manual (`doc/manual.md`), experimental manual
(`doc/manual_experimental.md`), compiler source (`compiler/concepts.nim`),
changelog 1.6.0, and the full test suite under `tests/concepts/`.


## What Concepts Are

Concepts are user-defined type classes. They define a set of requirements (proc
signatures, operators, field accesses) that a type must satisfy. Any type that
satisfies the requirements matches the concept -- retroactively, without the
type declaring anything. This is structural typing at compile time.

```nim
type
  Comparable = concept
    proc cmp(a, b: Self): int
```

Any type `T` for which `proc cmp(a, b: T): int` exists will match `Comparable`.


## Two Syntax Generations

There are two coexisting syntaxes. Both compile. They have different semantics
and different levels of compiler support.

### v1 -- Experimental (named instance variables)

Documented in `manual_experimental.md`. Uses named identifiers after the
`concept` keyword to represent instances of the type being matched:

```nim
type
  Stack[T] = concept s, var v
    s.pop() is T
    v.push(T)
    s.len is Ordinal
    for value in s:
      value is T
```

The body is expression-oriented: any expression that compiles for the tested
type counts as a match. The `is` operator checks return types. Type modifiers
(`var`, `ref`, `ptr`, `static`, `type`) can be applied to instance variables.

A concept matches if:
1. All expressions in the body compile for the tested type
2. All statically evaluable boolean expressions in the body are true
3. All type modifiers match their respective definitions

### v2 -- Current (Self)

Documented in `manual.md`. Introduced in Nim 1.6.0 (PR #15251, RFC #168).
Uses the special `Self` type instead of named variables:

```nim
type
  Comparable = concept
    proc cmp(a, b: Self): int

  Indexable[I, T] = concept
    proc `[]`(x: Self; at: I): T
    proc `[]=`(x: var Self; at: I; newVal: T)
    proc len(x: Self): I
```

The body consists of proc/func/iterator/template/macro/converter definitions.
`Self` refers to the type being matched (the "implementation"). The compiler
header states: *"this is a first implementation and only the 'Concept matching'
section has been implemented."*

The 1.6.0 changelog notes: *"The new design does not rely on `system.compiles`
and may compile faster."*

### Deprecated alias

`generic` was previously an alias for `concept`. Removed in Nim 0.18.1.


## Concept Variants

### Atomic concepts

No generic type variables. All types in definitions are concrete (or `Self`):

```nim
type
  Hashable = concept
    proc hash(x: Self): int
```

### Container / parameterised concepts

Have generic type variables bound to concrete types:

```nim
type
  Indexable[I, T] = concept
    proc `[]`(x: Self; at: I): T
    proc len(x: Self): I
```

### "Gray" concepts

No generic variables, but definitions contain unbound generics. The manual
warns: *"This kind of concept may disrupt the compiler's ability to type check
generic contexts, but it is useful for overload resolution."*

```nim
type
  Processor = concept
    proc process[T](s: Self; data: T)
```


## Overload Resolution

Concepts participate in overload disambiguation. The compiler uses simplified
specificity rules:

1. Concept vs `T`/`auto`: concept is more specific
2. Concept vs concept: deferred to subset matching
3. Concept vs anything else: concept is less specific

### Subset matching

When comparing concepts `C1` and `C2`: if every valid implementation of `C1`
is also a valid implementation of `C2` but not vice versa, `C1` is a subset
of `C2`, and `C2` is preferred as more specific. If neither is a subset, the
concept with the most definitions wins. No winner = ambiguity error.

### First-match semantics

The matcher evaluates to a successful match on the **first acceptable
candidate** for each binding. Consequences:

- Generic parameters are fulfilled by the first match even if alternatives exist
- Object inheritance depth is not accounted for in matching

### Proc matching rules (v2, from compiler source)

- `proc`/`func` definitions in a concept match any of:
  `{skProc, skTemplate, skMacro, skFunc, skMethod, skConverter}`
- `template`, `macro`, `converter`, `method`, `iterator` definitions are
  more restrictive and match only their own kind
- Extra parameters in candidate procs are allowed if they have default values
- `func` in a concept body does **not** enforce `.noSideEffect` on the
  matched implementation (compiler comment: *"XXX: Enforce .noSideEffect
  for 'nkFuncDef'? But then what are the use cases..."*)


## Recursive and Co-dependent Concepts

Concepts can reference themselves, which is useful for matching through
`distinct` type chains:

```nim
type
  Primitive = concept x
    x is PrimitiveBase or distinctBase(x) is Primitive

  Handle = distinct int
  SpecialHandle = distinct Handle

assert Handle is Primitive       # 1 level
assert SpecialHandle is Primitive # 2 levels
```

Concepts can be mutually recursive (co-dependent):

```nim
type
  Serializable = concept
    proc serialize(s: Self; writer: var Writer)
  Writer = concept
    proc write(w: var Self; data: Serializable)
```

The compiler uses cycle detection via a `HashSet` of `(conceptId, typeId)`
pairs. When a pair is encountered again, the match returns `true`
(coinductive semantics). There is no hardcoded recursion depth limit.
Test suite validates chains up to 5+ levels deep and 3-way mutual recursion.


## v1-Only Features

These features are documented in `manual_experimental.md` and only work with
the old-style named-variable syntax.

### Concept derived values

Types and constants declared in the concept body are accessible via dot
operator on matched types:

```nim
type
  DateTime = concept t1, t2, type T
    const Min = T.MinDate
    type TimeSpan = typeof(t1 - t2)
    t1 + TimeSpan is T

proc f(events: Enumerable[DateTime]): float =
  var interval: DateTime.TimeSpan  # resolved from the matched type
```

### Concept refinement with `of`

Concepts can inherit from other concepts:

```nim
type
  Graph = concept g, type G of EquallyComparable, Copyable
    type VertexType = G.VertexType

  IncidenceGraph = concept of Graph
    # symbols from Graph are automatically in scope
    g.source(e) is VertexType
```

### `{.explain.}` pragma

Apply to the concept or a call-site to get compiler hints about why matching
failed:

```nim
type
  MyConcept {.explain.} = concept x
    x.foo is int

someProc(x, y, z) {.explain.}
```

Diagnostic output includes messages like `"undeclared field: 'foo'"` and
`"concept predicate failed"`.

### `bind once` / `bind many` with `distinct`

Without `distinct`, a type variable is inferred once and locked. The `distinct`
modifier allows different bindings:

```nim
type
  MyConcept = concept o
    o.foo is distinct Enumerable  # could be Enumerable[int]
    o.bar is distinct Enumerable  # could be Enumerable[float]
```


## Compile-Time Testing

Use `is` and `isnot` to test concept matching:

```nim
assert int is Comparable
assert string isnot Comparable
```


## Unimplemented / Planned Features

These are documented in `manual_experimental.md` but commented out with RST
`..` directives, meaning they are **not implemented**:

### Converter type classes

Would use `return` in concept body to enable type conversion:

```nim
type
  Stringable = concept x
    $x is string
    return $x
```

### VTable types

Would convert concepts to fat pointers for runtime polymorphism via `vtref`
and `vtptr` magic keywords:

```nim
type
  IntEnumerable = vtref Enumerable[int]
```

Neither feature is available in any current Nim version.


## Known Limitations and Sharp Edges

### Generic type checking not implemented (v2)

The manual states: *"Generic type checking is forthcoming, so this will only
explain overload resolution for now."* Concepts currently help with overload
selection but do not check generic proc bodies against concept constraints.

### Block scope issues (v2)

Test `tconceptsv2.nim` line 522 documents: *"this code fails inside a block
for some reason"*. An `Indexable[T]` concept with an `items` iterator had to
be defined at module scope. Concepts with iterator definitions may fail inside
`block:` scopes.

### `byref` pragma not respected

Issue #16897: concepts do not respect the 24-byte ABI rule or `{.byref.}`
pragma. Values that should be passed by reference may be copied.

### `mArrGet`/`mArrPut` magic workaround

The compiler explicitly notes that `[]` and `[]=` magic in `system.nim` is
*"wrong"* and *"cannot be fixed that easily"*. Concept matching special-cases
these operators for `tyArray`, `tyOpenArray`, `tyString`, `tySequence`,
`tyCstring`, and `tyTuple` to avoid false matches.

### Implicit generic concept-derived values broken

Test `tmatrixconcept.nim` marks `m.TotalElements`, `m.FromFoo`, `m.FromConst`
with `XXX: fix these` -- concept-derived static values do not work in
implicit generic procs.

### `var`/modifier asymmetry

`var`, `sink`, `lent`, `owned` modifiers in a concept definition require the
implementation to also have them, but the reverse is not true. An
implementation with `var` can match a concept without `var`.

### Concept keyword placement

`concept` is only valid inside `type` sections. Using it elsewhere produces:
*"the 'concept' keyword is only valid in 'type' sections"*.

### `--mm:refc` restrictions

Some concept tests (`tusertypeclasses.nim`) are restricted to `--mm:refc` and
may be broken under ARC/ORC.

### Stdlib adoption is minimal

Only two stdlib files use concepts:
- `lib/pure/typetraits.nim`: `Generic = concept f; type _ = genericHead(typeof(f))`
  (in a `runnableExamples` block)
- `lib/js/jsffi.nim`: `JsKey* = concept a, type T; cstring.toJsKey(T) is T`
  (as a constraint for `JsAssoc`)


## v2 Concept Body Grammar

Only these AST node kinds are valid inside a v2 concept body:

| Node kind        | Matches against                                           |
|------------------|-----------------------------------------------------------|
| `nkProcDef`      | `{skProc, skTemplate, skMacro, skFunc, skMethod, skConverter}` |
| `nkFuncDef`      | Same as `nkProcDef` (no side-effect enforcement)          |
| `nkTemplateDef`  | `{skTemplate}`                                            |
| `nkMacroDef`     | `{skMacro}`                                               |
| `nkConverterDef` | `{skConverter}`                                           |
| `nkMethodDef`    | `{skMethod}`                                              |
| `nkIteratorDef`  | `{skIterator}`                                            |
| `nkCommentStmt`  | Always matches (ignored)                                  |
| `nkStmtList`     | Recurse into children                                     |

Anything else produces: `"unexpected construct in the new-styled concept"`.


## Relevance to This Project

This project uses distinct types extensively (`Id`, `AccountId`, `JmapState`,
etc.) with smart constructors. Concepts could potentially:

- Define a `JmapIdentifier` concept matching any type with `init`/`value` procs
- Constrain generic serialisation procs to types implementing a `Serializable`
  concept
- Replace some uses of `SomeId = Id | AccountId | ...` union types

However, given the experimental status, minimal stdlib adoption, known compiler
bugs (`byref`, block scope, implicit generics), and the explicit note that
generic type checking is not yet implemented, concepts should be adopted
cautiously if at all.

**Decision:** do not use concepts in production code for now. The `distinct`
type + smart constructor + `Result` pattern already provides the compile-time
safety guarantees that concepts would offer, without the risk of hitting
compiler bugs. Revisit when generic type checking is implemented and the
v2 syntax stabilises.
