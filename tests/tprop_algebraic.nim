# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Algebraic law tests for Result and Opt types.

import std/random

import pkg/results

import ./mproperty

block propResultLeftIdentity:
  checkProperty "ok(a).flatMap(f) == f(a)":
    let a = rng.rand(int.low div 2 .. int.high div 2)
    func f(x: int): Result[int, string] =
      ## Doubles the input.
      ok(x * 2)

    doAssert Result[int, string].ok(a).flatMap(f) == f(a)

block propResultRightIdentity:
  checkProperty "m.flatMap(ok) == m":
    let a = rng.rand(int)
    let m = Result[int, string].ok(a)
    doAssert m.flatMap(
      proc(x: int): Result[int, string] =
        Result[int, string].ok(x)
    ) == m

block propResultMapFlatMapCoherence:
  checkProperty "m.map(f) == m.flatMap(x => ok(f(x)))":
    let a = rng.rand(int.low .. int.high - 1)
    let m = Result[int, string].ok(a)
    func f(x: int): int =
      ## Increments the input.
      x + 1
    let mapped = m.map(f)
    let flatMapped = m.flatMap(
      proc(x: int): Result[int, string] =
        Result[int, string].ok(f(x))
    )
    doAssert mapped == flatMapped

block propMapErrIdentity:
  checkProperty "mapErr(identity) == m":
    let a = rng.rand(int)
    let m = Result[int, string].ok(a)
    doAssert m.mapErr(
      proc(e: string): string =
        e
    ) == m

block propOptSomeNoneRoundTrip:
  checkProperty "Opt.some(x).get() == x":
    let x = rng.rand(int)
    doAssert Opt[int].ok(x).get() == x
    doAssert Opt[int].err().isNone

block propQuestionMarkPropagatesErr:
  func failing(): Result[int, string] =
    ## Always returns an error.
    err("fail")

  func pipeline(): Result[string, string] =
    ## Chains through failing, propagating the error.
    let x = ?failing()
    ok($x)

  doAssert pipeline().isErr
  doAssert pipeline().error == "fail"
