# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H19 — C-header snapshot lock lint.
##
## H18 holds the header's function NAMES and the exportc inventory to
## each other. This lint locks everything a name set cannot see: each
## function's parameter types in order, each enum's members and their
## ordinals in order, the typedef declaration order, and the version
## macros. It compares the committed ``tests/wire_contract/c-header.txt``
## against a fresh render of ``include/jmap_client.h`` produced by
## ``scripts/render_c_header.nim``, which the ``lint-c-header-snapshot``
## recipe runs and passes here as the first argument.
##
## The comparison is a SEQUENCE comparison — the deliberate divergence
## from H16, whose set-diff fallback treats the same lines in a
## different order as equal. That is right for a symbol set and wrong
## here: declaration order is part of what this render states, and a
## member's position is what fixes its ordinal wherever the header
## leaves a value implicit. A pure reorder therefore fails, and the set
## difference is computed only to classify the report into REMOVED and
## ADDED lines.
##
## The library is pre-1.0, so this lock is not a compatibility promise.
## It detects drift: a change to the header's types, ordinals or macros
## fails CI until the snapshot is regenerated, which makes the change
## deliberate rather than accidental.

import std/[os, strutils, sets, sequtils, algorithm]

const SnapshotPath =
  currentSourcePath().parentDir.parentDir / "wire_contract" / "c-header.txt"

proc loadBody(path: string): seq[string] =
  ## Reads a snapshot / render file, dropping the leading ``# `` comment
  ## header block; the body's ``## <section>`` headers (double-hash) are
  ## kept. Trailing blank lines (from a final newline) are trimmed.
  result = @[]
  var raw = ""
  try:
    raw = readFile(path)
  except IOError, OSError:
    stderr.writeLine "H19: cannot read " & path
    quit(1)
  var inHeader = true
  for line in raw.splitLines():
    if inHeader and line.startsWith("# "):
      continue
    inHeader = false
    result.add(line)
  while result.len > 0 and result[^1].len == 0:
    result.setLen(result.len - 1)

proc report(label: string, lines: seq[string], marker: string) =
  ## Prints one classified group of lines, sorted for a stable report.
  if lines.len == 0:
    return
  stderr.writeLine ""
  stderr.writeLine "  " & label
  for line in lines.sorted():
    stderr.writeLine "    " & marker & " " & line.strip()

proc main() =
  ## Loads the committed snapshot and the live render (argv[1]), compares
  ## them as sequences, and exits non-zero on any drift.
  if paramCount() < 1:
    stderr.writeLine "H19: usage: h19_c_header_snapshot <live-render-file>"
    quit(1)
  let committed = loadBody(SnapshotPath)
  let live = loadBody(paramStr(1))

  # Two empty bodies compare equal, and the gate would then pass on
  # nothing: a truncated snapshot and a render that produced no
  # declarations agree perfectly. Neither is ever legitimately empty.
  if committed.len == 0:
    stderr.writeLine "H19: " & SnapshotPath & " has no body — with nothing to"
    stderr.writeLine "compare this gate would pass on nothing."
    quit(2)
  if live.len == 0:
    stderr.writeLine "H19: the live render " & paramStr(1) & " has no body —"
    stderr.writeLine "with nothing to compare this gate would pass on nothing."
    quit(2)

  # Fast path — identical line sequence (the common, passing case).
  if committed == live:
    quit(0)

  # Differ: classify by set membership. A retyped parameter or a changed
  # ordinal shows as both a REMOVED (old line) and an ADDED (new line).
  let committedSet = committed.toHashSet
  let liveSet = live.toHashSet
  let missing = toSeq(committedSet - liveSet).filterIt(it.strip().len > 0)
  let extra = toSeq(liveSet - committedSet).filterIt(it.strip().len > 0)

  stderr.writeLine "H19 C-header snapshot mismatch."
  if missing.len == 0 and extra.len == 0:
    stderr.writeLine ""
    stderr.writeLine "  REORDERED: the same lines in a different order. The render"
    stderr.writeLine "  pins declaration order, because a member's position is what"
    stderr.writeLine "  fixes its ordinal wherever the header leaves a value implicit."
  report("REMOVED from the live header (was in the snapshot):", missing, "-")
  report("ADDED to the live header (not in the snapshot):", extra, "+")
  stderr.writeLine ""
  stderr.writeLine "The C ABI is pre-1.0 and may still change, but not by accident."
  stderr.writeLine "If this change is intentional, regenerate and review the diff:"
  stderr.writeLine "    just snapshot-c-header   # rewrites tests/wire_contract/c-header.txt"
  quit(1)

when isMainModule:
  main()
