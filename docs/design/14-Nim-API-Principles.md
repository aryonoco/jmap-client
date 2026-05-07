# 14. Nim API Principles

## Why this document exists

The implementation of RFC 8620 (JMAP core) and RFC 8621 (JMAP mail) is
largely complete in `src/jmap_client/`. Layer 5 FFI is deferred; Push
(RFC 8620 §7) and Blob upload/download are deferred. What remains is the
hardest, longest-lived decision in any library project: the public API.

Libraries live or die by API quality. APIs that age well — libcurl,
SQLite, zlib — earn their adoption by being upgradable without fear,
predictable to learn, and stable for decades. APIs that age badly —
OpenSSL, c-client, libdbus — accumulate workarounds, get forked, and are
eventually wrapped by everyone instead of used directly.

This document distils the lessons from six C libraries — three "great"
and three "cautionary tales" — into principles for jmap-client's Nim API.
It is the guiding rubric for API design and refactor decisions before 1.0
lands. After 1.0 the API is locked; the time to choose well is now.

## The six libraries — what to remember

**libcurl (Daniel Stenberg, 1996–).** HTTP-and-many-other-protocols
transfer library. Stenberg's "Do. Not. Break. The. ABI." doctrine has
held since libcurl 7.16.0, 2006. Easy / multi
/ share handles separate single-blocking-transfer, event-loop-driven, and
cache-pooling concerns. `curl_easy_setopt(handle, OPTION, value)` is
variadic — extensibility paid for in compile-time type safety. Single
`CURLcode` enum across the API. Each callback is a function-pointer +
user-data-pointer pair. Connection cache, DNS cache, TLS session cache
all live on the handle, not in globals.

**SQLite (D. Richard Hipp, 2000–).** Embedded SQL database. Opaque pointers
(`sqlite3*`, `sqlite3_stmt*`) throughout — no exposed structs ever.
Five-call statement lifecycle (prepare / bind / step / reset / finalize)
separates compile cost from execution. Written compatibility promise —
file format and API stable since 2004, pledged through 2050. Single
integer-enum error channel. Extensions plug in via tables of function
pointers, never via new top-level symbols. The compatibility promise is
paid for by ~590× test code, four independent harnesses, MC/DC coverage.

**zlib (Jean-loup Gailly + Mark Adler, 1995–).** DEFLATE compression.
Originally extracted to support libpng. One core type (`z_stream`),
caller-allocated. Streaming-only API — caller owns input/output buffers,
library advances pointers. Custom allocator hooks via function-pointer
fields. 30 years of additive-only evolution; no zlib 2.0; zlib-ng forked
rather than break the API. Scope discipline — does compression, never
grew an archive layer or async runtime.

**OpenSSL (1998–, ex SSLeay).** TLS and crypto. Cautionary tale of API
rot. Four parallel layers public simultaneously (`RSA_*`, `EVP_*`,
`BIO_*`, `SSL_*`); ~20 context types with inconsistent lifecycles;
return-code chaos (some functions 1/0, some pointer/NULL, some
>0/0/<0); thread-local error queue with cross-contamination bugs across
PJSIP, Node, Ruby OpenSSL, PostgreSQL; initialisation churn across
1.0 / 1.1 / 3.0 with silent breakage; macro-emulated generics
(`STACK_OF`) the OpenBSD maintainers called "fragile, unusually
complicated, impossible to properly document". Two hostile forks
(LibreSSL deleted 90 KLOC in week one; BoringSSL explicitly abandoned
API stability). Tony Arcieri's "memory safety intervention" essay
reframes Heartbleed as inevitable in a 700kloc unsafe-C codebase nobody
could meaningfully audit.

**c-client / UW IMAP (Mark Crispin, 1988–2008).** Reference IMAP library,
written by IMAP's inventor. Single `MAILSTREAM*` god handle dispatching
to ~14 drivers (IMAP, POP3, NNTP, SMTP, mbox, mh, mx, mbx, …). Twelve
`mm_*` global link-time callback symbols — only one consumer per process
possible. Bespoke per-OS makefile (`make slx`, `make osx`, `make a32`,
~60 targets). Manual struct ownership (`mail_free_envelope`).
**CVE-2018-19518 (8.8 CVSS):** two-channel configuration (flags +
mailbox-name directives) became RCE through `ssh -oProxyCommand=`. PHP
`ext/imap` deprecated 2024 explicitly because c-client is unmaintained.
Every serious post-2000 IMAP project — Cyrus, Dovecot, Thunderbird,
mutt, Evolution — wrote its own implementation rather than reuse
c-client.

  **libdbus (Havoc Pennington / freedesktop, 2003–).** Reference D-Bus IPC
library. Cautionary tale of "if everyone wraps your library, your API is
wrong" — the maintainers themselves recommend GDBus, sd-bus, or QtDBus
over libdbus. Three callback-pair sets for main-loop integration (watch,
timeout, dispatch-status); manual `iter_open_container` /
`close_container` marshalling against stringly-typed signatures; three
paths for error reporting (bool return + `DBusError` out-param +
error-typed reply message); reference-counting ownership model. Lennart
Poettering on writing sd-bus from scratch: libdbus "lacks the bits that
make it easy and fun to use from C". GDBus is an independent
reimplementation, not a wrapper.

## Cross-cutting themes

Five themes recur across the great libraries and are violated in the
cautionary tales.

1. **Stability is operationalised, not declared.** libcurl publishes an
   ABI doctrine and a renamed-but-aliased mechanism for evolved options.
   SQLite publishes a written compatibility promise backed by 590× test
   coverage. OpenSSL has neither, and breaks behaviour in patch releases.

2. **One layer, one channel, one type per concept.** SQLite has
   `sqlite3*` and `sqlite3_stmt*`. zlib has `z_stream`. libcurl has
   `CURL*` / `CURLM*` / `CURLSH*` distinguished by I/O model. OpenSSL
   has ~20 context types and four parallel crypto layers.

3. **State is local to the handle, not the library.** libcurl's caches
   live on the easy handle; share handles are an explicit opt-in. zlib
   has no global state at all. c-client's `mm_*` globals make two
   consumers per process impossible. libdbus's
   environment-variable-and-init-flag matrix burns library authors.

4. **Errors travel through return values; diagnostics are typed.**
   SQLite's integer enum + `sqlite3_errmsg`. libcurl's `CURLcode` +
   per-handle error buffer. OpenSSL's thread-local error queue is the
   anti-pattern; libdbus's three error paths are the anti-pattern;
   c-client's `mm_log` global callback is the anti-pattern.

5. **The API is the spec, the spec is the API.** zlib does compression;
   it does not do archives. SQLite is `fopen()` for SQL; it is not
   Postgres. c-client did "all email protocols" through one abstraction
   and was forced by that to expose every backend's quirks. libdbus
   tried to be "useful as a backend for higher-level language bindings"
   and that hedge made it useless to direct consumers.

## Principles

Each principle has a name, a rule, evidence (which case study), Nim
translation (how the lesson lands in our type system), and application
(what it means concretely for jmap-client). Principles are numbered for
reference in PR review and design discussion.

### Stability and versioning

**P1. Lock the API contract before 1.0; evolve only by addition.**
*Rule.* Decide the public API surface, freeze it before announcing 1.0,
and after 1.0 add only — never rename, never repurpose, never silently
change behaviour. *Evidence.* libcurl's 18 years of ABI stability since
7.16.0; SQLite's 21+ years since SQLite 3 (2004); zlib's 30 years with
no 2.0. Anti-evidence: OpenSSL's 1.1.0c silent change to `SSL_read`
semantics, the 1.0→1.1 opaque-struct break, the 1.1→3.0
default-algorithm provider change. *Nim translation.* Strict SemVer;
Nim's `{.deprecated.}` pragma for evolved entry points; default-argument
additions and overloaded variants for new options instead of `_v2` /
`_v3` suffixes. *Application.* Before announcing 1.0: choose the public
symbol set, mark all internals private (no `*`). After 1.0: every
breaking change is a major version. New JMAP features (e.g. RFC 8887
WebSocket) arrive as new types and new entry points, never as
repurposed old ones.

**P2. Stability is bought with tests, not declared.**
*Rule.* The API stability promise is only as strong as the test suite
that catches its violations. *Evidence.* SQLite ships ~155 KLOC of code
shadowed by ~92 MLOC of test code (~590× ratio), four independent
harnesses, MC/DC coverage. The result is an API that has not had to
break in 21 years. OpenSSL has comparatively weaker testing and breaks
behaviour in patch releases. *Nim translation.* The existing `tests/`
taxonomy (`unit/`, `serde/`, `property/`, `compliance/`, `stress/`)
plus live integration against Stalwart, Apache James, Cyrus IMAP is the
right shape. Property-based tests defending wire-format invariants are
the API's compile-time-style guarantees. *Application.* Before 1.0,
audit which public functions lack test coverage. Add fuzz / property
tests for serde round-trip on every typed message variant. CI must fail
on any user-observable behaviour change unless that change is explicit
in a release note.

**P3. Prefer Nim's overloading and default arguments over suffix versioning.**
*Rule.* When an API entry point evolves, add overloads or new defaults;
do not add `_v2`. *Evidence.* SQLite uses `sqlite3_prepare_v2` because
C has no overloading; libcurl uses additive `CURLOPT_*` enum values for
the same reason. Nim has both overloading and default arguments.
*Nim translation.* `proc emailGet(session, ids)` and
`proc emailGet(session, ids, properties)` coexist via overloading.
*Application.* Audit the eventual public surface for any C-style suffix
versioning before 1.0. None should exist.

### Surface area and scope

**P4. Pick a scope; defend it ruthlessly.**
*Rule.* jmap-client implements RFC 8620 + RFC 8621 + the JMAP-defined
spec extensions. It does not implement IMAP, POP3, SMTP, contacts,
calendars, or PIM-shaped abstractions over JMAP. *Evidence.* zlib's 30
years of "no archive layer". SQLite's "fopen() for SQL, not Postgres"
framing. Anti-evidence: c-client's universal `MAILSTREAM*` over IMAP /
POP / NNTP / SMTP / mbox / mh forced every operation to be the union of
every backend's semantics; libdbus's "useful as a backend for bindings"
hedge made it baroque to direct consumers. *Nim translation.* Module
structure already enforces this — `src/jmap_client/mail/` is the only
mail-specific subtree. *Application.* When future feature requests
arrive ("can we add IMAP fallback?"), the answer is "this library does
JMAP; consume an IMAP library separately and compose them in the
application".

**P5. Single public layer; internals are internal.**
*Rule.* One public layer per concept. If lower layers must exist, they
are private (no `*` export, or in an `internal/` subdirectory).
*Evidence.* libcurl exposes only `curl_easy_*` and `curl_multi_*` as
parallel I/O models, not parallel crypto layers. SQLite exposes
prepare / bind / step but private internals are private. Anti-evidence:
OpenSSL's `RSA_*` + `EVP_*` + `BIO_*` + `SSL_*` all public, with
provider-pluggability available only via `EVP_*`, leading to silent
FIPS bypass when users pick the wrong layer. *Nim translation.* Audit
`src/jmap_client/`'s public re-exports. Decide whether the public API
is L3 protocol-flavoured (`session.email.get(...)`) or L1/L2-flavoured
(build typed `Request`, hand to a dispatcher, parse `Response`) — not
both. *Application.* If both flavours are useful, expose only one as the
documented "use this" API; the other is implementation detail.
Reviewers reject PRs that grow parallel public surfaces.

**P6. Convenience APIs are quarantined from the protocol-fidelity core.**
*Rule.* High-level convenience methods (e.g. `client.fetchInbox()`,
`client.archiveEmail()`) live in a separate module from the
protocol-fidelity primitives. Documentation for the core does not
assume the convenience layer. *Evidence.* zlib's `gz_*` family — a
`FILE*`-bound convenience layer with a long history of edge-case bugs
that contaminate users' image of the rest of zlib. SQLite's
`sqlite3_exec` — a callback-based convenience that the docs explicitly
steer serious users away from. *Nim translation.* Place convenience
helpers under a clearly-named module (`convenience.nim` already
exists); ensure the core L3 protocol API documents the underlying
mechanism without referencing convenience helpers. *Application.* Audit
`src/jmap_client/convenience.nim` — verify it does not leak abstractions
back into the core; verify documentation for L3 protocol primitives is
self-contained.

**P7. Watch the wrap rate.**
*Rule.* If the typical user pattern is "use a wrapper around
jmap-client", the API is wrong. *Evidence.* libdbus's failure: GDBus
and sd-bus are independent reimplementations explicitly because
libdbus is unusable directly. OpenSSL's failure: every language has its
OpenSSL wrapper that hides the API. Positive evidence: SQLite is
wrapped at the language-binding layer (Python's `sqlite3`, Node's
`better-sqlite3`, Rust's `rusqlite`) but the C API is itself directly
usable. *Nim translation.* When the eventual L5 FFI ships, ask: would a
competent C developer reach for jmap-client directly, or would they
look for "a wrapper that hides jmap-client"? The latter is failure.
*Application.* Before 1.0 lands, write a non-trivial sample app
(e.g. CLI: list mailboxes, query email, apply flag in a batch) using
only the public Nim API. Treat its painful spots as bugs against the
API, not against the user.

### Handles, identity, state

**P8. Opaque handles via private fields and ARC destructors.**
*Rule.* The library's primary value-types (`Session`, `Client`, future
`PushChannel`) are `ref object` with non-exported fields. ARC's
`=destroy` is the public destruction mechanism — no `client.close()`
ritual required. *Evidence.* SQLite's `sqlite3*` opaqueness has enabled
21 years of internal rewrites with zero ABI breaks. zlib's `z_stream`
keeps internals behind `internal_state*`. *Nim translation.*
`type Client* = ref object` with all fields unexported. ARC handles
cleanup. For the future L5 FFI, opaque handles via `distinct pointer`
types are the equivalent. *Application.* Audit which fields on
`Session`, `Client`, and request builders are currently exported (`*`)
vs private. Default to private. Each export is a deliberate decision.

**P9. Two clear context types per concept maximum.**
*Rule.* Resist a context-type zoo. One handle for each persistent
concept; one builder for each transient action. *Evidence.* SQLite has
`sqlite3*` and `sqlite3_stmt*`. Two types, lifecycle obvious.
Anti-evidence: OpenSSL's ~20 `*_CTX` types with inconsistent ownership
and reuse semantics. *Nim translation.* `Session` (long-lived, cached
capabilities) + `RequestBuilder` (transient, builds a batched
`Request`). Resist `EmailGetCtx`, `EmailSetCtx`, `MailboxQueryCtx`,
etc. *Application.* If a per-method context type is proposed, justify
why a generic `RequestBuilder` plus typed method invocations cannot do
the same job.

**P10. No global state. Configuration is a typed value.**
*Rule.* Every piece of configuration travels on a `Session` value. No
environment variables consumed inside L1–L3. No `setDefaultTimeout()`-
style top-level setters. No singleton `Client.instance()`. *Evidence.*
libcurl's per-handle-cache discipline. zlib's zero global state.
Anti-evidence: OpenSSL's `OPENSSL_CONF` env var, `OPENSSL_init_ssl`
flag bits, the `OSSL_LIB_CTX` retrofit. c-client's twelve `mm_*`
link-time globals. *Nim translation.* L1–L3 already has
`{.push raises: [], noSideEffect.}` which precludes global mutation.
The temptation to add globals will arise at L4 (transport) or L5 (FFI);
resist there. *Application.* Audit `client.nim` for any module-level
mutable state. The `Session` value owns everything; the library reads
no globals.

**P11. No global callbacks. Each callback is a per-handle field with a context pointer.**
*Rule.* Every callback registered on a handle is a field on that
handle, paired with a user-data pointer (or, in Nim, a closure
environment) that the library threads back unmodified. No link-time
global callback symbols. *Evidence.* libcurl's
`CURLOPT_WRITEFUNCTION` / `CURLOPT_WRITEDATA` pair. Anti-evidence:
c-client's `mm_log`, `mm_login`, `mm_fatal` — link-time globals making
two consumers per process impossible, forcing synchronous credential
prompts, forbidding async runtimes. *Nim translation.* Inside Nim,
prefer closures (the closure environment carries state). At the future
L5 FFI boundary, every C callback registration takes a `pointer`
userdata that the library threads back unchanged. *Application.* No
`proc registerLogger(p: LogProc)` at module level. Logging, auth
callbacks, and progress callbacks are all per-`Session` (or
per-`Client`).

**P12. Memory ownership is encoded in the type, not in documentation.**
*Rule.* Whether a value is owned, borrowed, or transferred is visible
in the signature. *Evidence.* SQLite's `SQLITE_STATIC` /
`SQLITE_TRANSIENT` / destructor sentinels make lifetime explicit at the
call site. Anti-evidence: c-client's `ENVELOPE*` returns with
`mail_free_envelope()` rules in prose; libdbus's reference-counting
with subtle "library takes its own ref" rules. *Nim translation.*
Inside Nim, ARC + `sink` / `lent` / `var` parameters make ownership
type-level. The lesson resurfaces only at L5 FFI, where
`nim-ffi-boundary.md`'s caller-allocated buffer vs library-owned
storage rules apply. *Application.* For the eventual L5 FFI: every
C-exposed function with a returned pointer documents and enforces
ownership in the function name or a paired `_destroy` routine.

### Errors

**P13. One error rail (`Result[T, E]`); name every variant.**
*Rule.* Every fallible function returns `Result[T, E]` where `E` is a
sum type with named variants. No string error returns; no integer
error codes; no thread-local error state. *Evidence.* libcurl's
`CURLcode` enum. SQLite's primary error code + extended code system.
Anti-evidence: OpenSSL's >0 / 0 / -1 + thread-local queue + `errno`;
libdbus's bool + `DBusError` out-param + error-message reply.
*Nim translation.* Already established convention —
`JmapResult[T] = Result[T, ClientError]`, `ClientError` a sum type,
`ValidationError` / `MethodError` / `SetError` plain objects. Defend
the variant kinds; never collapse to strings. *Application.* Audit any
`proc` that takes an out-parameter for error info — that's a code
smell. Every fallible function returns `Result`. The `?` operator is
the propagation idiom.

**P14. No thread-local error queues; no last-error globals.**
*Rule.* Errors travel through the return value at the call site.
Diagnostic context is a field of the error variant. *Evidence.*
OpenSSL's `ERR_get_error` is the canonical anti-pattern — bindings
(PJSIP, Node.js, Ruby OpenSSL, PostgreSQL, uSockets) shipped bugs from
cross-thread contamination and forgotten `ERR_clear_error`.
*Nim translation.* The Result rail is already in place. The danger is
at L5 FFI: a C ABI naturally pulls toward `int last_error()` style.
Resist. *Application.* Future L5 FFI design: errors are returned by the
function, not stashed. If FFI ergonomics demand a "fetch error string"
routine, it operates on a returned error code, not on global state.

**P15. Smart constructors return `Result`; raw constructors are private.**
*Rule.* Public constructors validate; raw struct construction is
unexported. *Evidence.* OpenSSL's `*_new` returning pointer or NULL
with no distinguishable failure mode. *Nim translation.*
`parseAccountId(s): Result[AccountId, ValidationError]` is the pattern.
Distinct types whose raw constructor is `AccountId(s)` must not be
reachable from outside their defining module. *Application.* Audit
distinct types: every `MyType(rawValue)` raw construction in `src/`
should be inside the defining module. External consumers go through
`parseMyType`. The modules `validation.nim`, `primitives.nim`, and
`identifiers.nim` are the model.

**P16. Encode preconditions in types.**
*Rule.* If a function has a precondition (X must be Y, X and Z must be
in the same state, etc.), encode it in the type — distinct
phantom-typed states, sum-type discriminators, builder patterns.
*Evidence.* OpenSSL's `SSL_get_error` is only valid on the same thread
that performed the I/O, with no other OpenSSL calls between, with the
queue cleared first — none of which appears in the signature.
*Nim translation.* `{.experimental: "strictCaseObjects".}` already buys
compile-time enforcement of variant access. Phantom types (`Email[Validated]`
vs `Email[Unvalidated]`) for state machines. Builder patterns
(`RequestBuilder` → `BuiltRequest` → `Response`) for lifecycle.
*Application.* The most fertile place for this in jmap-client is
request construction. A `RequestBuilder` that accumulates invocations
and a `BuiltRequest` that has been validated and is ready to dispatch
are different types. Result references (`#prev`) refer only to
invocations the type system knows preceded them.

### Configuration and extension

**P17. One configuration surface; one parser; one validator.**
*Rule.* Each piece of configuration has exactly one syntactic form. No
"you can pass X as a flag or as a directive in the URL string".
*Evidence.* c-client's CVE-2018-19518 (8.8 CVSS): the two-channel
`OP_*` flags + `{server/flag}` mailbox-name directives created a
parser composition that admitted `ssh -oProxyCommand=` injection.
*Nim translation.* JMAP server config (endpoint, auth, capabilities)
flows through one typed `SessionConfig` value; never split across
"field on Session" + "directive in URL". *Application.* Auditing
`client.nim`: any place where a configuration value can be supplied
two ways is a redesign target.

**P18. Sum types over bit-flag soup.**
*Rule.* Mode and state are sum-type discriminators, not OR-ed integer
constants. *Evidence.* c-client's `mail_open` flags
(`OP_HALFOPEN | OP_READONLY | OP_DEBUG | OP_SECURE | OP_TRYSSL |
OP_NOKOD | …`) — illegal combinations are not detectable by the
compiler. zlib's `inflateInit2(strm, 47)` for "auto-detect gzip" —
magic constants encoding mode bits in a numeric parameter.
*Nim translation.* `{.experimental: "strictCaseObjects".}` and case
objects with literal-discriminator construction. *Application.* No
`int` parameters carrying multiple Boolean flags. No Bool parameters
where an enum would name the alternatives. (Already covered by
`nim-functional-core.md` rule "Named two-case enum replaces bool";
restated for prominence.)

**P19. Schema-driven types are the source of truth, not stringly-typed signatures.**
*Rule.* The wire format is described by types; code construction goes
through those types; raw JSON access exists for diagnostics, not for
application code. *Evidence.* libdbus's `"a{sv}"` signature literals +
manual `iter_open_container` / `close_container` traversal — the
compiler cannot relate the signature to the appended values. GDBus's
`gdbus-codegen` and QtDBus's `qdbusxml2cpp` exist precisely to lift
this back into types. *Nim translation.* L1 (typed records) + L2
(typed serde) already establish the principle. The temptation to
expose a "build a request from a `JsonNode`" public API would be the
libdbus failure. *Application.* The public API for constructing a
`Request` accepts typed `Invocation` values; raw `JsonNode` request
construction is private to the library. Diagnostic emission
(`Request.toJson`, `Response.toJson`) is fine; the reverse direction
is not.

**P20. Add features via additive variants, not new module-level entry points.**
*Rule.* A new JMAP method or extension is a new variant of an existing
sum type, or a new method on an existing handle, not a new top-level
proc that mirrors an old one. *Evidence.* SQLite's virtual table /
custom function / VFS plugin tables of function pointers — capability
grows without growing the public symbol count. libcurl's `CURLOPT_*`
enum — 300+ options, no signature changes. *Nim translation.*
Capability negotiation flows through the `Session.capabilities` set;
methods discriminated by `MethodName` enum extend by adding variants.
*Application.* When implementing the deferred RFC 8620 §5 extensions,
prefer adding variants to existing types over adding parallel public
modules.

### Lifecycle and concurrency

**P21. Granular lifecycle via distinct types per phase.**
*Rule.* Lifecycle states are distinct types; transitions are functions
returning the next type. *Evidence.* SQLite's prepare → bind → step →
reset → finalize, where each phase has its own invariant.
*Nim translation.* `RequestBuilder` (mutable accumulator) →
`BuiltRequest` (validated, ready) → `DispatchedRequest` (sent,
awaiting) → `Response` (received). Reset = `BuiltRequest →
RequestBuilder`. Finalize = `=destroy`. *Application.* Designing the
request lifecycle now: each phase is a type. The compiler enforces
that you cannot dispatch a `RequestBuilder` directly, cannot re-bind a
`DispatchedRequest`, etc.

**P22. Sync-blocking API first; async second; async via interface, not framework lock-in.**
*Rule.* The headline API is
`Client.dispatch(request): Result[Response, ClientError]` — blocking,
complete in one call. Async support comes later, through the same type
but a different transport. The library does not link a specific async
framework. *Evidence.* libcurl shipped easy (blocking) first, then
multi (event-loop). PHP / Python / Ruby bindings overwhelmingly map to
easy. SQLite is unapologetically synchronous and dominates anyway.
*Nim translation.* L4 transport is a small interface (`Transport`
concept or trait); concrete implementations may use `std/httpclient`,
`puppy`, `chronos`, etc. The user picks. *Application.* Do not import
`std/asyncdispatch` or `chronos` from L1–L3. L4's transport interface
accepts a synchronous `httpRequest` proc; alternative transports can
wrap async runtimes themselves.

**P23. Plan async / push as a separate type from day one.**
*Rule.* Even though Push (RFC 8620 §7) and WebSocket (RFC 8887) are
deferred, the type they will inhabit (`PushChannel` or similar) is
named in the public design now. The synchronous request / response
API does not pretend it might one day grow async. *Evidence.* libdbus
retrofitted main-loop integration as three callback-pair sets and
made every consumer suffer. The right shape is "async is a different
type with different lifecycle, not a flag on the existing one".
*Nim translation.* A stub `PushChannel` type exists in the public
types module; its only method may be `unimplemented()` until Push is
built. The signal to consumers: "synchronous now; push when it arrives
is a separate, additive thing — your existing code does not change".
*Application.* As part of the pre-1.0 design pass, write down the type
signatures Push will inhabit. Do not implement; just lock in that the
shape will not be retrofit onto `Client`.

**P24. Decide the threading invariant explicitly; encode it.**
*Rule.* The library states one threading invariant per type:
"thread-safe", "single-threaded", or "movable but not shared".
Document and (where possible) type-encode. *Evidence.* libdbus's
"thread-safe with `dbus_threads_init_default`" is empirically false in
many configurations, leading to GDBus's reimplementation-from-scratch.
c-client's "single-threaded period" was a hard ceiling on adoption.
*Nim translation.* L1–L3 are pure (`{.noSideEffect.}`) hence trivially
thread-safe (referentially transparent). L4 transport is single-thread-
per-`Client`. Consumers needing concurrency hold one `Client` per
thread. State this explicitly in the docstrings of the relevant types.
*Application.* Add to `Client`'s docstring: "A `Client` is not
thread-safe. Hold one per thread."

### Craft and process

**P25. License clarity from v0.1.0.**
*Rule.* Pick a permissive standard licence and never deviate.
*Evidence.* c-client's custom UW Free-Fork licence kept it out of
mainstream Debian for years; the eventual Apache-2.0 relicence in 2008
came too late to win back the wave of consumers who had already
written their own. *Nim translation.* The current licence (visible in
<!-- REUSE-IgnoreStart -->
`LICENSE` and source-file `# SPDX-License-Identifier:` headers) is
<!-- REUSE-IgnoreEnd -->
`BSD-2-Clause`. *Application.* Confirm consistency across all source
files. Standard licence; keep it.

**P26. Standard build tooling, no per-OS branching.**
*Rule.* Use the language ecosystem's standard build system. No
bespoke per-OS makefile targets. *Evidence.* c-client's ~60 hand-coded
`make slx` / `make osx` / `make a32` / etc. targets meant every new
platform required a maintainer commit. *Nim translation.* `mise` +
`just` + `nimble` — already in place. *Application.* Resist any
temptation to add OS-conditional compile paths in shipped code.
Consumer integration must not require touching jmap-client's build.

**P27. Documentation as succession planning.**
*Rule.* The library's architecture is documented at a level where a
new maintainer can pick up a layer without prior knowledge.
*Evidence.* c-client's December 2012 freeze when Mark Crispin died;
no successor with full mental ownership. SQLite, libcurl, zlib all
have multiple competent maintainers and documentation that scales.
*Nim translation.* `docs/design/`, and
the L1–L5 layer separation are exactly this. *Application.* Continue
investing in design docs. New modules get a design note before
they're written.

**P28. Long-form first-party documentation.**
*Rule.* Reference docs (per-function man pages, generated API docs)
are necessary but insufficient. The library author writes a long-form
narrative companion. *Evidence.* libcurl's *Everything curl*
(everything.curl.dev) is widely cited as a model. SQLite's
`testing.html` and Hipp's talks are themselves marketing assets.
*Nim translation.* A `docs/guide/` or `docs/everything-jmap.md`
companion when the API stabilises. *Application.* Plan a narrative
consumer-facing guide written before 1.0; ship it alongside the
reference docs.

**P29. Bench API ergonomics with a real consumer before locking 1.0.**
*Rule.* Write a non-trivial sample consumer using only the public
API. Treat its painful spots as bugs against the API, not against the
user. *Evidence.* sd-bus's existence is the proof that libdbus's API
problems were not visible from inside the implementation; they were
visible only when someone tried to write a real client end-to-end.
*Nim translation.* Concretely: write a CLI tool (e.g. `jmap-cli
mailbox list`, `jmap-cli email query --in inbox --unread`, `jmap-cli
email flag --add seen`) using only the public `jmap_client` Nim API.
Watch where it gets awkward. *Application.* Before 1.0: the sample
CLI exists and has been used. Each awkwardness is either resolved or
documented as a known trade-off.

## Anti-patterns explicitly forbidden

The negative space, in tight form. If a future PR introduces any of
these, the right action is to redesign rather than wave it through.

- **Global mutable state.** No module-level `var`. No `setDefaults()`.
  No `Client.instance()` singleton. No env-var consumption inside
  L1–L3.
- **Global callbacks.** No `mm_*`-style link-time symbols. Every
  callback is a field on the handle it modifies.
- **Two-channel configuration.** No "you can pass this as a flag or in
  the URL string". One syntactic surface per option.
- **Stringly-typed APIs masquerading as typed.** No public `JsonNode`
  parameters where a typed message would do. No `string` discriminators
  where an enum exists.
- **Multiple coexisting public layers for the same task.** Pick one;
  the rest are private.
- **Convenience layer leaking back into the core.** Convenience
  helpers may call the core; the core does not import them.
- **Catch-all `else` on case statements over finite enums.** Already a
  project rule (`nim-functional-core.md`); restated for emphasis: new
  variants must force compile errors at every consuming site.
- **`.get()` on a `Result` without an adjacent invariant comment.**
  Already a project rule; restated.
- **Last-error thread-locals at the FFI boundary.** When L5 lands,
  errors travel through return values, not through
  `int jmap_last_error()`.
- **Behaviour changes in patch releases.** Anything that changes
  observable wire bytes or method semantics is a major version.
- **Renaming or removing public functions after 1.0.** Adding
  `proc emailGet2(...)` is a smell. Use overloads or default
  parameters.

## Concrete decisions to make before 1.0

This list is the action-item list this principles document implies. It
is the answer to "what's left between today and 1.0".

1. **Choose the public layer.** Decide whether the public API is L3
   protocol-flavoured (`session.email.get(...)`-style methods) or
   L1+L2 flavoured (build typed `Request` + dispatch). Pick one.
   Document the choice. Mark the other private.
2. **Public symbol audit.** Walk the `*` exports across `src/`. For
   each, ask "is this a load-bearing public commitment?" Default to
   private for anything not justified.
3. **Lock the wire contract.** Property-based / round-trip tests
   defending serde for every public type. CI fails on any change.
4. **Name the Push channel type.** Even if unimplemented, write down
   the type signatures Push and WebSocket will inhabit. Lock that
   they are separate from `Client.dispatch`.
5. **Threading invariant.** State the threading invariant for
   `Session`, `Client`, request builders. Document in the docstring.
6. **Sample consumer.** Build the CLI tool described in P29. Use the
   public API only. Bring back the awkwardness as bugs.
7. **Long-form guide.** Draft `docs/guide/everything-jmap.md` (or
   similar). It does not need to be complete; it needs to exist and
   reflect the locked API.
8. **License confirmation.** Verify `BSD-2-Clause` (or chosen) at
   top-level `LICENSE` and in every source-file header (already
   happening; audit consistency).
9. **L5 FFI design note.** Even with FFI deferred, write down which
   principles bind the future FFI now (especially: no last-error
   globals, opaque handles, enum errors, no init ritual).
10. **Convenience module quarantine.** Verify `convenience.nim` does
    not leak into the core; verify the docs for L3 primitives are
    self-contained.

## Verification

This document is a rubric, not an implementation. Verification is by
use:

- **At PR review time.** Reviewers reference principles by number
  ("this violates P5 — we'd be exposing two parallel public layers").
  The numbering exists for reference.
- **At design review time.** New design docs in `docs/design/` cite
  the principles they're upholding or trading off against.
- **At 1.0 freeze.** Each "Concrete decision" item above is checked
  off, written down, and merged into the design corpus.
- **During L5 FFI design.** The FFI design doc explicitly maps each
  principle to its C-ABI manifestation (or notes "Nim handles this; C
  ABI must mirror").
- **As a "would I do this in OpenSSL?" check.** When a design decision
  feels expedient, ask: would this be the OpenSSL or c-client choice?
  If yes, redesign.

The principles are not commandments. They are extracted experience
from libraries that lived and died on API design. Trade them off when
the trade-off is conscious and documented.
