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
  ## Per-handle diagnostic. message backs jmap_errmsg's borrow, and
  ## methodErrorType backs jmap_errtype's — both must outlive the call
  ## that set them.
  status: JmapStatus
  message: string
  methodErrorType: string ## "" unless this outcome was a method-level error

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

func methodErrorTypeOf(err: JmapError): string =
  ## The wire ``type`` string (RFC 8620 section 3.6.2) when ``err`` is a
  ## method-level failure, else "" — the sentinel jmap_errtype reads as
  ## absent. A live JmapError.methodFault.error.rawType is structurally
  ## never empty (the decoder's own nonEmptyStr guard on the wire "type"
  ## field), so "" here can only mean "not a method error". Exhaustive
  ## over JmapErrorKind so a new arm is a compile error here, not a
  ## silent gap.
  case err.kind
  of jeValidation, jeTransport, jeRequest, jeSession, jeMisuse, jeProtocol, jeSet:
    ""
  of jeMethod:
    err.methodFault.error.rawType

proc recordError(h: ptr JmapClientHandle, err: JmapError): cint =
  ## Renders the diagnostic at record time so the errmsg/errtype borrows
  ## need no later allocation. Called by every fallible handle-bearing
  ## operation once a handle exists to carry the JmapError rail's
  ## outcome; a pre-handle failure (jmap_client_new) has no handle yet
  ## and reports the bare status instead.
  let status = statusOf(err.kind)
  h[].err = ErrorSlot(
    status: status, message: err.message, methodErrorType: methodErrorTypeOf(err)
  )
  asCint(status)

proc recordMisuse(h: ptr JmapClientHandle, msg: string): cint =
  ## Misuse detected in L5 code itself — a NULL out-parameter or similar
  ## caller bug — rather than on the JmapError rail, so the message is
  ## authored here instead of carried from L4.
  h[].err = ErrorSlot(status: jsMisuse, message: msg)
  asCint(jsMisuse)

proc recordProtocolFault(h: ptr JmapClientHandle, msg: string): cint =
  ## A response decoded without a serde error yet still breaks a
  ## structural guarantee RFC 8620/8621 place on its shape (e.g. a
  ## singleton returning some count other than one) — authored here
  ## rather than carried from L4, since ``JmapError``'s ``jeProtocol``
  ## arm names dispatch/decode faults only, not this entity-specific
  ## conformance check.
  h[].err = ErrorSlot(status: jsProtocol, message: msg)
  asCint(jsProtocol)

proc recordValidationFault(h: ptr JmapClientHandle, msg: string): cint =
  ## An argument L5 can prove invalid before any Layer-4 call is made.
  ## Authored here, but reported as the status the substrate's own seal
  ## would answer for the same input, so WHERE the refusal happened is
  ## invisible to the caller.
  h[].err = ErrorSlot(status: jsValidation, message: msg)
  asCint(jsValidation)

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

proc jmapErrtype(
    client: ptr JmapClientHandle
): cstring {.exportc: "jmap_errtype", dynlib, cdecl, raises: [].} =
  ## The wire ``type`` string of the last JMAP method-level error on this
  ## handle — sqlite3_extended_errcode to jmap_errmsg's sqlite3_errmsg.
  ## NULL whenever the last outcome was not a method-level error (no
  ## client, no error, or a failure of any other JmapError kind); never
  ## empty otherwise, so the two cannot be confused.
  if client.isNil:
    return nil
  if client[].err.methodErrorType.len == 0:
    return nil
  client[].err.methodErrorType.cstring

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
    h[].primaryFail = ErrorSlot(
      status: statusOf(primary.error.kind),
      message: primary.error.message,
      methodErrorType: methodErrorTypeOf(primary.error),
    )
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

type JmapWireDirection {.size: sizeof(cint).} = enum
  ## The C projection of the substrate's ``WireDirection``: a locked
  ## ordinal pair, independent of L4's own enum declaration order, so
  ## a C caller's switch statement never breaks under an L4 reorder.
  jwdSend = 0
  jwdReceive = 1

func wireDirectionOf(direction: WireDirection): JmapWireDirection =
  ## Explicit total projection, in the same shape as ``statusOf`` and
  ## the ``req.httpMethod`` mapping in ``newCTransport`` — the wire
  ## ordinal must never ride on ``WireDirection``'s member order by
  ## coincidence.
  case direction
  of wdSend: jwdSend
  of wdReceive: jwdReceive

const emptyWireBuf: array[1, byte] = [0'u8]
  ## A stable, non-null address handed to the C callback in place of
  ## ``bytes[0]`` when a fire's payload is empty (the session GET's
  ## request body, notably the very first fire on every client) — a
  ## zero-length ``openArray`` has no addressable element, and the
  ## header's contract promises the callback a live pointer even at
  ## length 0, so ``memcpy(dst, bytes, 0)`` stays well defined. A
  ## ``const`` scalar has no runtime address in Nim; a single-element
  ## ``const array`` does, since aggregates are materialised as
  ## static storage.

type JmapDebugFn = proc(
  userdata: pointer, direction: JmapWireDirection, bytes: pointer, len: csize_t
) {.cdecl, gcsafe, raises: [].}
  ## A plain function pointer rather than a closure: C has no closure
  ## ABI to receive one, so ``jmapSetDebugCallback`` pairs it with
  ## ``userdata`` itself to stand in for the substrate's
  ## closure-typed ``DebugCallback``.

proc newDebugTrampoline(fn: JmapDebugFn, userdata: pointer): DebugCallback =
  ## Builds the closure the substrate installs. Kept in its own proc
  ## so the closure environment's allocation is a call site the
  ## caller controls: it is reached only from the branch below that
  ## already passed the latch and nil checks, never hoisted ahead of
  ## them the way an inline closure literal can be by the destructor
  ## injection pass.
  proc(
      direction: WireDirection, bytes: openArray[byte]
  ) {.closure, gcsafe, raises: [].} =
    let p =
      if bytes.len > 0:
        cast[pointer](unsafeAddr bytes[0])
      else:
        cast[pointer](unsafeAddr emptyWireBuf[0])
    fn(userdata, wireDirectionOf(direction), p, csize_t(bytes.len))

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
    setDebugCallback(client[].client, newDebugTrampoline(fn, userdata))
  clearError(client)
  asCint(jsOk)

type CMailboxRole {.size: sizeof(cint).} = enum
  ## The C projection of ``jmap_mailbox_role``: locked, additive-only
  ## ordinals matching ``include/jmap_client.h`` exactly, independent of
  ## ``MailboxRoleKind``'s own declaration order. ``crNone`` is the
  ## absent state (``Mailbox.role`` is ``Opt.none``); ``crUnknown`` is
  ## every present-but-vendor role (``mrOther``) this ordinal set does
  ## not further distinguish — see ``toCRole``.
  crNone = 0
  crInbox = 1
  crDrafts = 2
  crSent = 3
  crTrash = 4
  crJunk = 5
  crArchive = 6
  crImportant = 7
  crAll = 8
  crFlagged = 9
  crUnknown = 10

type CMailboxRight {.size: sizeof(cint).} = enum
  ## The C projection of ``jmap_mailbox_right``: locked, additive-only
  ## ordinals matching ``include/jmap_client.h`` exactly. RFC 8621 §2
  ## fixes ``MailboxRights`` at nine independent flags, so unlike
  ## ``CMailboxRole`` there is no "unknown" arm to reserve.
  cwReadItems = 0
  cwAddItems = 1
  cwRemoveItems = 2
  cwSetSeen = 3
  cwSetKeywords = 4
  cwCreateChild = 5
  cwRename = 6
  cwDelete = 7
  cwSubmit = 8

type MailboxField = enum
  ## Presence bits for ``MailboxItem``'s optional wire fields
  ## (``mfParentId`` today, one arm per future optional field).
  ## ``borrowInto`` sets the bit exactly when it also fills the
  ## matching view slot, so an absent field is never confused with one
  ## whose borrowed value happens to be empty.
  mfParentId

type MailboxItem {.ruleOff: "objects".} = object
  ## Flat snapshot of one mailbox: every string is stored here so the C
  ## getters return stable borrows against this view.
  id: string
  name: string
  parentId: string
  roleIdentifier: string
  role: CMailboxRole
  totalEmails: int64
  unreadEmails: int64
  subscribed: cint
  rights: set[CMailboxRight]
  present: set[MailboxField]

type JmapMailboxesHandle {.ruleOff: "objects".} = object
  items: seq[MailboxItem]

func toCRole(role: MailboxRole): CMailboxRole =
  ## Matched on ``role.kind`` — the L4 discriminator — rather than the
  ## wire string, so a tenth ``MailboxRoleKind`` member is a compile
  ## error here (no ``else``) instead of silently falling through to
  ## ``crUnknown``. ``mrOther`` is the one arm this ordinal set
  ## deliberately does not distinguish further: its wire text is still
  ## recoverable via ``jmap_mailbox_role_identifier``.
  case role.kind
  of mrInbox: crInbox
  of mrDrafts: crDrafts
  of mrSent: crSent
  of mrTrash: crTrash
  of mrJunk: crJunk
  of mrArchive: crArchive
  of mrImportant: crImportant
  of mrAll: crAll
  of mrFlagged: crFlagged
  of mrOther: crUnknown

func borrowInto[T; F: enum](
    value: Opt[T], slot: var string, field: F, present: var set[F]
) =
  ## Lowers one optional wire field into the view slot a C getter borrows
  ## from, recording its presence in the same step: the borrow and the
  ## presence bit are one fact, and every view mapper in this section
  ## needs it, so it is stated once here rather than at each field.
  for v in value:
    slot = $v
    present.incl(field)

func rightOrdinalTail(name: static string): CMailboxRight =
  ## The second half of ``rightOrdinal``'s field-name dispatch, split
  ## out purely to stay under nimalyzer's complexity ceiling — together
  ## the two cover every ``MailboxRights`` field, and an unmapped field
  ## still fails to compile, here rather than in the caller.
  when name == "mayCreateChild":
    cwCreateChild
  elif name == "mayRename":
    cwRename
  elif name == "mayDelete":
    cwDelete
  elif name == "maySubmit":
    cwSubmit
  else:
    {.error: "MailboxRights gained a field toCRights does not project: " & name.}

func rightOrdinal(name: static string): CMailboxRight =
  ## Compile-time dispatch from a ``MailboxRights`` field name to its C
  ## ordinal. ``toCRights`` below instantiates this once per field via
  ## ``fieldPairs``, so a ``MailboxRights`` field with no arm here (or
  ## in ``rightOrdinalTail``) fails to compile — the field-name analogue
  ## of ``toCRole``'s exhaustive ``case``, since ``MailboxRights`` is a
  ## record of independent flags (RFC 8621 §2), not a variant type a
  ## ``case`` can be total over.
  when name == "mayReadItems":
    cwReadItems
  elif name == "mayAddItems":
    cwAddItems
  elif name == "mayRemoveItems":
    cwRemoveItems
  elif name == "maySetSeen":
    cwSetSeen
  elif name == "maySetKeywords":
    cwSetKeywords
  else:
    rightOrdinalTail(name)

func toCRights(rights: MailboxRights): set[CMailboxRight] =
  ## Walks every ``MailboxRights`` field via ``fieldPairs`` — an
  ## unrolled, per-field compile-time iterator — instead of naming each
  ## field in an array literal, so ``rightOrdinal``'s compile-time
  ## dispatch is what enforces the ordinal-for-every-field invariant.
  var held: set[CMailboxRight] = {}
  for name, granted in rights.fieldPairs:
    if granted:
      held.incl(rightOrdinal(name))
  held

func toMailboxItem(mb: Mailbox): MailboxItem =
  ## Flattens every Opt field to its snapshot slot once, so getters
  ## never re-derive presence from the source Mailbox.
  var item = MailboxItem(
    id: $mb.id,
    name: mb.name,
    role: crNone,
    totalEmails: mb.totalEmails.toInt64,
    unreadEmails: mb.unreadEmails.toInt64,
    subscribed: cint(ord(mb.isSubscribed)),
    rights: toCRights(mb.myRights),
  )
  borrowInto(mb.parentId, item.parentId, mfParentId, item.present)
  for role in mb.role:
    # Not a plain borrow: the same Opt value feeds both the wire-string
    # slot and, via role.kind, the ordinal projection.
    item.roleIdentifier = identifier(role)
    item.role = toCRole(role)
  item

proc parseAccountArg(
    h: ptr JmapClientHandle, raw: cstring, outId: var AccountId
): cint =
  ## Shared boundary parse for every account_id parameter: NULL is
  ## misuse, an invalid id is validation — both recorded on the handle.
  ## Returns jsOk's ordinal on success.
  if raw.isNil:
    return recordMisuse(h, "account_id must not be NULL")
  let parsed = parseAccountId($raw).lift
  if parsed.isErr:
    return recordError(h, parsed.error)
  outId = parsed.get()
  asCint(jsOk)

proc jmapGetMailboxes(
    client: ptr JmapClientHandle,
    accountId: cstring,
    outMailboxes: ptr ptr JmapMailboxesHandle,
): cint {.exportc: "jmap_get_mailboxes", dynlib, cdecl, raises: [].} =
  ## Fetches synchronously; the returned handle is a frozen snapshot,
  ## unaffected by any server state change after this call returns.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outMailboxes.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  var acct = default(AccountId)
  let parsed = parseAccountArg(client, accountId, acct)
  if parsed != asCint(jsOk):
    return parsed
  let resp = getMailboxes(client[].client, acct)
  if resp.isErr:
    return recordError(client, resp.error)
  let p = createShared(JmapMailboxesHandle)
  for mb in resp.get().list:
    p[].items.add(toMailboxItem(mb))
  clearError(client)
  outMailboxes[] = p
  asCint(jsOk)

proc jmapMailboxesFree(
    handle: ptr JmapMailboxesHandle
) {.exportc: "jmap_mailboxes_free", dynlib, cdecl, raises: [].} =
  ## Drops the last reference to the fetched snapshot.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc jmapMailboxesCount(
    handle: ptr JmapMailboxesHandle
): csize_t {.exportc: "jmap_mailboxes_count", dynlib, cdecl, raises: [].} =
  ## A NULL handle is empty, not a defect: pure reads never fail.
  if handle.isNil:
    return 0
  csize_t(handle[].items.len)

proc jmapMailboxesAt(
    handle: ptr JmapMailboxesHandle, i: csize_t
): ptr MailboxItem {.exportc: "jmap_mailboxes_at", dynlib, cdecl, raises: [].} =
  ## Out-of-range is NULL, not a defect: pure reads never fail. Mirrors
  ## ``jmap_client_account_at``'s bounds check: ``i`` is compared against
  ## the count while both are still ``csize_t`` (unsigned), so a caller's
  ## ``SIZE_MAX`` answers NULL instead of narrowing to ``int`` first and
  ## raising a RangeDefect across this ``raises: []`` boundary.
  if handle.isNil:
    return nil
  if i >= csize_t(handle[].items.len):
    return nil
  addr handle[].items[int(i)]

proc jmapMailboxId(
    mb: ptr MailboxItem
): cstring {.exportc: "jmap_mailbox_id", dynlib, cdecl, raises: [].} =
  ## Always populated: JMAP mints an id for every returned mailbox.
  if mb.isNil: nil else: mb[].id.cstring

proc jmapMailboxName(
    mb: ptr MailboxItem
): cstring {.exportc: "jmap_mailbox_name", dynlib, cdecl, raises: [].} =
  ## Always populated: RFC 8621 §2 requires a non-empty name.
  if mb.isNil: nil else: mb[].name.cstring

proc jmapMailboxRoleGet(
    mb: ptr MailboxItem
): cint {.exportc: "jmap_mailbox_role_get", dynlib, cdecl, raises: [].} =
  ## crNone is the absent state, not a tenth well-known role.
  if mb.isNil:
    cint(ord(crNone))
  else:
    cint(ord(mb[].role))

proc jmapMailboxRoleIdentifier(
    mb: ptr MailboxItem
): cstring {.exportc: "jmap_mailbox_role_identifier", dynlib, cdecl, raises: [].} =
  ## "" identifies a role-less mailbox — never NULL for a live handle:
  ## parseMailboxRole rejects an empty wire identifier, so a *present*
  ## role's identifier can never collide with this absent sentinel. (A
  ## NULL ``mb`` still answers NULL, as with every getter in this
  ## section — that is a handle-nil guard, not a role-presence signal.)
  if mb.isNil: nil else: mb[].roleIdentifier.cstring

proc jmapMailboxParentId(
    mb: ptr MailboxItem
): cstring {.exportc: "jmap_mailbox_parent_id", dynlib, cdecl, raises: [].} =
  ## NULL marks a top-level mailbox, not an unset field.
  if mb.isNil or mfParentId notin mb[].present:
    return nil
  mb[].parentId.cstring

proc jmapMailboxTotalEmails(
    mb: ptr MailboxItem
): int64 {.exportc: "jmap_mailbox_total_emails", dynlib, cdecl, raises: [].} =
  ## Always populated: a mailbox always carries a total count.
  if mb.isNil: 0'i64 else: mb[].totalEmails

proc jmapMailboxUnreadEmails(
    mb: ptr MailboxItem
): int64 {.exportc: "jmap_mailbox_unread_emails", dynlib, cdecl, raises: [].} =
  ## Always populated: a mailbox always carries an unread count.
  if mb.isNil: 0'i64 else: mb[].unreadEmails

proc jmapMailboxIsSubscribed(
    mb: ptr MailboxItem
): cint {.exportc: "jmap_mailbox_is_subscribed", dynlib, cdecl, raises: [].} =
  ## Always populated: subscription defaults false, never absent.
  if mb.isNil: 0 else: mb[].subscribed

proc jmapMailboxHasRight(
    mb: ptr MailboxItem, right: cint
): cint {.exportc: "jmap_mailbox_has_right", dynlib, cdecl, raises: [].} =
  ## Ordinal-matched like jmap_strerror: an out-of-range right answers
  ## 0, never a conversion defect.
  if mb.isNil:
    return 0
  for r in CMailboxRight:
    if cint(ord(r)) == right:
      return cint(ord(r in mb[].rights))
  0

type EmailField = enum
  ## Presence bits for ``EmailItem``'s optional wire fields. ``borrowInto``
  ## sets a bit exactly when it also fills the matching view slot, so an
  ## absent field is never confused with one whose borrowed value happens
  ## to be empty — mirrors ``MailboxField``.
  cefId
  cefThreadId
  cefSubject
  cefFromEmail
  cefFromName
  cefReceivedAt
  cefTextBody

type EmailItem {.ruleOff: "objects".} = object
  ## Flat snapshot of one email: every string is stored here so the C
  ## getters return stable borrows against this view.
  id: string
  threadId: string
  subject: string
  fromEmail: string
  fromName: string
  preview: string
  receivedAt: string
  textBody: string
  hasAttachment: cint
  present: set[EmailField]

type JmapEmailsHandle {.ruleOff: "objects".} = object
  items: seq[EmailItem]
  notFound: seq[string]

func toEmailItem(e: Email): EmailItem =
  ## Flattens every Opt field to its snapshot slot once, so getters never
  ## re-derive presence from the source Email. ``borrowInto`` carries every
  ## plain field; only the From list needs its own walk, because two slots
  ## come out of one optional address sequence.
  var item = EmailItem(preview: e.preview, hasAttachment: cint(ord(e.hasAttachment)))
  borrowInto(e.id, item.id, cefId, item.present)
  borrowInto(e.threadId, item.threadId, cefThreadId, item.present)
  borrowInto(e.subject, item.subject, cefSubject, item.present)
  borrowInto(e.receivedAt, item.receivedAt, cefReceivedAt, item.present)
  borrowInto(decodedTextBody(e), item.textBody, cefTextBody, item.present)
  # A present-but-empty ``from: []`` collapses onto the same absent
  # projection as ``Opt.none`` below: cefFromEmail is set only when a
  # first address actually exists, so jmap_email_from_email and
  # jmap_email_from_name cannot tell a C caller "the server sent an
  # empty From" from "From was not returned" — the one optional field on
  # this view where present-vs-absent is not recoverable through the C
  # API (documented on the getters in include/jmap_client.h).
  for addrs in e.fromAddr:
    if addrs.len > 0:
      item.fromEmail = addrs[0].email
      item.present.incl(cefFromEmail)
      borrowInto(addrs[0].name, item.fromName, cefFromName, item.present)
  item

func toEmailsHandleContent(
    resp: GetResponse[Email]
): tuple[items: seq[EmailItem], notFound: seq[string]] =
  ## Separates found from notFound once, so the handle never re-walks the
  ## response.
  var items: seq[EmailItem] = @[]
  for e in resp.list:
    items.add(toEmailItem(e))
  var missing: seq[string] = @[]
  for id in resp.notFound:
    missing.add($id)
  (items: items, notFound: missing)

proc parseIdArray(
    h: ptr JmapClientHandle, ids: ptr cstring, n: csize_t, outSeq: var seq[Id]
): cint =
  ## Boundary parse for id arrays: NULL array with nonzero n is misuse;
  ## an n too large to narrow to Nim's signed int is misuse too, checked
  ## here while n is still csize_t — the same RangeDefect-across-
  ## raises:[] hazard the indexed accessors guard against on an index,
  ## here on a loop bound instead. Each surviving element parses through
  ## the lenient server-id rail.
  if ids.isNil and n > 0:
    return recordMisuse(h, "ids must not be NULL when n > 0")
  if n > csize_t(high(int)):
    return recordMisuse(h, "n exceeds the maximum representable count")
  let arr = cast[ptr UncheckedArray[cstring]](ids)
  for i in 0 ..< int(n):
    if arr[i].isNil:
      return recordMisuse(h, "ids[" & $i & "] must not be NULL")
    let parsed = parseIdFromServer($arr[i]).lift
    if parsed.isErr:
      return recordError(h, parsed.error)
    outSeq.add(parsed.get())
  asCint(jsOk)

proc jmapGetEmails(
    client: ptr JmapClientHandle,
    accountId: cstring,
    ids: ptr cstring,
    n: csize_t,
    outEmails: ptr ptr JmapEmailsHandle,
): cint {.exportc: "jmap_get_emails", dynlib, cdecl, raises: [].} =
  ## Fetches text bodies eagerly; there is no lazy body fetch on the
  ## returned handle.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outEmails.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  var wanted: seq[Id] = @[]
  let parsedIds = parseIdArray(client, ids, n, wanted)
  if parsedIds != asCint(jsOk):
    return parsedIds
  let resp = getEmails(
    client[].client, acct, ids = directIds(wanted), bodyFetchOptions = textBodies()
  )
  if resp.isErr:
    return recordError(client, resp.error)
  let (items, missing) = toEmailsHandleContent(resp.get())
  let p = createShared(JmapEmailsHandle)
  p[].items = items
  p[].notFound = missing
  clearError(client)
  outEmails[] = p
  asCint(jsOk)

proc jmapEmailsFree(
    handle: ptr JmapEmailsHandle
) {.exportc: "jmap_emails_free", dynlib, cdecl, raises: [].} =
  ## Drops the last reference to the fetched snapshot.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc jmapEmailsCount(
    handle: ptr JmapEmailsHandle
): csize_t {.exportc: "jmap_emails_count", dynlib, cdecl, raises: [].} =
  ## A NULL handle is empty, not a defect: pure reads never fail.
  if handle.isNil:
    0
  else:
    csize_t(handle[].items.len)

proc jmapEmailsAt(
    handle: ptr JmapEmailsHandle, i: csize_t
): ptr EmailItem {.exportc: "jmap_emails_at", dynlib, cdecl, raises: [].} =
  ## Out-of-range is NULL, not a defect: pure reads never fail. ``i`` is
  ## compared against the count while both are still ``csize_t``
  ## (unsigned), so a caller's ``SIZE_MAX`` answers NULL instead of
  ## narrowing to ``int`` first and raising a RangeDefect across this
  ## ``raises: []`` boundary.
  if handle.isNil or i >= csize_t(handle[].items.len):
    return nil
  addr handle[].items[int(i)]

proc jmapEmailsNotfoundCount(
    handle: ptr JmapEmailsHandle
): csize_t {.exportc: "jmap_emails_notfound_count", dynlib, cdecl, raises: [].} =
  ## A NULL handle has no missing ids, not a defect.
  if handle.isNil:
    0
  else:
    csize_t(handle[].notFound.len)

proc jmapEmailsNotfoundAt(
    handle: ptr JmapEmailsHandle, i: csize_t
): cstring {.exportc: "jmap_emails_notfound_at", dynlib, cdecl, raises: [].} =
  ## Out-of-range is NULL, not a defect: pure reads never fail. Same
  ## unsigned-domain compare as ``jmapEmailsAt`` — narrowing ``i`` before
  ## the bounds check would raise a RangeDefect across this ``raises: []``
  ## boundary for a caller's ``SIZE_MAX``.
  if handle.isNil or i >= csize_t(handle[].notFound.len):
    return nil
  handle[].notFound[int(i)].cstring

func emailField(e: ptr EmailItem, field: EmailField, value: string): cstring =
  ## Shared absent-is-NULL projection for the Opt-shaped getters. Never
  ## called with a nil ``e``: every call site already evaluates
  ## ``e[].<field>`` to build ``value`` before this runs, so an ``e.isNil``
  ## check here could never fire — the outer ``if e.isNil`` in each getter
  ## is the sole, load-bearing nil guard. ``value`` is always passed
  ## straight from the item's own field, never a temporary — the borrow
  ## this returns must outlive the call, and only a field of the
  ## handle-owned ``e`` does.
  if field notin e[].present:
    return nil
  value.cstring

proc jmapEmailId(
    e: ptr EmailItem
): cstring {.exportc: "jmap_email_id", dynlib, cdecl, raises: [].} =
  ## In practice always populated — jmap_get_emails never sends a
  ## property filter, so the server has no occasion to omit id — but the
  ## same presence check as every optional field still guards it: a
  ## future property-filtered path would answer NULL correctly rather
  ## than mis-borrow, instead of relying on a guarantee this proc cannot
  ## itself enforce.
  if e.isNil:
    nil
  else:
    emailField(e, cefId, e[].id)

proc jmapEmailThreadId(
    e: ptr EmailItem
): cstring {.exportc: "jmap_email_thread_id", dynlib, cdecl, raises: [].} =
  ## NULL when the server omitted threadId, not an empty string.
  if e.isNil:
    nil
  else:
    emailField(e, cefThreadId, e[].threadId)

proc jmapEmailSubject(
    e: ptr EmailItem
): cstring {.exportc: "jmap_email_subject", dynlib, cdecl, raises: [].} =
  ## NULL when the server omitted subject, not an empty string.
  if e.isNil:
    nil
  else:
    emailField(e, cefSubject, e[].subject)

proc jmapEmailFromEmail(
    e: ptr EmailItem
): cstring {.exportc: "jmap_email_from_email", dynlib, cdecl, raises: [].} =
  ## NULL when the server omitted the from address, not an empty string.
  if e.isNil:
    nil
  else:
    emailField(e, cefFromEmail, e[].fromEmail)

proc jmapEmailFromName(
    e: ptr EmailItem
): cstring {.exportc: "jmap_email_from_name", dynlib, cdecl, raises: [].} =
  ## NULL both when from is absent and when the address carries no
  ## display name.
  if e.isNil:
    nil
  else:
    emailField(e, cefFromName, e[].fromName)

proc jmapEmailPreview(
    e: ptr EmailItem
): cstring {.exportc: "jmap_email_preview", dynlib, cdecl, raises: [].} =
  ## Always populated: preview defaults to empty, never absent.
  if e.isNil: nil else: e[].preview.cstring

proc jmapEmailReceivedAt(
    e: ptr EmailItem
): cstring {.exportc: "jmap_email_received_at", dynlib, cdecl, raises: [].} =
  ## NULL when the server omitted receivedAt, not an empty string.
  if e.isNil:
    nil
  else:
    emailField(e, cefReceivedAt, e[].receivedAt)

proc jmapEmailTextBody(
    e: ptr EmailItem
): cstring {.exportc: "jmap_email_text_body", dynlib, cdecl, raises: [].} =
  ## NULL unless a text body was actually decoded from bodyValues.
  if e.isNil:
    nil
  else:
    emailField(e, cefTextBody, e[].textBody)

proc jmapEmailHasAttachment(
    e: ptr EmailItem
): cint {.exportc: "jmap_email_has_attachment", dynlib, cdecl, raises: [].} =
  ## Always populated: hasAttachment defaults false, never absent.
  if e.isNil: 0 else: e[].hasAttachment

type ThreadItem {.ruleOff: "objects".} = object
  ## Flat snapshot of one thread: every string is stored here so the C
  ## getters return stable borrows against this view.
  id: string
  emailIds: seq[string]

type JmapThreadsHandle {.ruleOff: "objects".} = object
  items: seq[ThreadItem]

proc jmapGetThreads(
    client: ptr JmapClientHandle,
    accountId: cstring,
    ids: ptr cstring,
    n: csize_t,
    outThreads: ptr ptr JmapThreadsHandle,
): cint {.exportc: "jmap_get_threads", dynlib, cdecl, raises: [].} =
  ## Fetches synchronously; the returned handle is a frozen snapshot.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outThreads.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  var wanted: seq[Id] = @[]
  let parsedIds = parseIdArray(client, ids, n, wanted)
  if parsedIds != asCint(jsOk):
    return parsedIds
  let resp = getThreads(client[].client, acct, ids = directIds(wanted))
  if resp.isErr:
    return recordError(client, resp.error)
  let p = createShared(JmapThreadsHandle)
  for th in resp.get().list:
    var item = ThreadItem(id: $th.id)
    for eid in th.emailIds:
      item.emailIds.add($eid)
    p[].items.add(item)
  clearError(client)
  outThreads[] = p
  asCint(jsOk)

proc jmapThreadsFree(
    handle: ptr JmapThreadsHandle
) {.exportc: "jmap_threads_free", dynlib, cdecl, raises: [].} =
  ## Drops the last reference to the fetched snapshot.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc jmapThreadsCount(
    handle: ptr JmapThreadsHandle
): csize_t {.exportc: "jmap_threads_count", dynlib, cdecl, raises: [].} =
  ## A NULL handle is empty, not a defect: pure reads never fail.
  if handle.isNil:
    0
  else:
    csize_t(handle[].items.len)

proc jmapThreadsAt(
    handle: ptr JmapThreadsHandle, i: csize_t
): ptr ThreadItem {.exportc: "jmap_threads_at", dynlib, cdecl, raises: [].} =
  ## Out-of-range is NULL, not a defect: pure reads never fail.
  if handle.isNil or i >= csize_t(handle[].items.len):
    return nil
  addr handle[].items[int(i)]

proc jmapThreadId(
    th: ptr ThreadItem
): cstring {.exportc: "jmap_thread_id", dynlib, cdecl, raises: [].} =
  ## Always populated: JMAP mints an id for every returned thread.
  if th.isNil: nil else: th[].id.cstring

proc jmapThreadEmailCount(
    th: ptr ThreadItem
): csize_t {.exportc: "jmap_thread_email_count", dynlib, cdecl, raises: [].} =
  ## A NULL thread is empty, not a defect: pure reads never fail.
  if th.isNil:
    0
  else:
    csize_t(th[].emailIds.len)

proc jmapThreadEmailAt(
    th: ptr ThreadItem, i: csize_t
): cstring {.exportc: "jmap_thread_email_at", dynlib, cdecl, raises: [].} =
  ## Out-of-range is NULL, not a defect: pure reads never fail.
  if th.isNil or i >= csize_t(th[].emailIds.len):
    return nil
  th[].emailIds[int(i)].cstring

type IdentityItem {.ruleOff: "objects".} = object
  ## Flat snapshot of one identity: every string is stored here so the C
  ## getters return stable borrows against this view.
  id: string
  name: string
  email: string

type JmapIdentitiesHandle {.ruleOff: "objects".} = object
  items: seq[IdentityItem]

proc jmapGetIdentities(
    client: ptr JmapClientHandle,
    accountId: cstring,
    outIdentities: ptr ptr JmapIdentitiesHandle,
): cint {.exportc: "jmap_get_identities", dynlib, cdecl, raises: [].} =
  ## Fetches synchronously; the returned handle is a frozen snapshot.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outIdentities.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  let resp = getIdentities(client[].client, acct)
  if resp.isErr:
    return recordError(client, resp.error)
  let p = createShared(JmapIdentitiesHandle)
  for ident in resp.get().list:
    p[].items.add(IdentityItem(id: $ident.id, name: ident.name, email: ident.email))
  clearError(client)
  outIdentities[] = p
  asCint(jsOk)

proc jmapIdentitiesFree(
    handle: ptr JmapIdentitiesHandle
) {.exportc: "jmap_identities_free", dynlib, cdecl, raises: [].} =
  ## Drops the last reference to the fetched snapshot.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc jmapIdentitiesCount(
    handle: ptr JmapIdentitiesHandle
): csize_t {.exportc: "jmap_identities_count", dynlib, cdecl, raises: [].} =
  ## A NULL handle is empty, not a defect: pure reads never fail.
  if handle.isNil:
    0
  else:
    csize_t(handle[].items.len)

proc jmapIdentitiesAt(
    handle: ptr JmapIdentitiesHandle, i: csize_t
): ptr IdentityItem {.exportc: "jmap_identities_at", dynlib, cdecl, raises: [].} =
  ## Out-of-range is NULL, not a defect: pure reads never fail.
  if handle.isNil or i >= csize_t(handle[].items.len):
    return nil
  addr handle[].items[int(i)]

proc jmapIdentityId(
    ident: ptr IdentityItem
): cstring {.exportc: "jmap_identity_id", dynlib, cdecl, raises: [].} =
  ## Always populated: JMAP mints an id for every returned identity.
  if ident.isNil: nil else: ident[].id.cstring

proc jmapIdentityName(
    ident: ptr IdentityItem
): cstring {.exportc: "jmap_identity_name", dynlib, cdecl, raises: [].} =
  ## Always populated: name defaults to empty, never absent.
  if ident.isNil: nil else: ident[].name.cstring

proc jmapIdentityEmail(
    ident: ptr IdentityItem
): cstring {.exportc: "jmap_identity_email", dynlib, cdecl, raises: [].} =
  ## Always populated and immutable after the identity was created.
  if ident.isNil: nil else: ident[].email.cstring

type VacationField = enum
  ## Presence bits for ``JmapVacationHandle``'s optional wire fields.
  ## ``borrowInto`` sets a bit exactly when it also fills the matching
  ## view slot, so an absent field is never confused with one whose
  ## borrowed value happens to be empty — mirrors ``MailboxField`` /
  ## ``EmailField``.
  vfSubject
  vfTextBody

type JmapVacationHandle {.ruleOff: "objects".} = object
  ## Flat snapshot of the one VacationResponse record. RFC 8621 §8.1
  ## guarantees exactly one, so — unlike the seq-of-items handles above
  ## — the fields are flattened straight onto the handle rather than
  ## into a separate item type behind a one-element seq.
  enabled: cint
  subject: string
  textBody: string
  present: set[VacationField]

proc jmapGetVacation(
    client: ptr JmapClientHandle,
    accountId: cstring,
    outVacation: ptr ptr JmapVacationHandle,
): cint {.exportc: "jmap_get_vacation", dynlib, cdecl, raises: [].} =
  ## Fetches synchronously; the returned handle is a frozen snapshot of
  ## the singleton VacationResponse object. RFC 8621 §8.1 requires the
  ## server to return exactly one record with id "singleton"; any other
  ## list length is reported as JMAP_E_PROTOCOL rather than guessed at —
  ## reading just the first entry of a wrongly-shaped list would risk
  ## silently pairing fields from unrelated records into one view.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outVacation.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  let resp = getVacationResponse(client[].client, acct)
  if resp.isErr:
    return recordError(client, resp.error)
  let list = resp.get().list
  if list.len != 1:
    return recordProtocolFault(
      client,
      "VacationResponse/get must return exactly one record (RFC 8621 §8.1); got " &
        $list.len,
    )
  let vr = list[0]
  let p = createShared(JmapVacationHandle)
  p[].enabled = cint(ord(vr.isEnabled))
  borrowInto(vr.subject, p[].subject, vfSubject, p[].present)
  borrowInto(vr.textBody, p[].textBody, vfTextBody, p[].present)
  clearError(client)
  outVacation[] = p
  asCint(jsOk)

proc jmapVacationFree(
    handle: ptr JmapVacationHandle
) {.exportc: "jmap_vacation_free", dynlib, cdecl, raises: [].} =
  ## Drops the last reference to the fetched snapshot.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc jmapVacationIsEnabled(
    v: ptr JmapVacationHandle
): cint {.exportc: "jmap_vacation_is_enabled", dynlib, cdecl, raises: [].} =
  ## Always populated: isEnabled defaults false, never absent.
  if v.isNil: 0 else: v[].enabled

proc jmapVacationSubject(
    v: ptr JmapVacationHandle
): cstring {.exportc: "jmap_vacation_subject", dynlib, cdecl, raises: [].} =
  ## NULL when the server omitted subject, not an empty string.
  if v.isNil or vfSubject notin v[].present:
    return nil
  v[].subject.cstring

proc jmapVacationTextBody(
    v: ptr JmapVacationHandle
): cstring {.exportc: "jmap_vacation_text_body", dynlib, cdecl, raises: [].} =
  ## NULL when the server omitted textBody, not an empty string.
  if v.isNil or vfTextBody notin v[].present:
    return nil
  v[].textBody.cstring

type SetFailureItem {.ruleOff: "objects".} = object
  ## One refused id from either the update or destroy rail of a
  ## ``SetResponse``, flattened onto a single failures list: within one
  ## call the two rails are disjoint by construction (mark/move only
  ## ever submit update ids, destroy only ever submits destroy ids), so
  ## the C surface never needs to say which rail an id failed on.
  id: string
  errorType: string

type JmapSetResultHandle {.ruleOff: "objects".} = object
  updated: seq[string]
  destroyed: seq[string]
  failures: seq[SetFailureItem]

func toSetResultContent[T, U](resp: SetResponse[T, U]): JmapSetResultHandle =
  ## RFC 8620 section 5.3's ``updated`` map may carry any server-changed
  ## property on a successful update — this view deliberately drops that
  ## echo and keeps only the id, since no write verb this section
  ## exports has a caller-visible use for it yet. All four rails are
  ## walked for every entity: ``T`` types the create payload alone, so
  ## an entity that cannot be created can still have rows on the update
  ## and destroy rails. Create rows have no home on this view because
  ## the verbs it serves submit none.
  var updated: seq[string] = @[]
  for id, serverEcho in resp.updated:
    updated.add($id)
  var destroyed: seq[string] = @[]
  for id in resp.destroyed:
    destroyed.add($id)
  var failures: seq[SetFailureItem] = @[]
  for id, error in resp.updateFailures:
    failures.add(SetFailureItem(id: $id, errorType: error.rawType))
  for id, error in resp.destroyFailures:
    failures.add(SetFailureItem(id: $id, errorType: error.rawType))
  JmapSetResultHandle(updated: updated, destroyed: destroyed, failures: failures)

type EmailWriteOp = enum
  ewMarkRead
  ewMarkUnread
  ewDestroy

proc runEmailWrite(
    client: ptr JmapClientHandle,
    accountId: cstring,
    ids: ptr cstring,
    n: csize_t,
    op: EmailWriteOp,
    outResult: ptr ptr JmapSetResultHandle,
): cint =
  ## Shared body of the three unary write entry points; move carries an
  ## extra argument and gets its own proc below.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outResult.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  var wanted: seq[Id] = @[]
  let parsedIds = parseIdArray(client, ids, n, wanted)
  if parsedIds != asCint(jsOk):
    return parsedIds
  let resp =
    case op
    of ewMarkRead:
      markEmailsRead(client[].client, acct, wanted)
    of ewMarkUnread:
      markEmailsUnread(client[].client, acct, wanted)
    of ewDestroy:
      destroyEmails(client[].client, acct, wanted)
  if resp.isErr:
    return recordError(client, resp.error)
  let p = createShared(JmapSetResultHandle)
  p[] = toSetResultContent(resp.get())
  clearError(client)
  outResult[] = p
  asCint(jsOk)

proc jmapMarkRead(
    client: ptr JmapClientHandle,
    accountId: cstring,
    ids: ptr cstring,
    n: csize_t,
    outResult: ptr ptr JmapSetResultHandle,
): cint {.exportc: "jmap_mark_read", dynlib, cdecl, raises: [].} =
  ## A thin op-selecting wrapper; runEmailWrite carries the boundary
  ## checks shared by every unary email write.
  runEmailWrite(client, accountId, ids, n, ewMarkRead, outResult)

proc jmapMarkUnread(
    client: ptr JmapClientHandle,
    accountId: cstring,
    ids: ptr cstring,
    n: csize_t,
    outResult: ptr ptr JmapSetResultHandle,
): cint {.exportc: "jmap_mark_unread", dynlib, cdecl, raises: [].} =
  ## A thin op-selecting wrapper; runEmailWrite carries the boundary
  ## checks shared by every unary email write.
  runEmailWrite(client, accountId, ids, n, ewMarkUnread, outResult)

proc jmapMoveEmails(
    client: ptr JmapClientHandle,
    accountId: cstring,
    ids: ptr cstring,
    n: csize_t,
    mailboxId: cstring,
    outResult: ptr ptr JmapSetResultHandle,
): cint {.exportc: "jmap_move_emails", dynlib, cdecl, raises: [].} =
  ## Not routed through runEmailWrite: the extra mailbox_id argument
  ## needs its own NULL check and its own parse.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outResult.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  if mailboxId.isNil:
    return recordMisuse(client, "mailbox_id must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  var wanted: seq[Id] = @[]
  let parsedIds = parseIdArray(client, ids, n, wanted)
  if parsedIds != asCint(jsOk):
    return parsedIds
  let parsedMb = parseIdFromServer($mailboxId).lift
  if parsedMb.isErr:
    return recordError(client, parsedMb.error)
  let resp = moveEmails(client[].client, acct, wanted, parsedMb.get())
  if resp.isErr:
    return recordError(client, resp.error)
  let p = createShared(JmapSetResultHandle)
  p[] = toSetResultContent(resp.get())
  clearError(client)
  outResult[] = p
  asCint(jsOk)

proc jmapDestroyEmails(
    client: ptr JmapClientHandle,
    accountId: cstring,
    ids: ptr cstring,
    n: csize_t,
    outResult: ptr ptr JmapSetResultHandle,
): cint {.exportc: "jmap_destroy_emails", dynlib, cdecl, raises: [].} =
  ## A thin op-selecting wrapper; runEmailWrite carries the boundary
  ## checks shared by every unary email write.
  runEmailWrite(client, accountId, ids, n, ewDestroy, outResult)

proc jmapSetResultFree(
    handle: ptr JmapSetResultHandle
) {.exportc: "jmap_set_result_free", dynlib, cdecl, raises: [].} =
  ## Drops the last reference to the set outcome.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc jmapSetResultUpdatedCount(
    r: ptr JmapSetResultHandle
): csize_t {.exportc: "jmap_set_result_updated_count", dynlib, cdecl, raises: [].} =
  ## A NULL handle is empty, not a defect: pure reads never fail.
  if r.isNil:
    0
  else:
    csize_t(r[].updated.len)

proc jmapSetResultUpdatedAt(
    r: ptr JmapSetResultHandle, i: csize_t
): cstring {.exportc: "jmap_set_result_updated_at", dynlib, cdecl, raises: [].} =
  ## Out-of-range is NULL, not a defect: pure reads never fail.
  if r.isNil or i >= csize_t(r[].updated.len):
    return nil
  r[].updated[int(i)].cstring

proc jmapSetResultDestroyedCount(
    r: ptr JmapSetResultHandle
): csize_t {.exportc: "jmap_set_result_destroyed_count", dynlib, cdecl, raises: [].} =
  ## A NULL handle is empty, not a defect: pure reads never fail.
  if r.isNil:
    0
  else:
    csize_t(r[].destroyed.len)

proc jmapSetResultDestroyedAt(
    r: ptr JmapSetResultHandle, i: csize_t
): cstring {.exportc: "jmap_set_result_destroyed_at", dynlib, cdecl, raises: [].} =
  ## Out-of-range is NULL, not a defect: pure reads never fail.
  if r.isNil or i >= csize_t(r[].destroyed.len):
    return nil
  r[].destroyed[int(i)].cstring

proc jmapSetResultFailureCount(
    r: ptr JmapSetResultHandle
): csize_t {.exportc: "jmap_set_result_failure_count", dynlib, cdecl, raises: [].} =
  ## A NULL handle is empty, not a defect: pure reads never fail.
  if r.isNil:
    0
  else:
    csize_t(r[].failures.len)

proc jmapSetResultFailureIdAt(
    r: ptr JmapSetResultHandle, i: csize_t
): cstring {.exportc: "jmap_set_result_failure_id_at", dynlib, cdecl, raises: [].} =
  ## Out-of-range is NULL, not a defect: pure reads never fail.
  if r.isNil or i >= csize_t(r[].failures.len):
    return nil
  r[].failures[int(i)].id.cstring

proc jmapSetResultFailureTypeAt(
    r: ptr JmapSetResultHandle, i: csize_t
): cstring {.exportc: "jmap_set_result_failure_type_at", dynlib, cdecl, raises: [].} =
  ## The lossless wire error type string, not a translated message.
  if r.isNil or i >= csize_t(r[].failures.len):
    return nil
  r[].failures[int(i)].errorType.cstring

type JmapVacationUpdateHandle {.ruleOff: "objects".} = object
  ## The patch the caller is assembling, one slot per property rather
  ## than an accumulated list: an option setter called twice must
  ## replace, and a list would instead hand the update-set seal a
  ## duplicate target property and lose the whole batch. The nesting is
  ## the three states a JMAP patch distinguishes — an absent outer
  ## ``Opt`` is "no setter named this property, leave it alone", an
  ## inner ``Opt.none`` is "clear it to null", an inner ``Opt.some`` is
  ## "set it to this". RFC 8621 section 8 types isEnabled as a plain
  ## Boolean, so it has two states, not three.
  isEnabled: Opt[bool]
  subject: Opt[Opt[string]]
  textBody: Opt[Opt[string]]

func clearableString(value: cstring): Opt[string] =
  ## The NULL-means-clear reading of a settable string property: a NULL
  ## pointer is the caller asking for the wire null RFC 8621 section 8
  ## allows, not a missing argument.
  if value.isNil:
    Opt.none(string)
  else:
    Opt.some($value)

func vacationUpdates(u: JmapVacationUpdateHandle): seq[VacationResponseUpdate] =
  ## Lowers the touched slots onto the update DSL. An untouched slot
  ## contributes nothing, so it never reaches the patch; a cleared one
  ## contributes ``Opt.none``, which the DSL spells as a wire null.
  var updates: seq[VacationResponseUpdate] = @[]
  for enabled in u.isEnabled:
    updates.add(setIsEnabled(enabled))
  for subject in u.subject:
    updates.add(setSubject(subject))
  for textBody in u.textBody:
    updates.add(setTextBody(textBody))
  updates

proc jmapVacationUpdateNew(
    outUpdate: ptr ptr JmapVacationUpdateHandle
): cint {.exportc: "jmap_vacation_update_new", dynlib, cdecl, raises: [].} =
  ## Starts with every property untouched, so a patch never carries a
  ## property the caller did not name.
  if not l5Initialised:
    return asCint(jsMisuse)
  if outUpdate.isNil:
    return asCint(jsMisuse)
  outUpdate[] = createShared(JmapVacationUpdateHandle)
  asCint(jsOk)

proc jmapVacationUpdateSetEnabled(
    update: ptr JmapVacationUpdateHandle, state: cint
): cint {.exportc: "jmap_vacation_update_set_enabled", dynlib, cdecl, raises: [].} =
  ## The two-arm enum is the whole domain: RFC 8621 section 8 types
  ## isEnabled as a Boolean, so there is no clear-to-null arm here and
  ## an ordinal outside the enum is a caller bug, not a value.
  if not l5Initialised or update.isNil:
    return asCint(jsMisuse)
  if state notin [cint(0), cint(1)]:
    return asCint(jsMisuse)
  update[].isEnabled = Opt.some(state == cint(1))
  asCint(jsOk)

proc jmapVacationUpdateSetSubject(
    update: ptr JmapVacationUpdateHandle, subject: cstring
): cint {.exportc: "jmap_vacation_update_set_subject", dynlib, cdecl, raises: [].} =
  ## A NULL value is accepted and means "clear": refusing it would leave
  ## the C surface unable to ask for something the wire type allows.
  ## The update carries no error slot, so the status is the whole
  ## diagnosis.
  if not l5Initialised or update.isNil:
    return asCint(jsMisuse)
  update[].subject = Opt.some(clearableString(subject))
  asCint(jsOk)

proc jmapVacationUpdateSetTextBody(
    update: ptr JmapVacationUpdateHandle, textBody: cstring
): cint {.exportc: "jmap_vacation_update_set_text_body", dynlib, cdecl, raises: [].} =
  ## A NULL value is accepted and means "clear": refusing it would leave
  ## the C surface unable to ask for something the wire type allows.
  ## The update carries no error slot, so the status is the whole
  ## diagnosis.
  if not l5Initialised or update.isNil:
    return asCint(jsMisuse)
  update[].textBody = Opt.some(clearableString(textBody))
  asCint(jsOk)

proc jmapVacationUpdateFree(
    handle: ptr JmapVacationUpdateHandle
) {.exportc: "jmap_vacation_update_free", dynlib, cdecl, raises: [].} =
  ## Drops the patch; safe either before or after a set call has
  ## consumed it, since that call copies what it needs.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc jmapSetVacation(
    client: ptr JmapClientHandle,
    accountId: cstring,
    update: ptr JmapVacationUpdateHandle,
    outResult: ptr ptr JmapSetResultHandle,
): cint {.exportc: "jmap_set_vacation", dynlib, cdecl, raises: [].} =
  ## A projection over the setVacationResponse one-shot: the singleton
  ## id, the update-set seal and the dispatch ceremony are all its
  ## business. The patch arrived already assembled by its setters, so
  ## nothing is lowered here. An update no setter touched is refused
  ## before the call rather than travelling as an empty patch — the
  ## substrate's seal refuses it too, and answering here keeps the C
  ## contract true whatever the substrate later chooses.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outResult.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  if update.isNil:
    return recordMisuse(client, "vacation update must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  let updates = vacationUpdates(update[])
  if updates.len == 0:
    return recordValidationFault(client, "vacation update names no properties")
  let resp = setVacationResponse(client[].client, acct, updates)
  if resp.isErr:
    return recordError(client, resp.error)
  let p = createShared(JmapSetResultHandle)
  p[] = toSetResultContent(resp.get())
  clearError(client)
  outResult[] = p
  asCint(jsOk)

proc jmapGetEmailState(
    client: ptr JmapClientHandle, accountId: cstring, outState: ptr cstring
): cint {.exportc: "jmap_get_email_state", dynlib, cdecl, raises: [].} =
  ## The current Email state string; hand it back unchanged as
  ## since_state on the next sync call. Bootstraps with an empty-ids
  ## Email/get, so a first cursor costs no email payload.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outState.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  let resp = getEmailState(client[].client, acct)
  if resp.isErr:
    return recordError(client, resp.error)
  client[].stateSlot = $resp.get()
  clearError(client)
  outState[] = client[].stateSlot.cstring
  asCint(jsOk)

type JmapSyncHandle {.ruleOff: "objects".} = object
  oldState: string
  newState: string
  hasMore: cint
  destroyed: seq[string]
  created: JmapEmailsHandle
  updated: JmapEmailsHandle

proc jmapSyncEmails(
    client: ptr JmapClientHandle,
    accountId: cstring,
    sinceState: cstring,
    outSync: ptr ptr JmapSyncHandle,
): cint {.exportc: "jmap_sync_emails", dynlib, cdecl, raises: [].} =
  ## Changes plus the two Email/get fetches in one round trip, so a
  ## caller never juggles three calls for a single sync step.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outSync.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  if sinceState.isNil:
    return recordMisuse(client, "since_state must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  let parsedState = parseJmapState($sinceState).lift
  if parsedState.isErr:
    return recordError(client, parsedState.error)
  let resp = syncEmails(client[].client, acct, parsedState.get())
  if resp.isErr:
    return recordError(client, resp.error)
  let sync = resp.get()
  let p = createShared(JmapSyncHandle)
  p[].oldState = $sync.changes.oldState
  p[].newState = $sync.changes.newState
  p[].hasMore = cint(ord(sync.changes.hasMoreChanges))
  for id in sync.changes.destroyed:
    p[].destroyed.add($id)
  let (createdItems, createdMissing) = toEmailsHandleContent(sync.created)
  p[].created = JmapEmailsHandle(items: createdItems, notFound: createdMissing)
  let (updatedItems, updatedMissing) = toEmailsHandleContent(sync.updated)
  p[].updated = JmapEmailsHandle(items: updatedItems, notFound: updatedMissing)
  clearError(client)
  outSync[] = p
  asCint(jsOk)

proc jmapSyncFree(
    handle: ptr JmapSyncHandle
) {.exportc: "jmap_sync_free", dynlib, cdecl, raises: [].} =
  ## Drops the last reference to the sync outcome, including its two
  ## nested email handles.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc jmapSyncOldState(
    s: ptr JmapSyncHandle
): cstring {.exportc: "jmap_sync_old_state", dynlib, cdecl, raises: [].} =
  ## Always populated: every sync response echoes the state it started
  ## from. Owned by the sync handle, not the client — unaffected by any
  ## later call on the client that produced it.
  if s.isNil: nil else: s[].oldState.cstring

proc jmapSyncNewState(
    s: ptr JmapSyncHandle
): cstring {.exportc: "jmap_sync_new_state", dynlib, cdecl, raises: [].} =
  ## Always populated: every sync response echoes the state it now
  ## sits at. Owned by the sync handle, not the client — unaffected by
  ## any later call on the client that produced it.
  if s.isNil: nil else: s[].newState.cstring

proc jmapSyncHasMore(
    s: ptr JmapSyncHandle
): cint {.exportc: "jmap_sync_has_more", dynlib, cdecl, raises: [].} =
  ## Always populated: signals whether another sync call is needed to
  ## catch up.
  if s.isNil: 0 else: s[].hasMore

proc jmapSyncDestroyedCount(
    s: ptr JmapSyncHandle
): csize_t {.exportc: "jmap_sync_destroyed_count", dynlib, cdecl, raises: [].} =
  ## A NULL handle is empty, not a defect: pure reads never fail.
  if s.isNil:
    0
  else:
    csize_t(s[].destroyed.len)

proc jmapSyncDestroyedAt(
    s: ptr JmapSyncHandle, i: csize_t
): cstring {.exportc: "jmap_sync_destroyed_at", dynlib, cdecl, raises: [].} =
  ## Out-of-range is NULL, not a defect: pure reads never fail. ``i`` is
  ## compared against the count while both are still ``csize_t``
  ## (unsigned), so a caller's ``SIZE_MAX`` answers NULL instead of
  ## narrowing to ``int`` first and raising a RangeDefect across this
  ## ``raises: []`` boundary.
  if s.isNil or i >= csize_t(s[].destroyed.len):
    return nil
  s[].destroyed[int(i)].cstring

proc jmapSyncCreated(
    s: ptr JmapSyncHandle
): ptr JmapEmailsHandle {.exportc: "jmap_sync_created", dynlib, cdecl, raises: [].} =
  ## A borrow into the sync handle's own storage, freed only when the
  ## sync handle is.
  if s.isNil:
    nil
  else:
    addr s[].created

proc jmapSyncUpdated(
    s: ptr JmapSyncHandle
): ptr JmapEmailsHandle {.exportc: "jmap_sync_updated", dynlib, cdecl, raises: [].} =
  ## A borrow into the sync handle's own storage, freed only when the
  ## sync handle is.
  if s.isNil:
    nil
  else:
    addr s[].updated

type JmapQueryHandle {.ruleOff: "objects".} = object
  ## The query spec in the library's OWN types, not the C caller's: each
  ## typed setter parses and validates its value at the boundary and
  ## stores the result here, so the query export has nothing left to
  ## lower. An untouched spec is the unfiltered, unsorted, unbounded
  ## query, which is a legal request rather than a special case.
  filter: Opt[Filter[EmailFilterCondition]]
  sort: Opt[seq[EmailComparator]]
  params: QueryParams

proc jmapQueryNew(
    outQuery: ptr ptr JmapQueryHandle
): cint {.exportc: "jmap_query_new", dynlib, cdecl, raises: [].} =
  ## Starts with no filter or sort selected; every set call is opt-in.
  if not l5Initialised:
    return asCint(jsMisuse)
  if outQuery.isNil:
    return asCint(jsMisuse)
  outQuery[] = createShared(JmapQueryHandle)
  asCint(jsOk)

proc jmapQueryFree(
    handle: ptr JmapQueryHandle
) {.exportc: "jmap_query_free", dynlib, cdecl, raises: [].} =
  ## Drops the query spec; safe to free either before or after a query
  ## call has consumed it. Declared before ``querySpec``, not after: see
  ## that func's docstring for why moving this destroy call below the
  ## copy it currently precedes reintroduces a spurious raises error.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

func accumulated(query: ptr JmapQueryHandle): EmailFilterCondition =
  ## The condition the spec has collected so far — the empty condition
  ## until a setter names its first term. One leaf condition is the whole
  ## C filter surface (operator trees are a builder-layer concern), so
  ## the operator arm is unreachable and answers the empty condition
  ## rather than making this a partial function.
  for f in query[].filter:
    case f.kind
    of fkCondition:
      return f.condition
    of fkOperator:
      return EmailFilterCondition()
  EmailFilterCondition()

proc setQueryLimit(query: ptr JmapQueryHandle, value: uint32): cint =
  ## 0 means "server default", which QueryParams already spells as an
  ## absent limit — so the C sentinel maps onto a real absence rather
  ## than travelling as a zero. Assigns the ``limit`` field alone: a
  ## whole-object replacement here would silently reset ``position``,
  ## ``anchor``, ``anchorOffset`` and ``calculateTotal`` too, clobbering
  ## whatever a future option for one of those fields had set.
  if value == 0'u32:
    query[].params.limit = Opt.none(UnsignedInt)
    return asCint(jsOk)
  let bound = parseUnsignedInt(int64(value))
  if bound.isErr:
    return asCint(jsValidation)
  query[].params.limit = Opt.some(bound.get())
  asCint(jsOk)

proc setQueryReadState(query: ptr JmapQueryHandle, value: uint32): cint =
  ## Lowers the read-state ordinal onto the $seen keyword pair here, at
  ## the boundary, so the boolean a JMAP filter cannot name stays
  ## unrepresentable inside the spec. Every arm sets BOTH keyword slots
  ## rather than only the one the ordinal names, so a second call with a
  ## different ordinal replaces the earlier read state outright instead
  ## of leaving its half of the pair stale alongside the new value.
  var cond = accumulated(query)
  case value
  of 0'u32:
    cond.hasKeyword = Opt.none(Keyword)
    cond.notKeyword = Opt.none(Keyword)
  of 1'u32:
    cond.hasKeyword = Opt.none(Keyword)
    cond.notKeyword = Opt.some(kwSeen)
  of 2'u32:
    cond.hasKeyword = Opt.some(kwSeen)
    cond.notKeyword = Opt.none(Keyword)
  else:
    return asCint(jsMisuse)
  query[].filter = Opt.some(filterCondition(cond))
  asCint(jsOk)

proc setQuerySort(query: ptr JmapQueryHandle, value: uint32): cint =
  ## The comparator is built here so the spec carries the sort the
  ## one-shot takes, not an ordinal a call site would have to translate.
  let direction =
    case value
    of 0'u32:
      sdDescending
    of 1'u32:
      sdAscending
    else:
      return asCint(jsMisuse)
  query[].sort = Opt.some(@[plainComparator(pspReceivedAt, direction)])
  asCint(jsOk)

func querySpec(query: ptr JmapQueryHandle): JmapQueryHandle =
  ## A NULL spec pointer is the empty spec: an unfiltered, unsorted,
  ## unbounded query is permitted, not a defect. Declared after
  ## ``jmapQueryFree`` deliberately: this is the one operation in the
  ## section that copies the whole spec by value, and a recursive
  ## ``Filter[C]`` case object's copy hook must be instantiated after
  ## its destroy hook, not before, for the compiler to infer both as
  ## ``raises: []`` (verified by reverting the order and watching the
  ## build fail on ```=destroy`(handle[])`` with a spurious "can raise
  ## Exception").
  if query.isNil:
    JmapQueryHandle()
  else:
    query[]

proc jmapQuerySetStr(
    query: ptr JmapQueryHandle, opt: cint, value: cstring
): cint {.exportc: "jmap_query_set_str", dynlib, cdecl, raises: [].} =
  ## Parses at the boundary: a mailbox id that is not an Id is refused
  ## here rather than carried as a string to the call site. The query
  ## handle has no error slot (it is a transient spec), so the status is
  ## the whole diagnosis.
  if not l5Initialised or query.isNil or value.isNil:
    return asCint(jsMisuse)
  var cond = accumulated(query)
  case opt
  of cint(0): # JMAP_Q_IN_MAILBOX
    let mailbox = parseIdFromServer($value)
    if mailbox.isErr:
      return asCint(jsValidation)
    cond.inMailbox = Opt.some(mailbox.get())
  of cint(1): # JMAP_Q_TEXT
    cond.text = Opt.some($value)
  else:
    return asCint(jsMisuse)
  query[].filter = Opt.some(filterCondition(cond))
  asCint(jsOk)

proc jmapQuerySetU32(
    query: ptr JmapQueryHandle, opt: cint, value: uint32
): cint {.exportc: "jmap_query_set_u32", dynlib, cdecl, raises: [].} =
  ## A dispatch table over the three u32 options; each helper owns its
  ## own boundary construction, so no ordinal nest lives here.
  if not l5Initialised or query.isNil:
    return asCint(jsMisuse)
  case opt
  of cint(2): # JMAP_Q_LIMIT
    setQueryLimit(query, value)
  of cint(3): # JMAP_Q_READ_STATE
    setQueryReadState(query, value)
  of cint(4): # JMAP_Q_SORT
    setQuerySort(query, value)
  else:
    asCint(jsMisuse)

proc jmapQueryEmails(
    client: ptr JmapClientHandle,
    accountId: cstring,
    query: ptr JmapQueryHandle,
    outEmails: ptr ptr JmapEmailsHandle,
): cint {.exportc: "jmap_query_emails", dynlib, cdecl, raises: [].} =
  ## A projection over the queryEmails one-shot. The spec arrived already
  ## parsed and validated by its setters, so nothing is lowered here; an
  ## absent query pointer runs an unfiltered, unsorted, unbounded query —
  ## permitted, not a defect.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outEmails.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  let spec = querySpec(query)
  let resp = queryEmails(
    client[].client,
    acct,
    filter = spec.filter,
    sort = spec.sort,
    queryParams = spec.params,
    bodyFetchOptions = textBodies(),
  )
  if resp.isErr:
    return recordError(client, resp.error)
  let qtg = resp.get()
  let (items, missing) = toEmailsHandleContent(qtg.get)
  let p = createShared(JmapEmailsHandle)
  p[].items = items
  p[].notFound = missing
  clearError(client)
  outEmails[] = p
  asCint(jsOk)

type JmapMessageHandle {.ruleOff: "objects".} = object
  ## The message in the library's OWN types wherever one exists: the
  ## three server-issued ids are parsed by their setter, so an id that
  ## is not an Id is refused where the caller supplied it. The address
  ## strings stay strings because the send parses them itself, into both
  ## the headers and the RFC 5321 envelope; parsing them here as well
  ## would duplicate a validation the substrate owns.
  ##
  ## Each address slot is optional so that "never set" stays distinct
  ## from "set to something unusable": the first is caller misuse, the
  ## second is a validation failure only the substrate can pronounce.
  ## The three recipient roles hold LISTS because the substrate takes
  ## lists, and the list itself sits inside the Opt so that a role no
  ## verb has named stays distinguishable from one a caller named with
  ## a single unusable address — a bare empty seq would flatten the two
  ## together and turn a validation failure into a misuse. Subject and
  ## body need no such distinction — absent and empty travel identically
  ## — so they are plain strings with one representation.
  identity: Opt[Id]
  drafts: Opt[Id]
  sent: Opt[Id]
  fromAddr: Opt[string]
  to: Opt[seq[string]]
  cc: Opt[seq[string]]
  bcc: Opt[seq[string]]
  subject: string
  body: string

proc jmapMessageNew(
    outMessage: ptr ptr JmapMessageHandle
): cint {.exportc: "jmap_message_new", dynlib, cdecl, raises: [].} =
  ## Every slot starts unset; a send names what it needs and nothing is
  ## assumed on the caller's behalf. The latch is checked before the
  ## allocation, not after: with --noMain the allocator's globals are
  ## not up until jmap_init has run NimMain.
  if not l5Initialised:
    return asCint(jsMisuse)
  if outMessage.isNil:
    return asCint(jsMisuse)
  outMessage[] = createShared(JmapMessageHandle)
  asCint(jsOk)

proc jmapMessageFree(
    handle: ptr JmapMessageHandle
) {.exportc: "jmap_message_free", dynlib, cdecl, raises: [].} =
  ## Drops the message; safe to free either before or after a send has
  ## consumed it, since the send copies what it needs into the
  ## substrate's own records.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

func recipientList(slot: Opt[seq[string]]): seq[string] =
  ## A role no verb has named contributes no header and no envelope
  ## recipient, which is exactly what the substrate makes of an empty
  ## list — so the two collapse here, at the boundary with the one-shot,
  ## rather than inside the slot where the distinction still earns its
  ## keep.
  for addresses in slot:
    return addresses
  @[]

func appended(slot: Opt[seq[string]], value: string): Opt[seq[string]] =
  ## The role's addresses with one more at the end. A role no verb has
  ## named yet becomes a one-address list, so an append needs no set to
  ## work from.
  for addresses in slot:
    return Opt.some(addresses & @[value])
  Opt.some(@[value])

func sendArguments(
    message: ptr JmapMessageHandle
): Result[
    tuple[identity: Id, mailboxes: SendMailboxes, plain: PlainTextMessage], string
] =
  ## Either the complete argument set the send takes, or the name of the
  ## first required option the message left unset. One function states
  ## what a send needs, so the readiness check and the diagnosis the
  ## caller reads back cannot disagree, and nothing is unwrapped that
  ## was not proven present.
  let identity = message[].identity.valueOr:
    return err("JMAP_MSG_IDENTITY_ID")
  let drafts = message[].drafts.valueOr:
    return err("JMAP_MSG_DRAFTS_MAILBOX")
  let sent = message[].sent.valueOr:
    return err("JMAP_MSG_SENT_MAILBOX")
  let fromAddr = message[].fromAddr.valueOr:
    return err("JMAP_MSG_FROM")
  let to = recipientList(message[].to)
  let cc = recipientList(message[].cc)
  let bcc = recipientList(message[].bcc)
  if to.len + cc.len + bcc.len == 0:
    # The envelope's rcptTo is the To ∪ Cc ∪ Bcc union and cannot be
    # empty (RFC 8621 §7.5), so one recipient in ANY role is the real
    # requirement — naming To here is the diagnosis a caller acts on.
    return err("JMAP_MSG_TO")
  ok(
    (
      identity: identity,
      mailboxes: SendMailboxes(drafts: drafts, sent: sent),
      plain: PlainTextMessage(
        fromAddr: fromAddr,
        to: to,
        cc: cc,
        bcc: bcc,
        subject: message[].subject,
        body: message[].body,
      ),
    )
  )

proc setMessageId(message: ptr JmapMessageHandle, opt: cint, value: cstring): cint =
  ## The three server-issued ids, parsed at the boundary and assigned to
  ## exactly one slot, so a second call for the same option replaces the
  ## first rather than leaving a sibling behind.
  let parsed = parseIdFromServer($value)
  if parsed.isErr:
    return asCint(jsValidation)
  let id = parsed.get()
  case opt
  of cint(0): # JMAP_MSG_IDENTITY_ID
    message[].identity = Opt.some(id)
  of cint(1): # JMAP_MSG_DRAFTS_MAILBOX
    message[].drafts = Opt.some(id)
  of cint(2): # JMAP_MSG_SENT_MAILBOX
    message[].sent = Opt.some(id)
  else:
    return asCint(jsMisuse)
  asCint(jsOk)

proc setMessageText(message: ptr JmapMessageHandle, opt: cint, value: cstring): cint =
  ## The address and content slots. One assignment per call: an option
  ## set twice keeps the second value only, and on a list-valued role
  ## the assignment replaces the whole list rather than growing it —
  ## which is what keeps this verb meaning one thing whichever ordinal
  ## it is handed.
  let text = $value
  case opt
  of cint(3): # JMAP_MSG_FROM
    message[].fromAddr = Opt.some(text)
  of cint(4): # JMAP_MSG_TO
    message[].to = Opt.some(@[text])
  of cint(5): # JMAP_MSG_CC
    message[].cc = Opt.some(@[text])
  of cint(6): # JMAP_MSG_BCC
    message[].bcc = Opt.some(@[text])
  of cint(7): # JMAP_MSG_SUBJECT
    message[].subject = text
  of cint(8): # JMAP_MSG_BODY
    message[].body = text
  else:
    return asCint(jsMisuse)
  asCint(jsOk)

proc jmapMessageSetStr(
    message: ptr JmapMessageHandle, opt: cint, value: cstring
): cint {.exportc: "jmap_message_set_str", dynlib, cdecl, raises: [].} =
  ## Two families, split by how the value is validated rather than by
  ## how it is spelled in C: an id is parsed here, a free-text value is
  ## not. The latch is checked before ``$value`` allocates. Neither
  ## helper recognises the other's ordinals, so an option outside the
  ## enum falls out of whichever it reaches as misuse.
  if not l5Initialised or message.isNil or value.isNil:
    return asCint(jsMisuse)
  if opt <= cint(2):
    setMessageId(message, opt, value)
  else:
    setMessageText(message, opt, value)

proc addMessageRecipient(
    message: ptr JmapMessageHandle, opt: cint, value: cstring
): cint =
  ## Only the three recipient roles hold lists. Appending to a slot with
  ## room for one value would have to mean "replace", which is the other
  ## verb's job, so it is refused rather than quietly reinterpreted.
  let text = $value
  case opt
  of cint(4): # JMAP_MSG_TO
    message[].to = appended(message[].to, text)
  of cint(5): # JMAP_MSG_CC
    message[].cc = appended(message[].cc, text)
  of cint(6): # JMAP_MSG_BCC
    message[].bcc = appended(message[].bcc, text)
  else:
    return asCint(jsMisuse)
  asCint(jsOk)

proc jmapMessageAddStr(
    message: ptr JmapMessageHandle, opt: cint, value: cstring
): cint {.exportc: "jmap_message_add_str", dynlib, cdecl, raises: [].} =
  ## Append is a verb of its own so that neither verb's meaning depends
  ## on which ordinal it was handed: set replaces a role outright, add
  ## extends one. Same guard order as the setter, and the latch is
  ## checked before ``$value`` allocates.
  if not l5Initialised or message.isNil or value.isNil:
    return asCint(jsMisuse)
  addMessageRecipient(message, opt, value)

type JmapSendResultHandle {.ruleOff: "objects".} = object
  ## The two server-assigned ids a successful send yields, flattened to
  ## strings so every getter is a stable borrow.
  emailId: string
  submissionId: string

proc jmapSend(
    client: ptr JmapClientHandle,
    accountId: cstring,
    message: ptr JmapMessageHandle,
    outResult: ptr ptr JmapSendResultHandle,
): cint {.exportc: "jmap_send", dynlib, cdecl, raises: [].} =
  ## A projection over the sendPlainText one-shot: composing the draft,
  ## filing it in Drafts and submitting it are its business (RFC 8621
  ## §7.5), so this reads the message's slots and records the outcome.
  ## An incomplete message is refused here, before any request is built,
  ## and the client's error slot carries the name the message handle has
  ## nowhere to put.
  if not l5Initialised:
    return asCint(jsMisuse)
  if client.isNil:
    return asCint(jsMisuse)
  if outResult.isNil:
    return recordMisuse(client, "out parameter must not be NULL")
  if message.isNil:
    return recordMisuse(client, "message must not be NULL")
  var acct = default(AccountId)
  let parsedAcct = parseAccountArg(client, accountId, acct)
  if parsedAcct != asCint(jsOk):
    return parsedAcct
  let args = sendArguments(message)
  if args.isErr:
    return recordMisuse(client, "message option not set: " & args.error)
  let ready = args.get()
  let resp =
    sendPlainText(client[].client, acct, ready.identity, ready.mailboxes, ready.plain)
  if resp.isErr:
    return recordError(client, resp.error)
  let sent = resp.get()
  let p = createShared(JmapSendResultHandle)
  p[].emailId = $sent.emailId
  p[].submissionId = $sent.submissionId
  clearError(client)
  outResult[] = p
  asCint(jsOk)

proc jmapSendResultFree(
    handle: ptr JmapSendResultHandle
) {.exportc: "jmap_send_result_free", dynlib, cdecl, raises: [].} =
  ## Drops the last reference to the send outcome.
  if handle.isNil:
    return
  `=destroy`(handle[])
  deallocShared(handle)

proc jmapSendResultEmailId(
    r: ptr JmapSendResultHandle
): cstring {.exportc: "jmap_send_result_email_id", dynlib, cdecl, raises: [].} =
  ## Always populated: the id of the drafted email that was submitted.
  if r.isNil: nil else: r[].emailId.cstring

proc jmapSendResultSubmissionId(
    r: ptr JmapSendResultHandle
): cstring {.exportc: "jmap_send_result_submission_id", dynlib, cdecl, raises: [].} =
  ## Always populated: the id of the EmailSubmission this send created.
  if r.isNil: nil else: r[].submissionId.cstring
