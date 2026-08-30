# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H18 — the C header and the exportc inventory cannot drift apart.
##
## Direction 1: every ``{.exportc: "jmap_…".}`` in
## ``src/jmap_client.nim`` must be declared as a function in
## ``include/jmap_client.h``, or the shared object exports a symbol no
## consumer can call. Direction 2: every function the header declares
## must exist as an exportc, or a consumer compiles against a
## declaration that will not link.
##
## Third, every exportc pragma must carry ``dynlib``, ``cdecl`` and
## ``raises: []`` alongside the exported name. Each of the four prevents
## a distinct failure — Nim name mangling, POSIX symbol hiding, the
## wrong calling convention, and an exception unwinding through a C
## stack frame — and three of them fail at run time rather than at
## build time, which is why they are checked here.
##
## The header side is parsed by ``scripts/render_c_header.nim``, the same
## parser the H19 snapshot renders through, so the two gates cannot
## disagree about what the header declares. The Nim side is a text scan:
## the pragma text runs from ``exportc: "`` to the next ``.}``, so a
## pragma wrapped across lines is still read whole. The scan takes every
## occurrence of that marker at face value, pragma or not, so it reads
## what the file literally says rather than what the compiler sees.
##
## The library is pre-1.0 and this lint is not a compatibility promise:
## it only holds the two inventories to each other.

import std/[algorithm, os, sequtils, sets, strutils]
import ../../scripts/render_c_header

const
  RepoRoot = currentSourcePath().parentDir.parentDir.parentDir
  SourceRel = "src" / "jmap_client.nim"
  ExportcMarker = "exportc: \""
  PragmaEnd = ".}"
  RequiredPragmas = ["dynlib", "cdecl", "raises: []"]

proc readSource(path: string): string =
  ## Reads a file the lint scans, exiting non-zero when it cannot.
  result = ""
  try:
    result = readFile(path)
  except IOError, OSError:
    stderr.writeLine "H18: cannot read " & path
    quit(2)

proc exportcInventory(
    source: string
): tuple[names: HashSet[string], violations: seq[string]] =
  ## Collects every exported C name in ``source`` and reports the pragma
  ## lists that are missing one of the four mandatory pragmas.
  var names = initHashSet[string]()
  var violations: seq[string] = @[]
  var idx = source.find(ExportcMarker)
  while idx >= 0:
    let nameStart = idx + ExportcMarker.len
    let nameEnd = source.find('"', nameStart)
    let pragmaEnd = source.find(PragmaEnd, nameStart)
    if nameEnd < 0 or pragmaEnd < 0:
      stderr.writeLine "H18: unterminated exportc pragma at offset " & $idx
      quit(2)
    let name = source[nameStart ..< nameEnd]
    let pragma = source[idx ..< pragmaEnd]
    names.incl(name)
    for required in RequiredPragmas:
      if required notin pragma:
        violations.add(name & " is missing " & required)
    idx = source.find(ExportcMarker, pragmaEnd)
  (names: names, violations: violations)

proc declaredFunctions(): HashSet[string] =
  ## The names of every function ``include/jmap_client.h`` declares.
  parseHeader(readHeaderSource(RepoRoot))
    .filterIt(it.section == secFunctions)
    .mapIt(it.name).toHashSet

proc reportAll(label: string, names: seq[string]) =
  ## Prints one classified group of names, sorted for a stable report.
  if names.len == 0:
    return
  stderr.writeLine ""
  stderr.writeLine "  " & label
  for name in names.sorted():
    stderr.writeLine "    " & name

proc main() =
  ## Compares the two inventories in both directions, audits the pragma
  ## lists, and exits non-zero on any divergence.
  let (exported, violations) = exportcInventory(readSource(RepoRoot / SourceRel))
  let declared = declaredFunctions()
  let missing = toSeq(exported - declared)
  let extra = toSeq(declared - exported)
  if violations.len == 0 and missing.len == 0 and extra.len == 0:
    echo "H18 C header inventory: ", exported.len, " symbols match the header"
    return

  stderr.writeLine "H18 C header inventory mismatch."
  reportAll("PRAGMA (an exportc without the full four-pragma list):", violations)
  reportAll("MISSING from include/jmap_client.h (exported, undeclared):", missing)
  reportAll("EXTRA in include/jmap_client.h (declared, not exported):", extra)
  stderr.writeLine ""
  stderr.writeLine "The header is hand-written: add, remove or rename the declaration"
  stderr.writeLine "in include/jmap_client.h to match src/jmap_client.nim, then run:"
  stderr.writeLine "    just snapshot-c-header   # rewrites tests/wire_contract/c-header.txt"
  quit(1)

when isMainModule:
  main()
