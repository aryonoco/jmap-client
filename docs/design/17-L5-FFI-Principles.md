<!--
SPDX-License-Identifier: BSD-2-Clause
Copyright (c) 2026 Aryan Ameri
-->

# 17. Layer-5 C ABI Principles

## Why this document exists

Decision 9 of `14-Nim-API-Principles.md` requires the C ABI's binding
principles to be written down before the FFI is built — especially the
error model, handle opacity, and the absence of any initialisation
ritual. This document is that design note (ledger item D10). It records
the decisions settled with the user on 2026-08-04 and maps each API
principle to its C-ABI manifestation.

It is authoritative for the C ABI and supersedes two earlier sources
where they disagree with it:

- `.claude/rules/nim-ffi-boundary.md` and the `nim-ffi-boundary` skill,
  which previously mandated thread-local last-error state (rewritten in
  the same change that lands this note);
- `docs/design/00-architecture.md` §5.1–5.4, whose handle inventory
  (four PascalCase types including `JmapRequest`/`JmapResponse`) and
  §5.4 "no raw enum exposure … prefer `cint` constants" rule predate
  this decision. §5.5's instruction to "follow the patterns described
  in §5.1–5.4 when the C ABI boundary is built" is amended by this
  note; a dated pointer is recorded at the head of that section.

The tracker's original title for this note was
`16-L5-FFI-Principles.md`; number 16 was taken by the consumer-chair
audit, so the note lands as 17.

Everything here binds the *first* C ABI (v1). Where a section reserves
a future surface (the builder projection, Push, Blob), the reservation
is itself a commitment: the future surface arrives additively (P1, P20)
and nothing in v1 will need renaming to accommodate it.

## Settled decisions (2026-08-04)

Four forks were put to the user and settled; they are the axioms of
this document.

1. **Error model: per-handle state** — the SQLite/libcurl model. Every
   fallible function returns a `jmap_status` code; rich diagnostics are
   read from the handle the call was made on; `jmap_strerror` is static
   and stateless. Thread-local last-error state is forbidden (P14). The
   rules file and skill are rewritten accordingly.
2. **v1 scope: lift the missing one-shots first, wrap the easy path
   only** — a prerequisite Nim PR adds the write one-shot (ledger item
   **C15**, Email/set: flag, move, destroy) and an Email/changes sync
   one-shot (**no ledger item exists yet**; the prerequisite PR opens
   one, and it subsumes C17's `/updated` back-reference and C21's
   current-state accessor as its components). The C ABI then wraps
   only the one-shot easy path. The RequestBuilder pipeline stays
   Nim-only in v1 and is reserved for a future additive C layer — the
   libcurl easy→multi trajectory (P22).
3. **Memory: library-owned borrows** — read accessors return
   `const char*` / opaque views owned by the library, valid until the
   owning handle is freed (or, where documented, the next mutating call
   on it). Nothing returned by a read accessor is freed by the caller;
   objects are released via paired `jmap_*_free` functions.
   `jmap_errmsg` follows `sqlite3_errmsg` semantics exactly.
4. **Design ratified in sections** — hand-curated public header with a
   CI consistency gate; entity reads as opaque views with per-field
   getters; `jmap_version()` plus header version macros (lifting the
   C-side half of parked ledger item C6).

## 1. The error model

**Rule.** One status enum across the whole ABI; errors travel through
return values; diagnostics live on the handle; nothing lives in
thread-local or global state.

```c
typedef enum {
  JMAP_OK = 0,
  JMAP_E_VALIDATION = 1,
  JMAP_E_TRANSPORT  = 2,
  JMAP_E_REQUEST    = 3,
  JMAP_E_SESSION    = 4,
  JMAP_E_MISUSE     = 5,
  JMAP_E_PROTOCOL   = 6,
  JMAP_E_METHOD     = 7,
  JMAP_E_SET        = 8,
  /* additive growth only — existing ordinals never change (P1) */
} jmap_status;
```

- `jmap_status` is the C projection of `JmapErrorKind` plus `JMAP_OK`.
  The Nim enum is `{.size: sizeof(cint).}`-compatible by construction;
  ordinals are locked at first release and grow additively (P1, P13,
  P20). A `JMAP_E_*` value maps 1:1 onto a `JmapErrorKind` arm; a new
  arm in Nim is a new ordinal in C, never a reuse.
- **Every fallible exported function returns `jmap_status`.** Outputs
  travel through out-parameters. No function communicates failure
  through NULL alone, through negative sentinels, or through any
  fetchable side state (P13, P14).
- `const char *jmap_strerror(jmap_status code)` returns a static,
  never-freed description of the code. It reads no state of any kind
  and is callable before `jmap_init` (SQLite's `sqlite3_errstr`
  analogue).
- `const char *jmap_errmsg(const jmap_client *client)` returns the
  bounded diagnostic `message()` of the most recent error on *that
  handle* — `sqlite3_errmsg` semantics: the pointer is owned by the
  handle, valid until the next fallible call on the same handle or
  `jmap_client_free`, whichever comes first. A12's stable `kind`
  discriminator and bounded `message()` projection exist precisely so
  this function is total and allocation-predictable.
- **Failure before a handle exists** (e.g. `jmap_client_new` rejecting
  its arguments) reports through the returned `jmap_status` alone;
  `jmap_strerror` supplies the human-readable form. This is the one
  place diagnostics are code-granular rather than message-granular —
  the trade accepted with the per-handle model.
- **Why not thread-local.** `int jmap_last_error()` is OpenSSL's
  `ERR_get_error` — the anti-pattern P14 cites by name, with a
  documented history of cross-contamination bugs in every binding
  ecosystem that consumed it. Per-handle state has no such failure
  mode here because handles are thread-confined by contract (P24):
  the state and its reader are on the same thread by construction.
- **Defects stay fatal, so the defect surface must be empty.** The
  library compiles with `--panics:on`: any `Defect` is `rawQuit(1)` —
  no unwinding, no C error return. The existing
  `{.push raises: [].}` walls plus the Tier-1 macro tests from
  `docs/TODO/macro-tests-ffi.md` (assert/doAssert ban, raw-index
  audit) are part of the L5 work: a C ABI whose host process can be
  killed by a library assertion is not shippable.

## 2. Handles and lifecycle

**Rule.** Opaque pointers only; create/free pairs; no init ritual
beyond one process-wide call.

- The v1 pointer taxonomy has three tiers, every type opaque (P8) and
  every one forward-declared in the header
  (`typedef struct jmap_client jmap_client;`) with the struct never
  defined:
  1. **Owning context handles** — `jmap_client*` and `jmap_transport*`,
     the only two long-lived contexts (P9). These carry state (session,
     transport, error slot) and are what P9's "two context types"
     means.
  2. **A transient spec handle** — `jmap_query*` (§5): caller-built,
     caller-freed, no state beyond the options set on it.
  3. **Result objects and non-owning views** — `jmap_mailboxes*`,
     `jmap_emails*` (freed by their own `_free`, §3) and the borrows
     they hand out (`jmap_mailbox*`, …), which are never freed by the
     caller.
- On the Nim side handles are minted with `create(T)` (untracked by
  ARC) and released with `` `=destroy`(p[]) `` followed by `dealloc` —
  never `new`/`GC_ref` (rules file, unchanged). The `T` here is an
  **L5-owned wrapper object**, not an L4 type: `JmapClient` is
  `ref JmapClientObj` with a module-private object and private fields
  (`internal/client.nim`), so `create(JmapClientObj)` is not reachable
  from `src/jmap_client.nim`. The C `jmap_client` is therefore a
  wrapper struct minted with `create(JmapClientHandle)` that *holds*
  the L4 `JmapClient` ref plus the handle's error slot (§1); its
  `=destroy` drops the ref — which closes the transport through
  `TransportObj`'s destructor — before `dealloc`. `jmap_transport` and
  the result objects follow the same wrapper shape. This is also where
  §1's per-handle diagnostic physically lives.
- `jmap_status jmap_client_new(const char *session_url,
  const char *username, const char *password, jmap_transport *transport,
  jmap_client **out)` — mirrors the Nim `connect` one-shot's
  three-string shape, with `transport == NULL` selecting the built-in
  `std/httpclient` transport and a non-NULL `transport` mirroring the
  transport-carrying `connect`. C has neither overloading nor default
  arguments (P3), so the selector is an explicit NULL rather than a
  second `jmap_client_new_with_transport` entry point: one constructor
  keeps connection configuration on one surface (P17) and avoids the
  `sqlite3_open`/`sqlite3_open_v2` split. On failure `*out` is
  untouched and the status is the diagnosis.
- `void jmap_client_free(jmap_client *client)` — idempotent on NULL,
  runs `=destroy` (which closes the transport via its `CloseProc`)
  then deallocates. Every `_new`/`_free` pair is named so ownership is
  in the signature (P12).
- `jmap_status jmap_init(void)` / `void jmap_cleanup(void)` — wrap
  NimMain and runtime teardown once per process. The call is
  load-bearing because the library is built with `--app:lib --noMain`
  (`justfile`), which suppresses the `__attribute__((constructor))`
  NimMain call Nim would otherwise emit for a POSIX shared library:
  without `jmap_init` the runtime's globals are never initialised. No
  thread-local setup, no flags argument, no configuration (P10): a
  consumer that forgets `jmap_init` gets `JMAP_E_MISUSE` from the
  first call that needs the runtime, not undefined behaviour. That
  detection costs one process-wide latch — the single carve-out from
  §7's no-global-state rule, stated there.
- All pointer arguments are validated (NULL checks, then
  `JMAP_E_MISUSE`) before any dereference — defects are fatal under
  `--panics:on`, so validation is the only acceptable response to a
  bad pointer the library can detect.

## 3. Memory ownership

**Rule.** The library owns what its read accessors return; the caller
owns what it passed in; transfer only ever happens through `_new` /
`_free` pairs.

- String getters return `const char*` (UTF-8, NUL-terminated) owned by
  the queried object, valid until that object is freed. No read
  accessor allocates into caller-freed memory; no read accessor
  returns memory the caller must free. The header documents the
  invalidation window on every accessor whose window is narrower than
  the owning handle's lifetime (`jmap_errmsg` is the canonical case).
- Caller-supplied strings are copied on entry; the library never
  retains a pointer into caller memory past the call (the transport
  and debug callbacks' `userdata` pointer is the deliberate exception:
  threaded back unchanged, never dereferenced by the library — P11).
- Result/collection objects returned by operations (`jmap_mailboxes*`,
  `jmap_emails*`, …) are library-allocated and released by their own
  `jmap_*_free`. Views handed out by those objects (an element, a
  field string) are borrows against them — freeing the result
  invalidates every view it produced. This is the SQLite
  statement/column contract, stated once in the header preamble and
  repeated nowhere.

## 4. Reading data: opaque views and per-field getters

**Rule.** No exposed structs (P8); no JSON passthrough (P19); columns,
not copies.

- **Every account-scoped operation names its account.** The Nim
  one-shots (`getMailboxes`, `getEmails`, `getThreads`,
  `getIdentities`, `queryEmails`, `sendPlainText`) all take a mandatory
  `accountId: AccountId` second parameter, and the C ABI wraps them
  without inventing an implicit default: the account travels as
  `const char *account_id` on every operation, and NULL is
  `JMAP_E_MISUSE`, not "guess the primary". Multi-account consumers are
  a supported case — one session can carry several accounts, and A6's
  `BuilderId` rationale names multi-account scenarios explicitly — so
  the selector cannot be process- or client-global.
- The session's account information is read through its own accessors,
  so the common single-account consumer writes one extra line, not a
  session parse:
  `jmap_status jmap_client_primary_account(const jmap_client *c,
  const char **out)` (the RFC 8621 mail primary account from
  `primaryAccounts`, `JMAP_E_SESSION` when the session designates
  none), plus `size_t jmap_client_account_count(const jmap_client *c)`
  and `const char *jmap_client_account_at(const jmap_client *c,
  size_t i)` for enumeration. All three return borrows owned by the
  client handle, valid until `jmap_client_free`.
- Each operation returns an opaque result handle via out-parameter:
  `jmap_status jmap_get_mailboxes(jmap_client *c,
  const char *account_id, jmap_mailboxes **out)`.
- Collections use count + indexed borrow (FFI skill convention):
  `size_t jmap_mailboxes_count(const jmap_mailboxes *r)` and
  `const jmap_mailbox *jmap_mailboxes_at(const jmap_mailboxes *r,
  size_t i)` (NULL when out of range — never a defect).
- Fields are per-field getters on the view:
  `const char *jmap_mailbox_name(const jmap_mailbox *mb)`,
  `uint32_t jmap_mailbox_unread(const jmap_mailbox *mb)`, etc.
  `Opt[T]` fields project as NULL (pointer-shaped fields) or a
  `bool jmap_x_has_y(...)` / `jmap_x_y(...)` pair (value-shaped
  fields). Enums project as C enums with locked ordinals; the
  forward-compat arms (e.g. an unrecognised mailbox role) project as
  the `_UNKNOWN` ordinal plus a raw-identifier string getter — the
  same lossless posture the Nim read model takes.
- The set of getters v1 ships is derived from what the C bench
  (§8) actually needs plus the fields the Nim CLI bench consumed —
  the P29 discipline: surface follows demonstrated consumer need, and
  grows additively.

## 5. Query options: one tagged-option surface

**Rule.** Extensible option-setting goes through one tagged enum, not
a proliferation of per-option entry points (P20; D10's original
inventory).

The easy path's only structured input is the email query. v1 projects
it as an opaque query-spec handle with a `setopt`-shaped surface:

```c
jmap_status jmap_query_new(jmap_query **out);
jmap_status jmap_query_set(jmap_query *q, jmap_query_opt opt, ...);
  /* JMAP_Q_IN_MAILBOX  (const char*)
     JMAP_Q_TEXT        (const char*)
     JMAP_Q_LIMIT       (uint32_t)
     JMAP_Q_READ_STATE  (jmap_read_state ordinal: JMAP_READ_ANY /
                         JMAP_READ_UNREAD / JMAP_READ_READ)
     JMAP_Q_SORT        (jmap_sort ordinal)
     ... additive */
void jmap_query_free(jmap_query *q);
jmap_status jmap_query_emails(jmap_client *c, const char *account_id,
                              const jmap_query *q, jmap_emails **out);
```

- `jmap_query_new` takes the same status-plus-out-parameter shape as
  every other `_new` (§1, P13, P15): allocation failure is a status,
  never a bare NULL return.
- Every value-shaped option takes a named ordinal, never a boolean
  carried as an `int` and never OR-ed bits (P18): the read-state
  filter is `JMAP_Q_READ_STATE` over a three-arm enum, which also
  leaves room for the states a boolean cannot name.
- The variadic value slot follows libcurl's discipline: each option
  documents its exact expected type in the header; the library
  validates what it can and answers `JMAP_E_MISUSE` for detectable
  misuse. This is the one place compile-time type safety is traded for
  additive extensibility — the same trade libcurl made, made once,
  quarantined to options (P20's application text).
- Internally an option set lowers onto the typed Nim
  `EmailFilterCondition`/`QueryParams` — the C surface never touches
  JSON (P19).

## 6. Callbacks and transport

**Rule.** Every callback is a per-handle registration carrying a
`userdata` pointer the library threads back unchanged (P11). No
link-time hooks, no registration globals.

- `jmap_set_debug_callback(jmap_client *c, jmap_debug_fn fn,
  void *userdata)` — the C projection of A31's `setDebugCallback`;
  `fn == NULL` detaches (libcurl `CURLOPT_DEBUGFUNCTION` shape).
- `jmap_status jmap_transport_new(jmap_send_fn send, jmap_close_fn close,
  void *userdata, jmap_transport **out)` and
  `void jmap_transport_free(jmap_transport *t)` — bring-your-own-HTTP,
  mirroring A19's closure-vtable `Transport` directly; a consumer
  integrating via libcurl is the first-class use case. Passing NULL as
  `jmap_client_new`'s `transport` selects the built-in
  `std/httpclient` transport instead (§2 — C has no default
  arguments, so the selector is explicit).
- **Transport ownership.** The Nim `Transport` is a refcounted `ref`
  whose `=destroy` fires the user's `close` exactly once, on the last
  drop (`internal/transport.nim`). The C rule follows it literally:
  `jmap_transport_new` gives the caller one reference; attaching it to
  a client takes a second; `jmap_client_free` drops the client's;
  `jmap_transport_free` drops the caller's; `close` fires on whichever
  goes last, once. So a transport that is created and never attached
  is released by `jmap_transport_free` alone, and a consumer that
  hands its transport to a client may free its own handle immediately
  after. One transport backs at most one client — the Nim type
  documents the same restriction — and a second attach is
  `JMAP_E_MISUSE`. In the common case (attach, then let
  `jmap_client_free` do the work) freeing the client remains the only
  teardown call the consumer makes.
- Callback typedefs carry `{.cdecl.}` on the Nim side and are
  documented as must-not-throw; a callback that fails signals failure
  through its return value (the send callback returns a
  transport-error code), never by unwinding through the library.

## 7. Threading and global state

- The header states P24 verbatim: **a handle is confined to one thread
  at a time; hand a handle to another thread by ceasing to use it on
  the old one.** Per-handle error state is race-free by this contract.
- The library reads no environment variables, holds no module-level
  mutable state beyond the one latch carved out below, and has no
  cross-handle shared caches (P10). Two
  independent `jmap_client` handles in one process never observe each
  other — the c-client failure this project exists not to repeat.
- **One carve-out, named here so it cannot spread:** a single
  process-wide initialisation latch, written once by `jmap_init` and
  read to answer `JMAP_E_MISUSE` when a consumer skips it (§2). It
  carries no configuration, no defaults, no caches, and no per-handle
  data; handles cannot observe it and cannot be influenced by it. It
  is the price of `--noMain`, not a foothold for global state, and
  `jmap_init` still takes no arguments (P10, P17).

## 8. Scope, sequencing, and the consumer bench

The v1 C surface is the easy path, complete for an email client:

| Capability | C entry point | Nim substrate |
|---|---|---|
| Connect + session | `jmap_client_new` | `connect` one-shot |
| List mailboxes | `jmap_get_mailboxes` | `getMailboxes` |
| Query email | `jmap_query_emails` | `queryEmails` |
| Read email (bodies) | `jmap_get_emails` | `getEmails` + body readers |
| Threads / identities / vacation | `jmap_get_threads` / … | one-shots |
| Send plain text | `jmap_send_plain_text` | `sendPlainText` |
| Flag / move / destroy | `jmap_mark_read` / `jmap_move_emails` / … | **C15 write one-shot (prerequisite PR)** |
| Incremental sync | `jmap_sync_emails` | **Email/changes sync one-shot — no ledger item yet (prerequisite PR opens one)** |

- **Prerequisite Nim PR:** two lifts, on the same `JmapResult`
  easy-path contract as the existing one-shots.
  1. **C15** (Email/set write one-shot: mark read/unread, move,
     destroy) — the ledger item already exists and this PR closes it.
  2. **An Email/changes sync one-shot** — *no ledger item covers
     this*. C17 is the `/updated` back-reference combinator and C21 is
     the per-type current-state accessor; both are components the sync
     one-shot has to fold (bootstrap cursor from C21, then
     changes-to-get over `/updated` from C17), neither is the one-shot
     itself. The prerequisite PR opens the missing item rather than
     retrofitting the work onto C17 or C21.
  The C ABI wraps one-shots only; it never re-implements protocol
  logic.
- **Reserved, not implemented:** the builder→send→extract pipeline as
  a future additive C layer (its handle names and the `BuilderId`
  cookie strategy — A6's phantom-token analogue — are reserved here so
  nothing in v1 collides with it); Push (RFC 8620 §7), WebSocket
  (RFC 8887), Blob up/download — all deferred, all additive when they
  come (P20, P23).
- **The C bench** (`examples/jmap-c-cli/`): a small, plain-C program
  driving the full loop (list, query, read, send, flag, move, sync)
  against the same live servers as the Nim bench. P29 applied to the
  FFI: every awkward call site is a bug against this design, and the
  wrap-rate question — "would a C developer use jmap-client directly,
  or wrap it?" — is answered by this program before v1 freezes (P7).

## 9. Versioning

- `include/jmap_client.h` carries `JMAP_CLIENT_VERSION_MAJOR/MINOR/
  PATCH` macros and `const char *jmap_version(void)` (libcurl shape).
  This lifts the C-side half of parked ledger item C6; the Nim-side
  version constant remains parked with C6 itself.
- The header is the ABI contract: symbols are added at the end,
  ordinals never reused, nothing removed after v1 (P1). SemVer policy
  documents (D1/D1.5) remain deferred; the header's own comment block
  states the additive-only rule until they land.

## 10. The header and its gates

- **Hand-curated `include/jmap_client.h`** — the single public header,
  written and reviewed like the API surface it is (libcurl/SQLite
  practice). Generated headers are build artefacts, not contracts.
- **Consistency gate:** a CI lint (H16-style) that compiles the header
  against the built library and cross-checks the exported symbol set
  (`{.exportc.}` inventory ↔ header declarations, both directions), so
  the header can neither drift from the exports nor advertise symbols
  that do not exist. The header itself is snapshot-frozen alongside
  the existing wire contracts (P1, P2).
- Exports live in `src/jmap_client.nim` only (A10); the module keeps
  its re-export-hub role for Nim consumers, and its L5 section carries
  `{.push raises: [].}` with the four mandatory pragmas per export
  (rules file, unchanged).

## 11. Testing

- **C compliance tests**: plain-C programs compiled against the real
  header and linked against the built library, exercising lifecycle
  (double-free, use-after-free under ASan in CI where available),
  error paths (every `JMAP_E_*` reachable and correctly reported via
  `jmap_errmsg`), borrow invalidation, and NULL-argument misuse.
  These extend the existing `tffi_panic_surface` direction: the
  process must never die on any input a C caller can construct.
- **The bench builds in CI** and runs in the live-integration lane
  against Stalwart/James/Cyrus alongside the Nim shards.
- **Panic-surface macro tests** (Tier 1 of `macro-tests-ffi.md`) land
  with L5: assert/doAssert ban and raw-index audit over `src/`.

## 12. Principle-by-principle map

| Principle | C-ABI manifestation |
|---|---|
| P1 lock-then-add | Header frozen at v1; additive symbols/ordinals only |
| P2 tests buy stability | C compliance tests + header snapshot + bench in CI |
| P3 overloads over suffixes | C has neither: new defaulted behaviour = new option ordinal, never `_v2` |
| P4 scope | ABI wraps one-shots; no protocol logic in L5 |
| P5 single layer | One header, one easy-path surface; builder reserved, not parallel |
| P6 easy path first-class | The ABI *is* the easy path; core stays Nim-only until additively projected |
| P7 wrap rate | The C bench answers it pre-freeze |
| P8 opaque handles | All types opaque; structs never defined in the header |
| P9 two context types | Two owning contexts (`jmap_client`, `jmap_transport`); one transient spec (`jmap_query`); result objects and views (§2 taxonomy) — all opaque |
| P10 no global state | `jmap_init` takes nothing; no env reads; state on handles; one init latch, carved out in §7 |
| P11 per-handle callbacks | debug + transport callbacks with threaded userdata |
| P12 ownership in types | `_new`/`_free` pairs; `const` borrows; documented windows |
| P13 one error rail | `jmap_status` everywhere; no NULL-as-error, no sentinels |
| P14 no TLS errors | Per-handle `jmap_errmsg`; static `jmap_strerror`; no `jmap_last_error()` |
| P15 smart constructors | `_new` functions validate and return status; no partial construction reachable |
| P16 preconditions in types | Opacity forces construction through `_new`; misuse detected → `JMAP_E_MISUSE` |
| P17 one config surface | Connection config enters through `jmap_client_new` params only |
| P18 no flag soup | Options are tagged enum ordinals with typed values, not OR-ed bits |
| P19 schema-driven | C never sees JSON; options lower onto typed Nim filters |
| P20 additive variants | New capability = new ordinal/getter, not parallel entry points |
| P21 lifecycle types | v1: `_new`→use→`_free`; builder lifecycle reserved for the future layer |
| P22 sync first | v1 is blocking easy-path only — the libcurl-easy analogue |
| P23 async separate | Push/WS reserved as future distinct types; nothing retrofits onto `jmap_client` |
| P24 threading invariant | Handle confinement stated in the header; error state rides it |
| P25 licence | Header carries the same SPDX/BSD-2-Clause header as source |
| P26 standard build | The `.so`/header ship from the existing `just build`; no per-OS branching |
| P27 succession docs | This document; the header's preamble is consumer-facing |
| P28 long-form guide | Deferred with D9; header preamble carries the minimum orientation |
| P29 consumer bench | `examples/jmap-c-cli/` before v1 freezes |

## 13. Anti-patterns restated for L5

- No `jmap_last_error()`; no `{.threadvar.}` error state; no error
  queues (P14).
- No exposed struct layouts; no "fast path" raw structs alongside the
  getters (P5, P8).
- No `jmap_set_default_*()` process-level configuration (P10).
- No boolean parameter where an enum names the alternatives; no OR-ed
  flag ints (P18).
- No `char *json` parameters or return values (P19).
- No init flags, no `jmap_init_ex(flags)` — if initialisation ever
  needs configuration, that is a design failure to redesign, not
  parameterise (P17).
- No silent truncation: any buffer-limited operation reports required
  size or fails loudly.

## Verification

- At implementation review: PRs cite this document's sections the way
  they cite P-numbers today.
- The rules file `.claude/rules/nim-ffi-boundary.md` and the
  `nim-ffi-boundary` skill are rewritten in the same change that lands
  this note — one decision, three artefacts, zero contradictions
  (user decision 2026-08-04 recorded on ledger item D10).
- At v1 freeze: the header snapshot, the export-consistency lint, the
  C compliance suite, and the bench are all green in CI, and every
  section above either holds or carries a dated amendment explaining
  why it was consciously traded off.
