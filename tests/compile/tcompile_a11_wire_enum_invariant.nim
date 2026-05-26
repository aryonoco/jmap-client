# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A11 wire-enum invariant compile-time audit. Every public
## open-world wire enum MUST carry a catch-all variant for
## forward-compat additive evolution. New open-world wire enums
## require adding the catch-all assertion here in the same commit.
##
## Companion item H14 (docs/TODO/pre-1.0-api-alignment.md) tracks
## the comprehensive AST-walking lint that catches addition of new
## non-compliant wire enums; this test catches regression of
## established enums (named-list discipline).

import jmap_client

static:
  # Enum catch-all variants — must be publicly declared via the hub.
  doAssert declared(mnUnknown) # MethodName
  doAssert declared(ckUnknown) # CapabilityKind
  doAssert declared(retUnknown) # RequestErrorType
  doAssert declared(metUnknown) # MethodErrorType
  doAssert declared(setUnknown) # SetErrorType
  doAssert declared(caOther) # CollationAlgorithmKind
  doAssert declared(mrOther) # MailboxRoleKind
  doAssert declared(cdExtension) # ContentDispositionKind
  doAssert declared(dsOther) # DeliveredState
  doAssert declared(dpOther) # DisplayedState
  doAssert declared(rpUnknown) # RefPath (A11 closing)

  # Parser functions reachable via the hub — proves the Total and
  # Fallible families are both publicly callable.
  doAssert compiles(parseMethodName("x")) # Total
  doAssert compiles(parseRefPath("x")) # Total (new)
  doAssert compiles(parseCollationAlgorithm("x")) # Fallible
  doAssert compiles(parseMailboxRole("x")) # Fallible
  doAssert compiles(parseContentDisposition("x")) # Fallible
