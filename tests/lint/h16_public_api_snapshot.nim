# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H16 — public-API snapshot lock lint (backs A26, F6; P1, P5, P2).
##
## The set of symbols reachable through ``import jmap_client`` and
## ``import jmap_client/convenience`` (A10) is a public commitment the moment 1.0
## ships: adding or removing a re-exported symbol changes the import graph
## consumers observe. This lint recomputes that surface from the ``export`` /
## ``export … except …`` graph (via ``scripts/api_surface``) and compares it
## against the frozen ``tests/wire_contract/public-api.txt``. Bidirectional:
## symbols missing from the live surface (a removal) and symbols extra in the
## live surface (an addition) both fail CI.
##
## Sibling to H13 (module-path lock) and H15 (error-message lock); the generator
## and this lint share ``snapshotLines`` so their formats cannot drift.

import std/[os, strutils, sets, sequtils, algorithm]

import "../../scripts/api_surface"

const SnapshotPath =
  currentSourcePath().parentDir.parentDir / "wire_contract" / "public-api.txt"

proc loadSnapshotBody(): seq[string] =
  ## Reads the committed snapshot, dropping the leading ``#`` comment header.
  result = @[]
  var raw = ""
  try:
    raw = readFile(SnapshotPath)
  except IOError, OSError:
    stderr.writeLine "H16: cannot read " & SnapshotPath
    quit(1)
  # The file header is the leading block of single-hash ``# `` comment lines;
  # the body's ``## <module>`` section headers (double-hash) are kept.
  var inHeader = true
  for line in raw.splitLines():
    if inHeader and line.startsWith("# "):
      continue
    inHeader = false
    result.add(line)
  # Drop a single trailing empty line from the final newline.
  while result.len > 0 and result[^1].len == 0:
    result.setLen(result.len - 1)

proc main() =
  ## Entry point: loads the committed snapshot, recomputes the live public
  ## surface, diffs them bidirectionally, and exits non-zero on any drift.
  let committed = loadSnapshotBody()
  let live = snapshotLines()

  # Fast path — identical line sequence (the common, passing case).
  if committed == live:
    quit(0)

  # Differ: classify by set membership. A decl/signature change shows as both a
  # REMOVED (old line) and an ADDED (new line). ``## module`` headers and blanks
  # are identical in both and so never appear in the diff. Ignore blanks.
  let committedSet = committed.toHashSet
  let liveSet = live.toHashSet
  var missing = toSeq(committedSet - liveSet) # in snapshot, not live → removed
  var extra = toSeq(liveSet - committedSet) # in live, not snapshot → added
  missing = missing.filterIt(it.len > 0)
  extra = extra.filterIt(it.len > 0)
  missing.sort()
  extra.sort()

  if missing.len == 0 and extra.len == 0:
    # Only blank-line / ordering noise differs — treat as equal.
    quit(0)

  stderr.writeLine "H16 public-API snapshot mismatch (A26)."
  if missing.len > 0:
    stderr.writeLine ""
    stderr.writeLine "  REMOVED from the live surface (was in the snapshot):"
    for m in missing:
      stderr.writeLine "    - " & m
  if extra.len > 0:
    stderr.writeLine ""
    stderr.writeLine "  ADDED to the live surface (not in the snapshot):"
    for e in extra:
      stderr.writeLine "    + " & e
  stderr.writeLine ""
  stderr.writeLine "The public-API surface is a 1.0 contract (P1/P5). If this"
  stderr.writeLine "change is intentional, regenerate the snapshot and tag the PR:"
  stderr.writeLine "    just freeze-api      # rewrites tests/wire_contract/public-api.txt"
  stderr.writeLine "    PR label: [API-CHANGE]"
  quit(1)

main()
