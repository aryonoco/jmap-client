# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H17 — public-type-shape snapshot lock lint (backs A25; P1, P2).
##
## H16 locks the *set* of public symbols; this lint locks the *shape* of every
## public type: its public-field signature (object fields, case discriminator
## and variants, enum members). Silently adding, removing, or retyping a public
## field changes the wire/FFI contract consumers depend on even when the type's
## name is unchanged, so that drift must be deliberate. Private ``raw*`` fields
## are excluded (the resolver keeps only ``*``-public members), so internal
## sealing refactors do not trip this lint.
##
## Recomputes the shapes via ``scripts/api_surface`` and compares against the
## frozen ``tests/wire_contract/type-shapes.txt``. Bidirectional: a removed or
## added shape line both fail CI. Sibling to H16; the generator and this lint
## share ``typeShapeLines`` so their formats cannot drift.

import std/[os, strutils, sets, sequtils, algorithm]

import "../../scripts/api_surface"

const SnapshotPath =
  currentSourcePath().parentDir.parentDir / "wire_contract" / "type-shapes.txt"

proc loadSnapshotBody(): seq[string] =
  ## Reads the committed snapshot, dropping the leading ``# `` comment header
  ## (the body's ``## <Type>`` section headers are double-hash and kept).
  result = @[]
  var raw = ""
  try:
    raw = readFile(SnapshotPath)
  except IOError, OSError:
    stderr.writeLine "H17: cannot read " & SnapshotPath
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
  ## Entry point: loads the committed snapshot, recomputes the live type
  ## shapes, diffs them bidirectionally, and exits non-zero on any drift.
  let committed = loadSnapshotBody()
  let live = typeShapeLines()

  if committed == live:
    quit(0)

  let committedSet = committed.toHashSet
  let liveSet = live.toHashSet
  var missing = toSeq(committedSet - liveSet).filterIt(it.strip().len > 0)
  var extra = toSeq(liveSet - committedSet).filterIt(it.strip().len > 0)
  missing.sort()
  extra.sort()

  if missing.len == 0 and extra.len == 0:
    quit(0)

  stderr.writeLine "H17 public-type-shape snapshot mismatch (A25)."
  if missing.len > 0:
    stderr.writeLine ""
    stderr.writeLine "  REMOVED from the live type shapes (was in the snapshot):"
    for m in missing:
      stderr.writeLine "    - " & m.strip()
  if extra.len > 0:
    stderr.writeLine ""
    stderr.writeLine "  ADDED to the live type shapes (not in the snapshot):"
    for e in extra:
      stderr.writeLine "    + " & e.strip()
  stderr.writeLine ""
  stderr.writeLine "A public type's field shape is a 1.0 contract (P1/P2). If this"
  stderr.writeLine "change is intentional, regenerate the snapshot and tag the PR:"
  stderr.writeLine "    just freeze-type-shapes   # rewrites tests/wire_contract/type-shapes.txt"
  stderr.writeLine "    PR label: [TYPE-SHAPE-CHANGE]"
  quit(1)

main()
