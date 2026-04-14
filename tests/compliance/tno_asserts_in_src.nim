# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

discard """
  action: "compile"
"""

## Regression macro: rejects any textual ``assert`` or ``doAssert``
## call in ``src/jmap_client/**/*.nim`` at compile time. The L5
## entry point ``src/jmap_client.nim`` is exempt — it is the sole
## module hosting C ABI exports (CLAUDE.md) and may require raw
## C-input guards the type system cannot express. Companion to
## ``tffi_panic_surface.nim`` — together they close the two defect
## families (``FieldDefect`` and ``AssertionDefect``) that bypass
## ``{.raises: [].}`` from inside pure code. Under the project's
## ``--panics:on`` regime those defects become ``rawQuit(1)`` with
## no unwinding — a silent process kill for any FFI consumer.
## Invariants belong in the type system, not in runtime guards;
## this audit prevents regressions from reintroducing the panic
## surface inside the pure-Nim interior.

import std/[macros, os, strutils]

proc isAssertCall(n: NimNode): bool =
  ## True when ``n`` is an ``assert`` or ``doAssert`` invocation in
  ## either command form (``doAssert cond``) or call form
  ## (``doAssert(cond)``). The callee ident/sym match is textual —
  ## shadowing ``assert`` with a local symbol would still be flagged,
  ## which is the intended behaviour.
  if n.kind notin {nnkCall, nnkCommand}:
    return false
  let callee = n[0]
  if callee.kind notin {nnkIdent, nnkSym}:
    return false
  let name = $callee
  name == "assert" or name == "doAssert"

proc walk(node: NimNode, file: string) =
  ## Recursive AST visitor. Emits a compile error at every
  ## ``assert``/``doAssert`` call site, naming the offending file so
  ## the violation is traceable without opening the audit macro.
  if isAssertCall(node):
    error(
      "assert/doAssert in `" & file & "` — push the invariant to the type system " &
        "(see tests/compliance/tno_asserts_in_src.nim)",
      node,
    )
  for child in node:
    walk(child, file)

macro auditAll(listing: static[string]) =
  ## Iterate over a newline-separated list of file paths, reading and
  ## parsing each at compile time. The loop lives inside the macro
  ## body (not the ``static:`` block) so each path can be a VM-local
  ## string rather than a ``static[string]`` literal — macros execute
  ## in the compiler VM where ``staticRead`` accepts runtime values.
  ## L5 (C ABI) exemption: ``src/jmap_client.nim`` is the sole
  ## ``{.exportc.}`` module (CLAUDE.md) and may perform raw C-input
  ## guards that the type system cannot express. The rest of
  ## ``src/jmap_client/**`` remains strictly audited. The anchored
  ## ``/src/jmap_client.nim`` suffix prevents a hypothetical nested
  ## ``src/jmap_client/jmap_client.nim`` from being exempted.
  for line in listing.splitLines():
    let path = line.strip()
    if path.len == 0:
      continue
    if path.endsWith("/src/jmap_client.nim"):
      continue
    walk(parseStmt(staticRead(path)), path)

static:
  ## Enumerate every ``.nim`` file under ``src/`` via ``staticExec``,
  ## anchored on ``currentSourcePath`` so the audit works regardless
  ## of the compiler's working directory. The resulting listing is
  ## passed as a single ``static[string]`` to ``auditAll``.
  const projectRoot = parentDir(parentDir(parentDir(currentSourcePath())))
  const srcDir = projectRoot / "src"
  const listing = staticExec("find " & srcDir & " -type f -name '*.nim'")
  auditAll(listing)
