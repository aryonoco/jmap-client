# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H13 module-path lock lint.
##
## Verifies that the set of ``.nim`` files directly under
## ``src/jmap_client/`` (plus ``src/jmap_client.nim`` for the
## root) matches the closed allowlist committed in
## ``tests/wire_contract/module-paths.txt`` exactly.
##
## Bidirectional:
##   - MISSING: a path is in the snapshot but no backing file
##     exists on disk (a deleted public path that the snapshot
##     still names).
##   - EXTRA: a top-level file exists but is not in the
##     snapshot (a new public path snuck in without going
##     through the freeze workflow).
##
## H10 closes the boundary in the OTHER direction: no
## ``import jmap_client/internal/...`` from outside the package.
## H13 + H10 together make the public/internal boundary
## symmetric.
##
## See ``docs/TODO/pre-1.0-api-alignment.md`` Section A, item
## A10.

import std/[os, sets, strutils]

const
  RepoRoot = currentSourcePath().parentDir.parentDir.parentDir
  SnapshotRel = "tests/wire_contract/module-paths.txt"
  PackageDir = "src/jmap_client"
  PackageRoot = "src/jmap_client.nim"

proc loadSnapshot(): HashSet[string] =
  ## Reads the committed snapshot. Each non-empty,
  ## non-comment line is a module path. Exits non-zero on
  ## read failure.
  result = initHashSet[string]()
  let path = RepoRoot / SnapshotRel
  let content =
    try:
      readFile(path)
    except IOError, OSError:
      stderr.writeLine "H13: cannot read snapshot at " & path
      quit(2)
  for line in content.splitLines:
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("#"):
      continue
    result.incl(trimmed)

proc walkFilesystem(): HashSet[string] =
  ## Returns the set of public module paths derived from the
  ## filesystem. Includes ``jmap_client`` if
  ## ``src/jmap_client.nim`` exists. Walks
  ## ``src/jmap_client/*.nim`` NON-recursively — the
  ## ``internal/`` subtree is excluded (H10 covers that
  ## boundary).
  result = initHashSet[string]()
  let rootFile = RepoRoot / PackageRoot
  if fileExists(rootFile):
    result.incl("jmap_client")
  let pkgDir = RepoRoot / PackageDir
  if dirExists(pkgDir):
    for kind, entry in walkDir(pkgDir):
      if kind != pcFile:
        continue
      if not entry.endsWith(".nim"):
        continue
      let leaf = entry.lastPathPart.changeFileExt("")
      result.incl("jmap_client/" & leaf)

proc main() =
  ## Compares snapshot vs filesystem bidirectionally; exits
  ## non-zero on any divergence with a fix-it suggestion.
  let snapshot = loadSnapshot()
  let actual = walkFilesystem()
  let missing = snapshot - actual
  let extra = actual - snapshot
  if missing.len == 0 and extra.len == 0:
    echo "H13 module-path lock: ", snapshot.len, " public module paths match snapshot"
    return
  if missing.len > 0:
    stderr.writeLine "H13: MISSING from filesystem (in snapshot, no backing file):"
    for p in missing:
      stderr.writeLine "  " & p
  if extra.len > 0:
    stderr.writeLine "H13: EXTRA on filesystem (file exists, not in snapshot):"
    for p in extra:
      stderr.writeLine "  " & p
  stderr.writeLine ""
  stderr.writeLine "If this is an intentional module-path change:"
  stderr.writeLine "  1. just freeze-module-paths"
  stderr.writeLine "  2. review the diff"
  stderr.writeLine "  3. tag the PR [MODULE-PATH-CHANGE]"
  stderr.writeLine ""
  stderr.writeLine "See A10 in docs/TODO/pre-1.0-api-alignment.md."
  quit(1)

when isMainModule:
  main()
