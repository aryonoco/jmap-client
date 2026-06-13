# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H12 test-backdoor-symbol lint.
##
## Enforces that no public symbol on ``src/jmap_client/**`` carries the
## naming shapes that historically betrayed test-only escape hatches:
## the ``*ForTest*`` / ``*ForTesting*`` suffixes, the ``setSessionFor*``
## family, and the ``last*Response*`` / ``last*Request*`` / ``lastRaw*``
## families. The A9 / A13 / A19 refactor removed every such backdoor
## on the public surface; this lint mechanically blocks re-introduction.
##
## See ``docs/TODO/pre-1.0-api-alignment.md`` Section H, entry H12.
##
## Principle references: P5 (single layer, no test API), P8 (opaque
## handles, no test-only field accessors), P14 (no thread-local state
## on production handles).
##
## **Scope.** Walks every ``.nim`` file under ``src/jmap_client/``.
##
## **What it flags.** Any exported ``func`` / ``proc`` / ``template`` /
## ``type`` declaration whose name matches one of the forbidden shapes.

import std/[os, strutils]

const
  RepoRoot = currentSourcePath().parentDir.parentDir.parentDir
  ScannedRoot = "src" / "jmap_client"
  DeclarationKinds = ["func ", "proc ", "template ", "type ", "iterator "]

func nameEnd(s: string, start: int): int =
  ## Returns the index past the last identifier character starting at
  ## ``start`` in ``s``. Caller has already verified the start is an
  ## identifier character.
  var i = start
  while i < s.len and s[i] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}:
    inc i
  i

func extractExportedName(line: string): string =
  ## Returns the exported symbol name on this line, or empty string
  ## when the line is not an exported declaration. Recognised forms
  ## (with leading whitespace tolerated):
  ##   ``func name*(...)``  /  ``func name*[T](...)``  /  ``func name*:T``
  ##   ``proc name*(...)``  /  ``template name*(...)``  /  ``type name*``
  let s = line.strip(leading = true, trailing = false)
  for kind in DeclarationKinds:
    if not s.startsWith(kind):
      continue
    let rest = s[kind.len ..^ 1]
    if rest.len == 0 or rest[0] notin {'A' .. 'Z', 'a' .. 'z', '_'}:
      return ""
    let i = nameEnd(rest, 0)
    if i >= rest.len or rest[i] != '*':
      return ""
    return rest[0 ..< i]
  ""

func hasForTestSuffix(name: string): bool =
  ## ``name`` ends with the ``ForTest`` or ``ForTesting`` suffix.
  name.endsWith("ForTest") or name.endsWith("ForTesting")

func hasLastResponseOrRequestShape(name: string): bool =
  ## ``name`` starts with ``last`` followed by a capital letter and
  ## carries either ``Response`` or ``Request`` somewhere in its body.
  ## Catches the P14 "last-operation state on handle" family
  ## (``lastResponseBody``, ``lastRequest``, etc.) without flagging
  ## benign words that merely start with ``last``.
  if not name.startsWith("last"):
    return false
  if name.len <= 4 or name[4] notin {'A' .. 'Z'}:
    return false
  "Response" in name or "Request" in name

func isForbiddenName(name: string): bool =
  ## True when ``name`` carries one of the forbidden naming shapes.
  ## Sets P5/P8/P14-violating symbols apart from legitimate library
  ## names.
  hasForTestSuffix(name) or name.startsWith("setSessionFor") or
    name.startsWith("lastRaw") or hasLastResponseOrRequestShape(name)

proc scanFile(path: string): seq[string] {.raises: [].} =
  ## Returns one ``"path:line: name"`` entry per H12 violation in
  ## ``path``. Empty seq when the file has no violations or cannot be
  ## read.
  result = @[]
  let content =
    try:
      readFile(path)
    except IOError, OSError:
      return
  var lineNum = 0
  for line in content.splitLines:
    inc lineNum
    let name = extractExportedName(line)
    if name.len > 0 and isForbiddenName(name):
      result.add(path & ":" & $lineNum & ": " & name)

proc main() =
  ## Walks ``src/jmap_client/``, collects H12 violations, exits non-zero
  ## on any. Wired to ``just lint-h12-no-test-backdoors`` and ``just ci``.
  var violations: seq[string] = @[]
  let scanRoot = RepoRoot / ScannedRoot
  for path in walkDirRec(scanRoot, relative = false):
    if not path.endsWith(".nim"):
      continue
    violations.add scanFile(path)
  if violations.len > 0:
    stderr.writeLine "H12 test-backdoor-symbol violations:"
    for v in violations:
      stderr.writeLine "  " & v
    stderr.writeLine ""
    stderr.writeLine "Public symbols on src/jmap_client/** MUST NOT carry"
    stderr.writeLine "*ForTest* / *ForTesting* / setSessionFor* / lastRaw* /"
    stderr.writeLine "last*Response* / last*Request* naming shapes. These"
    stderr.writeLine "shapes betray test-only escape hatches on the public"
    stderr.writeLine "surface (P5, P8, P14). Tests must compose the public"
    stderr.writeLine "Transport API instead."
    stderr.writeLine "See P5, P8, P14, A9, A13, A19, H12 in"
    stderr.writeLine "docs/TODO/pre-1.0-api-alignment.md."
    quit(1)
  echo "H12 test-backdoor-symbol: 0 violations"

when isMainModule:
  main()
