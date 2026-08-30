# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

discard """
  action: "compile"
"""

## Tier-1 raw-index audit: under ``--panics:on`` an out-of-bounds index is
## ``rawQuit(1)`` — a silent host-process kill through the C ABI. Every
## bracket access on a seq/string/openArray with a literal, ``^``-terminal
## or arithmetic index must sit behind a length guard or inside a bounded
## loop. The macro flags violations at compile time; fix the code, never
## the audit.
##
## Nim declares roughly twenty ``Defect`` subtypes, none of which
## ``{.raises: [].}`` can see. Three are audited in this directory:
## ``AssertionDefect`` by ``tno_asserts_in_src.nim``, ``FieldDefect`` by
## ``tffi_panic_surface.nim``, and here ``IndexDefect`` tree-wide plus
## ``RangeDefect`` at the C ABI boundary (below). The rest —
## ``NilAccessDefect``, ``OverflowDefect``, ``DivByZeroDefect``,
## ``StackOverflowDefect`` and the floating-point family among them —
## have no audit anywhere in this repository.
##
## The C ABI narrowing rule
## ------------------------
## A second, separately scoped rule runs over ``src/jmap_client.nim``
## alone. Narrowing a caller-supplied ``csize_t`` — ``int(i)`` on an
## index, ``int(n)`` on a count — raises ``RangeDefect`` when the value
## exceeds the target's range, and ``SIZE_MAX`` is the ordinary result of
## an ``n - 1`` underflow in C caller code. The rule requires every such
## conversion to sit behind a comparison made *in the unsigned domain*
## (``if i >= csize_t(xs.len): return nil``), because a comparison that
## narrows first has already raised. It is deliberately confined to the
## one file that exports ``cdecl`` symbols declared ``raises: []``, where
## an escaping defect is ``rawQuit(1)`` rather than a stack unwind.
##
## What the audit reads
## --------------------
## Every ``.nim`` file under ``src/``, enumerated with ``walkDirRec`` and
## parsed with ``parseStmt``. An empty listing is rejected outright, and
## so is a file that reads back empty. Reading happens inside the macro
## body, where a missing path raises a normal compile error; the same
## ``staticRead`` written as a ``static[string]`` macro *argument* is
## constant-folded under an error trap that discards the diagnostic and
## substitutes ``""``, so a stale path written that way audits an empty
## file and still passes.
##
## What the audit cannot reach
## ---------------------------
## ``parseStmt`` yields an *untyped* AST, so no expression here has a
## type. Four consequences, all of them permanent:
##
## - Tuple, array and ``JsonNode`` indexing is indistinguishable from seq
##   indexing. ``pair[0]`` on a tuple cannot raise, but the audit sees the
##   same node it sees for ``parts[0]``. Such sites live in ``Exempt``.
## - A collection is named by its source text, so two same-named locals
##   share one key. Facts are dropped at every routine boundary and at the
##   end of every statement list, which confines the confusion to one
##   routine, but two locals called ``parts`` within one routine still
##   share a key and a guard on either satisfies an index on the other.
## - Only ``len``-versus-integer-literal comparisons are understood.
##   ``if remaining >= 2`` where ``remaining = s.len - i`` proves nothing
##   here, and neither does a postcondition of a called function (``split``
##   always returns at least one element; the audit cannot know that).
## - An index whose expression is arithmetic (``s[i + 1]``) admits no
##   length fact that would discharge it, so it is always reported unless
##   exempted.
##
## Sites in those categories are listed in ``Exempt`` with a reason. The
## table is self-verifying: an entry that matches nothing is a compile
## error, so a deleted or rewritten site cannot leave a stale exemption
## quietly widening the audit's blind spot.
##
## The audit is a *syntactic* check. It does not prove absence of
## ``IndexDefect``: a bare identifier index (``s[i]``) is out of scope by
## construction — flagging every one of them would drown the signal — and
## slice expressions (``s[a ..< b]``) are not examined either. The
## narrowing rule inherits the same limits and adds one of its own: it
## recognises a bound check only in the shape described above, so a check
## expressed some other way reads as absent and is reported.

import std/[macros, os, strutils]

type FactKind = enum
  ## What kind of conclusion a guard in scope has established.
  fkMinLen ## The named collection holds at least ``minLen`` elements.
  fkUnsignedBound
    ## The named ``csize_t`` parameter was compared against a
    ## ``csize_t`` bound, so narrowing it cannot overflow.

type Fact = tuple[kind: FactKind, name: string, minLen: int]
  ## A guard's conclusion, valid for the scope that guard encloses.
  ## ``minLen`` is meaningful for ``fkMinLen`` only.

type IndexNeed = enum
  ## What discharging one bracket access would take.
  inIgnored ## Not an audited index shape (bare ident, slice, type argument).
  inLength ## Satisfied by a proven minimum length.
  inUnprovable ## Arithmetic index — no length fact can discharge it.

## Sites the untyped AST cannot decide, each with the reason it is safe.
## A row is matched by path suffix and expression text with no line
## number, so it also covers any *later* occurrence of the same
## expression anywhere in the same file — several rows already discharge
## more than one site. Keep the expressions specific for that reason.
const Exempt: seq[tuple[file, expr, why: string]] = @[
  # Tuple element access — `it` is the (CreationId, payload) pair bound
  # by `validateUniqueByIt`; a tuple index is resolved at compile time.
  ("internal/mail/email.nim", "it[0]", "tuple element"),
  ("internal/mail/email_submission.nim", "it[0]", "tuple element"),
  ("internal/mail/email_update.nim", "it[0]", "tuple element"),
  ("internal/mail/identity.nim", "it[0]", "tuple element"),
  ("internal/mail/mailbox.nim", "it[0]", "tuple element"),
  # `variables` is a const array of (name, value) pairs; both the outer
  # index and the tuple index are checked by the compiler.
  ("internal/types/session.nim", "variables[i][0]", "tuple element"),
  ("internal/types/session.nim", "variables[i][1]", "tuple element"),
  # `remaining = s.len - i` bounds both reads; the audit reasons about
  # `len` comparisons only, not about derived arithmetic.
  ("internal/types/credential.nim", "s[i + 1]", "guarded by `remaining >= 2`"),
  ("internal/types/credential.nim", "s[i + 2]", "guarded by `remaining >= 3`"),
  # SubmissionParam payloads are tuples destructured by index.
  ("internal/mail/serde_submission_envelope.nim", "oc[0]", "tuple element"),
  ("internal/mail/serde_submission_envelope.nim", "oc[1]", "tuple element"),
  ("internal/mail/serde_submission_envelope.nim", "by[0]", "tuple element"),
  ("internal/mail/serde_submission_envelope.nim", "by[1]", "tuple element"),
  ("internal/mail/serde_submission_envelope.nim", "ext[1]", "tuple element"),
  # Fixed-size array; the compiler bounds-checks the literal index.
  ("src/jmap_client.nim", "emptyWireBuf[0]", "array[1, byte]"),
  # `NonEmptySeq` / `NonEmptyIdSeq` carry non-emptiness as a
  # constructor invariant; `head` is the accessor that spends it.
  ("internal/types/primitives.nim", "a.rawValue[0]", "non-empty by construction"),
  # `?detectDate` two lines above returns unless `raw.len >= 20`; the
  # audit does not follow a callee's guarantees back to its caller.
  ("internal/types/primitives.nim", "raw[^1]", "`?detectDate` proved `len >= 20`"),
  # `hasComp` is the let-bound alias for `compParts.len == 2`; the
  # audit reads conditions, not names bound to them.
  ("internal/mail/submission_mailbox.nim", "compParts[0]", "guarded by `hasComp`"),
  ("internal/mail/submission_mailbox.nim", "compParts[1]", "guarded by `hasComp`"),
  # `split` yields at least one element for any input, including "".
  ("internal/mail/submission_status.nim", "allLines[^1]", "`split` yields >= 1"),
  # One code per line, and `splitReplyLines` Errs on zero lines.
  ("internal/mail/submission_status.nim", "codes[0]", "one code per non-empty line"),
  # `?expectLen` above each read fixes the JSON array's arity, then
  # `getElems` projects it one-for-one into the seq being indexed.
  ("internal/serialisation/serde_framework.nim", "children[0]", "`?expectLen(_, 1)`"),
  ("internal/serialisation/serde_envelope.nim", "elems[0]", "`?expectLen(_, 3)`"),
  ("internal/serialisation/serde_envelope.nim", "elems[1]", "`?expectLen(_, 3)`"),
  ("internal/serialisation/serde_envelope.nim", "elems[2]", "`?expectLen(_, 3)`"),
]

proc collKey(n: NimNode): string =
  ## Stable textual key naming the collection an index or ``len`` refers
  ## to. Identifiers, dotted chains and literal-indexed elements are
  ## nameable (``parts[0].len`` keys as ``parts[0]``); every other shape
  ## yields the empty string, which callers read as "cannot name this".
  case n.kind
  of nnkIdent, nnkSym:
    $n
  of nnkDotExpr:
    let base = collKey(n[0])
    if base.len == 0 or n[1].kind notin {nnkIdent, nnkSym}:
      ""
    else:
      base & "." & $n[1]
  of nnkBracketExpr:
    let base =
      if n.len == 2 and n[1].kind == nnkIntLit:
        collKey(n[0])
      else:
        ""
    if base.len == 0:
      ""
    else:
      base & "[" & $n[1].intVal & "]"
  else:
    ""

proc lenTarget(n: NimNode): string =
  ## The collection whose length ``n`` computes — ``s.len`` and ``len(s)``
  ## both key as ``s``. Empty string when ``n`` is not a length expression.
  if n.kind == nnkDotExpr and n[1].kind in {nnkIdent, nnkSym} and $n[1] == "len":
    return collKey(n[0])
  if n.kind in {nnkCall, nnkCommand} and n.len == 2 and n[0].kind in {nnkIdent, nnkSym} and
      $n[0] == "len":
    return collKey(n[1])
  ""

proc impliedMin(
    op: string, k: BiggestInt, holds: bool
): tuple[ok: bool, m: BiggestInt] =
  ## Lower bound on a length implied by ``len <op> k`` evaluating to
  ## ``holds``. ``ok`` is false when the comparison implies no bound —
  ## ``len == 3`` being false, for instance, rules out nothing.
  if holds:
    case op
    of ">":
      (true, k + 1)
    of ">=", "==":
      (true, k)
    of "!=":
      (k == 0, 1.BiggestInt)
    else:
      (false, 0.BiggestInt)
  else:
    case op
    of "<", "!=":
      (true, k)
    of "<=":
      (true, k + 1)
    of "==":
      (k == 0, 1.BiggestInt)
    else:
      (false, 0.BiggestInt)

proc mirrorOp(op: string): string =
  ## The same comparison written with its operands swapped, so
  ## ``3 < s.len`` can be read as ``s.len > 3``.
  case op
  of "<": ">"
  of "<=": ">="
  of ">": "<"
  of ">=": "<="
  else: op

proc comparisonBounds(cond: NimNode, holds: bool): seq[Fact] =
  ## Bounds implied by one ``len``-versus-integer-literal comparison,
  ## in either operand order.
  result = @[]
  if cond.kind != nnkInfix or cond.len != 3:
    return
  let leftIsLen = lenTarget(cond[1]).len > 0
  let name =
    if leftIsLen:
      lenTarget(cond[1])
    else:
      lenTarget(cond[2])
  let lit =
    if leftIsLen:
      cond[2]
    else:
      cond[1]
  if name.len == 0 or lit.kind != nnkIntLit:
    return
  let op =
    if leftIsLen:
      $cond[0]
    else:
      mirrorOp($cond[0])
  let bound = impliedMin(op, lit.intVal, holds)
  if bound.ok:
    result.add (fkMinLen, name, int(bound.m))

proc isCsizeConv(n: NimNode): bool =
  ## True for ``csize_t(x)`` — the conversion that keeps a comparison in
  ## the unsigned domain instead of narrowing the parameter first.
  n.kind in {nnkCall, nnkCommand} and n.len == 2 and n[0].kind in {nnkIdent, nnkSym} and
    $n[0] == "csize_t"

proc unsignedCompare(cond: NimNode): tuple[name, op: string] =
  ## Decompose a comparison between a bare identifier and an explicit
  ## ``csize_t`` conversion into that identifier and the operator read
  ## with the identifier on the left. Empty name for any other shape.
  if cond.kind != nnkInfix or cond.len != 3:
    return ("", "")
  if cond[1].kind in {nnkIdent, nnkSym} and isCsizeConv(cond[2]):
    return ($cond[1], $cond[0])
  if cond[2].kind in {nnkIdent, nnkSym} and isCsizeConv(cond[1]):
    return ($cond[2], mirrorOp($cond[0]))
  ("", "")

proc unsignedFacts(cond: NimNode, holds: bool): seq[Fact] =
  ## ``p >= csize_t(n)`` failing, or ``p < csize_t(n)`` holding, keeps
  ## ``p`` inside the narrowing target's range. The bound must be an
  ## explicit ``csize_t`` conversion: that is what proves the comparison
  ## did not itself narrow before comparing.
  let cmp = unsignedCompare(cond)
  let bounded =
    if holds:
      cmp.op in ["<", "<="]
    else:
      cmp.op in [">", ">="]
  if cmp.name.len > 0 and bounded:
    @[(fkUnsignedBound, cmp.name, 0)]
  else:
    @[]

proc leafFacts(cond: NimNode, holds: bool): seq[Fact] =
  ## Both readings of one comparison: the length bound it proves, and the
  ## unsigned-domain check that makes a later narrowing safe.
  comparisonBounds(cond, holds) & unsignedFacts(cond, holds)

proc condFacts(cond: NimNode, holds: bool): seq[Fact] =
  ## Facts implied by ``cond`` evaluating to ``holds``. ``and``
  ## contributes both operands when true and ``or`` both negations when
  ## false — respectively the positive-branch and the early-exit
  ## direction. The converses imply nothing and yield an empty seq.
  if cond.kind == nnkPrefix and cond.len == 2 and $cond[0] == "not":
    return condFacts(cond[1], not holds)
  if cond.kind == nnkInfix and cond.len == 3 and $cond[0] in ["and", "or"]:
    let conjunction = $cond[0] == "and"
    if conjunction != holds:
      return @[]
    return condFacts(cond[1], holds) & condFacts(cond[2], holds)
  leafFacts(cond, holds)

const IterNames = ["items", "mitems", "pairs", "mpairs", "keys", "values"]

proc iterSource(iter: NimNode): string =
  ## The collection a ``for`` loop draws from: the upper bound of a
  ## ``0 ..< s.len`` range, the base of an ``s.items``-style call, or the
  ## collection itself. Empty string when the source cannot be named.
  if iter.kind == nnkInfix and iter.len == 3 and $iter[0] in ["..", "..<"]:
    return lenTarget(iter[2])
  if iter.kind == nnkDotExpr and iter[1].kind in {nnkIdent, nnkSym} and
      $iter[1] in IterNames:
    return collKey(iter[0])
  collKey(iter)

proc loopBounds(iter: NimNode): seq[Fact] =
  ## A ``for`` body runs only when its source yields, so ``for x in s``,
  ## ``for x in s.items`` and ``for i in 0 ..< s.len`` all prove
  ## ``s.len >= 1`` for the duration of the body.
  let source = iterSource(iter)
  if source.len > 0:
    @[(fkMinLen, source, 1)]
  else:
    @[]

proc indexNeed(idx: NimNode): tuple[need: IndexNeed, minLen: int] =
  ## Classify a bracket index. A literal ``k`` needs ``len >= k + 1``; a
  ## ``^k`` terminal index needs ``len >= k``; anything arithmetic is
  ## unprovable from length facts alone.
  if idx.kind == nnkIntLit:
    return (inLength, int(idx.intVal) + 1)
  if idx.kind == nnkPrefix and idx.len == 2 and $idx[0] == "^":
    return
      if idx[1].kind == nnkIntLit:
        (inLength, int(idx[1].intVal))
      else:
        (inUnprovable, 0)
  if idx.kind == nnkInfix and idx.len == 3 and $idx[0] in ["+", "-", "*", "div", "mod"]:
    return (inUnprovable, 0)
  (inIgnored, 0)

proc satisfied(stack: seq[Fact], name: string, minLen: int): bool =
  ## True when some enclosing guard proves ``name`` long enough.
  for f in stack:
    if f.kind == fkMinLen and f.name == name and f.minLen >= minLen:
      return true
  false

proc unsignedChecked(stack: seq[Fact], name: string): bool =
  ## True when some enclosing guard compared ``name`` in the unsigned
  ## domain, which is what makes narrowing it safe.
  for f in stack:
    if f.kind == fkUnsignedBound and f.name == name:
      return true
  false

proc isExit(body: NimNode): bool =
  ## True when the last statement of ``body`` unconditionally leaves the
  ## surrounding scope, which is what makes a preceding ``if`` an early
  ## exit whose negation holds for every later sibling.
  let tail =
    if body.kind == nnkStmtList and body.len > 0:
      body[^1]
    else:
      body
  tail.kind in {nnkReturnStmt, nnkBreakStmt, nnkContinueStmt, nnkRaiseStmt}

proc isEarlyExitIf(child: NimNode): bool =
  ## True for ``if cond: <exit>`` — a single-branch ``if`` whose body
  ## unconditionally exits.
  child.kind == nnkIfStmt and child.len == 1 and child[0].kind == nnkElifBranch and
    isExit(child[0][1])

type Ctx = object ## Everything the walker threads through one audit run.
  path*: string ## File currently being parsed, for the violation message.
  stack*: seq[Fact] ## Guards in force at the current node.
  problems*: seq[string] ## Violation lines, reported together at the end.
  used*: seq[int] ## Indices into ``Exempt`` that matched at least once.
  csizeParams*: seq[string]
    ## ``csize_t`` parameters of the enclosing routine; empty outside the
    ## C ABI entry point, which is what confines the narrowing rule to it.

proc exemptIndex(ctx: Ctx, node: NimNode): int =
  ## Position in ``Exempt`` covering this site, or ``-1``. The file half
  ## is a path suffix so the table stays independent of the checkout root.
  for i, e in Exempt:
    if ctx.path.endsWith(e.file) and repr(node) == e.expr:
      return i
  -1

proc walk(node: NimNode, ctx: var Ctx)
  ## Forward declaration — see implementation below for documentation.

proc walkScoped(node: NimNode, ctx: var Ctx, facts: seq[Fact]) =
  ## Walk ``node`` with ``facts`` in force, then drop them again.
  for f in facts:
    ctx.stack.add f
  walk(node, ctx)
  for _ in facts:
    discard ctx.stack.pop

proc walkIf(node: NimNode, ctx: var Ctx) =
  ## Visit an ``if``/``elif``/``else`` chain. A branch is reached only
  ## when every earlier condition failed, so each inherits their
  ## negations; an ``elif`` body additionally gets what its own condition
  ## proves. That is what makes ``if s.len <= 1: … else: s[^1]`` pass.
  var inherited: seq[Fact] = @[]
  for branch in node:
    if branch.kind notin {nnkElifBranch, nnkElifExpr}:
      walkScoped(branch[^1], ctx, inherited)
      continue
    walkScoped(branch[0], ctx, inherited)
    walkScoped(branch[1], ctx, inherited & condFacts(branch[0], true))
    inherited.add condFacts(branch[0], false)

proc walkShortCircuit(node: NimNode, ctx: var Ctx) =
  ## ``a and b`` evaluates ``b`` only when ``a`` holds, and ``a or b``
  ## only when ``a`` does not — so the right operand runs under the
  ## bounds the left one implies.
  walk(node[1], ctx)
  walkScoped(node[2], ctx, condFacts(node[1], $node[0] == "and"))

proc caseBranchBounds(selector: NimNode, branch: NimNode): seq[Fact] =
  ## An ``of`` arm of ``case s.len`` proves the smallest length its labels
  ## admit. Non-literal labels prove nothing and yield an empty seq.
  let name = lenTarget(selector)
  if name.len == 0 or branch.kind != nnkOfBranch:
    return @[]
  var lowest = -1
  for i in 0 ..< branch.len - 1:
    if branch[i].kind != nnkIntLit:
      return @[]
    let label = int(branch[i].intVal)
    if lowest < 0 or label < lowest:
      lowest = label
  if lowest < 0:
    @[]
  else:
    @[(fkMinLen, name, lowest)]

proc walkCase(node: NimNode, ctx: var Ctx) =
  ## Visit a ``case`` statement, giving each ``of`` arm the length bound
  ## its labels prove when the selector is a ``len`` expression.
  walk(node[0], ctx)
  for i in 1 ..< node.len:
    let branch = node[i]
    for j in 0 ..< branch.len - 1:
      walk(branch[j], ctx)
    walkScoped(branch[^1], ctx, caseBranchBounds(node[0], branch))

proc walkStmtList(node: NimNode, ctx: var Ctx) =
  ## Visit a statement list, threading the negation of every early-exit
  ## condition through the statements that follow it.
  var added = 0
  for child in node:
    walk(child, ctx)
    if not isEarlyExitIf(child):
      continue
    for b in condFacts(child[0][0], false):
      ctx.stack.add b
      inc added
  for _ in 0 ..< added:
    discard ctx.stack.pop

const L5EntryPoint = "/src/jmap_client.nim"

const Narrowing = [
  "int", "int8", "int16", "int32", "int64", "cint", "cshort", "clong", "clonglong",
  "uint8", "uint16", "uint32", "cuchar", "cushort", "cuint", "Natural", "Positive",
]

const RoutineDefs = {
  nnkProcDef, nnkFuncDef, nnkMethodDef, nnkIteratorDef, nnkConverterDef, nnkTemplateDef,
  nnkMacroDef,
}

proc csizeParamNames(routine: NimNode): seq[string] =
  ## Names of the routine's ``csize_t`` parameters — the caller-supplied
  ## widths a narrowing conversion can overflow on.
  result = @[]
  let formals = routine[3]
  if formals.kind != nnkFormalParams:
    return
  for i in 1 ..< formals.len:
    let defs = formals[i]
    if defs.kind != nnkIdentDefs or defs[^2].kind notin {nnkIdent, nnkSym} or
        $defs[^2] != "csize_t":
      continue
    for j in 0 ..< defs.len - 2:
      if defs[j].kind in {nnkIdent, nnkSym}:
        result.add $defs[j]

proc namedParam(n: NimNode, params: seq[string]): string =
  ## First ``csize_t`` parameter appearing anywhere in ``n``, or ``""``.
  ## A conversion of a derived expression (``int(n - 1)``) is judged on
  ## the parameter it derives from, which is the conservative reading.
  if n.kind in {nnkIdent, nnkSym} and $n in params:
    return $n
  for child in n:
    let hit = namedParam(child, params)
    if hit.len > 0:
      return hit
  ""

proc checkNarrowing(node: NimNode, ctx: var Ctx) =
  ## Judge one ``int(p)``-style conversion of a ``csize_t`` parameter.
  ## Reachable only inside the C ABI entry point, where ``ctx.csizeParams``
  ## is non-empty.
  if node.len != 2 or node[0].kind notin {nnkIdent, nnkSym} or $node[0] notin Narrowing:
    return
  let name = namedParam(node[1], ctx.csizeParams)
  if name.len == 0 or unsignedChecked(ctx.stack, name):
    return
  ctx.problems.add ctx.path & ":" & $node.lineInfoObj.line &
    ": unchecked narrowing of csize_t parameter " & repr(node)

proc walkRoutine(node: NimNode, ctx: var Ctx) =
  ## Enter a routine definition on an empty guard stack. A nested routine
  ## shares no scope with the one enclosing it, and facts are keyed by
  ## source text, so without this an inner name would inherit an outer
  ## name's discharge. The ``csize_t`` parameter set is swapped for the
  ## same reason, and stays empty outside the C ABI entry point.
  let savedStack = ctx.stack
  let savedParams = ctx.csizeParams
  ctx.stack = @[]
  ctx.csizeParams =
    if ctx.path.endsWith(L5EntryPoint):
      csizeParamNames(node)
    else:
      @[]
  for child in node:
    walk(child, ctx)
  ctx.stack = savedStack
  ctx.csizeParams = savedParams

proc checkIndex(node: NimNode, ctx: var Ctx) =
  ## Judge one ``a[b]`` node against the guards in force, recording a
  ## violation unless a bound discharges it or ``Exempt`` covers it.
  let want = indexNeed(node[1])
  if want.need == inIgnored:
    return
  let name = collKey(node[0])
  if want.need == inLength and name.len > 0 and satisfied(ctx.stack, name, want.minLen):
    return
  let hit = exemptIndex(ctx, node)
  if hit >= 0:
    ctx.used.add hit
    return
  ctx.problems.add ctx.path & ":" & $node.lineInfoObj.line & ": unguarded index " &
    repr(node)

proc walk(node: NimNode, ctx: var Ctx) =
  ## Recursive AST visitor. Guard-introducing constructs push bounds for
  ## the scope they cover; every other node is traversed unchanged.
  case node.kind
  of nnkStmtList, nnkStmtListExpr:
    walkStmtList(node, ctx)
  of nnkIfStmt, nnkIfExpr, nnkWhenStmt:
    walkIf(node, ctx)
  of nnkCaseStmt:
    walkCase(node, ctx)
  of nnkWhileStmt:
    walk(node[0], ctx)
    walkScoped(node[1], ctx, condFacts(node[0], true))
  of nnkForStmt:
    walk(node[^2], ctx)
    walkScoped(node[^1], ctx, loopBounds(node[^2]))
  of nnkInfix:
    if node.len == 3 and $node[0] in ["and", "or"]:
      walkShortCircuit(node, ctx)
    else:
      for child in node:
        walk(child, ctx)
  of nnkBracketExpr:
    if node.len == 2:
      checkIndex(node, ctx)
    for child in node:
      walk(child, ctx)
  of nnkCall, nnkCommand:
    checkNarrowing(node, ctx)
    for child in node:
      walk(child, ctx)
  of RoutineDefs:
    walkRoutine(node, ctx)
  else:
    for child in node:
      walk(child, ctx)

proc reportIndexAudit(ctx: Ctx) =
  ## Emit every finding as one compile error: unguarded index sites first,
  ## then any ``Exempt`` row that matched nothing. A single ``error`` call
  ## because ``macros.error`` aborts macro execution — reporting per site
  ## would show only the first.
  var lines = ctx.problems
  for i, e in Exempt:
    if i notin ctx.used:
      lines.add "stale exemption: " & e.file & " " & e.expr & " (" & e.why & ")"
  if lines.len > 0:
    error(
      "raw-index audit (" & $lines.len & "):\n" & lines.join("\n") &
        "\nSee tests/compliance/traw_index_audit.nim.",
      nil,
    )

macro auditIndexing(listing: static[string]) =
  ## Parse and walk every path in a newline-separated listing. Reading
  ## happens in the macro body rather than in a ``static[string]``
  ## argument: an argument-position ``staticRead`` of a missing path is
  ## constant-folded under an error trap that discards the diagnostic and
  ## substitutes ``""``, which would make this audit pass on nothing.
  if listing.strip().len == 0:
    error("raw-index audit received an empty file listing — nothing was audited")
  var ctx = Ctx(path: "", stack: @[], problems: @[], used: @[], csizeParams: @[])
  for line in listing.splitLines():
    let path = line.strip()
    if path.len == 0:
      continue
    let source = staticRead(path)
    if source.len == 0:
      error("raw-index audit could not read `" & path & "`")
    ctx.path = path
    walk(parseStmt(source), ctx)
  reportIndexAudit(ctx)

static:
  ## Enumerate every ``.nim`` file under ``src/``, anchored on
  ## ``currentSourcePath`` so the audit is independent of the compiler's
  ## working directory. ``walkDirRec`` rather than a shelled-out ``find``:
  ## it is a compiler VM callback, so it returns the same entries under
  ## ``nim check`` as under ``nim c``, whereas ``staticExec`` runs no
  ## sub-process under ``nim check`` and hands back an empty string.
  const projectRoot = parentDir(parentDir(parentDir(currentSourcePath())))
  const listing = block:
    var paths: seq[string] = @[]
    for path in walkDirRec(projectRoot / "src"):
      if path.endsWith(".nim"):
        paths.add path
    paths.join("\n")
  auditIndexing(listing)
