# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Algebraic law tests for Result and Opt types.

import std/random

import results

import ./mproperty

block propResultLeftIdentity:
  checkProperty "ok(a).flatMap(f) == f(a)":
    let a = rng.rand(int.low div 2 .. int.high div 2)
    lastInput = $a
    func f(x: int): Result[int, string] =
      ## Doubles the input.
      ok(x * 2)

    doAssert Result[int, string].ok(a).flatMap(f) == f(a)

block propResultRightIdentity:
  checkProperty "m.flatMap(ok) == m":
    let a = rng.rand(int)
    lastInput = $a
    let m = Result[int, string].ok(a)
    doAssert m.flatMap(
      proc(x: int): Result[int, string] =
        Result[int, string].ok(x)
    ) == m

block propResultMapFlatMapCoherence:
  checkProperty "m.map(f) == m.flatMap(x => ok(f(x)))":
    let a = rng.rand(int.low .. int.high - 1)
    lastInput = $a
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
    lastInput = $a
    let m = Result[int, string].ok(a)
    doAssert m.mapErr(
      proc(e: string): string =
        e
    ) == m

block propOptSomeNoneRoundTrip:
  checkProperty "Opt.some(x).get() == x":
    let x = rng.rand(int)
    lastInput = $x
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

# --- Result monad associativity ---

block propResultMonadAssociativity:
  checkProperty "m.flatMap(f).flatMap(g) == m.flatMap(x => f(x).flatMap(g))":
    let a = rng.rand(int.low div 4 .. int.high div 4)
    lastInput = $a
    let m = Result[int, string].ok(a)
    func f(x: int): Result[int, string] =
      ## Doubles the input.
      ok(x * 2)

    func g(x: int): Result[int, string] =
      ## Adds one to the input.
      ok(x + 1)

    let lhs = m.flatMap(f).flatMap(g)
    let rhs = m.flatMap(
      proc(x: int): Result[int, string] =
        f(x).flatMap(g)
    )
    doAssert lhs == rhs

# --- Result functor laws ---

block propResultFunctorIdentity:
  checkProperty "m.map(identity) == m":
    let a = rng.rand(int)
    lastInput = $a
    let m = Result[int, string].ok(a)
    let mapped = m.map(
      proc(x: int): int =
        x
    )
    doAssert mapped == m

block propResultFunctorComposition:
  checkProperty "m.map(f).map(g) == m.map(g . f)":
    let a = rng.rand(int.low div 4 .. int.high div 4)
    lastInput = $a
    let m = Result[int, string].ok(a)
    func f(x: int): int =
      ## Doubles the input.
      x * 2

    func g(x: int): int =
      ## Adds three to the input.
      x + 3

    let lhs = m.map(f).map(g)
    let rhs = m.map(
      proc(x: int): int =
        g(f(x))
    )
    doAssert lhs == rhs

# --- mapErr laws ---

block propMapErrComposition:
  checkProperty "m.mapErr(f).mapErr(g) == m.mapErr(g . f)":
    let a = rng.rand(int)
    lastInput = $a
    let m = Result[int, string].err("oops")
    func f(e: string): string =
      ## Appends exclamation mark.
      e & "!"

    func g(e: string): string =
      ## Appends question mark.
      e & "?"

    let lhs = m.mapErr(f).mapErr(g)
    let rhs = m.mapErr(
      proc(e: string): string =
        g(f(e))
    )
    doAssert lhs == rhs

block propMapErrOnOkIsNoop:
  checkProperty "ok(a).mapErr(f) == ok(a)":
    let a = rng.rand(int)
    lastInput = $a
    let m = Result[int, string].ok(a)
    let mapped = m.mapErr(
      proc(e: string): string =
        e & "!!!"
    )
    doAssert mapped == m

# --- Opt ---

block propOptSomeIsSome:
  checkProperty "Opt.some(x).isSome == true":
    let x = rng.rand(int)
    lastInput = $x
    doAssert Opt[int].ok(x).isSome == true

# --- Left zero / error-path laws ---

block propLeftZeroLaw:
  checkProperty "err(e).flatMap(f) == err(e)":
    let e = "error-" & $rng.rand(0 .. 9999)
    lastInput = e
    func f(x: int): Result[int, string] =
      ## Arbitrary pure mapping that should never be reached.
      ok(x * 3 + 7)

    let errVal = Result[int, string].err(e)
    doAssert errVal.flatMap(f) == Result[int, string].err(e)

block propFunctorOnError:
  checkProperty "err(e).map(f) == err(e)":
    let e = "error-" & $rng.rand(0 .. 9999)
    lastInput = e
    func f(x: int): int =
      ## Arbitrary pure mapping that should never be reached.
      x * 7 + 13

    let errVal = Result[int, string].err(e)
    doAssert errVal.map(f) == Result[int, string].err(e)

# --- Right identity on err ---

block propResultRightIdentityOnErr:
  checkProperty "err(e).flatMap(ok) == err(e)":
    let e = "error-" & $rng.rand(0 .. 9999)
    lastInput = e
    let errVal = Result[int, string].err(e)
    doAssert errVal.flatMap(
      proc(x: int): Result[int, string] =
        Result[int, string].ok(x)
    ) == errVal

# --- Mixed ok/err flatMap chain ---

block propResultMixedOkErrFlatMapChain:
  ## When f returns err, flatMap short-circuits: g is never reached.
  checkProperty "ok(a).flatMap(f_err).flatMap(g) == err(e)":
    let a = rng.rand(int.low div 2 .. int.high div 2)
    lastInput = $a
    # Left side: ok(a) -> err -> should stay err regardless of g
    let okVal = Result[int, string].ok(a)
    let afterFail = okVal.flatMap(
      proc(x: int): Result[int, string] =
        Result[int, string].err("fail-" & $x)
    )
    let lhs = afterFail.flatMap(
      proc(x: int): Result[int, string] =
        Result[int, string].ok(x + 1)
    )
    doAssert lhs.isErr
    doAssert lhs == afterFail

# --- valueOr properties ---

block propResultValueOrOnOk:
  checkProperty "ok(a).valueOr(d) == a":
    let a = rng.rand(int)
    let d = rng.rand(int)
    lastInput = $a
    let m = Result[int, string].ok(a)
    let got = m.valueOr:
      d
    doAssert got == a

block propResultValueOrOnErr:
  checkProperty "err(e).valueOr(d) == d":
    let e = "error-" & $rng.rand(0 .. 9999)
    let d = rng.rand(int)
    lastInput = e
    let m = Result[int, string].err(e)
    let got = m.valueOr:
      d
    doAssert got == d

# --- isOk xor isErr exhaustiveness ---

block propResultIsOkXorIsErr:
  checkProperty "m.isOk != m.isErr for ok and err":
    let a = rng.rand(int)
    lastInput = $a
    let okVal = Result[int, string].ok(a)
    doAssert okVal.isOk != okVal.isErr
    let e = "error-" & $rng.rand(0 .. 9999)
    let errVal = Result[int, string].err(e)
    doAssert errVal.isOk != errVal.isErr

# --- Natural transformation: Result projected to Opt ---

block propNaturalTransformationResultToOpt:
  checkProperty "Result.ok(x) -> Opt.ok(x), Result.err(e) -> Opt.none":
    let x = rng.rand(int)
    lastInput = $x
    let okRes = Result[int, string].ok(x)
    let okOpt = Opt[int].ok(x)
    doAssert okRes.isOk == okOpt.isSome
    doAssert okRes.get() == okOpt.get()
    let e = "error-" & $rng.rand(0 .. 9999)
    let errRes = Result[int, string].err(e)
    let errOpt = Opt[int].err()
    doAssert errRes.isErr == errOpt.isNone
