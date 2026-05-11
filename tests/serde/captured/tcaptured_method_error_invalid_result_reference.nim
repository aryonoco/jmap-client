# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``invalidResultReference``
## method-level rejection (``tests/testdata/captured/
## method-error-invalid-result-reference-stalwart.json``).
##
## Stalwart 0.15.5 RFC-conforms: returns ``"invalidResultReference"``
## rawType when a method's back-reference points at a non-existent
## prior method call.  Verifies the parser handles the variant
## byte-for-byte.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedMethodErrorInvalidResultReference:
  forEachCapturedServer("method-error-invalid-result-reference", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len >= 1
    let inv = resp.methodResponses[resp.methodResponses.len - 1]
    doAssert inv.rawName == "error",
      "method-level errors arrive on the literal 'error' rawName, got " & inv.rawName
    let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
    doAssert me.rawType == "invalidResultReference",
      "Stalwart returns the canonical 'invalidResultReference' rawType, got " &
        me.rawType
    doAssert me.errorType == metInvalidResultReference,
      "errorType must project to metInvalidResultReference, got " & $me.errorType
    doAssert me.errorType == parseMethodErrorType(me.rawType),
      "errorType / rawType must be derived consistently"
    # ``description`` is RFC 8620 §3.6 optional ("MAY include").
    # Stalwart and James populate it with a human-readable resolution
    # failure; Cyrus 3.12.2 omits it. Both shapes are conformant; the
    # client-library contract is that when present it's a non-empty
    # string and when absent it projects to ``Opt.none``.
    for desc in me.description:
      doAssert desc.len > 0,
        "when description is provided, it must be a non-empty string"
