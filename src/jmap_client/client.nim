# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP client handle — type definition, smart constructors, read-only
## accessors, and mutators. The imperative shell boundary where IO occurs
## (Layer 4). Not thread-safe — all calls must originate from a single
## thread (architecture §4.3).

import std/httpclient
import std/strutils

import ./types

# Design §9.1 (D4.12): compile-time hint when -d:ssl is missing.
# Uses {.hint:} rather than {.warning:} because config.nims promotes
# User warnings to errors (warningAsError: User). A hint achieves the
# same informational goal without blocking compilation.
when not defined(ssl):
  {.
    hint:
      "jmap-client: -d:ssl is not defined. " & "HTTPS connections will fail at runtime. " &
      "Add -d:ssl to your compile flags."
  .}

{.push ruleOff: "objects".}

type JmapClient* = object
  ## JMAP client handle. Encapsulates connection state, authentication,
  ## cached session, and HTTP configuration. Not thread-safe — all calls
  ## must originate from a single thread.
  ##
  ## Construction: ``initJmapClient()`` or ``discoverJmapClient()``.
  ## Destruction: ``close()`` releases the underlying HTTP connection.
  ##
  ## All fields are module-private — access via public accessor procs.
  ## This makes invalid states unrepresentable: callers cannot construct
  ## a JmapClient with an empty URL or missing token.
  ##
  ## Copying a ``JmapClient`` shares the underlying HTTP connection —
  ## ``close()`` on any copy closes it for all copies.
  httpClient: HttpClient
  sessionUrl: string
  bearerToken: string
  session: Option[Session]
  maxResponseBytes: int
  userAgent: string

{.pop.}

proc initJmapClient*(
    sessionUrl: string,
    bearerToken: string,
    timeout: int = 30_000,
    maxRedirects: int = 5,
    maxResponseBytes: int = 50_000_000,
    userAgent: string = "jmap-client-nim/0.1.0",
): JmapClient =
  ## Creates a new JmapClient from a known session URL and bearer token.
  ##
  ## Does NOT fetch the session — call ``fetchSession()`` explicitly or
  ## let ``send()`` fetch it lazily on first call.
  ##
  ## Raises ``ValidationError`` if any parameter is invalid.
  if sessionUrl.len == 0:
    raise newValidationError("JmapClient", "sessionUrl must not be empty", "")
  if not sessionUrl.startsWith("https://") and not sessionUrl.startsWith("http://"):
    raise newValidationError(
      "JmapClient", "sessionUrl must start with https:// or http://", sessionUrl
    )
  if bearerToken.len == 0:
    raise newValidationError("JmapClient", "bearerToken must not be empty", "")
  if timeout < -1:
    raise newValidationError("JmapClient", "timeout must be >= -1", $timeout)
  if maxRedirects < 0:
    raise newValidationError("JmapClient", "maxRedirects must be >= 0", $maxRedirects)
  if maxResponseBytes < 0:
    raise newValidationError(
      "JmapClient", "maxResponseBytes must be >= 0", $maxResponseBytes
    )
  let headers = newHttpHeaders(
    {
      "Authorization": "Bearer " & bearerToken,
      "Content-Type": "application/json",
      "Accept": "application/json",
    }
  )
  let httpClient = newHttpClient(
    userAgent = userAgent,
    timeout = timeout,
    maxRedirects = maxRedirects,
    headers = headers,
  )
  JmapClient(
    httpClient: httpClient,
    sessionUrl: sessionUrl,
    bearerToken: bearerToken,
    session: none(Session),
    maxResponseBytes: maxResponseBytes,
    userAgent: userAgent,
  )

proc discoverJmapClient*(
    domain: string,
    bearerToken: string,
    timeout: int = 30_000,
    maxRedirects: int = 5,
    maxResponseBytes: int = 50_000_000,
    userAgent: string = "jmap-client-nim/0.1.0",
): JmapClient =
  ## Creates a JmapClient by constructing the ``.well-known/jmap`` URL from
  ## a domain name (RFC 8620 §2.2).
  ##
  ## Raises ``ValidationError`` if domain or bearerToken are invalid.
  if domain.len == 0:
    raise newValidationError("JmapClient", "domain must not be empty", "")
  for c in domain:
    if c in Whitespace:
      raise
        newValidationError("JmapClient", "domain must not contain whitespace", domain)
  if '/' in domain:
    raise newValidationError("JmapClient", "domain must not contain '/'", domain)
  initJmapClient(
    sessionUrl = "https://" & domain & "/.well-known/jmap",
    bearerToken = bearerToken,
    timeout = timeout,
    maxRedirects = maxRedirects,
    maxResponseBytes = maxResponseBytes,
    userAgent = userAgent,
  )

proc session*(client: JmapClient): Option[Session] =
  ## Returns the cached Session, or ``none`` if not yet fetched.
  client.session

proc sessionUrl*(client: JmapClient): string =
  ## Returns the session resource URL.
  client.sessionUrl

proc bearerToken*(client: JmapClient): string =
  ## Returns the current bearer token.
  client.bearerToken

proc setBearerToken*(client: var JmapClient, token: string) =
  ## Updates the bearer token. Subsequent requests use the new token.
  ## Also updates the Authorization header on the underlying HttpClient.
  ##
  ## Raises ``ValidationError`` if token is empty.
  if token.len == 0:
    raise newValidationError("JmapClient", "bearerToken must not be empty", "")
  client.bearerToken = token
  client.httpClient.headers["Authorization"] = "Bearer " & token

proc close*(client: var JmapClient) =
  ## Closes the underlying HTTP connection. Releases the socket
  ## immediately. Idempotent — safe to call multiple times.
  client.httpClient.close()
