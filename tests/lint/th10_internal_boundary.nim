# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H10 internal-boundary lint.
##
## Enforces that ``import jmap_client/internal/...`` only appears under
## ``src/jmap_client/`` (the package itself) and ``tests/`` (which are
## allowed to reach private helpers). Any other location — examples,
## external consumers, sample apps, downstream code that lands in this
## repo — fails CI with a pointer to A1 / P5.
##
## See ``docs/TODO/pre-1.0-api-alignment.md`` Section H, entry H10.

import std/[os, strutils]

const
  RepoRoot = currentSourcePath().parentDir.parentDir.parentDir
  ForbiddenPrefixes = ["import jmap_client/internal/", "from jmap_client/internal/"]
  AllowedRoots = ["src" / "jmap_client", "tests"]

proc isAllowed(path: string): bool =
  ## True when ``path`` lives under one of ``AllowedRoots``. Used to
  ## skip files that are permitted to import ``jmap_client/internal/...``
  ## (the package itself and the test tree).
  let rel = path.relativePath(RepoRoot).replace('\\', '/')
  for root in AllowedRoots:
    if rel.startsWith(root.replace('\\', '/')):
      return true
  false

proc scanFile(path: string): seq[string] =
  ## Returns one ``"path:line: source"`` entry per forbidden import in
  ## ``path``. Empty seq when the file has no violations or cannot be
  ## read (binary files, permission errors).
  result = @[]
  let content =
    try:
      readFile(path)
    except IOError, OSError:
      return
  var lineNum = 0
  for line in content.splitLines:
    inc lineNum
    let stripped = line.strip(leading = true, trailing = false)
    for prefix in ForbiddenPrefixes:
      if stripped.startsWith(prefix):
        result.add(path & ":" & $lineNum & ": " & stripped)

proc main() =
  ## Walks the repo, collects H10 violations, and exits non-zero on any.
  ## Wired to ``just lint-internal-boundary`` and ``just ci`` so the
  ## public/internal boundary is enforced by CI rather than review.
  var violations: seq[string] = @[]
  for path in walkDirRec(RepoRoot, relative = false):
    if not path.endsWith(".nim"):
      continue
    if isAllowed(path):
      continue
    if "vendor" in path or ".nim-reference" in path or "scripts/output" in path:
      continue
    violations.add scanFile(path)
  if violations.len > 0:
    stderr.writeLine "H10 internal-boundary violations:"
    for v in violations:
      stderr.writeLine "  " & v
    stderr.writeLine ""
    stderr.writeLine "import jmap_client/internal/* is forbidden outside the"
    stderr.writeLine "package. Use the public hubs (jmap_client/types,"
    stderr.writeLine "/serialisation, /protocol, /client, /mail, /convenience)."
    stderr.writeLine "See P5, A1, H10 in docs/TODO/pre-1.0-api-alignment.md."
    quit(1)
  echo "H10 internal-boundary: 0 violations"

when isMainModule:
  main()
