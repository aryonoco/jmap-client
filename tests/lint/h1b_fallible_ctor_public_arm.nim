# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H1b fallible-constructor ∩ public-arm lint.
##
## Enforces the closed-A8 invariant that a public case object whose value is
## produced by a fallible smart constructor (``Result[T, ValidationError]``)
## must not expose any public arm field. A public arm lets a consumer read a
## construction-time-validated payload after ``case x.kind``, which is benign
## on its own — but a public arm travels with a public discriminator, and a
## public discriminator means the arm can also be *written* via raw
## construction, bypassing the smart constructor's invariant (the empty
## ``NOTIFY=`` hole that A30b closed on ``SubmissionParam``). The seal is a
## private discriminator plus private ``raw*`` arms with ``asX`` Opt-accessors.
##
## This complements H1 (no public ``distinct`` under ``src/``): H1 covers the
## newtype surface, H1b covers the sum-type surface. Together they make the
## A8 universal claim — "every hub-reachable public case object is either
## sealed or has no invariant to bypass" — mechanically checked.
##
## See ``docs/TODO/pre-1.0-api-alignment.md`` Section A, entries A8 / H1b.
##
## **Scope.** Walks every ``.nim`` file under ``src/``. The predicate is
## per-file: a type and its fallible constructor live in the same module
## (smart constructors are module-private privileges, P15).
##
## **What it flags.** For each file: (1) collect every ``T`` returned by an
## exported ``func/proc NAME*(...): Result[T, ...]``; (2) for each public
## case-object declaration of such a ``T``, flag it if any ``of``-arm field
## is public *and carries a raw, externally-constructible payload* — a
## lowercase builtin (``int`` / ``string`` / ``seq[`` / ``set[`` / ...) or a
## freely-constructible builtin container (``Opt[`` / ``Table[`` /
## ``JsonNode`` / ...).
##
## **Why the payload test.** A public arm whose payload is itself a sealed
## domain newtype (e.g. ``NonEmptySeq[string]`` on ``BlueprintHeaderMultiValue``)
## cannot be filled with an invariant-violating value — the seal lives in the
## payload type, so exposing the arm is harmless. The hole is specifically a
## public arm over a *raw* type (``SubmissionParam``'s former
## ``notifyFlags: set[DsnNotifyFlag]``, which a caller could set to ``{}``).

import std/[os, strutils, sets, tables]

const
  RepoRoot = currentSourcePath().parentDir.parentDir.parentDir
  ScannedDir = "src"

func leadingSpaces(line: string): int =
  ## Number of leading space characters (indentation depth).
  var n = 0
  while n < line.len and line[n] == ' ':
    inc n
  n

func identAt(s: string, start: int): string =
  ## Reads a Nim identifier (``[A-Za-z0-9_]``) starting at ``start``.
  var i = start
  while i < s.len and s[i] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}:
    inc i
  s[start ..< i]

func resultReturnType(line: string): string =
  ## When ``line`` carries a ``): Result[T, ...]`` return annotation,
  ## returns ``T``; otherwise "". ``T`` is the first generic argument.
  const marker = "): Result["
  let idx = line.find(marker)
  if idx < 0:
    return ""
  identAt(line, idx + marker.len)

func exportedRoutineName(stripped: string): string =
  ## When ``stripped`` begins an exported ``func`` / ``proc`` declaration
  ## (``func NAME*(`` or ``func NAME*[``), returns ``NAME``; else "". The
  ## ``*`` export marker must sit directly after the name.
  for kind in ["func ", "proc "]:
    if stripped.startsWith(kind):
      let name = identAt(stripped, kind.len)
      if name.len == 0:
        return ""
      let after = kind.len + name.len
      if after < stripped.len and stripped[after] == '*':
        let nxt = after + 1
        if nxt < stripped.len and stripped[nxt] in {'(', '['}:
          return name
      return ""
  ""

func objectTypeName(stripped: string): string =
  ## When ``stripped`` declares a public object type — either the
  ## standalone ``type X* ... = object`` or the in-``type``-block member
  ## ``X* ... = object`` — returns ``X``; else "". Pragmas and generic
  ## parameters between the name and ``= object`` are tolerated.
  var s = stripped
  if s.startsWith("type "):
    s = s[len("type ") ..^ 1].strip(leading = true, trailing = false)
  let name = identAt(s, 0)
  if name.len == 0:
    return ""
  if name.len >= s.len or s[name.len] != '*':
    return ""
  if not s.contains("= object"):
    return ""
  name

func payloadUnsafe(payload: string): bool =
  ## True when ``payload`` is a raw, externally-constructible type — a
  ## lowercase builtin (``int`` / ``string`` / ``seq[`` / ``set[`` / ...) or a
  ## freely-constructible builtin container. A PascalCase domain newtype (e.g.
  ## ``NonEmptySeq``) enforces its own invariant and is therefore safe.
  if payload.len == 0:
    return false
  if payload[0] in {'a' .. 'z'}:
    return true
  identAt(payload, 0) in [
    "Opt", "Option", "Table", "OrderedTable", "HashSet", "CountTable", "JsonNode",
    "Hash",
  ]

func starColonAt(s: string, i: int): bool =
  ## True when ``s[i]`` is the ``*`` of an exported-field token ``ident*:``.
  i >= 1 and s[i] == '*' and i + 1 < s.len and s[i + 1] == ':' and
    s[i - 1] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}

func armPayloadAt(s: string, starIdx: int): string =
  ## The payload-type text after the ``*:`` at ``starIdx``, up to the next
  ## ``;`` (combined-arm separator) or end of line.
  var j = starIdx + 2
  while j < s.len and s[j] == ' ':
    inc j
  var k = j
  while k < s.len and s[k] != ';':
    inc k
  s[j ..< k].strip()

func hasUnsafePublicArm(stripped: string): bool =
  ## True when ``stripped`` declares at least one public field (``ident*: T``,
  ## possibly several ``;``-separated, inline after ``of X:`` or on its own
  ## line) whose payload ``T`` is raw (``payloadUnsafe``). The discriminator
  ## line ``case kind*: ...`` is handled separately by the caller, so its
  ## ``kind*:`` is never seen here.
  var i = 1
  while i < stripped.len:
    if starColonAt(stripped, i) and payloadUnsafe(armPayloadAt(stripped, i)):
      return true
    inc i
  false

proc fallibleCtorTypes(lines: seq[string]): HashSet[string] {.raises: [].} =
  ## Pass 1 — every ``T`` returned by an exported ``Result[T, ...]`` routine.
  result = initHashSet[string]()
  var exportedActive = false
  for raw in lines:
    let stripped = raw.strip(leading = true, trailing = false)
    if exportedRoutineName(stripped).len > 0:
      exportedActive = true
    if exportedActive:
      let t = resultReturnType(raw)
      if t.len > 0:
        result.incl(t)
        exportedActive = false

func bodyEnded(stripped: string, indent, typeIndent: int): bool =
  ## True when ``stripped`` is a structural line (non-blank, non-comment) at
  ## or below the type declaration's indentation — i.e. the type body ended.
  stripped.len > 0 and not stripped.startsWith("#") and indent <= typeIndent

func typeBodyHasUnsafeArm(lines: seq[string], startIdx, typeIndent: int): bool =
  ## Scans the body of the case object declared at ``lines[startIdx]`` (at
  ## indentation ``typeIndent``) for an unsafe public arm — a public field
  ## with a raw payload appearing after the ``case`` discriminator.
  var seenCase = false
  var i = startIdx + 1
  while i < lines.len:
    let stripped = lines[i].strip(leading = true, trailing = false)
    if bodyEnded(stripped, leadingSpaces(lines[i]), typeIndent):
      return false
    if stripped.startsWith("case "):
      seenCase = true
    elif seenCase and hasUnsafePublicArm(stripped):
      return true
    inc i
  false

proc scanFile(path: string): seq[string] {.raises: [].} =
  ## Returns one ``"path:line: Type"`` entry per H1b violation in ``path``.
  result = @[]
  let content =
    try:
      readFile(path)
    except IOError, OSError:
      return
  let lines = content.splitLines
  let fallible = fallibleCtorTypes(lines)
  var flagged = initHashSet[string]()
  for i, raw in lines:
    let name = objectTypeName(raw.strip(leading = true, trailing = false))
    if name.len > 0 and name in fallible and name notin flagged:
      if typeBodyHasUnsafeArm(lines, i, leadingSpaces(raw)):
        result.add(path & ":" & $(i + 1) & ": " & name)
        flagged.incl(name)

proc main() =
  ## Walks ``src/``, collects H1b violations, and exits non-zero on any.
  let scanRoot = RepoRoot / ScannedDir
  var violations: seq[string] = @[]
  for path in walkDirRec(scanRoot, relative = false):
    if not path.endsWith(".nim"):
      continue
    violations.add scanFile(path)
  if violations.len > 0:
    stderr.writeLine "H1b fallible-ctor ∩ public-arm violations:"
    for v in violations:
      stderr.writeLine "  " & v
    stderr.writeLine ""
    stderr.writeLine "A public case object built by a fallible smart constructor"
    stderr.writeLine "MUST seal its discriminator and arms (private rawKind / raw*"
    stderr.writeLine "with asX Opt-accessors). A public arm reopens raw construction"
    stderr.writeLine "and bypasses the constructor's invariant (P15/P16)."
    stderr.writeLine "See A8 / H1b in docs/TODO/pre-1.0-api-alignment.md."
    quit(1)
  echo "H1b fallible-ctor ∩ public-arm: 0 violations"

when isMainModule:
  main()
