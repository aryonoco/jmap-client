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

proc recordError(h: ptr JmapClientHandle, err: JmapError): cint {.used.} =
  ## Renders the diagnostic at record time so the errmsg borrow needs no
  ## later allocation. No exported proc calls this yet — jmap_client_new
  ## fails before a handle exists, so it reports the bare status instead;
  ## later handle-bearing operations call this, hence ``{.used.}``.
  let status = statusOf(err.kind)
  h[].err = ErrorSlot(status: status, message: err.message)
  asCint(status)

proc recordMisuse(h: ptr JmapClientHandle, msg: string): cint {.used.} =
  ## Misuse detected in L5 code, not on the JmapError rail, so the
  ## message is authored here rather than carried from L4. Unused until
  ## a later handle-bearing operation can detect misuse post-construction,
  ## hence ``{.used.}``.
  h[].err = ErrorSlot(status: jsMisuse, message: msg)
  asCint(jsMisuse)

proc clearError(h: ptr JmapClientHandle) {.used.} =
  ## A fallible call that succeeds resets the slot — jmap_errmsg reports
  ## the MOST RECENT call's outcome, exactly like sqlite3_errmsg. Unused
  ## until a later handle-bearing operation exists to succeed, hence
  ## ``{.used.}``.
  h[].err = ErrorSlot(status: jsOk, message: "")

proc jmapClientNew(
    sessionUrl, username, password: cstring,
    transport: pointer,
    outClient: ptr ptr JmapClientHandle,
): cint {.exportc: "jmap_client_new", dynlib, cdecl, raises: [].} =
  ## Pre-handle failures answer the bare status: there is no handle yet
  ## to carry a message; that is the accepted trade.
  if not l5Initialised:
    return asCint(jsMisuse)
  if outClient.isNil or sessionUrl.isNil or username.isNil or password.isNil:
    return asCint(jsMisuse)
  if not transport.isNil:
    # transport arrives as an opaque C pointer; nothing here can turn
    # it into the Nim ``Transport`` that initJmapClient/connect require,
    # so only nil (the built-in HTTP backend) is interpretable.
    return asCint(jsMisuse)
  let connected = connect($sessionUrl, $username, $password)
  if connected.isErr:
    return asCint(statusOf(connected.error.kind))
  # include/jmap_client.h permits handing a handle to another thread;
  # plain create/dealloc are documented thread-local in
  # lib/system/memalloc.nim ("The freed memory must belong to its
  # allocating thread!"), so the box goes on the shared heap instead —
  # correct whether or not the build defines -d:useMalloc.
  let p = createShared(JmapClientHandle)
  p[].client = connected.get()
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
