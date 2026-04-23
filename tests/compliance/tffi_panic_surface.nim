# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

discard """
  action: "compile"
"""

## FFI panic-surface compile-time contract (Part E §6.4.4 scenario 102).
## Audits ``email_blueprint.nim`` and ``serde_email_blueprint.nim`` at
## compile time: every case-object field access must sit inside a
## matching discriminant guard. A violation is a compile error — the
## strongest form of the R5-2 "make illegal states unrepresentable"
## contract. Defends the L5 ``{.raises: [].}`` surface against interior
## ``FieldDefect``, which under ``--panics:on`` becomes ``rawQuit(1)``
## with no unwinding (a silent process kill for any FFI consumer).
##
## Accepted guard idioms: ``case x.disc of V``, ``if x.disc == V``,
## ``if x.flag``, the early-exit form ``if x.disc != V: return``
## (siblings receive the positive guard via the binary-flip table),
## and the cross-variable ``if a.disc != b.disc: return`` ``==``-pattern
## (alias propagation).

import std/macros

type
  Guard = tuple[varExpr, disc, variant: string]
  Alias = tuple[fromVar, toVar, disc: string]

const Guarded: seq[tuple[field, disc, variant: string]] = @[
  ("bodyStructure", "kind", "ebkStructured"),
  ("textBody", "kind", "ebkFlat"),
  ("htmlBody", "kind", "ebkFlat"),
  ("attachments", "kind", "ebkFlat"),
  ("partId", "kind", "bplInline"),
  ("blobId", "kind", "bplBlobRef"),
  ("path", "kind", "bplMultipart"),
  ("dupName", "constraint", "ebcEmailTopLevelHeaderDuplicate"),
  ("bodyStructureDupName", "constraint", "ebcBodyStructureHeaderDuplicate"),
  ("where", "constraint", "ebcBodyPartHeaderDuplicate"),
  ("bodyPartDupName", "constraint", "ebcBodyPartHeaderDuplicate"),
  ("actualTextType", "constraint", "ebcTextBodyNotTextPlain"),
  ("actualHtmlType", "constraint", "ebcHtmlBodyNotTextHtml"),
  ("rejectedName", "constraint", "ebcAllowedFormRejected"),
  ("rejectedForm", "constraint", "ebcAllowedFormRejected"),
  ("subParts", "isMultipart", "true"),
  ("leaf", "isMultipart", "false"),
  # BlueprintLeafPart variant fields — discriminator is ``source``.
  # The outer ``leaf`` is itself a variant field of BlueprintBodyPart
  # gated on ``isMultipart == false`` (above). Inside the ``of false:``
  # arm, ``leaf`` becomes accessible and its own ``source`` discriminator
  # gates the remaining leaf-specific fields.
  ("partId", "source", "bpsInline"),
  ("value", "source", "bpsInline"),
  ("blobId", "source", "bpsBlobRef"),
]

const Flip: seq[(string, string)] = @[
  ("ebkStructured", "ebkFlat"),
  ("ebkFlat", "ebkStructured"),
  ("bpsInline", "bpsBlobRef"),
  ("bpsBlobRef", "bpsInline"),
  ("true", "false"),
  ("false", "true"),
]

proc dotName(n: NimNode): string =
  ## Reconstruct the dotted-name string for a variable expression
  ## (``a``, ``a.b``, ``a.b.c``). Returns ``""`` for unsupported shapes.
  case n.kind
  of nnkIdent, nnkSym:
    $n
  of nnkDotExpr:
    dotName(n[0]) & "." & $n[1]
  else:
    ""

proc flipVariant(v: string): string =
  ## Returns the binary-opposite variant label for a two-valued
  ## discriminant (e.g. ``ebkFlat`` → ``ebkStructured``). Empty
  ## string when ``v`` is not in the ``Flip`` table.
  for (a, b) in Flip:
    if a == v:
      return b
  ""

proc matchDot(n: NimNode): tuple[ok: bool, v, d: string] =
  ## Decompose a ``var.field`` expression into its dotted-base ``v``
  ## and field-name ``d`` strings. ``ok`` is false for any other shape.
  if n.kind == nnkDotExpr and n[1].kind in {nnkIdent, nnkSym}:
    let v = dotName(n[0])
    if v.len > 0:
      return (true, v, $n[1])
  (false, "", "")

proc isExit(body: NimNode): bool =
  ## True when the last statement of ``body`` unconditionally exits the
  ## current scope (``return`` / ``break`` / ``continue`` / ``raise``).
  var t = body
  if t.kind == nnkStmtList and t.len > 0:
    t = t[^1]
  t.kind in {nnkReturnStmt, nnkBreakStmt, nnkContinueStmt, nnkRaiseStmt}

proc condGuard(cond: NimNode, positive: bool): Guard =
  ## Recognise an ``==`` (positive=true) or ``!=`` (positive=false)
  ## comparison between a ``var.disc`` accessor and a variant ident,
  ## or the bare-flag form ``if x.flag`` (positive only). Returns an
  ## empty Guard when ``cond`` doesn't match any known shape.
  if cond.kind == nnkInfix and cond.len == 3 and
      $cond[0] == (if positive: "==" else: "!="):
    let m = matchDot(cond[1])
    if m.ok and cond[2].kind in {nnkIdent, nnkSym}:
      return (m.v, m.d, $cond[2])
  elif positive and cond.kind == nnkDotExpr:
    let m = matchDot(cond)
    if m.ok:
      return (m.v, m.d, "true")
  ("", "", "")

proc condAlias(cond: NimNode): Alias =
  ## Recognise the cross-variable inequality ``a.disc != b.disc`` —
  ## the early-exit pattern that proves two variables share a
  ## discriminant value beyond the guard. Returns the alias triple
  ## or an empty Alias when ``cond`` is not such a comparison.
  if cond.kind == nnkInfix and cond.len == 3 and $cond[0] == "!=":
    let l = matchDot(cond[1])
    let r = matchDot(cond[2])
    if l.ok and r.ok and l.d == r.d:
      return (l.v, r.v, l.d)
  ("", "", "")

proc directlyGuarded(stack: seq[Guard], v, d, variant: string): bool =
  ## Returns true when an enclosing guard binds ``v.d == variant``
  ## directly, with no alias indirection.
  for g in stack:
    if g.varExpr == v and g.disc == d and g.variant == variant:
      return true
  false

proc aliasGuarded(stack: seq[Guard], aliases: seq[Alias], v, d, variant: string): bool =
  ## Returns true when ``v`` shares discriminant ``d`` with some other
  ## variable for which an enclosing guard binds the matching variant.
  for a in aliases:
    if a.fromVar == v and a.disc == d and directlyGuarded(stack, a.toVar, d, variant):
      return true
  false

proc hasGuard(stack: seq[Guard], aliases: seq[Alias], v, d, variant: string): bool =
  ## Combined direct-or-aliased guard lookup — the predicate the walker
  ## consults at every guarded field access.
  directlyGuarded(stack, v, d, variant) or aliasGuarded(stack, aliases, v, d, variant)

proc walk(node: NimNode, stack: var seq[Guard], aliases: var seq[Alias])
  ## Forward declaration — see implementation below for documentation.

proc walkCase(node: NimNode, stack: var seq[Guard], aliases: var seq[Alias]) =
  ## Visit a ``case x.disc of V: ...`` statement, pushing the matched
  ## ``(x, disc, V)`` guard for the duration of each ``of`` branch.
  walk(node[0], stack, aliases)
  let m = matchDot(node[0])
  for i in 1 ..< node.len:
    let br = node[i]
    var pushed = 0
    if br.kind == nnkOfBranch and m.ok:
      for j in 0 ..< br.len - 1:
        if br[j].kind in {nnkIdent, nnkSym}:
          stack.add (m.v, m.d, $br[j])
          inc pushed
    walk(br[^1], stack, aliases)
    for _ in 0 ..< pushed:
      discard stack.pop

proc walkIf(node: NimNode, stack: var seq[Guard], aliases: var seq[Alias]) =
  ## Visit an ``if/elif/else`` chain. A positive guard ``if x.d == V``
  ## binds inside its branch only; subsequent ``elif`` siblings then
  ## inherit the binary-opposite (``flipVariant``) as a negative guard.
  var negs: seq[Guard] = @[]
  for br in node:
    var pushed = 0
    for n in negs:
      stack.add n
      inc pushed
    if br.kind == nnkElifBranch:
      walk(br[0], stack, aliases)
      let pos = condGuard(br[0], true)
      if pos.disc.len > 0:
        stack.add pos
        walk(br[1], stack, aliases)
        discard stack.pop
      else:
        walk(br[1], stack, aliases)
      if pos.disc.len > 0:
        let other = flipVariant(pos.variant)
        if other.len > 0:
          negs.add (pos.varExpr, pos.disc, other)
    else:
      walk(br[0], stack, aliases)
    for _ in 0 ..< pushed:
      discard stack.pop

proc isEarlyExitIf(child: NimNode): bool =
  ## True for ``if cond: <exit>`` — a single-branch ``if`` whose body
  ## unconditionally exits the surrounding scope.
  child.kind == nnkIfStmt and child.len == 1 and child[0].kind == nnkElifBranch and
    isExit(child[0][1])

proc earlyExitGuard(cond: NimNode): tuple[g: Guard, ok: bool] =
  ## Translate an early-exit condition into the positive guard that
  ## subsequent siblings inherit. ``if x.d != V: return`` directly
  ## yields ``(x, d, V)``; ``if x.d == V: return`` instead yields the
  ## flipped sibling variant. ``ok`` is false for unrecognised shapes.
  let neg = condGuard(cond, false)
  if neg.disc.len > 0:
    return (neg, true)
  let pos = condGuard(cond, true)
  if pos.disc.len > 0:
    let other = flipVariant(pos.variant)
    if other.len > 0:
      return ((pos.varExpr, pos.disc, other), true)
  (("", "", ""), false)

proc walkStmtList(node: NimNode, stack: var seq[Guard], aliases: var seq[Alias]) =
  ## Visit a statement list, threading any early-exit-derived guards
  ## and aliases through statements that follow the early-exit ``if``.
  var addedG = 0
  var addedA = 0
  for child in node:
    walk(child, stack, aliases)
    if not isEarlyExitIf(child):
      continue
    let cond = child[0][0]
    let extracted = earlyExitGuard(cond)
    if extracted.ok:
      stack.add extracted.g
      inc addedG
    let al = condAlias(cond)
    if al.disc.len > 0:
      aliases.add al
      aliases.add (al.toVar, al.fromVar, al.disc)
      addedA += 2
  for _ in 0 ..< addedG:
    discard stack.pop
  for _ in 0 ..< addedA:
    discard aliases.pop

proc walk(node: NimNode, stack: var seq[Guard], aliases: var seq[Alias]) =
  ## Recursive AST visitor. Dispatches to ``walkCase`` / ``walkIf`` /
  ## ``walkStmtList`` for guard-introducing constructs; at every
  ## ``nnkDotExpr`` whose RHS is a guarded field, asserts the guard
  ## stack covers it and emits ``error`` on the offending node otherwise.
  case node.kind
  of nnkCaseStmt:
    walkCase(node, stack, aliases)
  of nnkIfStmt:
    walkIf(node, stack, aliases)
  of nnkStmtList, nnkStmtListExpr:
    walkStmtList(node, stack, aliases)
  of nnkDotExpr:
    let m = matchDot(node)
    if m.ok:
      var anyField = false
      var ok = false
      for (f, d, v) in Guarded:
        if f == m.d:
          anyField = true
          if hasGuard(stack, aliases, m.v, d, v):
            ok = true
            break
      if anyField and not ok:
        error(
          "FFI panic-surface: unguarded case-object access " & m.v & "." & m.d &
            " (no enclosing case/if guard)",
          node,
        )
    walk(node[0], stack, aliases)
  else:
    for c in node:
      walk(c, stack, aliases)

macro audit(src: static[string]) =
  ## Public entry point: parse ``src`` as a Nim statement list and walk
  ## it under empty guard/alias stacks. Emits compile errors for every
  ## unguarded case-object access found.
  var stack: seq[Guard] = @[]
  var aliases: seq[Alias] = @[]
  walk(parseStmt(src), stack, aliases)

static:
  audit(staticRead("../../src/jmap_client/mail/email_blueprint.nim"))
  audit(staticRead("../../src/jmap_client/mail/serde_email_blueprint.nim"))
