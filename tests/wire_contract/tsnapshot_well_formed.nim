# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Smoke test for the A10a module-paths snapshot. Verifies
## ``tests/wire_contract/module-paths.txt`` is readable and
## non-empty. The bidirectional snapshot-vs-filesystem check
## lives in ``tests/lint/h13_module_path_lock.nim`` (A10b);
## this file's sole purpose is to anchor the
## ``tests/wire_contract/`` directory as a testament category
## so testament's ``cat`` enumeration succeeds.

import std/[os, strutils]

const
  RepoRoot = currentSourcePath().parentDir.parentDir.parentDir
  SnapshotPath = RepoRoot / "tests/wire_contract/module-paths.txt"

let content = readFile(SnapshotPath)
var nonEmptyLines = 0
for line in content.splitLines:
  if line.strip().len > 0:
    inc nonEmptyLines
doAssert nonEmptyLines >= 1, "module-paths.txt must list at least one module path"
