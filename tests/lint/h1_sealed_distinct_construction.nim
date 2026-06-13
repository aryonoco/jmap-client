# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H1 sealed-construction lint.
##
## Enforces the post-A8 invariant: zero public ``distinct`` type
## declarations under ``src/``. The seal that binds external consumers
## (P15) is the sealed Pattern-A object pattern — a module-private
## ``rawValue`` field — not any form of ``distinct`` wrapping. This lint
## blocks regression: a re-introduced public ``distinct`` would reopen
## the raw-construction surface that A8 closed.
##
## See ``docs/TODO/pre-1.0-api-alignment.md`` Section A, entry A8.
##
## **Scope.** Walks every ``.nim`` file under ``src/``.
##
## **What it flags.** Any line matching the syntactic shape of a public
## distinct declaration — both the single-line ``type Foo* = distinct ...``
## form and an in-``type``-block member line ``Foo* = distinct ...`` (the
## latter is how an unsealed distinct previously slipped past this lint).
## Generic (``Foo*[T] = distinct``) and pragma (``Foo* {.x.} = distinct``)
## forms are covered. Comment lines are ignored.
##
## **Exemption.** None at present. If a future principled need arises,
## add an explicit allowlist alongside the existing checks rather than
## suppressing this lint.

import std/[os, strutils]

const
  RepoRoot = currentSourcePath().parentDir.parentDir.parentDir
  ScannedDir = "src"

func isTypeDistinctDeclaration(line: string): bool =
  ## True iff ``line`` syntactically introduces a public distinct
  ## declaration: ``Foo* = distinct <X>`` with optional generic parameters
  ## and pragmas between the name and ``=``. Accepts both the single-line
  ## ``type Foo* = distinct ...`` spelling and the in-``type``-block member
  ## spelling (no ``type`` keyword) — ``distinct`` only appears in type
  ## sections in valid Nim, so no block-state tracking is required.
  ##
  ## Comment lines are excluded by the caller (this function expects the
  ## leading whitespace already stripped).
  var s = line
  if s.startsWith("type "):
    s = s[len("type ") ..^ 1].strip(leading = true, trailing = false)
  # The export marker must follow a bare identifier (the type name).
  let starIdx = s.find('*')
  if starIdx <= 0:
    return false
  for ch in s[0 ..< starIdx]:
    if ch notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}:
      return false
  let eqIdx = s.find('=', start = starIdx)
  if eqIdx < 0:
    return false
  let after = s[eqIdx + 1 ..^ 1].strip(leading = true, trailing = false)
  after.startsWith("distinct ") or after == "distinct" or after.startsWith("distinct\t")

iterator walkNimFiles(root: string): string =
  ## Yields every ``.nim`` file path under ``root`` recursively. Paths
  ## are absolute.
  for path in walkDirRec(root, yieldFilter = {pcFile}, followFilter = {pcDir}):
    if path.endsWith(".nim"):
      yield path

proc main() =
  ## Entry point. Walks ``src/`` for top-level ``type Foo* = distinct``
  ## declarations and exits non-zero on any match.
  let scanRoot = RepoRoot / ScannedDir
  var violations: seq[(string, int, string)] = @[]
  for path in walkNimFiles(scanRoot):
    let relPath = path.relativePath(RepoRoot)
    var lineNo = 0
    for line in lines(path):
      inc lineNo
      let stripped = line.strip(leading = true, trailing = false)
      if stripped.startsWith("#"):
        continue
      if isTypeDistinctDeclaration(stripped):
        violations.add((relPath, lineNo, line))
  if violations.len == 0:
    echo "H1: ok — no public `distinct` types under src/."
    quit(0)
  echo "H1 violations: ", violations.len
  for (path, lineNo, line) in violations:
    echo "  ", path, ":", lineNo, ": ", line.strip()
  echo ""
  echo "Every public value-carrying type must be a sealed Pattern-A"
  echo "object (A8). The seal prevents raw-construction across module"
  echo "boundaries; ``distinct`` reopens the surface."
  quit(1)

when isMainModule:
  main()
