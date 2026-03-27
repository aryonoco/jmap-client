# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

import std/strutils
from std/json import JsonNode

import pkg/results

import ./primitives

type TransportErrorKind* = enum
  tekNetwork
  tekTls
  tekTimeout
  tekHttpStatus

type TransportError* = object
  message*: string
  case kind*: TransportErrorKind
  of tekHttpStatus:
    httpStatus*: int
  of tekNetwork, tekTls, tekTimeout:
    discard

func transportError*(kind: TransportErrorKind, message: string): TransportError =
  ## For non-HTTP-status transport errors.
  TransportError(kind: kind, message: message)

func httpStatusError*(status: int, message: string): TransportError =
  ## For HTTP-level failures without a JMAP problem details body.
  TransportError(kind: tekHttpStatus, message: message, httpStatus: status)

type RequestErrorType* = enum
  retUnknownCapability = "urn:ietf:params:jmap:error:unknownCapability"
  retNotJson = "urn:ietf:params:jmap:error:notJSON"
  retNotRequest = "urn:ietf:params:jmap:error:notRequest"
  retLimit = "urn:ietf:params:jmap:error:limit"
  retUnknown

func parseRequestErrorType*(raw: string): RequestErrorType =
  ## Total function: always succeeds. Unknown URIs map to retUnknown.
  strutils.parseEnum[RequestErrorType](raw, retUnknown)

type RequestError* = object
  errorType*: RequestErrorType ## parsed enum variant
  rawType*: string ## always populated — lossless round-trip
  status*: Opt[int] ## RFC 7807 "status" field
  title*: Opt[string] ## RFC 7807 "title" field
  detail*: Opt[string] ## RFC 7807 "detail" field
  limit*: Opt[string] ## which limit was exceeded (retLimit only)
  extras*: Opt[JsonNode] ## non-standard fields, lossless preservation

func requestError*(
    rawType: string,
    status: Opt[int] = Opt.none(int),
    title: Opt[string] = Opt.none(string),
    detail: Opt[string] = Opt.none(string),
    limit: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): RequestError =
  RequestError(
    errorType: parseRequestErrorType(rawType),
    rawType: rawType,
    status: status,
    title: title,
    detail: detail,
    limit: limit,
    extras: extras,
  )

type ClientErrorKind* = enum
  cekTransport
  cekRequest

type ClientError* = object
  case kind*: ClientErrorKind
  of cekTransport:
    transport*: TransportError
  of cekRequest:
    request*: RequestError

func clientError*(transport: TransportError): ClientError =
  ClientError(kind: cekTransport, transport: transport)

func clientError*(request: RequestError): ClientError =
  ClientError(kind: cekRequest, request: request)

func message*(err: ClientError): string =
  ## Human-readable message for any ClientError variant.
  case err.kind
  of cekTransport:
    err.transport.message
  of cekRequest:
    if err.request.detail.isSome:
      err.request.detail.unsafeGet
    elif err.request.title.isSome:
      err.request.title.unsafeGet
    else:
      err.request.rawType

type MethodErrorType* = enum
  metServerUnavailable = "serverUnavailable"
  metServerFail = "serverFail"
  metServerPartialFail = "serverPartialFail"
  metUnknownMethod = "unknownMethod"
  metInvalidArguments = "invalidArguments"
  metInvalidResultReference = "invalidResultReference"
  metForbidden = "forbidden"
  metAccountNotFound = "accountNotFound"
  metAccountNotSupportedByMethod = "accountNotSupportedByMethod"
  metAccountReadOnly = "accountReadOnly"
  metAnchorNotFound = "anchorNotFound"
  metUnsupportedSort = "unsupportedSort"
  metUnsupportedFilter = "unsupportedFilter"
  metCannotCalculateChanges = "cannotCalculateChanges"
  metTooManyChanges = "tooManyChanges"
  metRequestTooLarge = "requestTooLarge"
  metStateMismatch = "stateMismatch"
  metFromAccountNotFound = "fromAccountNotFound"
  metFromAccountNotSupportedByMethod = "fromAccountNotSupportedByMethod"
  metUnknown

func parseMethodErrorType*(raw: string): MethodErrorType =
  ## Total function: always succeeds. Unknown types map to metUnknown.
  strutils.parseEnum[MethodErrorType](raw, metUnknown)

type MethodError* = object
  errorType*: MethodErrorType ## parsed enum variant
  rawType*: string ## always populated — lossless round-trip
  description*: Opt[string] ## RFC "description" field
  extras*: Opt[JsonNode] ## non-standard fields, lossless preservation

func methodError*(
    rawType: string,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): MethodError =
  MethodError(
    errorType: parseMethodErrorType(rawType),
    rawType: rawType,
    description: description,
    extras: extras,
  )

type SetErrorType* = enum
  setForbidden = "forbidden"
  setOverQuota = "overQuota"
  setTooLarge = "tooLarge"
  setRateLimit = "rateLimit"
  setNotFound = "notFound"
  setInvalidPatch = "invalidPatch"
  setWillDestroy = "willDestroy"
  setInvalidProperties = "invalidProperties"
  setAlreadyExists = "alreadyExists"
  setSingleton = "singleton"
  setUnknown

func parseSetErrorType*(raw: string): SetErrorType =
  ## Total function: always succeeds. Unknown types map to setUnknown.
  strutils.parseEnum[SetErrorType](raw, setUnknown)

type SetError* = object
  rawType*: string ## always populated — lossless round-trip
  description*: Opt[string] ## optional human-readable description
  extras*: Opt[JsonNode] ## non-standard fields, lossless preservation
  existingId*: Opt[Id] ## the existing record's ID (§5.4); set for setAlreadyExists
  case errorType*: SetErrorType
  of setInvalidProperties:
    properties*: seq[string] ## invalid property names (§5.3)
  else:
    discard

func setError*(
    rawType: string,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## For non-variant-specific set errors.
  let errorType = parseSetErrorType(rawType)
  let safeType =
    if errorType in {setInvalidProperties, setAlreadyExists}: setUnknown else: errorType
  SetError(
    errorType: safeType, rawType: rawType, description: description, extras: extras
  )

func setErrorInvalidProperties*(
    rawType: string,
    properties: seq[string],
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  SetError(
    errorType: setInvalidProperties,
    rawType: rawType,
    description: description,
    extras: extras,
    properties: properties,
  )

func setErrorAlreadyExists*(
    rawType: string,
    existingId: Id,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  SetError(
    errorType: setAlreadyExists,
    rawType: rawType,
    description: description,
    extras: extras,
    existingId: Opt.some(existingId),
  )
