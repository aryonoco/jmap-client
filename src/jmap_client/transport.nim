# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Pluggable HTTP transport for the JMAP client (Layer 4). Application
## developers bring their own HTTP backend via ``newTransport(send,
## close)`` — libcurl, puppy, chronos, an in-process mock, a recording
## proxy. The default ``std/httpclient`` backend is delivered by
## ``newHttpTransport()`` and is what ``initJmapClient(sessionUrl,
## token)`` chooses when the caller does not supply a transport.
##
## The vtable is a two-closure shape (``SendProc``, ``CloseProc``)
## carried by a private ``TransportObj``. Construction uses smart
## constructors that reject nil closures at the boundary. ARC's
## ``=destroy`` on ``TransportObj`` invokes ``closeImpl`` when the last
## reference drops — the JMAP client never calls a public ``close``
## proc; ref-handle lifecycle alone is the contract.
##
## **Threading.** One ``Transport`` per ``JmapClient``; not shareable
## across clients; not required to be thread-safe. ARC ref-count
## manipulation IS thread-safe under ``--threads:on``, but the
## ``closeImpl`` invocation runs on whichever thread releases the last
## reference. Library-level threading invariant (P24) keeps the
## destructor on the owning thread.

{.push raises: [].}
{.experimental: "strictCaseObjects".}

import std/httpclient
import std/strutils

import results

import ./internal/types/validation
import ./internal/types/errors

type HttpMethodKind* = enum
  ## Subset of HTTP verbs used by JMAP: GET for session discovery, POST
  ## for ``/jmap/api`` invocations. RFC 8620 §3 does not use PUT, DELETE,
  ## or PATCH; the enum is closed on the two shapes the client emits.
  hmGet
  hmPost

type HttpRequest* = object
  ## Wire-shape value passed to ``SendProc``. The Transport never holds
  ## bearer-token state — every request carries its own ``Authorization``
  ## header value (e.g., ``"Bearer <token>"``) constructed by the
  ## ``JmapClient`` from its private credentials. ``body`` is empty for
  ## ``hmGet``.
  url*: string
  httpMethod*: HttpMethodKind
  body*: string
  authorization*: string

type HttpResponse* = object
  ## Wire-shape value returned by ``SendProc``. The transport eagerly
  ## reads the response body up to its configured size cap and emits a
  ## fully-populated value. ``contentType`` is lowercased with no
  ## parameters (e.g., ``"application/json"`` not
  ## ``"application/json; charset=utf-8"``).
  statusCode*: int
  contentType*: string
  body*: string

type SendProc* =
  proc(req: HttpRequest): Result[HttpResponse, TransportError] {.closure, raises: [].}
  ## Send callback. Pure ``Result`` contract — no exceptions cross the
  ## boundary; transport failures (network, TLS, timeout, size-limit
  ## breach) flow through the err rail as ``TransportError``.

type CloseProc* = proc() {.closure, raises: [].}
  ## Close callback invoked once per ``Transport`` by ARC ``=destroy``
  ## when the last reference drops. Must be idempotent if the underlying
  ## resource may be cleaned up by both the destructor and an explicit
  ## release on the application developer's side; the default HTTP
  ## transport implementation is naturally idempotent.

{.push ruleOff: "objects".}

type TransportObj = object
  ## Inner value type for ``Transport``. Hub-private — only ``Transport``
  ## (the ref alias below) is reachable from ``import jmap_client``.
  ## ``objects publicfields`` is disabled by the surrounding ``push``
  ## because TransportObj is a sealed Pattern-A handle (P8 opaque
  ## handle): the fields are deliberately private; the public API
  ## reaches them through ``newTransport`` / ``newHttpTransport`` /
  ## ``send``, not via field reads.
  sendImpl: SendProc
  closeImpl: CloseProc

{.pop.}

# nimalyzer 0.12.2 (hasdoc.nim:217-228) attempts ``node[2][0][2]`` on
# the nkRefTy arm of nkTypeDef, assuming the ref's inner node is
# always nkObjectTy (inline ``ref object``). For ``ref NamedType``
# the inner node is nkIdent (a leaf without ``.sons``) — the rule
# raises FieldDefect and nimalyzer aborts with "can't be parsed to
# AST". The pattern below mirrors Nim stdlib (``Regex* = ref
# RegexDesc`` in ``impure/re.nim``, ``FlowVar* = ref FlowVarObj``
# in ``threadpool.nim``) and is load-bearing for ARC ``=destroy``
# binding on TransportObj. The ``{.ruleOff: "hasDoc".}`` pragma
# below skips the hasDoc check on this one declaration; the
# docstring is still preserved on the type def and nim doc emits
# it normally.
type Transport* {.ruleOff: "hasDoc".} = ref TransportObj
  ## Per-handle vtable carried by ``JmapClient``. One ``Transport`` per
  ## ``JmapClient``; not shareable across clients; not required to be
  ## thread-safe. ARC manages lifetime — when the last reference drops,
  ## ``=destroy`` invokes ``closeImpl``.

proc `=destroy`*(t: TransportObj) {.raises: [].} =
  ## ARC destructor hook. Runs on the thread that releases the last
  ## reference to ``TransportObj``. The ``{.cast(gcsafe).}`` block is
  ## required because the user-supplied ``closeImpl`` closure cannot be
  ## proved gcsafe by ARC; the library's threading invariant (P24) keeps
  ## the destructor on the owning thread, so the cast is structural and
  ## does not represent a real escape.
  if not t.closeImpl.isNil:
    {.cast(gcsafe).}:
      t.closeImpl()

proc newTransport*(
    sendImpl: SendProc, closeImpl: CloseProc
): Result[Transport, ValidationError] =
  ## Strict on receive: rejects nil closures at the boundary. Both
  ## callbacks must be non-nil. Application developers reach for
  ## ``newTransport`` when they want to plug a custom HTTP backend in
  ## place of the default ``std/httpclient`` transport. Raw construction
  ## (``Transport(sendImpl: ...)``) is impossible outside this module —
  ## fields are private.
  if sendImpl.isNil:
    return err(validationError("Transport", "sendImpl must not be nil", ""))
  if closeImpl.isNil:
    return err(validationError("Transport", "closeImpl must not be nil", ""))
  ok(Transport(sendImpl: sendImpl, closeImpl: closeImpl))

proc send*(t: Transport, req: HttpRequest): Result[HttpResponse, TransportError] =
  ## Vtable dispatcher. Invokes the Transport's ``sendImpl`` closure.
  ## The JMAP client calls this once per ``fetchSession`` / ``send``;
  ## tests that bypass the typed surface call it directly with a
  ## hand-built ``HttpRequest``.
  t.sendImpl(req)

# ---------------------------------------------------------------------------
# Default HTTP transport built on std/httpclient
# ---------------------------------------------------------------------------

func detectHttpTransportConfig(
    timeout, maxRedirects, maxResponseBytes: int
): Result[void, ValidationError] =
  ## Validates the three numeric configuration knobs. ``std/httpclient``
  ## accepts ``timeout = -1`` (no timeout) and non-negative values;
  ## anything below -1 is nonsense. ``maxRedirects`` is typed
  ## ``Natural`` inside the stdlib, so a negative value would
  ## ``RangeDefect`` at construction — rejecting at the boundary is the
  ## fix. ``maxResponseBytes`` of zero disables the cap (preserved
  ## from the pre-refactor semantics); negative is rejected.
  if timeout < -1:
    return err(validationError("HttpTransport", "timeout must be >= -1", $timeout))
  if maxRedirects < 0:
    return
      err(validationError("HttpTransport", "maxRedirects must be >= 0", $maxRedirects))
  if maxResponseBytes < 0:
    return err(
      validationError(
        "HttpTransport", "maxResponseBytes must be >= 0", $maxResponseBytes
      )
    )
  ok()

func enforceContentLengthLimit(
    maxResponseBytes: int, httpResp: httpclient.Response
): Result[void, TransportError] =
  ## Phase 1 body size enforcement: early rejection via Content-Length
  ## header before the body is read into memory. No-op when
  ## ``maxResponseBytes == 0`` or Content-Length is absent/unparseable.
  ## File-private to ``transport.nim`` — coupled to ``std/httpclient``.
  if maxResponseBytes > 0:
    let cl =
      try:
        {.cast(raises: [CatchableError]).}:
          httpResp.contentLength
      except CatchableError:
        -1
    if cl > maxResponseBytes:
      return err(sizeLimitExceeded("Content-Length", cl, maxResponseBytes))
  ok()

proc readContentType(httpResp: httpclient.Response): string =
  ## Reads the Content-Type header, returning empty string on failure.
  ## Lowercased and stripped of parameters (``"application/json;
  ## charset=utf-8"`` becomes ``"application/json"``) so downstream
  ## classification matches the wire shape exactly.
  let raw =
    try:
      {.cast(raises: [CatchableError]).}:
        httpResp.contentType.toLowerAscii
    except CatchableError:
      return ""
  let semi = raw.find(';')
  if semi < 0:
    raw.strip()
  else:
    raw[0 ..< semi].strip()

proc newHttpTransport*(
    timeout: int = 30_000,
    maxRedirects: int = 5,
    maxResponseBytes: int = 50_000_000,
    userAgent: string = "jmap-client-nim/0.1.0",
): Result[Transport, ValidationError] =
  ## Default HTTP transport built on ``std/httpclient``. Validates the
  ## three numeric knobs at the boundary, allocates a single
  ## ``HttpClient`` reused across calls, and packages the send/close
  ## closures via ``newTransport``. ``userAgent`` is not validated —
  ## RFC 9110 §10.1.5 makes User-Agent a SHOULD-send, not a MUST, and
  ## Stalwart / Apache James / Cyrus IMAP all accept any non-control-
  ## character UA including empty.
  ?detectHttpTransportConfig(timeout, maxRedirects, maxResponseBytes)
  let headers =
    try:
      {.cast(raises: [CatchableError]).}:
        newHttpHeaders(
          {"Content-Type": "application/json", "Accept": "application/json"}
        )
    except CatchableError:
      return err(validationError("HttpTransport", "failed to create HTTP headers", ""))
  let httpClient =
    try:
      {.cast(raises: [CatchableError]).}:
        newHttpClient(
          userAgent = userAgent,
          timeout = timeout,
          maxRedirects = maxRedirects,
          headers = headers,
        )
    except CatchableError:
      return err(validationError("HttpTransport", "failed to create HTTP client", ""))

  let sendImpl: SendProc = proc(
      req: HttpRequest
  ): Result[HttpResponse, TransportError] {.closure, raises: [].} =
    {.cast(gcsafe).}:
      try:
        {.cast(raises: [CatchableError]).}:
          httpClient.headers["Authorization"] = req.authorization
      except CatchableError:
        return err(transportError(tekNetwork, "failed to set Authorization header"))
    let stdMethod =
      case req.httpMethod
      of hmGet: HttpGet
      of hmPost: HttpPost
    let httpResp =
      try:
        {.warning[Uninit]: off.}
        {.cast(raises: [CatchableError]).}:
          {.cast(gcsafe).}:
            if req.httpMethod == hmPost:
              httpClient.request(req.url, httpMethod = stdMethod, body = req.body)
            else:
              httpClient.request(req.url, httpMethod = stdMethod)
      except CatchableError as e:
        return err(classifyTransportException(e))
    ?enforceContentLengthLimit(maxResponseBytes, httpResp)
    let body =
      try:
        {.cast(raises: [CatchableError]).}:
          httpResp.body
      except CatchableError:
        return err(transportError(tekNetwork, "failed to read body"))
    ?enforceBodySizeLimit(maxResponseBytes, body)
    let statusCode =
      try:
        {.cast(raises: [CatchableError]).}:
          int(httpResp.code)
      except CatchableError:
        return
          err(transportError(tekNetwork, "malformed HTTP status: " & httpResp.status))
    ok(
      HttpResponse(
        statusCode: statusCode, contentType: readContentType(httpResp), body: body
      )
    )

  let closeImpl: CloseProc = proc() {.closure, raises: [].} =
    {.cast(gcsafe).}:
      try:
        {.cast(raises: [CatchableError]).}:
          httpClient.close()
      except CatchableError:
        discard

  newTransport(sendImpl, closeImpl)
