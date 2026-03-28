# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Compile-time type safety verification via doAssert not compiles(...).

import pkg/results

import jmap_client/types

# --- Distinct type isolation ---

block distinctTypeIsolation:
  let id = parseId("abc").get()
  let aid = parseAccountId("abc").get()
  let state = parseJmapState("abc").get()
  doAssert not compiles(id == aid)
  doAssert not compiles(id == state)
  doAssert not compiles(aid == state)

block distinctTypeNoConcatenation:
  let a = parseId("abc").get()
  let b = parseId("def").get()
  doAssert not compiles(a & b)

block unsignedIntNoArithmetic:
  let a = parseUnsignedInt(1).get()
  let b = parseUnsignedInt(2).get()
  doAssert not compiles(a + b)
  doAssert not compiles(a - b)
  doAssert not compiles(a * b)

block jmapIntNoArithmetic:
  let a = parseJmapInt(1).get()
  let b = parseJmapInt(2).get()
  doAssert not compiles(a + b)
  doAssert not compiles(a - b)
  doAssert not compiles(a * b)
  doAssert compiles(-a)

# --- Case object construction type safety ---

block transportErrorWrongVariantConstruction:
  doAssert not compiles(
    TransportError(kind: tekNetwork, httpStatus: 404, message: "fail")
  )

block clientErrorWrongVariantConstruction:
  doAssert not compiles(
    ClientError(
      kind: cekTransport,
      request: RequestError(
        errorType: retUnknown,
        rawType: "x",
        status: Opt.none(int),
        title: Opt.none(string),
        detail: Opt.none(string),
        limit: Opt.none(string),
        extras: Opt.none(JsonNode),
      ),
    )
  )

block referencableWrongVariantConstruction:
  doAssert not compiles(
    Referencable[int](
      kind: rkDirect,
      reference: ResultReference(
        resultOf: parseMethodCallId("c1").get(), name: "Foo/get", path: "/ids"
      ),
    )
  )

block filterWrongVariantConstruction:
  doAssert not compiles(
    Filter[int](kind: fkCondition, operator: foAnd, conditions: @[])
  )

# --- Railway type independence ---

block railwayTypesNotInterchangeable:
  let ve = Result[int, ValidationError].ok(1)
  let me = Result[int, MethodError].ok(1)
  doAssert not compiles(
    block:
      let x: JmapResult[int] = ve
  )
  doAssert not compiles(
    block:
      let y: JmapResult[int] = me
  )

# --- Hash divergence (non-degenerate hash smoke test) ---

block hashDivergenceId:
  doAssert hash(parseId("abc").get()) != hash(parseId("xyz").get())

block hashDivergenceAccountId:
  doAssert hash(parseAccountId("abc").get()) != hash(parseAccountId("xyz").get())

block hashDivergenceJmapState:
  doAssert hash(parseJmapState("abc").get()) != hash(parseJmapState("xyz").get())

block hashDivergenceUriTemplate:
  doAssert hash(parseUriTemplate("https://a.com").get()) !=
    hash(parseUriTemplate("https://b.com").get())

block hashDivergencePropertyName:
  doAssert hash(parsePropertyName("name").get()) !=
    hash(parsePropertyName("other").get())
