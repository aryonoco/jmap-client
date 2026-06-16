# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H16 — public-API snapshot lock lint (backs A26, F6; P1, P5).
##
## The set of symbols reachable through ``import jmap_client`` (A10) is a
## consumer-facing commitment: adding or removing a re-exported symbol
## changes the surface a consumer observes. This lint compares the committed
## ``tests/wire_contract/public-api.txt`` against the live surface produced by
## the compiler-as-library oracle (``scripts/api_oracle.nim``), which the
## ``lint-public-api`` recipe runs and passes here as the first argument.
## Bidirectional: symbols missing from the live surface (a removal) and symbols
## extra in the live surface (an addition) both fail CI.
##
## The oracle reads the compiler's own post-sem symbol table — the literal
## definition of what the hub exposes — so the generator and this lint now share
## ground truth, not the retired text scraper's blind spots.

import std/[os, strutils, sets, sequtils, algorithm]

const SnapshotPath =
  currentSourcePath().parentDir.parentDir / "wire_contract" / "public-api.txt"

proc loadBody(path: string): seq[string] =
  ## Reads a snapshot / oracle-output file, dropping the leading ``# `` comment
  ## header block; the body's ``## <module>`` section headers (double-hash) are
  ## kept. Trailing blank lines (from a final newline) are trimmed.
  result = @[]
  var raw = ""
  try:
    raw = readFile(path)
  except IOError, OSError:
    stderr.writeLine "H16: cannot read " & path
    quit(1)
  var inHeader = true
  for line in raw.splitLines():
    if inHeader and line.startsWith("# "):
      continue
    inHeader = false
    result.add(line)
  while result.len > 0 and result[^1].len == 0:
    result.setLen(result.len - 1)

proc main() =
  ## Loads the committed snapshot and the live oracle output (argv[1]), diffs
  ## them bidirectionally, and exits non-zero on any drift.
  if paramCount() < 1:
    stderr.writeLine "H16: usage: h16_public_api_snapshot <live-oracle-output-file>"
    quit(1)
  let committed = loadBody(SnapshotPath)
  let live = loadBody(paramStr(1))

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
  stderr.writeLine "The public-API surface is a consumer-facing contract (P1/P5)."
  stderr.writeLine "If this change is intentional, regenerate and review the diff:"
  stderr.writeLine "    just freeze-api      # rewrites tests/wire_contract/public-api.txt"
  quit(1)

main()
