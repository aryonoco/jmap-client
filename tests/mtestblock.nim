# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Test-block helper. Wraps a test body in an immediately-invoked proc
## so Nim's move analysis can prove wasMoved state across the
## destructor at scope end. Required because module top-level code
## (where ``block <name>:`` lives) treats the implicit ``=destroy``
## at module exit as a non-last "read", which makes single-move
## ``sink`` calls on uncopyable types (``RequestBuilder`` /
## ``BuiltRequest``, A7c/A7d) fail to compile. Inside the proc,
## move analysis is correct.
##
## Drop-in replacement: ``block <name>:`` becomes ``testCase <name>:``.

template testCase*(name, body: untyped) =
  ## Drop-in replacement for ``block <name>:``. Wraps the body in an
  ## immediately-invoked proc so move analysis works correctly.
  proc name() =
    ## Generated test-block proc body.
    {.push warning[Uninit]: off, warning[ProveInit]: off.}
    try:
      body
    except CatchableError as e:
      doAssert false, "test raised: " & e.msg
    {.pop.}

  name()
