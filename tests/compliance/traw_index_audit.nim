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
## narrows first has already raised. The bound must be a container length
## or a signed ceiling: comparing against another caller-supplied width
## discharges nothing. It is deliberately confined to the one file that
## exports ``cdecl`` symbols declared ``raises: []``, where an escaping
## defect is ``rawQuit(1)`` rather than a stack unwind.
##
## The rule counts what it examines and reports if either count is zero,
## so a renamed entry point or a signature change cannot leave it
## silently green over no routines at all. Deleting the last narrowing
## conversion from the C ABI therefore fails this audit, which is the
## intended trade: that deletion should be a deliberate edit here too.
##
## Bound and target are compared by width, because the two bound kinds
## differ in what they leave the caller. A ``.len`` bound is in-tree
## data, so the value it bounds is no longer caller-controlled; a
## ``high(T)`` ceiling is not, and leaves the value caller-controlled all
## the way up to that ceiling — ``if n > csize_t(high(int)): return`` then
## ``cint(n)`` raises for any ``n >= 2^31``. So a bound discharges a
## conversion whose target is wide enough to hold what the bound proves:
## ``high(int)`` vouches for ``int(n)`` and not for ``cint(n)``. A length
## is read as proving ``int`` and nothing narrower — the conservative
## reading rather than a proof, since no site narrows a length-bounded
## value below ``int``, and the audit will say so if one appears.
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
##   An anonymous closure is deliberately not a boundary — it shares its
##   enclosing routine's parameters, and dropping facts there would lose
##   real ones — so a closure *parameter* shadowing a guarded outer name
##   inherits that name's discharge.
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
  ## What kind of conclusion a guard or binding in scope has established.
  fkMinLen ## The named collection holds at least ``value`` elements.
  fkUnsignedBound
    ## The named ``csize_t`` parameter was compared, in the unsigned
    ## domain, against a bound that confines it to ``value`` bits.
  fkSafeBound
    ## The named local is bound to such a bound, itself confining a
    ## compared value to ``value`` bits.
  fkCsizeAlias
    ## The named local is bound to a ``csize_t`` parameter, or to another
    ## alias of one, and carries the same exposure. ``value`` is unused.

type Fact = tuple[kind: FactKind, name: string, value: int]
  ## A guard's conclusion, valid for the scope that guard encloses.
  ## ``value`` reads as a minimum element count for ``fkMinLen`` and as a
  ## bit width for the two bound kinds; see ``FactKind``.

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

const IntWidths: seq[tuple[name: string, bits: int]] = @[
  ("int", 64),
  ("int64", 64),
  ("clonglong", 64),
  ("BiggestInt", 64),
  ("Natural", 64),
  ("Positive", 64),
  ("int32", 32),
  ("cint", 32),
  ("clong", 32), # LLP64 keeps this 32-bit; the narrow reading is the safe one.
  ("uint32", 32),
  ("cuint", 32),
  ("int16", 16),
  ("cshort", 16),
  ("uint16", 16),
  ("cushort", 16),
  ("int8", 8),
  ("uint8", 8),
  ("cuchar", 8),
]
  ## Bit width of every type a narrowing can target, and of every type
  ## whose ``high`` can appear as a ceiling. A bound proves a value fits
  ## its own width, so it discharges a narrowing only to a target at
  ## least that wide — which is what stops ``high(int)`` from vouching
  ## for a ``cint``.

const LengthBits = 64
  ## A Nim ``len`` yields ``int``, so a length bound proves ``int`` and
  ## nothing narrower. There is no live site narrowing a length-bounded
  ## value below ``int``; if one appears, the audit will say so.

proc widthOf(name: string): int =
  ## Bit width of the named integer type, or 0 when it is not one.
  for entry in IntWidths:
    if entry.name == name:
      return entry.bits
  0

proc hasFact(stack: seq[Fact], kind: FactKind, name: string): bool =
  ## True when something in scope established ``kind`` for ``name``.
  for f in stack:
    if f.kind == kind and f.name == name:
      return true
  false

proc factWidth(stack: seq[Fact], kind: FactKind, name: string): int =
  ## Tightest bound in scope of ``kind`` for ``name``; 0 when there is
  ## none. Tightest rather than first because a second, looser guard does
  ## not undo what a narrower one already proved.
  result = 0
  for f in stack:
    if f.kind == kind and f.name == name and (result == 0 or f.value < result):
      result = f.value

proc isLenExpr(n: NimNode): bool =
  ## True for ``<anything>.len`` and ``len(<anything>)``. Deliberately
  ## indifferent to what names the container: a length is in-tree data
  ## whatever expression produced it, and that — not which collection it
  ## came from — is what makes a narrowing safe. Reading the base instead
  ## would mean naming it, and ``collKey`` cannot name a deref, so every
  ## ``handle[].items.len`` guard in the C ABI would stop discharging.
  ##
  ## The cost is that a bound rooted in the *wrong* collection still
  ## discharges: ``if i >= csize_t(b[].other.len)`` vouches for
  ## ``a[].items[int(i)]``. That is an ``IndexDefect`` rather than the
  ## ``RangeDefect`` this rule exists for, and the raw-index rule does not
  ## reach it either — a call-shaped index classifies as ``inIgnored``.
  ## No check in this repository catches a wrong-collection bound.
  if n.kind == nnkDotExpr and n[1].kind in {nnkIdent, nnkSym} and $n[1] == "len":
    return true
  n.kind in {nnkCall, nnkCommand} and n.len == 2 and n[0].kind in {nnkIdent, nnkSym} and
    $n[0] == "len"

proc ceilingWidth(n: NimNode): int =
  ## Width ``high(T)`` proves, or 0 when ``n`` is not such a ceiling.
  ## Used where the value being narrowed is a count rather than an index,
  ## and the reason a ``high(int)`` ceiling cannot vouch for a ``cint``
  ## narrowing: it leaves the value caller-controlled up to 2^63-1.
  if n.kind notin {nnkCall, nnkCommand} or n.len != 2 or
      n[0].kind notin {nnkIdent, nnkSym} or $n[0] != "high" or
      n[1].kind notin {nnkIdent, nnkSym}:
    return 0
  widthOf($n[1])

proc boundWidth(n: NimNode): int =
  ## Width a bound expression proves: a container length or a ceiling.
  ## 0 for anything else, including a second caller-supplied width, which
  ## proves nothing at all.
  if isLenExpr(n):
    LengthBits
  else:
    ceilingWidth(n)

proc prefixCsize(n: NimNode): bool =
  ## True for ``csize_t(x)``.
  n.kind in {nnkCall, nnkCommand} and n.len == 2 and n[0].kind in {nnkIdent, nnkSym} and
    $n[0] == "csize_t"

proc postfixCsize(n: NimNode): bool =
  ## True for ``x.csize_t`` — the same conversion the other way round,
  ## and just as sound, so rejecting it would push authors elsewhere.
  n.kind == nnkDotExpr and n[1].kind in {nnkIdent, nnkSym} and $n[1] == "csize_t"

proc safeBoundWidth(n: NimNode, known: seq[Fact]): int =
  ## Width the bound ``n`` proves, or 0 when ``n`` is not one. A bound is
  ## a ``csize_t`` conversion — prefix or postfix — of a container length
  ## or an integer ceiling, or a local bound to one.
  ##
  ## The ``len``-rooted requirement is the whole point. Accepting any
  ## ``csize_t(x)`` would discharge ``i >= csize_t(cap)`` where ``cap`` is
  ## itself caller-supplied, which proves nothing; and because that is
  ## also the shape a developer reaches for when a stricter rule rejects
  ## their guard, the loose reading would actively teach the unsafe
  ## spelling. Both sound spellings — the postfix conversion and the
  ## hoisted local — are accepted here so no one is pushed towards it.
  if prefixCsize(n):
    return boundWidth(n[1])
  if postfixCsize(n):
    return boundWidth(n[0])
  if n.kind in {nnkIdent, nnkSym}:
    return factWidth(known, fkSafeBound, $n)
  0

proc unsignedCompare(
    cond: NimNode, known: seq[Fact]
): tuple[name, op: string, bits: int] =
  ## Decompose a comparison between a bare identifier and a safe bound
  ## into that identifier, the operator read with the identifier on the
  ## left, and the width the bound proves. Empty name for any other shape.
  if cond.kind != nnkInfix or cond.len != 3:
    return ("", "", 0)
  if cond[1].kind in {nnkIdent, nnkSym} and safeBoundWidth(cond[2], known) > 0:
    return ($cond[1], $cond[0], safeBoundWidth(cond[2], known))
  if cond[2].kind in {nnkIdent, nnkSym} and safeBoundWidth(cond[1], known) > 0:
    return ($cond[2], mirrorOp($cond[0]), safeBoundWidth(cond[1], known))
  ("", "", 0)

proc unsignedFacts(cond: NimNode, holds: bool, known: seq[Fact]): seq[Fact] =
  ## ``p >= csize_t(xs.len)`` failing, or ``p < csize_t(xs.len)`` holding,
  ## keeps ``p`` inside the narrowing target's range — provided the
  ## comparison itself did not narrow, which the explicit ``csize_t`` on
  ## the bound is what proves.
  let cmp = unsignedCompare(cond, known)
  let bounded =
    if holds:
      cmp.op in ["<", "<="]
    else:
      cmp.op in [">", ">="]
  if cmp.name.len > 0 and bounded:
    @[(fkUnsignedBound, cmp.name, cmp.bits)]
  else:
    @[]

proc leafFacts(cond: NimNode, holds: bool, known: seq[Fact]): seq[Fact] =
  ## Both readings of one comparison: the length bound it proves, and the
  ## unsigned-domain check that makes a later narrowing safe.
  comparisonBounds(cond, holds) & unsignedFacts(cond, holds, known)

proc condFacts(cond: NimNode, holds: bool, known: seq[Fact]): seq[Fact] =
  ## Facts implied by ``cond`` evaluating to ``holds``. ``and``
  ## contributes both operands when true and ``or`` both negations when
  ## false — respectively the positive-branch and the early-exit
  ## direction. The converses imply nothing and yield an empty seq.
  ## ``known`` is the enclosing scope, consulted for locals already bound
  ## to a bound expression.
  if cond.kind == nnkPrefix and cond.len == 2 and $cond[0] == "not":
    return condFacts(cond[1], not holds, known)
  if cond.kind == nnkInfix and cond.len == 3 and $cond[0] in ["and", "or"]:
    let conjunction = $cond[0] == "and"
    if conjunction != holds:
      return @[]
    return condFacts(cond[1], holds, known) & condFacts(cond[2], holds, known)
  leafFacts(cond, holds, known)

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
    if f.kind == fkMinLen and f.name == name and f.value >= minLen:
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
  l5Routines*: int ## Routines in the entry point carrying a ``csize_t`` parameter.
  narrowSites*: int
    ## Narrowing conversions of such a parameter actually judged. Both
    ## counters exist so the narrowing rule cannot report success over
    ## nothing the way an unchecked file listing would.

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
    walkScoped(branch[1], ctx, inherited & condFacts(branch[0], true, ctx.stack))
    inherited.add condFacts(branch[0], false, ctx.stack)

proc walkShortCircuit(node: NimNode, ctx: var Ctx) =
  ## ``a and b`` evaluates ``b`` only when ``a`` holds, and ``a or b``
  ## only when ``a`` does not — so the right operand runs under the
  ## bounds the left one implies.
  walk(node[1], ctx)
  walkScoped(node[2], ctx, condFacts(node[1], $node[0] == "and", ctx.stack))

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

proc bindingKinds(defs: NimNode, ctx: Ctx): seq[tuple[kind: FactKind, value: int]] =
  ## Which facts one ``a, b = rhs`` group introduces for every name it
  ## binds: the right-hand side is read once, the names share the verdict.
  result = @[]
  let rhs = defs[^1]
  let bits = safeBoundWidth(rhs, ctx.stack)
  if bits > 0:
    result.add (fkSafeBound, bits)
  if rhs.kind in {nnkIdent, nnkSym} and
      ($rhs in ctx.csizeParams or hasFact(ctx.stack, fkCsizeAlias, $rhs)):
    result.add (fkCsizeAlias, 0)

proc bindingFacts(child: NimNode, ctx: Ctx): seq[Fact] =
  ## Facts introduced by a ``let``/``var``/``const`` section. Hoisting a
  ## bound into a local (``let count = csize_t(xs.len)``) is the idiomatic
  ## spelling and must keep working, and a local bound to a ``csize_t``
  ## parameter inherits that parameter's exposure rather than escaping it.
  result = @[]
  if child.kind notin {nnkLetSection, nnkVarSection, nnkConstSection}:
    return
  for defs in child:
    if defs.kind != nnkIdentDefs or defs.len < 3:
      continue
    let kinds = bindingKinds(defs, ctx)
    for i in 0 ..< defs.len - 2:
      if defs[i].kind in {nnkIdent, nnkSym}:
        for k in kinds:
          result.add (k.kind, $defs[i], k.value)

proc walkStmtList(node: NimNode, ctx: var Ctx) =
  ## Visit a statement list, threading through the statements that follow
  ## each one the negation of an early-exit condition and the bindings a
  ## ``let`` introduces.
  var added = 0
  for child in node:
    walk(child, ctx)
    var introduced = bindingFacts(child, ctx)
    if isEarlyExitIf(child):
      introduced.add condFacts(child[0][0], false, ctx.stack)
    for f in introduced:
      ctx.stack.add f
      inc added
  for _ in 0 ..< added:
    discard ctx.stack.pop

const L5EntryPoint = "/src/jmap_client.nim"

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

proc narrowedParam(n: NimNode, ctx: Ctx): string =
  ## First ``csize_t`` parameter — or local alias of one — appearing
  ## anywhere in ``n``, or ``""``. A conversion of a derived expression
  ## (``int(n - 1)``) is judged on the parameter it derives from, which is
  ## the conservative reading.
  if n.kind in {nnkIdent, nnkSym} and
      ($n in ctx.csizeParams or hasFact(ctx.stack, fkCsizeAlias, $n)):
    return $n
  for child in n:
    let hit = narrowedParam(child, ctx)
    if hit.len > 0:
      return hit
  ""

proc checkNarrowing(node, target, operand: NimNode, ctx: var Ctx) =
  ## Judge one narrowing of a ``csize_t`` parameter, written either
  ## ``int(p)`` or ``p.int``. Reachable only inside the C ABI entry point,
  ## where ``ctx.csizeParams`` is non-empty. A bound discharges the
  ## conversion only if what it proves fits the target: a ``high(int)``
  ## ceiling leaves the value caller-controlled well above what a
  ## ``cint`` can hold, so it vouches for ``int(n)`` and not ``cint(n)``.
  if target.kind notin {nnkIdent, nnkSym}:
    return
  let targetBits = widthOf($target)
  if targetBits == 0:
    return
  let name = narrowedParam(operand, ctx)
  if name.len == 0:
    return
  inc ctx.narrowSites
  let proven = factWidth(ctx.stack, fkUnsignedBound, name)
  if proven > 0 and proven <= targetBits:
    return
  let subject =
    if name in ctx.csizeParams:
      "csize_t parameter `" & name & "`"
    else:
      "local `" & name & "`, which aliases a csize_t parameter"
  ctx.problems.add ctx.path & ":" & $node.lineInfoObj.line & ": unchecked narrowing of " &
    subject & " in " & repr(node)

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
  if ctx.csizeParams.len > 0:
    inc ctx.l5Routines
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

proc walkConversion(node: NimNode, ctx: var Ctx) =
  ## Visit a call or dotted expression, checking it for a narrowing of a
  ## ``csize_t`` parameter in either spelling — ``int(p)`` or ``p.int`` —
  ## before descending into it.
  if node.len == 2:
    if node.kind == nnkDotExpr:
      checkNarrowing(node, node[1], node[0], ctx)
    else:
      checkNarrowing(node, node[0], node[1], ctx)
  for child in node:
    walk(child, ctx)

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
    walkScoped(node[1], ctx, condFacts(node[0], true, ctx.stack))
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
  of nnkCall, nnkCommand, nnkDotExpr:
    walkConversion(node, ctx)
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
  if ctx.l5Routines == 0:
    lines.add(
      "the narrowing rule entered no routine with a csize_t parameter — `" &
        L5EntryPoint & "` no longer names a file this walk reached"
    )
  elif ctx.narrowSites == 0:
    lines.add(
      "the narrowing rule judged no conversion — it ran over nothing, " &
        "so its silence means nothing"
    )
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
  var ctx = Ctx(
    path: "",
    stack: @[],
    problems: @[],
    used: @[],
    csizeParams: @[],
    l5Routines: 0,
    narrowSites: 0,
  )
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
