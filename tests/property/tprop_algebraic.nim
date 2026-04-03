# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Algebraic law tests for Option types.

import std/options
import std/random

import ../mproperty

# --- Option ---

block propOptSomeNoneRoundTrip:
  checkProperty "some(x).get() == x":
    let x = rng.rand(int)
    lastInput = $x
    doAssert some(x).get() == x
    doAssert none(int).isNone

block propOptSomeIsSome:
  checkProperty "some(x).isSome == true":
    let x = rng.rand(int)
    lastInput = $x
    doAssert some(x).isSome == true

block propOptNoneIsNone:
  checkProperty "none(int).isNone == true":
    lastInput = "(none)"
    doAssert none(int).isNone == true

block propOptMapIdentity:
  checkProperty "some(x).map(identity) == some(x)":
    let x = rng.rand(int)
    lastInput = $x
    let m = some(x)
    let mapped = m.map(
      proc(v: int): int =
        v
    )
    doAssert mapped == m

block propOptMapComposition:
  checkProperty "some(x).map(f).map(g) == some(x).map(g . f)":
    let x = rng.rand(int.low div 4 .. int.high div 4)
    lastInput = $x
    let m = some(x)
    proc f(v: int): int =
      v * 2

    proc g(v: int): int =
      v + 3

    let lhs = m.map(f).map(g)
    let rhs = m.map(
      proc(v: int): int =
        g(f(v))
    )
    doAssert lhs == rhs

block propOptFlatMapLeftIdentity:
  checkProperty "some(a).flatMap(f) == f(a)":
    let a = rng.rand(int.low div 2 .. int.high div 2)
    lastInput = $a
    proc f(x: int): Option[int] =
      some(x * 2)

    doAssert some(a).flatMap(f) == f(a)

block propOptFlatMapRightIdentity:
  checkProperty "m.flatMap(some) == m":
    let a = rng.rand(int)
    lastInput = $a
    let m = some(a)
    doAssert m.flatMap(
      proc(x: int): Option[int] =
        some(x)
    ) == m

block propOptFlatMapAssociativity:
  checkProperty "m.flatMap(f).flatMap(g) == m.flatMap(x => f(x).flatMap(g))":
    let a = rng.rand(int.low div 4 .. int.high div 4)
    lastInput = $a
    let m = some(a)
    proc f(x: int): Option[int] =
      some(x * 2)

    proc g(x: int): Option[int] =
      some(x + 1)

    let lhs = m.flatMap(f).flatMap(g)
    let rhs = m.flatMap(
      proc(x: int): Option[int] =
        f(x).flatMap(g)
    )
    doAssert lhs == rhs

block propOptNoneFlatMapIsNone:
  checkProperty "none.flatMap(f) == none":
    lastInput = "(none)"
    proc f(x: int): Option[int] =
      some(x * 3 + 7)

    doAssert none(int).flatMap(f) == none(int)

block propOptNoneMapIsNone:
  checkProperty "none.map(f) == none":
    lastInput = "(none)"
    proc f(x: int): int =
      x * 7 + 13

    doAssert none(int).map(f) == none(int)

block propOptIsSomeXorIsNone:
  checkProperty "o.isSome != o.isNone for some and none":
    let a = rng.rand(int)
    lastInput = $a
    let someVal = some(a)
    doAssert someVal.isSome != someVal.isNone
    let noneVal = none(int)
    doAssert noneVal.isSome != noneVal.isNone
