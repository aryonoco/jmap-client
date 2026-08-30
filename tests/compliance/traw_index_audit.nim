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
## Companion to ``tno_asserts_in_src.nim`` (``AssertionDefect``) and
## ``tffi_panic_surface.nim`` (``FieldDefect``); this one closes
## ``IndexDefect``, the third defect family that slips past
## ``{.push raises: [], noSideEffect.}``.
##
## What the audit reads
## --------------------
## Every ``.nim`` file under ``src/``, enumerated by ``staticExec find``
## and parsed with ``parseStmt``. An empty listing is rejected outright,
## and so is a file that reads back empty. The first check is
## load-bearing: ``staticExec`` yields ``""`` under ``nim check``, so
## without it the audit would pass on nothing. Reading happens inside the
## macro body, where a missing path raises a normal compile error; the
## same ``staticRead`` written as a ``static[string]`` macro *argument*
## is constant-folded under an error trap that discards the diagnostic
## and substitutes ``""``, so a stale path written that way audits an
## empty file and still passes.
##
## What the audit cannot reach
## ---------------------------
## ``parseStmt`` yields an *untyped* AST, so no expression here has a
## type. Four consequences, all of them permanent:
##
## - Tuple, array and ``JsonNode`` indexing is indistinguishable from seq
##   indexing. ``pair[0]`` on a tuple cannot raise, but the audit sees the
##   same node it sees for ``parts[0]``. Such sites live in ``Exempt``.
## - A collection is named by its source text. Two different locals called
##   ``parts`` in two procs share one key, and a guard on either satisfies
##   an index on the other. Guards are scoped to the enclosing statement
##   list, which bounds the damage but does not eliminate it.
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
## slice expressions (``s[a ..< b]``) are not examined either.

import std/[macros, os, strutils]

type Bound = tuple[name: string, minLen: int]
  ## Proof that ``name`` holds at least ``minLen`` elements, valid for the
  ## scope the guard that produced it encloses.

type IndexNeed = enum
  ## What discharging one bracket access would take.
  inIgnored ## Not an audited index shape (bare ident, slice, type argument).
  inLength ## Satisfied by a proven minimum length.
  inUnprovable ## Arithmetic index — no length fact can discharge it.

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

proc comparisonBounds(cond: NimNode, holds: bool): seq[Bound] =
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
    result.add (name, int(bound.m))

proc condBounds(cond: NimNode, holds: bool): seq[Bound] =
  ## Bounds implied by ``cond`` evaluating to ``holds``. ``and``
  ## contributes both operands when true and ``or`` both negations when
  ## false — respectively the positive-branch and the early-exit
  ## direction. The converses imply nothing and yield an empty seq.
  if cond.kind == nnkPrefix and cond.len == 2 and $cond[0] == "not":
    return condBounds(cond[1], not holds)
  if cond.kind == nnkInfix and cond.len == 3 and $cond[0] in ["and", "or"]:
    let conjunction = $cond[0] == "and"
    if conjunction != holds:
      return @[]
    return condBounds(cond[1], holds) & condBounds(cond[2], holds)
  comparisonBounds(cond, holds)

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

proc loopBounds(iter: NimNode): seq[Bound] =
  ## A ``for`` body runs only when its source yields, so ``for x in s``,
  ## ``for x in s.items`` and ``for i in 0 ..< s.len`` all prove
  ## ``s.len >= 1`` for the duration of the body.
  let source = iterSource(iter)
  if source.len > 0:
    @[(source, 1)]
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

proc satisfied(stack: seq[Bound], name: string, minLen: int): bool =
  ## True when some enclosing guard proves ``name`` long enough.
  for b in stack:
    if b.name == name and b.minLen >= minLen:
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
  stack*: seq[Bound] ## Guards in force at the current node.
  problems*: seq[string] ## Violation lines, reported together at the end.
  used*: seq[int] ## Indices into ``Exempt`` that matched at least once.

proc exemptIndex(ctx: Ctx, node: NimNode): int =
  ## Position in ``Exempt`` covering this site, or ``-1``. The file half
  ## is a path suffix so the table stays independent of the checkout root.
  for i, e in Exempt:
    if ctx.path.endsWith(e.file) and repr(node) == e.expr:
      return i
  -1

proc walk(node: NimNode, ctx: var Ctx)
  ## Forward declaration — see implementation below for documentation.

proc walkScoped(node: NimNode, ctx: var Ctx, bounds: seq[Bound]) =
  ## Walk ``node`` with ``bounds`` in force, then drop them again.
  for b in bounds:
    ctx.stack.add b
  walk(node, ctx)
  for _ in bounds:
    discard ctx.stack.pop

proc walkIf(node: NimNode, ctx: var Ctx) =
  ## Visit an ``if``/``elif``/``else`` chain. A branch is reached only
  ## when every earlier condition failed, so each inherits their
  ## negations; an ``elif`` body additionally gets what its own condition
  ## proves. That is what makes ``if s.len <= 1: … else: s[^1]`` pass.
  var inherited: seq[Bound] = @[]
  for branch in node:
    if branch.kind notin {nnkElifBranch, nnkElifExpr}:
      walkScoped(branch[^1], ctx, inherited)
      continue
    walkScoped(branch[0], ctx, inherited)
    walkScoped(branch[1], ctx, inherited & condBounds(branch[0], true))
    inherited.add condBounds(branch[0], false)

proc walkShortCircuit(node: NimNode, ctx: var Ctx) =
  ## ``a and b`` evaluates ``b`` only when ``a`` holds, and ``a or b``
  ## only when ``a`` does not — so the right operand runs under the
  ## bounds the left one implies.
  walk(node[1], ctx)
  walkScoped(node[2], ctx, condBounds(node[1], $node[0] == "and"))

proc caseBranchBounds(selector: NimNode, branch: NimNode): seq[Bound] =
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
    @[(name, lowest)]

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
    for b in condBounds(child[0][0], false):
      ctx.stack.add b
      inc added
  for _ in 0 ..< added:
    discard ctx.stack.pop

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
    walkScoped(node[1], ctx, condBounds(node[0], true))
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
  var ctx = Ctx(path: "", stack: @[], problems: @[], used: @[])
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
  ## working directory.
  const projectRoot = parentDir(parentDir(parentDir(currentSourcePath())))
  const listing = staticExec("find " & projectRoot / "src" & " -type f -name '*.nim'")
  auditIndexing(listing)
