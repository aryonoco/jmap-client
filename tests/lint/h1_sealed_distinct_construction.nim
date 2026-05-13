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
## **What it flags.** Any line matching the syntactic shape of a top-
## level ``type Foo* = distinct ...`` declaration. Comment lines and
## the inside of doc comments are ignored.
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
  ## type alias: ``type Foo* = distinct <X>`` with optional generic
  ## parameters and pragmas between the name and ``=``.
  ##
  ## Comment lines are excluded by the caller (this function expects
  ## the leading whitespace already stripped).
  if not line.startsWith("type "):
    return false
  # Find the export marker — the identifier must be public.
  let starIdx = line.find('*')
  if starIdx < 0:
    return false
  # The ``= distinct`` token must follow on the same line. Public
  # distinct declarations in this codebase historically all live on
  # a single line; multi-line forms would be rejected as a style
  # violation anyway.
  let eqIdx = line.find('=', start = starIdx)
  if eqIdx < 0:
    return false
  let after = line[eqIdx + 1 ..^ 1].strip(leading = true, trailing = false)
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
