Potential Macro Tests to Add:

Tier 1 — Do these now

  1. assert / doAssert ban in @src (L1 to L5) (highest value, ~30 lines)

  Contract it defends. AssertionDefect is the exact analogue of FieldDefect — a defect, not a checked exception, so {.push
  raises: [], noSideEffect.} doesn't see it. Under --panics:on, assert x == y failing = rawQuit(1) = silent FFI kill.

  The pattern. Walk src/jmap_client/**/*.nim, flag any assert or doAssert call. The whole
  detection is a single nnkCall match on the callee ident.

  Why this is urgent. Your existing {.push raises: [], noSideEffect.} pragma is doing heavy lifting, but
  it leaves AssertionDefect open. Right now nothing prevents a contributor from writing doAssert bp.body.kind == ebkFlat as a
  "safety check" — which under panics:on is worse than no check at all (kills the process vs. returning an error). The fix is
  mechanical: convert to Result or remove.

  2. Raw seq/openArray indexing audit

  Contract it defends. IndexDefect from s[0], s[^1], s[i] where i isn't provably in bounds. The common panic-surface form:

  let first = parts[0]                  # panic if parts is empty
  let last = parts[^1]                  # panic if parts is empty
  for i in 0 ..< parts.len: parts[i+1]  # panic at last iteration

  The pattern. Flag any nnkBracketExpr whose index is a literal 0, ^1, or an arithmetic expression — UNLESS the enclosing scope
   has a preceding if parts.len > 0: guard or a for ... in parts: / for i in 0 ..< parts.len: loop pattern. The "preceding
  guard" half is the same early-exit detection Step 23's walkStmtList already implements — you could share logic.

  The false-positive risk. Real. Iterator-based access (for part in parts:) is always safe; index arithmetic inside a
  properly-bounded loop is safe; the macro has to recognise both. But it's still tractable.

  3. Table[key] without in guard

  Contract it defends. KeyError is technically a CatchableError, not a defect — so {.raises: [].} actually does catch it, which
   means std/tables lookups with [] produce compile errors in your L1–L3 code already. But the compiler error points at [], not
   at the habit of using [] instead of hasKey/getOrDefault. A macro can give a better diagnostic:

  Error: Table lookup `extraHeaders[name]` may raise KeyError —
    use `in` guard or `.getOrDefault(name)` instead

  The pattern. Any nnkBracketExpr whose left operand type-resolves to Table[...] (you don't actually need type resolution — the
   macro can just flag every bare [] on an identifier whose name is in an allowlist of known-Table fields, mirroring the
  Guarded whitelist approach). Low false-positive rate because the codebase is small.

  Tier 2 — Worth doing, higher complexity

  4. ref / ptr types banned  (nil-safety)

  Contract. NilAccessDefect from someRef[] when someRef == nil. The project already uses Opt[T] discipline — a macro can
  enforce it structurally by forbidding ref object declarations anywhere in L1–L3.

  The pattern. Walk type sections in each L1–L3 module; emit error on any nnkRefTy in a type definition. Trivial (~20 lines).

  Why Tier 2 not Tier 1. Unlike assert, the convention is already well-established and the codebase probably has zero
  violations today. Low discovered-bug value, but high regression-prevention value for new contributors.

  5. L5 export-pragma audit (defer until Parts F–I)

  Every {.exportc.} must carry dynlib, cdecl, raises: []. Easy to audit, but src/jmap_client.nim hasn't been populated yet —
  the check would be vacuous today. Add it alongside the first real FFI export so it can't regress.

  Tier 3 — Dishonourable mentions (tempting but don't bother)

  - Integer overflow audit. Needs value-range analysis; compile-time macros can't do this tractably. Rely on floatChecks:on +
  explicit-width integers at the FFI boundary instead.
  - Stack-depth audit for recursion. Needs flow analysis. Use runtime depth limits (you already do in bpToJsonImpl).
  - range[T] audit. Already discouraged by nim-type-safety.md; I'd audit it in code review, not statically — the false-positive
   risk on legitimate range[0..255] for C-compat types is too high.
