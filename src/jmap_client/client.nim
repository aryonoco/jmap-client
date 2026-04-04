# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP client handle — type definition, smart constructors, read-only
## accessors, and mutators. The imperative shell boundary where IO occurs
## (Layer 4). Not thread-safe — all calls must originate from a single
## thread (architecture §4.3).

import std/httpclient
import std/json
import std/strutils

from std/net import TimeoutError
when defined(ssl):
  from std/net import SslError

import ./types
import ./serialisation

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

# ---------------------------------------------------------------------------
# Pure helpers (§2, §7)
# ---------------------------------------------------------------------------

proc expandUriTemplate*(
    tmpl: UriTemplate, variables: openArray[(string, string)]
): string =
  ## Expands an RFC 6570 Level 1 URI template by replacing ``{name}`` with
  ## the corresponding value. Variables not found in ``variables`` are left
  ## unexpanded. Caller is responsible for percent-encoding values that
  ## require it (``std/uri.encodeUrl(value, usePlus=false)``). Pure.
  result = string(tmpl)
  for (name, value) in variables:
    result = result.replace("{" & name & "}", value)

proc isTlsRelatedMsg(msg: string): bool =
  ## Heuristic: checks whether an OSError message indicates a TLS failure.
  ## OpenSSL surfaces TLS errors as OSError with keywords in the message
  ## (D4.5). False positives are harmless — the error is still a transport
  ## failure and ``msg`` carries the actual underlying error.
  let lower = msg.toLowerAscii
  "ssl" in lower or "tls" in lower or "certificate" in lower

proc classifyException*(e: ref CatchableError): ref ClientError =
  ## Maps ``std/httpclient`` exceptions to ``ClientError(cekTransport)``.
  ## Pure: no IO, no side effects. Exhaustive over known exception types.
  var te: TransportError
  if e of ref TimeoutError:
    te = transportError(tekTimeout, e.msg)
  elif (when defined(ssl): e of ref SslError else: false):
    te = transportError(tekTls, e.msg)
  elif e of ref OSError:
    te =
      if isTlsRelatedMsg(e.msg):
        transportError(tekTls, e.msg)
      else:
        transportError(tekNetwork, e.msg)
  elif e of ref IOError:
    te = transportError(tekNetwork, e.msg)
  elif e of ref ValueError:
    te = transportError(tekNetwork, "protocol error: " & e.msg)
  else:
    te = transportError(tekNetwork, "unexpected error: " & e.msg)
  newClientError(te)

proc enforceBodySizeLimit*(maxResponseBytes: int, body: string, context: string) =
  ## Phase 2 body size enforcement: post-read rejection via actual body
  ## length. No-op when ``maxResponseBytes == 0`` (no limit). Pure.
  if maxResponseBytes > 0 and body.len > maxResponseBytes:
    let te = transportError(
      tekNetwork,
      context & " response body exceeds limit: " & $body.len & " bytes > " &
        $maxResponseBytes & " byte limit",
    )
    raise newClientError(te)

proc enforceContentLengthLimit(
    maxResponseBytes: int, httpResp: httpclient.Response, context: string
) =
  ## Phase 1 body size enforcement: early rejection via Content-Length
  ## header before the body is read into memory. No-op when
  ## ``maxResponseBytes == 0`` or Content-Length is absent/unparseable.
  if maxResponseBytes > 0:
    let cl =
      try:
        httpResp.contentLength
      except ValueError:
        -1
    if cl > maxResponseBytes:
      let te = transportError(
        tekNetwork,
        context & " Content-Length exceeds limit: " & $cl & " bytes > " &
          $maxResponseBytes & " byte limit",
      )
      raise newClientError(te)

proc parseJsonBody(body: string, context: string): JsonNode =
  ## Parses a response body as JSON. Raises ``ClientError(cekTransport)``
  ## if the body is not valid JSON. Pure.
  try:
    parseJson(body)
  except JsonParsingError as e:
    let te =
      transportError(tekNetwork, "invalid JSON in " & context & " response: " & e.msg)
    raise newClientError(te)

proc classifyHttpResponse(
    maxResponseBytes: int, httpResp: httpclient.Response, context: string
): string =
  ## Classifies an HTTP response. Returns the body string on 2xx with
  ## correct Content-Type. Raises ``ClientError`` otherwise. Not pure —
  ## ``httpResp.body`` lazily reads from ``bodyStream`` on first access.
  let code =
    try:
      httpResp.code
    except ValueError:
      let te = transportError(
        tekNetwork, "malformed HTTP status from " & context & ": " & httpResp.status
      )
      raise newClientError(te)

  # Phase 1 body size enforcement (R9) — reject before reading body
  enforceContentLengthLimit(maxResponseBytes, httpResp, context)

  let body = httpResp.body # lazy: reads bodyStream on first access

  # Phase 2 body size enforcement (R9) — reject after reading body
  enforceBodySizeLimit(maxResponseBytes, body, context)

  if code.is4xx or code.is5xx:
    # Attempt to parse as RFC 7807 problem details
    let ct = httpResp.contentType.toLowerAscii
    if ct.startsWith("application/problem+json") or ct.startsWith("application/json"):
      try:
        let jsonNode = parseJson(body)
        if jsonNode.kind == JObject and jsonNode.hasKey("type"):
          let reqErr = RequestError.fromJson(jsonNode)
          raise newClientError(reqErr)
      except ClientError:
        raise # re-raise the ClientError we just created
      except CatchableError:
        # Malformed JSON, or valid JSON that fails RequestError schema
        # validation — fall through to generic HTTP status error
        discard
    # Generic HTTP status error (no problem details, or parsing failed)
    let te = httpStatusError(int(code), "HTTP " & $int(code) & " from " & context)
    raise newClientError(te)

  # Guard: non-2xx that is not 4xx/5xx (e.g. 1xx, 3xx).
  if not code.is2xx:
    let te =
      httpStatusError(int(code), "unexpected HTTP " & $int(code) & " from " & context)
    raise newClientError(te)

  # Check Content-Type on 2xx success
  let ct = httpResp.contentType.toLowerAscii
  if not ct.startsWith("application/json"):
    let te = transportError(
      tekNetwork,
      "unexpected Content-Type from " & context & ": " & httpResp.contentType,
    )
    raise newClientError(te)

  body
