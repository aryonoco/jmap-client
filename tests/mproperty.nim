# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based testing infrastructure with fixed-seed reproducibility.

import std/random

import jmap_client/validation

{.push ruleOff: "hasDoc".}
{.push ruleOff: "params".}

const DefaultTrials* = 500

template checkProperty*(name: string, body: untyped) =
  ## Runs body DefaultTrials times with an injected `rng` and `trial` variable.
  ## Fixed seed (42) ensures deterministic reproduction. The `name` parameter
  ## documents the property being tested.
  block:
    var rng {.inject.} = initRand(42)
    for trial {.inject.} in 0 ..< DefaultTrials:
      body

{.pop.} # params

proc genBase64UrlChar*(rng: var Rand): char =
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  chars[rng.rand(chars.high)]

proc genAsciiPrintable*(rng: var Rand): char =
  ## Characters 0x20-0x7E (space through tilde, excluding DEL).
  char(rng.rand(0x20 .. 0x7E))

proc genControlChar*(rng: var Rand): char =
  ## Characters 0x00-0x1F plus DEL (0x7F).
  let i = rng.rand(0 .. 32) # 33 control chars total
  if i == 32:
    return '\x7F'
  char(i)

proc genArbitraryByte*(rng: var Rand): char =
  char(rng.rand(0 .. 255))

proc genValidIdStrict*(rng: var Rand, minLen = 1, maxLen = 255): string =
  let length = rng.rand(minLen .. maxLen)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genBase64UrlChar()

proc genArbitraryString*(rng: var Rand, maxLen = 512): string =
  let length = rng.rand(0 .. maxLen)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genArbitraryByte()

proc genValidUnsignedInt*(rng: var Rand): int64 =
  rng.rand(0'i64 .. 9_007_199_254_740_991'i64)

proc genValidJmapInt*(rng: var Rand): int64 =
  rng.rand(-9_007_199_254_740_991'i64 .. 9_007_199_254_740_991'i64)
