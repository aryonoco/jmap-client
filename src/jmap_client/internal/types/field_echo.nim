# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Partial-response primitives consumed by ``SetResponse[T, U]``
## (`internal/protocol/methods.nim`) and ``GetResponse[PartialT]``
## (typed sparse `/get`).
##
## ``FieldEcho[T]`` represents the RFC 8620 §5.3 three-state per-field
## echo: absent / null / value. Two-state ``Opt[T]`` would conflate
## "server did not echo" with "server echoed null", losing one bit
## of fidelity per wire-nullable property.
##
## ``NoCreate`` fills the ``T`` slot of ``SetResponse[T, U]`` for entities
## whose ``/set`` has no create rail (singleton entities — currently
## only ``VacationResponse``).
##
## Serde (``NoCreate.fromJson``/``toJson`` plus the ``parsePartialOptField``
## / ``parsePartialFieldEcho`` / ``emitPartialFieldEcho`` helper templates)
## lives in ``internal/serialisation/serde_field_echo.nim`` — keeping this
## L1 module free of ``JsonNode`` / ``SerdeViolation`` dependencies.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes

import ./validation

type FieldEchoKind* = enum
  ## Discriminator for ``FieldEcho`` — names the three RFC 8620 §5.3
  ## per-field echo states.
  fekAbsent
  fekNull
  fekValue

type FieldEcho*[T] {.ruleOff: "objects".} = object
  ## RFC 8620 §5.3 three-state per-field echo for a wire-nullable
  ## property. Generic over the payload type ``T``; ``T`` is read only
  ## inside the ``fekValue`` arm so callers must dispatch on ``kind``.
  case kind*: FieldEchoKind
  of fekAbsent, fekNull:
    discard
  of fekValue:
    value*: T

template fieldAbsent*[T](t: typedesc[T]): FieldEcho[T] =
  ## Smart constructor for the ``fekAbsent`` variant — the server did
  ## not echo the property.
  discard $t
  FieldEcho[T](kind: fekAbsent)

template fieldNull*[T](t: typedesc[T]): FieldEcho[T] =
  ## Smart constructor for the ``fekNull`` variant — the server echoed
  ## the property with wire JSON null.
  discard $t
  FieldEcho[T](kind: fekNull)

template fieldValue*[T](v: T): FieldEcho[T] =
  ## Smart constructor for the ``fekValue`` variant — ``T`` is inferred
  ## from the argument.
  FieldEcho[T](kind: fekValue, value: v)

func isValue*[T](fe: FieldEcho[T]): bool =
  ## ``true`` iff the server echoed a non-null value (``fekValue``).
  fe.kind == fekValue

func isNull*[T](fe: FieldEcho[T]): bool =
  ## ``true`` iff the server echoed JSON ``null`` (``fekNull`` — the property
  ## was affirmatively cleared, RFC 8620 §5.3).
  fe.kind == fekNull

func isAbsent*[T](fe: FieldEcho[T]): bool =
  ## ``true`` iff the property was not echoed (``fekAbsent`` — unchanged / not
  ## requested; distinct from ``isNull`` for incremental ``/changes`` sync).
  fe.kind == fekAbsent

template valueOr*[T](fe: FieldEcho[T], def: untyped): T =
  ## Primary fallback reader, mirroring ``nim-results`` ``Opt.valueOr`` so an
  ## ``Opt`` field and a ``FieldEcho`` field read through the same call shape:
  ## the echoed value on ``fekValue``, the lazily-evaluated ``def`` on
  ## ``fekAbsent``/``fekNull``. ``fe`` is bound once (the argument may be a
  ## call), exactly as ``Opt.valueOr`` binds ``let s = self``.
  let f = fe
  case f.kind
  of fekValue: f.value
  of fekAbsent, fekNull: def

iterator items*[T](fe: FieldEcho[T]): T =
  ## Mirrors ``for v in opt:`` — yields once on ``fekValue``, never otherwise.
  case fe.kind
  of fekValue:
    yield fe.value
  of fekAbsent, fekNull:
    discard

func toOpt*[T](fe: FieldEcho[T]): Opt[T] =
  ## The everyday bridge for render-only callers: lets ``Email.subject`` (Opt)
  ## and ``PartialEmail.subject`` (FieldEcho) flow through one rendering
  ## function. DELIBERATELY collapses ``fekAbsent`` + ``fekNull`` → ``none`` —
  ## an opt-in lossy reader, NOT a converter, NOT erasure of the type (the
  ## ``isAbsent``/``isNull`` predicates remain for offline-sync callers).
  case fe.kind
  of fekValue:
    Opt.some(fe.value)
  of fekAbsent, fekNull:
    Opt.none(T)

func `==`*[T](a, b: FieldEcho[T]): bool =
  ## Arm-dispatched equality. Case-objects under strict require nested
  ## ``case`` rather than mixed ``if``/field-access (Rule 1 in
  ## ``nim-type-safety.md``).
  case a.kind
  of fekAbsent:
    case b.kind
    of fekAbsent: true
    of fekNull, fekValue: false
  of fekNull:
    case b.kind
    of fekNull: true
    of fekAbsent, fekValue: false
  of fekValue:
    case b.kind
    of fekValue:
      a.value == b.value
    of fekAbsent, fekNull:
      false

func hash*[T](e: FieldEcho[T]): Hash =
  ## Arm-dispatched hash; mixes the discriminator ordinal into the
  ## payload so distinct variants do not collide.
  var h: Hash = 0
  h = h !& hash(e.kind.ord)
  case e.kind
  of fekAbsent, fekNull:
    discard
  of fekValue:
    h = h !& hash(e.value)
  !$h

type NoCreate* {.ruleOff: "objects".} = object
  ## Marker filling the ``T`` slot of ``SetResponse[T, U]`` for entities
  ## with no create rail. Empty by construction; ``createResults`` is
  ## empty for compliant servers.
