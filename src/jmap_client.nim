# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
{.experimental: "strictCaseObjects".}

## JMAP client library entry point — the canonical user import.
##
## ``import jmap_client`` is the headline API. It re-exports the
## full public surface: L1 domain vocabulary, L2 serialisation, L3
## protocol builders + dispatch, L4 transport + client, RFC 8621
## mail entities, and the ``PushChannel`` / ``WebSocketChannel``
## reservation types (RFC 8620 §7 / RFC 8887 — types named pre-1.0;
## implementations land additively per P20).
##
## The per-entity pipeline combinators (``add<Entity>QueryThenGet``,
## ``add<Entity>ChangesToGet``, ``getBoth``) are part of this always-on
## hub — surfaced through the mail re-export, reachable from the single
## ``import jmap_client``.

import jmap_client/internal/types
import jmap_client/internal/protocol
import jmap_client/internal/transport
import jmap_client/internal/client
import jmap_client/internal/one_shot
import jmap_client/internal/mail
import jmap_client/internal/push
import jmap_client/internal/websocket

export types
export protocol
export transport
export client
export one_shot
export mail
export push
export websocket

# --- Layer 5: the C ABI ---------------------------------------------------
# Everything below carries C linkage only. No symbol here has a Nim export
# marker, so nothing in this section appears on the Nim public surface —
# the C contract lives in include/jmap_client.h, held consistent by the
# H18 gate. Handles are L5-owned wrapper objects; per-handle error state
# follows the SQLite model (status returns + jmap_errmsg borrows).
#
# The library is built --app:lib --noMain: module globals are
# uninitialised until jmap_init runs NimMain(). Every proc below that
# allocates GC'd memory or returns a status therefore checks the init
# latch first. Pure reads through a live handle and the *_free family
# are exempt: a non-nil handle proves a constructor already ran the
# latch. jmap_strerror and jmap_version take no handle and are the only
# pre-init entry points.

import std/[algorithm, strutils, tables]

type JmapStatus {.size: sizeof(cint).} = enum
  jsOk = 0
  jsValidation = 1
  jsTransport = 2
  jsRequest = 3
  jsSession = 4
  jsMisuse = 5
  jsProtocol = 6
  jsMethod = 7
  jsSet = 8

func statusOf(kind: JmapErrorKind): JmapStatus =
  ## The C projection of the error rail: one arm, one ordinal, locked at
  ## v1 so a C caller's switch statements never break.
  case kind
  of jeValidation: jsValidation
  of jeTransport: jsTransport
  of jeRequest: jsRequest
  of jeSession: jsSession
  of jeMisuse: jsMisuse
  of jeProtocol: jsProtocol
  of jeMethod: jsMethod
  of jeSet: jsSet

func asCint(s: JmapStatus): cint =
  ## The wire-stable ordinal a C caller's switch statement matches on.
  cint(ord(s))

# The single process-wide latch: written once by
# jmap_init, read to answer misuse when a consumer skips it. A bool in
# BSS is zero (false) before NimMain runs, so reading it pre-init is
# safe — which is the entire point.
var l5Initialised = false

proc NimMain() {.importc, cdecl.}
  ## The runtime's own initialiser; only jmap_init may call it, and once.

# The compiler only emits a standalone NimDestroyGlobals when the target
# is a static/dynamic library (see "Backend code calling Nim" in the Nim
# manual) — for an ordinary `nim c` executable the same cleanup is
# inlined straight into that program's own `main`. src/jmap_client.nim
# is compiled both ways: as this library's --app:lib --noMain shared
# object, and, unmodified, as the entry point every test module imports
# as a plain executable. `--app:lib` and `--app:staticlib` both define
# the `library` symbol (no other app type does), so guarding on
# ``defined(library)`` keeps the latter linkable while matching exactly
# the build shapes that actually emit the symbol.
when defined(library):
  proc NimDestroyGlobals() {.importc, cdecl.}
    ## Undoes NimMain; only jmap_cleanup may call it.

proc jmapInit(): cint {.exportc: "jmap_init", dynlib, cdecl, raises: [].} =
  ## Runs the Nim runtime's module initialisers exactly once. Everything
  ## else in this section refuses to run before this has happened.
  if not l5Initialised:
    NimMain()
    l5Initialised = true
  asCint(jsOk)

proc jmapCleanup() {.exportc: "jmap_cleanup", dynlib, cdecl, raises: [].} =
  ## Idempotent: a caller that never initialised finds this a no-op.
  if l5Initialised:
    when defined(library):
      NimDestroyGlobals()
    l5Initialised = false

func statusText(s: JmapStatus): cstring =
  ## cstring literals live in static storage — never freed, callable
  ## before the runtime is up.
  case s
  of jsOk:
    cstring"no error"
  of jsValidation:
    cstring"invalid input"
  of jsTransport:
    cstring"transport failure"
  of jsRequest:
    cstring"request rejected by server"
  of jsSession:
    cstring"session capability absent"
  of jsMisuse:
    cstring"API misuse"
  of jsProtocol:
    cstring"malformed server response"
  of jsMethod:
    cstring"method-level error"
  of jsSet:
    cstring"set-level error"

proc jmapStrerror(
    code: cint
): cstring {.exportc: "jmap_strerror", dynlib, cdecl, raises: [].} =
  ## Matches by ordinal rather than converting int→enum: an
  ## out-of-range code must answer a string, not trip a range check.
  for s in JmapStatus:
    if asCint(s) == code:
      return statusText(s)
  cstring"unknown status code"

proc jmapVersion(): cstring {.exportc: "jmap_version", dynlib, cdecl, raises: [].} =
  ## A static literal, so callable before jmap_init unlike GC-touching exports.
  cstring"0.1.0"

type ErrorSlot {.ruleOff: "objects".} = object
  ## Per-handle diagnostic. message backs
  ## jmap_errmsg's borrow, so it must outlive the call that set it.
  status: JmapStatus
  message: string

type SessionCacheState = enum
  scsEmpty
  scsReady

type JmapClientHandle {.ruleOff: "objects".} = object
  ## The C jmap_client: an L5-owned box holding the L4 ref (the object
  ## behind it is module-private and cannot be minted here) plus every
  ## per-handle slot the C contract needs. Dropping `client` closes the
  ## transport through ARC.
  client: JmapClient
  err: ErrorSlot
  cacheState: SessionCacheState
  accountIds: seq[string] ## sorted render of the session's account ids
  primaryAccount: string ## "" until resolved; backs a borrow
  primaryFail: ErrorSlot ## jsOk when a mail primary was resolved
  stateSlot: string ## backs jmap_get_email_state's borrow

proc recordError(h: ptr JmapClientHandle, err: JmapError): cint =
  ## Renders the diagnostic at record time so the errmsg borrow needs no
  ## later allocation. Called by every fallible handle-bearing operation
  ## once a handle exists to carry the JmapError rail's outcome; a
  ## pre-handle failure (jmap_client_new) has no handle yet and reports
  ## the bare status instead.
  let status = statusOf(err.kind)
  h[].err = ErrorSlot(status: status, message: err.message)
  asCint(status)

proc recordMisuse(h: ptr JmapClientHandle, msg: string): cint =
  ## Misuse detected in L5 code itself — a NULL out-parameter or similar
  ## caller bug — rather than on the JmapError rail, so the message is
  ## authored here instead of carried from L4.
  h[].err = ErrorSlot(status: jsMisuse, message: msg)
  asCint(jsMisuse)

proc clearError(h: ptr JmapClientHandle) =
  ## A fallible call that succeeds resets the slot — jmap_errmsg reports
  ## the MOST RECENT call's outcome, exactly like sqlite3_errmsg.
  h[].err = ErrorSlot(status: jsOk, message: "")

type JmapHttpMethod {.size: sizeof(cint).} = enum
  ## The C projection of ``HttpMethodKind``: the two verbs RFC 8620 §3
  ## uses (GET for session discovery, POST for ``/jmap/api``).
  jhmGet = 0
  jhmPost = 1

type JmapTransportCode {.size: sizeof(cint).} = enum
  ## The send callback's own outcome rail — distinct from ``jmap_status``
  ## because a transport exchange is one HTTP round trip, not a whole
  ## library call.
  jtcOk = 0
  jtcNetwork = 1
  jtcTls = 2
  jtcTimeout = 3

type JmapSendFn = proc(
  userdata: pointer,
  httpMethod: JmapHttpMethod,
  url, body, authorization: cstring,
  outHttpStatus: ptr cint,
  outContentType, outBody: ptr cstring,
): JmapTransportCode {.cdecl, raises: [].} ## The C vtable's send slot.

type JmapCloseFn = proc(userdata: pointer) {.cdecl, raises: [].}
  ## The C vtable's close slot.

type AttachState = enum
  ## Whether a ``JmapTransportHandle`` is still free to attach to a
  ## client, or already spoken for — the guard behind the attach-once
  ## rule (one transport backs at most one client).
  atFree
  atAttached

type JmapTransportHandle {.ruleOff: "objects".} = object
  ## The C jmap_transport: an L5-owned box holding the L4 ``Transport``
  ## ref plus the attach-once guard. ``objects publicfields`` is
  ## incompatible with this encapsulated handle shape (see
  ## ``JmapClientHandle`` above).
  transport: Transport
  attach: AttachState

proc cFree(p: pointer) {.importc: "free", header: "<stdlib.h>".}
  ## Frees buffers the send callback allocated; Nim's allocator never touches them.

func normaliseContentType(raw: string): string =
  ## Lowercases and drops any ``; parameter`` suffix (RFC 9110 §8.3), the
  ## same shape ``readContentType`` in
  ## ``src/jmap_client/internal/transport.nim`` produces for the same
  ## wire value. That proc is module-private to L4 (no ``*``) and takes
  ## an ``httpclient.Response`` rather than a bare string, so L5 cannot
  ## call it — and widening its API is the owner's decision, not this
  ## task's. Kept algorithmically identical to it (lowercase, slice at
  ## the first ``;``, strip) rather than drifting into a second
  ## definition of "normalised content type".
  let lowered = raw.toLowerAscii()
  let semi = lowered.find(';')
  if semi < 0:
    lowered.strip()
  else:
    lowered[0 ..< semi].strip()

func toHttpResponse(status: cint, ctype, body: cstring): HttpResponse =
  ## Copies the callback's malloc'd buffers into Nim storage and
  ## normalises the content type; the caller frees the originals
  ## immediately afterwards, so the copy must happen here.
  let raw =
    if ctype.isNil:
      ""
    else:
      $ctype
  HttpResponse(
    statusCode: int(status),
    contentType: normaliseContentType(raw),
    body:
      if body.isNil:
        ""
      else:
        $body,
  )

func transportFault(code: JmapTransportCode): TransportError =
  ## Names the failure the callback reported on the substrate's own rail.
  ## All three arms fold onto ``JMAP_E_TRANSPORT`` at the C ABI by design
  ## (one transport status), so the per-arm detail is what lets
  ## jmap_errmsg distinguish TLS from timeout from network — a shared
  ## string here would silently discard that distinction. ``jtcOk``
  ## shares the network arm rather than being excluded by type: the
  ## success arm is taken before this is ever called, and a total
  ## projection is cheaper than a partial one.
  case code
  of jtcTls:
    transportError(tekTls, "TLS failure reported by transport callback")
  of jtcTimeout:
    transportError(tekTimeout, "timeout reported by transport callback")
  of jtcOk, jtcNetwork:
    transportError(tekNetwork, "network failure reported by transport callback")

proc newCTransport(
    send: JmapSendFn, close: JmapCloseFn, userdata: pointer
): Result[Transport, JmapError] =
  ## The closure-construction half of jmap_transport_new: it adapts the C
  ## fn-pointer vtable onto the substrate's closure vtable, the closures
  ## capturing the pointers plus userdata — which is how userdata threads
  ## through a substrate that has no such field. Split out so the
  ## exported entry point is argument validation and nothing else.
  let sendClosure: SendProc = proc(
      req: HttpRequest
  ): Result[HttpResponse, TransportError] {.closure, raises: [].} =
    var status: cint = 0
    var ctype: cstring = nil
    var body: cstring = nil
    let m =
      case req.httpMethod
      of hmGet: jhmGet
      of hmPost: jhmPost
    let code = send(
      userdata,
      m,
      req.url.cstring,
      req.body.cstring,
      req.authorization.cstring,
      addr status,
      addr ctype,
      addr body,
    )
    if code != jtcOk:
      return err(transportFault(code))
    let response = toHttpResponse(status, ctype, body)
    # The buffers are the callback's malloc'd gifts and the contract says
    # the library releases them once it has copied them.
    if not ctype.isNil:
      cFree(ctype)
    if not body.isNil:
      cFree(body)
    ok(response)
  let closeClosure: CloseProc =
    if close.isNil:
      proc() {.closure, raises: [].} =
        discard
    else:
      proc() {.closure, raises: [].} =
        close(userdata)
  newTransport(sendClosure, closeClosure)

proc jmapTransportNew(
    send: JmapSendFn,
    close: JmapCloseFn,
    userdata: pointer,
    outTransport: ptr ptr JmapTransportHandle,
): cint {.exportc: "jmap_transport_new", dynlib, cdecl, raises: [].} =
  ## Function-pointer validation only; newCTransport owns the vtable
  ## adaptation, so neither half carries the other's branches.
  if not l5Initialised:
    return asCint(jsMisuse)
  if outTransport.isNil or send.isNil:
    return asCint(jsMisuse)
  let built = newCTransport(send, close, userdata)
  if built.isErr:
    return asCint(statusOf(built.error.kind))
  let p = createShared(JmapTransportHandle)
  p[].transport = built.get()
  p[].attach = atFree
  outTransport[] = p
  asCint(jsOk)

proc jmapTransportFree(
    handle: ptr JmapTransportHandle
) {.exportc: "jmap_transport_free", dynlib, cdecl, raises: [].} =
  ## Drops the caller's reference — the last one only when the transport
  ## was never attached to a client; if a client holds the other
  ## reference the transport lives until jmap_client_free. `=destroy`
  ## fires the registered close callback exactly when the reference it
  ## drops here is the last one, even when close was registered with a
  ## NULL userdata.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc connectViaTransportGuard(
    sessionUrl, username, password: cstring, transport: ptr JmapTransportHandle
): Result[JmapClient, JmapStatus] =
  ## Split out of jmapClientNew to keep it under nimalyzer's complexity
  ## ceiling: folds the attach-once guard (a non-nil transport already
  ## spoken for is misuse, checked before any connect attempt) with the
  ## dispatch to whichever ``connect`` overload the transport selects.
  ## The error rail stays the named ``JmapStatus`` — never collapsed to a
  ## bare ``cint`` — so the call site is the one place that projects to
  ## the wire ordinal via ``asCint``.
  if not transport.isNil and transport[].attach == atAttached:
    return err(jsMisuse)
  let connected =
    if transport.isNil:
      connect($sessionUrl, $username, $password)
    else:
      connect($sessionUrl, $username, $password, transport[].transport)
  if connected.isErr:
    return err(statusOf(connected.error.kind))
  ok(connected.get())

proc jmapClientNew(
    sessionUrl, username, password: cstring,
    transport: ptr JmapTransportHandle,
    outClient: ptr ptr JmapClientHandle,
): cint {.exportc: "jmap_client_new", dynlib, cdecl, raises: [].} =
  ## Pre-handle failures answer the bare status: there is no handle yet
  ## to carry a message; that is the accepted trade.
  if not l5Initialised:
    return asCint(jsMisuse)
  if outClient.isNil or sessionUrl.isNil or username.isNil or password.isNil:
    return asCint(jsMisuse)
  let connected = connectViaTransportGuard(sessionUrl, username, password, transport)
  if connected.isErr:
    return asCint(connected.error)
  # include/jmap_client.h permits handing a handle to another thread;
  # plain create/dealloc are documented thread-local in
  # lib/system/memalloc.nim ("The freed memory must belong to its
  # allocating thread!"), so the box goes on the shared heap instead —
  # correct whether or not the build defines -d:useMalloc.
  let p = createShared(JmapClientHandle)
  p[].client = connected.get()
  if not transport.isNil:
    transport[].attach = atAttached
  outClient[] = p
  asCint(jsOk)

proc jmapClientFree(
    handle: ptr JmapClientHandle
) {.exportc: "jmap_client_free", dynlib, cdecl, raises: [].} =
  ## Drops the last reference; `=destroy` fires any attached transport's
  ## close.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc jmapErrmsg(
    client: ptr JmapClientHandle
): cstring {.exportc: "jmap_errmsg", dynlib, cdecl, raises: [].} =
  ## Reports the most recently completed call's outcome, mirroring
  ## sqlite3_errmsg.
  if client.isNil:
    return cstring"null client handle"
  if client[].err.status == jsOk:
    return cstring"no error"
  client[].err.message.cstring

proc ensureCaches(h: ptr JmapClientHandle): Result[void, JmapError] =
  ## First use fetches the session and freezes the sorted account-id
  ## render the borrow accessors read from, so later calls need no
  ## further network IO. requireMail's failure is captured, not raised
  ## here — account enumeration must still work on a mail-less session.
  if h[].cacheState == scsReady:
    return ok()
  let session = ?fetchSession(h[].client)
  var ids: seq[string] = @[]
  for id in tables.keys(session.accounts):
    ids.add($id)
  sort(ids)
  h[].accountIds = ids
  let primary = requireMail(session)
  if primary.isOk:
    h[].primaryAccount = $primary.get()
    h[].primaryFail = ErrorSlot(status: jsOk, message: "")
  else:
    h[].primaryAccount = ""
    h[].primaryFail =
      ErrorSlot(status: statusOf(primary.error.kind), message: primary.error.message)
  h[].cacheState = scsReady
  ok()

proc jmapClientPrimaryAccount(
    client: ptr JmapClientHandle, outAccount: ptr cstring
): cint {.exportc: "jmap_client_primary_account", dynlib, cdecl, raises: [].} =
  ## A mail-less session has no primary account; that failure is
  ## reported here rather than at cache time, so enumeration still works.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outAccount.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  let cached = ensureCaches(client)
  if cached.isErr:
    return recordError(client, cached.error)
  if client[].primaryFail.status != jsOk:
    client[].err = client[].primaryFail
    return asCint(client[].primaryFail.status)
  clearError(client)
  outAccount[] = client[].primaryAccount.cstring
  asCint(jsOk)

proc jmapClientAccountCount(
    client: ptr JmapClientHandle, outCount: ptr csize_t
): cint {.exportc: "jmap_client_account_count", dynlib, cdecl, raises: [].} =
  ## Triggers the lazy session fetch on first call; every later call
  ## reads the frozen cache.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outCount.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  let cached = ensureCaches(client)
  if cached.isErr:
    return recordError(client, cached.error)
  clearError(client)
  outCount[] = csize_t(client[].accountIds.len)
  asCint(jsOk)

proc jmapClientAccountAt(
    client: ptr JmapClientHandle, i: csize_t
): cstring {.exportc: "jmap_client_account_at", dynlib, cdecl, raises: [].} =
  ## Pure read over the frozen cache: never fetches, never a defect. The
  ## out-of-range check compares ``i`` against the count while both are
  ## still ``csize_t`` (unsigned), so a caller's ``SIZE_MAX`` underflow
  ## (e.g. ``n - 1`` on an empty cache) answers NULL instead of narrowing
  ## an out-of-``int64``-range value to ``int`` and raising a RangeDefect
  ## across this ``raises: []`` boundary. No latch check: the handle came
  ## from a constructor that ran one.
  if client.isNil:
    return nil
  if client[].cacheState != scsReady:
    return nil
  if i >= csize_t(client[].accountIds.len):
    return nil
  client[].accountIds[int(i)].cstring

type JmapDebugFn = proc(
  userdata: pointer, direction: cint, bytes: pointer, len: csize_t
) {.cdecl, gcsafe, raises: [].} ## The C vtable's wire-debug slot.

proc jmapSetDebugCallback(
    client: ptr JmapClientHandle, fn: JmapDebugFn, userdata: pointer
): cint {.exportc: "jmap_set_debug_callback", dynlib, cdecl, raises: [].} =
  ## fn == NULL detaches; userdata threads through the trampoline
  ## unchanged, since the substrate's callback carries none of its own.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if fn.isNil:
    setDebugCallback(client[].client, nil)
  else:
    let trampoline: DebugCallback = proc(
        direction: WireDirection, bytes: openArray[byte]
    ) {.closure, gcsafe, raises: [].} =
      # bytes may be empty (the session GET has no request body); the
      # length guard keeps the address-of total.
      let p =
        if bytes.len > 0:
          cast[pointer](unsafeAddr bytes[0])
        else:
          nil
      fn(userdata, cint(ord(direction)), p, csize_t(bytes.len))
    setDebugCallback(client[].client, trampoline)
  clearError(client)
  asCint(jsOk)
