# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Algebraic law tests for Opt types.

import std/random

import results

import ../mproperty
import ../mtestblock

# --- Opt ---

testCase propOptSomeNoneRoundTrip:
  checkProperty "Opt.some(x).get() == x":
    let x = rng.rand(int)
    lastInput = $x
    doAssert Opt.some(x).get() == x
    doAssert Opt.none(int).isNone

testCase propOptSomeIsSome:
  checkProperty "Opt.some(x).isSome == true":
    let x = rng.rand(int)
    lastInput = $x
    doAssert Opt.some(x).isSome == true

testCase propOptNoneIsNone:
  checkProperty "Opt.none(int).isNone == true":
    lastInput = "(none)"
    doAssert Opt.none(int).isNone == true

testCase propOptMapIdentity:
  checkProperty "Opt.some(x).map(identity) == Opt.some(x)":
    let x = rng.rand(int)
    lastInput = $x
    let m = Opt.some(x)
    let mapped = m.map(
      proc(v: int): int =
        v
    )
    doAssert mapped == m

testCase propOptMapComposition:
  checkProperty "Opt.some(x).map(f).map(g) == Opt.some(x).map(g . f)":
    let x = rng.rand(int.low div 4 .. int.high div 4)
    lastInput = $x
    let m = Opt.some(x)
    proc f(v: int): int =
      ## Doubles the input.
      v * 2

    proc g(v: int): int =
      ## Adds three to the input.
      v + 3

    let lhs = m.map(f).map(g)
    let rhs = m.map(
      proc(v: int): int =
        g(f(v))
    )
    doAssert lhs == rhs

testCase propOptFlatMapLeftIdentity:
  checkProperty "Opt.some(a).flatMap(f) == f(a)":
    let a = rng.rand(int.low div 2 .. int.high div 2)
    lastInput = $a
    proc f(x: int): Opt[int] =
      ## Doubles the input, wrapped in Some.
      Opt.some(x * 2)

    doAssert Opt.some(a).flatMap(f) == f(a)

testCase propOptFlatMapRightIdentity:
  checkProperty "m.flatMap(some) == m":
    let a = rng.rand(int)
    lastInput = $a
    let m = Opt.some(a)
    doAssert m.flatMap(
      proc(x: int): Opt[int] =
        Opt.some(x)
    ) == m

testCase propOptFlatMapAssociativity:
  checkProperty "m.flatMap(f).flatMap(g) == m.flatMap(x => f(x).flatMap(g))":
    let a = rng.rand(int.low div 4 .. int.high div 4)
    lastInput = $a
    let m = Opt.some(a)
    proc f(x: int): Opt[int] =
      ## Doubles the input, wrapped in Some.
      Opt.some(x * 2)

    proc g(x: int): Opt[int] =
      ## Increments the input, wrapped in Some.
      Opt.some(x + 1)

    let lhs = m.flatMap(f).flatMap(g)
    let rhs = m.flatMap(
      proc(x: int): Opt[int] =
        f(x).flatMap(g)
    )
    doAssert lhs == rhs

testCase propOptNoneFlatMapIsNone:
  checkProperty "none.flatMap(f) == none":
    lastInput = "(none)"
    proc f(x: int): Opt[int] =
      ## Affine transform, wrapped in Some.
      Opt.some(x * 3 + 7)

    doAssert Opt.none(int).flatMap(f) == Opt.none(int)

testCase propOptNoneMapIsNone:
  checkProperty "none.map(f) == none":
    lastInput = "(none)"
    proc f(x: int): int =
      ## Affine transform.
      x * 7 + 13

    doAssert Opt.none(int).map(f) == Opt.none(int)

testCase propOptIsSomeXorIsNone:
  checkProperty "o.isSome != o.isNone for some and none":
    let a = rng.rand(int)
    lastInput = $a
    let someVal = Opt.some(a)
    doAssert someVal.isSome != someVal.isNone
    let noneVal = Opt.none(int)
    doAssert noneVal.isSome != noneVal.isNone
