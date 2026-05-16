# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## HTTP-response classification for JMAP. Pure: takes a wire-shape
## ``HttpResponse`` (produced by any ``Transport``), returns either a
## parsed JSON value (used by ``fetchSession``), a parsed
## ``envelope.Response`` (used by ``send``), or a ``ClientError``
## carrying the appropriate transport / request rejection.
##
## Internal to the client package. H10's ``tests/`` exemption permits
## test files to import this module when they need to project a wire
## response without driving the full typed-builder pipeline (e.g., the
## adversarial-POST tests that previously called
## ``sendRawHttpForTesting``).

{.push raises: [].}
{.experimental: "strictCaseObjects".}

import std/json
import std/strutils

import results

import ../transport
import ../types/errors
import ../types/envelope as envelope
import ../serialisation/serde
import ../serialisation/serde_diagnostics
import ../serialisation/serde_errors
import ../serialisation/serde_envelope

proc tryParseProblemDetails(body: string): Opt[ClientError] =
  ## Attempts to parse RFC 7807 problem details from a response body.
  ## Returns ``Opt.some(ClientError)`` on success, ``none`` when the body
  ## is not JSON, not an object, missing ``"type"``, or otherwise fails
  ## ``RequestError.fromJson``.
  try:
    {.cast(raises: [CatchableError]).}:
      let jsonNode = parseJson(body)
      if jsonNode.kind == JObject and jsonNode.hasKey("type"):
        let reqErrResult = RequestError.fromJson(jsonNode)
        if reqErrResult.isOk:
          return Opt.some(clientError(reqErrResult.get()))
  except CatchableError:
    discard
  Opt.none(ClientError)

proc parseJsonBody(
    body: string, context: RequestContext
): Result[JsonNode, ClientError] =
  ## Parses a response body as JSON. Returns err if the body is not
  ## valid JSON, carrying the context label (``session`` / ``api``) in
  ## the diagnostic so the caller can distinguish the failing endpoint.
  try:
    {.cast(raises: [CatchableError]).}:
      ok(parseJson(body))
  except CatchableError as e:
    err(
      clientError(
        transportError(
          tekNetwork, "invalid JSON in " & $context & " response: " & e.msg
        )
      )
    )

proc classifyStatus(
    statusCode: int, contentType, body: string, context: RequestContext
): Result[void, ClientError] =
  ## HTTP-status classification. 2xx with ``application/json`` Content-
  ## Type proceeds to the caller's parse step; 4xx/5xx attempt RFC 7807
  ## problem-details extraction then fall back to a generic
  ## ``httpStatusError``; anything else (1xx, 3xx) is rejected.
  if statusCode >= 400 and statusCode < 600:
    if contentType.startsWith("application/problem+json") or
        contentType.startsWith("application/json"):
      for ce in tryParseProblemDetails(body):
        return err(ce)
    return err(
      clientError(
        httpStatusError(statusCode, "HTTP " & $statusCode & " from " & $context)
      )
    )
  if statusCode < 200 or statusCode >= 300:
    return err(
      clientError(
        httpStatusError(
          statusCode, "unexpected HTTP " & $statusCode & " from " & $context
        )
      )
    )
  if not contentType.startsWith("application/json"):
    return err(
      clientError(
        transportError(
          tekNetwork, "unexpected Content-Type from " & $context & ": " & contentType
        )
      )
    )
  ok()

proc parseJmapJson*(
    httpResp: HttpResponse, context: RequestContext
): Result[JsonNode, ClientError] =
  ## Classifies the HTTP response and parses the body as JSON.
  ## Returns the parsed ``JsonNode`` on 2xx with ``application/json``
  ## Content-Type. Used by ``fetchSession`` — the caller invokes
  ## ``Session.fromJson`` on the result.
  ?classifyStatus(httpResp.statusCode, httpResp.contentType, httpResp.body, context)
  parseJsonBody(httpResp.body, context)

proc parseJmapResponse*(
    httpResp: HttpResponse, context: RequestContext
): Result[envelope.Response, ClientError] =
  ## Classifies the HTTP response, parses the body as JSON, detects
  ## RFC 7807 problem details on HTTP 200, and decodes the envelope.
  ## Used by ``send`` and by tests that POST adversarial bodies through
  ## their own transport.
  let respJson = ?parseJmapJson(httpResp, context)
  if respJson.kind == JObject and respJson.hasKey("type") and
      not respJson.hasKey("methodResponses"):
    let reqErrResult = RequestError.fromJson(respJson)
    if reqErrResult.isOk:
      return err(clientError(reqErrResult.get()))
  envelope.Response.fromJson(respJson).mapErr(
    proc(sv: SerdeViolation): ClientError =
      validationToClientErrorCtx(
        toValidationError(sv, "Response"), "invalid response: "
      )
  )
