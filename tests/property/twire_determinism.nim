# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A28b: ``BuiltRequest.toJson`` wire-byte determinism. The bytes
## are locked by the rendering implementation in
## ``internal/serialisation/serde_envelope.nim``'s ``Request.toJson``;
## any future refactor that breaks key order or whitespace
## normalisation trips one of the assertions below.

{.push raises: [].}

import std/[json, random]

import results
import jmap_client
import jmap_client/internal/protocol/builder
import jmap_client/internal/serialisation/serde_envelope
import jmap_client/internal/types/envelope

import ../mproperty
import ../mtestblock

const trials = 100

testCase a28bByteDeterminism:
  ## $br.toJson() produces the same bytes on every call for the same
  ## BuiltRequest.
  var rng = initRand(0x28b)
  for _ in 0 ..< trials:
    let br = rng.genBuiltRequest()
    let a = $br.toJson()
    let b = $br.toJson()
    doAssert a == b

testCase a28bKeyOrder:
  ## Top-level keys appear in the locked order: ``using``,
  ## ``methodCalls``, then ``createdIds`` (when present).
  var rng = initRand(0x28b + 1)
  for _ in 0 ..< trials:
    let br = rng.genBuiltRequest()
    let node = parseJson($br.toJson())
    var keys: seq[string] = @[]
    for k in node.keys:
      keys.add k
    doAssert keys[0] == "using"
    doAssert keys[1] == "methodCalls"
    if keys.len >= 3:
      doAssert keys[2] == "createdIds"

testCase a28bRoundTripIdentity:
  ## Request.fromJson(parseJson($br.toJson())).get() equals br.request.
  var rng = initRand(0x28b + 2)
  for _ in 0 ..< trials:
    let br = rng.genBuiltRequest()
    let parsed = Request.fromJson(parseJson($br.toJson())).get()
    doAssert parsed == br.request
