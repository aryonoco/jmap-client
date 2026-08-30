# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H18 — the C header and the exportc inventory cannot drift apart.
##
## Direction 1: every ``{.exportc: "jmap_…".}`` under ``src/`` must be
## declared as a function in ``include/jmap_client.h``, or the shared
## object exports a symbol no consumer can call. Direction 2: every
## function the header declares must exist as an exportc, or a consumer
## compiles against a declaration that will not link.
##
## Third, every exportc pragma must carry ``dynlib``, ``cdecl`` and
## ``raises: []`` alongside the exported name. Each of the four prevents
## a distinct failure — Nim name mangling, POSIX symbol hiding, the
## wrong calling convention, and an exception unwinding through a C
## stack frame. The Nim compiler flags none of the three omissions: a
## missing ``dynlib`` hides the symbol under ``--app:lib`` and surfaces
## when a C consumer fails to LINK, and a missing ``cdecl`` or
## ``raises: []`` goes wrong at run time. That is why they are checked
## here.
##
## What this lint does NOT check is that a declaration's TYPES match the
## Nim proc's; ``tests/lint/h20_c_header_types.nim`` does that.
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
  SourceDir = "src"
  ExportcMarker = "exportc: \""
  PragmaEnd = ".}"
  RequiredPragmas = ["dynlib", "cdecl", "raises: []"]

proc nimSources(): string =
  ## Every ``.nim`` file under ``src/`` concatenated. The exports all sit
  ## in ``src/jmap_client.nim`` today, but scanning the whole tree is
  ## what makes that a finding rather than an assumption: an exportc
  ## added to another module would otherwise be invisible here.
  result = ""
  for path in walkDirRec(RepoRoot / SourceDir):
    if not path.endsWith(".nim"):
      continue
    try:
      result.add(readFile(path))
      result.add("\n")
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
  let (exported, violations) = exportcInventory(nimSources())
  let declared = declaredFunctions()
  # Two empty inventories agree, and agreeing on nothing is how a gate
  # stops being one: a scan that finds no exportc and a parse that finds
  # no declaration would report a clean match. Neither side is ever
  # legitimately empty, so an empty one is a broken input, not a result.
  if exported.len == 0:
    stderr.writeLine "H18: no exportc found under src/ — with nothing to compare"
    stderr.writeLine "this gate would pass on nothing."
    quit(2)
  if declared.len == 0:
    stderr.writeLine "H18: include/jmap_client.h declares no functions — with"
    stderr.writeLine "nothing to compare this gate would pass on nothing."
    quit(2)
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
  stderr.writeLine "in include/jmap_client.h to match the Nim exports, then run:"
  stderr.writeLine "    just snapshot-c-header   # rewrites tests/wire_contract/c-header.txt"
  quit(1)

when isMainModule:
  main()
