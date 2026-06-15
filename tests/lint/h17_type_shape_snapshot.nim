# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H17 — public-type-shape snapshot lock lint (backs A25; P1, P2).
##
## H16 locks the *set* of public symbols; this lint locks the *shape* of every
## public type: its public-field signature (object fields, case discriminator
## and variants, enum members). Silently adding, removing, or retyping a public
## field changes the wire/FFI contract consumers depend on even when the type's
## name is unchanged, so that drift must be deliberate. Private ``raw*`` fields
## are excluded by the oracle (it keeps only exported members), so internal
## sealing refactors do not trip this lint.
##
## Compares the committed ``tests/wire_contract/type-shapes.txt`` against the
## live shapes produced by the compiler-as-library oracle
## (``scripts/api_oracle.nim --mode:type-shapes``), which the ``lint-type-shapes``
## recipe runs and passes here as the first argument. Bidirectional: a removed
## or added shape line both fail CI.

import std/[os, strutils, sets, sequtils, algorithm]

const SnapshotPath =
  currentSourcePath().parentDir.parentDir / "wire_contract" / "type-shapes.txt"

proc loadBody(path: string): seq[string] =
  ## Reads a snapshot / oracle-output file, dropping the leading ``# `` comment
  ## header block (the body's ``## <Type>`` section headers are double-hash and
  ## kept). Trailing blank lines are trimmed.
  result = @[]
  var raw = ""
  try:
    raw = readFile(path)
  except IOError, OSError:
    stderr.writeLine "H17: cannot read " & path
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
    stderr.writeLine "H17: usage: h17_type_shape_snapshot <live-oracle-output-file>"
    quit(1)
  let committed = loadBody(SnapshotPath)
  let live = loadBody(paramStr(1))

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
  stderr.writeLine "A public type's field shape is a consumer-facing contract (P1/P2)."
  stderr.writeLine "If this change is intentional, regenerate and review the diff:"
  stderr.writeLine "    just freeze-type-shapes   # rewrites tests/wire_contract/type-shapes.txt"
  quit(1)

main()
