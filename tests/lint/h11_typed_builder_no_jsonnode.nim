# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H11 typed-builder JsonNode prohibition lint.
##
## Enforces that no public ``add<Entity><Method>*`` builder accepts a
## ``JsonNode`` parameter outside the documented allowlist (``addEcho``,
## ``addCapabilityInvocation``, ``addInvocation``). After A5, the
## per-entity typed-builder family is fully ``JsonNode``-free at the
## parameter surface; this lint mechanically blocks re-introduction of
## stringly-typed escape hatches in the typed builder family.
##
## See ``docs/TODO/pre-1.0-api-alignment.md`` Section H, entry H11.
##
## **Scope.** Walks every ``.nim`` file under
## ``src/jmap_client/internal/protocol/`` and
## ``src/jmap_client/internal/mail/``, plus ``src/jmap_client.nim`` and
## ``src/jmap_client/convenience.nim``.
##
## **What it flags.** Any exported ``func`` / ``proc`` / ``template``
## declaration whose name matches ``^add[A-Z][A-Za-z]+\*`` and whose
## parameter list contains the substring ``JsonNode``, unless the name
## is on the allowlist.
##
## **Allowlist.**
## - ``addEcho`` — RFC 8620 §4 echo verbatim (P19 send-side exception 1).
## - ``addCapabilityInvocation`` — RFC 8620 §2.5 vendor URN escape
##   (P19 send-side exception 2).
## - ``addInvocation`` — hub-private but ``*``-exported for in-tree
##   cross-internal use.

import std/[os, strutils]

const
  RepoRoot = currentSourcePath().parentDir.parentDir.parentDir
  ScannedDirs = [
    "src" / "jmap_client" / "internal" / "protocol",
    "src" / "jmap_client" / "internal" / "mail",
  ]
  ScannedFiles = ["src" / "jmap_client.nim", "src" / "jmap_client" / "convenience.nim"]
  Allowlist = ["addEcho", "addCapabilityInvocation", "addInvocation"]

func isUnderScanned(rel: string): bool =
  ## True iff ``rel`` lies under one of the scanned directories or is
  ## one of the scanned standalone files.
  let normal = rel.replace('\\', '/')
  for dir in ScannedDirs:
    if normal.startsWith(dir.replace('\\', '/') & "/"):
      return true
  for f in ScannedFiles:
    if normal == f.replace('\\', '/'):
      return true
  false

const DeclarationKinds = ["func ", "proc ", "template "]

func nameEnd(rest: string): int =
  ## Returns the index past the last identifier character of the
  ## leading symbol name in ``rest``. Caller has already verified the
  ## ``add[A-Z]`` prefix; this scans the camelCase tail.
  var i = 3
  while i < rest.len and rest[i] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9'}:
    inc i
  i

func isExportedAddTail(rest: string, i: int): bool =
  ## True when ``rest[i]`` is the ``*`` export marker and the following
  ## character opens a parameter list (``(``) or generic list (``[``).
  if i >= rest.len or rest[i] != '*':
    return false
  let next =
    if i + 1 < rest.len:
      rest[i + 1]
    else:
      '\0'
  next == '(' or next == '['

func tryExtractFromTail(rest: string): string =
  ## Validates the post-``func ``/``proc ``/``template `` slice as an
  ## exported ``add<Entity><Method>*`` declaration and returns the
  ## symbol name. Empty string when the slice doesn't match.
  if rest.len < 5 or not rest.startsWith("add"):
    return ""
  if rest[3] notin {'A' .. 'Z'}:
    return ""
  let i = nameEnd(rest)
  if not isExportedAddTail(rest, i):
    return ""
  rest[0 ..< i]

func extractAddName(line: string): string =
  ## Returns the exported ``add*`` symbol name on this line, or empty
  ## string when the line is not an exported ``add<Entity><Method>*``
  ## declaration. Recognised forms (with leading whitespace tolerated):
  ##   ``func add<Name>*(...)``  /  ``func add<Name>*[T](...)``
  ##   ``proc add<Name>*(...)``  /  ``proc add<Name>*[T](...)``
  ##   ``template add<Name>*(...)``  /  ``template add<Name>*[T](...)``
  let s = line.strip(leading = true, trailing = false)
  for kind in DeclarationKinds:
    if s.startsWith(kind):
      let name = tryExtractFromTail(s[kind.len ..^ 1])
      if name.len > 0:
        return name
  ""

func updateDepth(depth: int, line: string): (int, bool) =
  ## Walks one line of source, updating the paren depth (``(``/``)``).
  ## Returns the new depth and whether at least one ``(`` was seen on
  ## this line. ``[``/``]`` are ignored — Nim's generic brackets close
  ## before the parameter list opens.
  var d = depth
  var seenOpen = false
  for ch in line:
    case ch
    of '(':
      inc d
      seenOpen = true
    of ')':
      if d > 0:
        dec d
    else:
      discard
  (d, seenOpen)

func paramListSpan(lines: seq[string], startIdx: int): seq[string] =
  ## Returns the slice of source lines from ``startIdx`` covering the
  ## parameter list of the declaration on ``lines[startIdx]``. Tracks
  ## paren depth (``(`` opens, ``)`` closes), starting from the first
  ## ``(`` on the declaration line; emits lines until depth returns to
  ## zero. Returns at most ``lines.len - startIdx`` lines.
  result = @[]
  var depth = 0
  var seenOpen = false
  var i = startIdx
  while i < lines.len:
    result.add(lines[i])
    let (newDepth, sawOpen) = updateDepth(depth, lines[i])
    depth = newDepth
    seenOpen = seenOpen or sawOpen
    if seenOpen and depth == 0:
      return
    inc i

proc scanFile(path: string): seq[string] {.raises: [].} =
  ## Returns one ``"path:line: name"`` entry per H11 violation in
  ## ``path``. Empty seq when the file has no violations or cannot be
  ## read.
  result = @[]
  let content =
    try:
      readFile(path)
    except IOError, OSError:
      return
  let lines = content.splitLines
  var i = 0
  while i < lines.len:
    let name = extractAddName(lines[i])
    if name.len == 0 or name in Allowlist:
      inc i
      continue
    let span = paramListSpan(lines, i)
    let blob = span.join("\n")
    if "JsonNode" in blob:
      result.add(path & ":" & $(i + 1) & ": " & name)
    inc i

proc main() =
  ## Walks the scanned src/ subset, collects H11 violations, and exits
  ## non-zero on any.
  var violations: seq[string] = @[]
  for path in walkDirRec(RepoRoot, relative = false):
    if not path.endsWith(".nim"):
      continue
    let rel = path.relativePath(RepoRoot).replace('\\', '/')
    if not isUnderScanned(rel):
      continue
    violations.add scanFile(path)
  if violations.len > 0:
    stderr.writeLine "H11 typed-builder JsonNode violations:"
    for v in violations:
      stderr.writeLine "  " & v
    stderr.writeLine ""
    stderr.writeLine "Public add<Entity><Method>* builders MUST NOT acquire a"
    stderr.writeLine "JsonNode parameter. Use typed arguments and route any"
    stderr.writeLine "vendor-capability escape through addCapabilityInvocation"
    stderr.writeLine "(RFC 8620 §2.5)."
    stderr.writeLine "See P19, A5, H11 in docs/TODO/pre-1.0-api-alignment.md."
    quit(1)
  echo "H11 typed-builder JsonNode: 0 violations"

when isMainModule:
  main()
