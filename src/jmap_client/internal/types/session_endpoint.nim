# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP session endpoint (Layer 1). Sealed Pattern-A sum describing how the
## client locates the session resource: a direct session URL or a bare
## discovery domain (RFC 8620 §2.2 ``.well-known/jmap``). Resolution to a
## concrete URL is effectful (future DNS-SRV) and lives at Layer 4 — this type
## is pure construction-time intent.
##
## **Threading.** A ``SessionEndpoint`` is an immutable value type — copy and
## share freely across threads.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/strutils

import ./validation

type SessionEndpointKind* = enum
  ## How the session resource is located. Additive: a future ``sekSrvDomain``
  ## arm carries DNS-SRV autodiscovery (RFC 8620 §2.2; P20/P23) and plugs into
  ## the Layer-4 resolver with no constructor change.
  sekDirectUrl
  sekDiscoveryDomain

type SessionEndpoint* {.ruleOff: "objects".} = object
  ## Sealed session endpoint. Construct via ``directEndpoint`` /
  ## ``discoveryEndpoint``; the payload is unreachable outside this module and
  ## the Layer-4 resolver.
  case kind*: SessionEndpointKind
  of sekDirectUrl:
    directUrl: string
  of sekDiscoveryDomain:
    domain: string

type SessionEndpointViolation = enum
  ## Structural-failure vocabulary for endpoint construction.
  sevEmptyUrl
  sevUrlBadScheme
  sevUrlControlChar
  sevEmptyDomain
  sevDomainWhitespace
  sevDomainSlash

func toValidationError(v: SessionEndpointViolation, raw: string): ValidationError =
  ## Sole domain-to-wire translator for ``SessionEndpointViolation``. Adding a
  ## variant forces a compile error here.
  case v
  of sevEmptyUrl:
    validationError("SessionEndpoint", "url must not be empty", raw)
  of sevUrlBadScheme:
    validationError("SessionEndpoint", "url must start with https:// or http://", raw)
  of sevUrlControlChar:
    validationError("SessionEndpoint", "url must not contain newline characters", raw)
  of sevEmptyDomain:
    validationError("SessionEndpoint", "domain must not be empty", raw)
  of sevDomainWhitespace:
    validationError("SessionEndpoint", "domain must not contain whitespace", raw)
  of sevDomainSlash:
    validationError("SessionEndpoint", "domain must not contain '/'", raw)

func directEndpoint*(url: string): Result[SessionEndpoint, ValidationError] =
  ## A precomputed JMAP session URL (RFC 8620 §2). Requires an ``https://`` or
  ## ``http://`` scheme and rejects embedded newlines (HTTP-framing guard).
  if url.len == 0:
    return err(toValidationError(sevEmptyUrl, url))
  if not url.startsWith("https://") and not url.startsWith("http://"):
    return err(toValidationError(sevUrlBadScheme, url))
  if url.contains({'\c', '\L'}):
    return err(toValidationError(sevUrlControlChar, url))
  ok(SessionEndpoint(kind: sekDirectUrl, directUrl: url))

func discoveryEndpoint*(domain: string): Result[SessionEndpoint, ValidationError] =
  ## A bare domain for ``.well-known/jmap`` autodiscovery (RFC 8620 §2.2).
  ## Rejects empty, whitespace, and ``/`` (scheme/path are synthesised at
  ## resolution).
  if domain.len == 0:
    return err(toValidationError(sevEmptyDomain, domain))
  if domain.contains(Whitespace):
    return err(toValidationError(sevDomainWhitespace, domain))
  if domain.contains('/'):
    return err(toValidationError(sevDomainSlash, domain))
  ok(SessionEndpoint(kind: sekDiscoveryDomain, domain: domain))

func `==`*(a, b: SessionEndpoint): bool =
  ## Arm-dispatched structural equality.
  case a.kind
  of sekDirectUrl:
    case b.kind
    of sekDirectUrl:
      a.directUrl == b.directUrl
    of sekDiscoveryDomain:
      false
  of sekDiscoveryDomain:
    case b.kind
    of sekDiscoveryDomain:
      a.domain == b.domain
    of sekDirectUrl:
      false

func `$`*(e: SessionEndpoint): string =
  ## Diagnostic rendering — the endpoint carries no secret.
  case e.kind
  of sekDirectUrl:
    "SessionEndpoint(url: " & e.directUrl & ")"
  of sekDiscoveryDomain:
    "SessionEndpoint(domain: " & e.domain & ")"

func asDirectUrl*(e: SessionEndpoint): Opt[string] =
  ## Hub-private projection (filtered at the L1 hub): the direct URL when
  ## ``kind`` is ``sekDirectUrl``, else ``Opt.none``. Consumed by the Layer-4
  ## endpoint resolver.
  case e.kind
  of sekDirectUrl:
    Opt.some(e.directUrl)
  of sekDiscoveryDomain:
    Opt.none(string)

func asDiscoveryDomain*(e: SessionEndpoint): Opt[string] =
  ## Hub-private projection: the discovery domain when ``kind`` is
  ## ``sekDiscoveryDomain``, else ``Opt.none``.
  case e.kind
  of sekDiscoveryDomain:
    Opt.some(e.domain)
  of sekDirectUrl:
    Opt.none(string)
