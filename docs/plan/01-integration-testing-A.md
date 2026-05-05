# Integration Testing Plan — Phase A: Foundation

## Status

| Layer | State |
|---|---|
| **Phase 0 — Orchestration** | Done |
| **Phase 1 — Foundational live tests** | Done — 6 tests (1 session discovery + 5 method-coverage) running against every configured target |

Phase A delivers the orchestration layer and the six foundational live
tests that anchor every later phase. Phases B–L (separate docs)
expand coverage to additional method surfaces, wire-format edge
cases, and second/third reference servers; this doc describes the
foundation that they build on.

## Context

The project ships a substantial unit / serde / property / compliance
test corpus that validates the library against itself. Unit tests
exercise pure functions. Serde tests round-trip JSON through internally
constructed types. Property tests fuzz parsers against their own
output. Compliance tests feed RFC-quoted example JSON into parsers and
inspect the resulting values.

None of that establishes what the library does against a real JMAP
server. Phase A bridges that gap.

## Strategy

*Stop writing tests. Start running what you have.*

Two layers of untested code stack on top of one another: the JMAP
server orchestration (devcontainer compose service, seed scripts,
auth wiring in `client.nim`) and the JMAP client library itself.
Writing a live test for `Mailbox/get` before validating the
orchestration layer means every failure is ambiguous — is the bug
in the transport, the auth header, the JSON shape the server emits,
or the client's parser?

Validate the layers bottom-up. When step N fails, steps 1..N-1 have
been proven, so the bug is isolated.

## Phase 0 — Orchestration

### Step 1: Boot a JMAP server

Three reference servers are configured in
`.devcontainer/docker-compose.yml`, each behind a separate compose
profile so per-server bring-up does not pull the others:

| Server | Image / source | HTTP port | Profile |
|---|---|---|---|
| Stalwart 0.15.5 | `stalwartlabs/stalwart:v0.15` | 8080 | `stalwart` |
| Apache James 3.9 | derivative of `apache/james:memory-3.9.0` (`.devcontainer/james-conf/`) | 8001 | `james` |
| Cyrus IMAP 3.12.2 | `ghcr.io/cyrusimap/cyrus-docker-test-server` (digest-pinned) | 9080 | `cyrus` |

`just <server>-up` brings up exactly one server; `just jmap-up`
composes all three. `just <server>-down` / `<server>-reset` /
`<server>-status` / `<server>-logs` complete the per-server recipe
set, with `jmap-down` / `jmap-reset` / `jmap-status` / `jmap-logs`
operating across every configured profile.

Each `seed-<server>.sh` script under `.devcontainer/scripts/`:

- Polls the server until ready.
- Provisions Alice and Bob (`alice@example.com` / `alice123`,
  `bob@example.com` / `bob123`) via the server's admin API.
- Writes `/tmp/<server>-env.sh` exporting the four
  `JMAP_TEST_<SERVER>_*` env vars consumed by `mconfig.nim`:
  `_SESSION_URL`, `_AUTH_SCHEME`, `_ALICE_TOKEN`, `_BOB_TOKEN`.
  Stalwart additionally exports `_ADMIN_BASIC` (consumed by
  `mlive.awaitSmtpQueueDrain`).

Auth schemes vary across the three servers; `authScheme` in
`initJmapClient` substitutes the right header prefix:

- **Stalwart** — HTTP Basic, base64(`name:secret`). The internal
  directory matches the username against the principal's `name`
  field, not its `emails[]`, so `alice:alice123` works,
  `alice@example.com:alice123` does not.
- **James** — HTTP Basic, base64(`email:secret`). James enables
  `enableVirtualHosting=true` and matches the full email address.
- **Cyrus** — HTTP Basic, base64(`username:any`). The Cyrus test
  image accepts any password for any provisioned user.

**Stalwart-specific seed-time setup.** Stalwart's seed script does
three additional steps that are not relevant to James or Cyrus
(neither has equivalent surfaces):

1. **Roles.** `POST /api/principal` with `{"type":"individual",
   "name":"alice", …}` succeeds with HTTP 200 but the resulting
   principal carries zero JMAP-method permissions; the seed body
   includes `"roles":["user"]` per Stalwart's role model
   (`stalw.art/docs/auth/authorization/roles`).
2. **SMTP rate limiters.** Stalwart 0.15.5 ships
   `queue.limiter.inbound.sender` enabled at 25 messages/hour per
   `(sender_domain, rcpt)` and `queue.limiter.inbound.ip` at 5/sec
   per remote IP. The 26th alice→bob submission would defer with
   SMTP 452, leaving the corresponding `EmailSubmission` stuck at
   `pending` indefinitely and breaking sequential test runs. The
   seed disables both. The dev container topology (private Docker
   network, two test users) has no abuse vector.
3. **JMAP-level smoke check.** The seed script issues a real
   alice→bob submission via the JMAP API, polls
   `EmailSubmission/get` until `undoStatus == final`, then drains
   the outgoing SMTP queue. The check fails fast (non-zero exit) on
   HTTP error, set-error, JMAP timeout, or queue-drain timeout.
   Future Stalwart upgrades that alter SMTP listener defaults,
   `route.local`, or the submission capability trip the gate before
   any test runs.

### Step 2: Verify session discovery

`tests/integration/live/tsession_discovery_live.nim` runs
`client.fetchSession()` against every configured target, asserting:

- `session.accounts.len > 0`
- `session.apiUrl.len > 0`

The test wraps its body in `forEachLiveTarget(target):` from
`mconfig.nim`, so a single testament invocation iterates every
configured target in enum order (Stalwart → James → Cyrus).
Failures attribute to a specific target via the `[<target>]`
suffix injected by `mlive.assertOn`.

Once Step 2 is green, the foundation is real: HTTP keep-alive and
connection reuse work; HTTP Basic auth is accepted across every
target's configured scheme; the `authScheme` parameter correctly
substitutes the right header prefix; each server's session JSON
satisfies the shape `Session.fromJson` expects; `UriTemplate`
parsing succeeds for the actual `downloadUrl` / `uploadUrl` /
`eventSourceUrl` values; and `primaryAccounts` is populated across
the RFC 8620 / 8621 capability set plus any server-specific
extensions.

## Test scaffolding

### `tests/integration/live/mconfig.nim`

Pure configuration module. Defines the `LiveTargetKind` enum
(`ltkStalwart`, `ltkJames`, `ltkCyrus`) and the `LiveTestTarget`
record (`kind`, `sessionUrl`, `authScheme`, `aliceToken`,
`bobToken`).

`loadLiveTestTargets()` reads each `JMAP_TEST_<SERVER>_*` env
quartet and returns every configured target, in enum order. It
errs only when no target is configured.

`forEachLiveTarget(target):` is the iteration template every live
test wraps its body in. When no env vars are set, the body is a
no-op so the file still joins testament's megatest cleanly under
`just test-full`.

### `tests/integration/live/mlive.nim`

Helper module for shared server-interaction recipes that would
otherwise be inlined verbatim across multiple test files.
Phase A's six tests use:

- `resolveMailAccountId(session)` /
  `resolveSubmissionAccountId(session)` — extract primary account
  ids from `session.primaryAccounts` for the
  `urn:ietf:params:jmap:mail` and `urn:ietf:params:jmap:submission`
  URNs respectively.
- `resolveInboxId(client, mailAccountId)` — `Mailbox/get` →
  return the id of the mailbox carrying `role == roleInbox`.
- `seedSimpleEmail(client, mailAccountId, inbox, subject,
  creationLabel)` — `Email/set create` for a minimal text/plain
  message addressed alice→alice, filed in `inbox`. Returns the
  server-assigned `EmailId`.
- `assertOn(target, cond, msg)` — assertion template that
  suffixes `[<target>]` to every message so test failures from a
  single `forEachLiveTarget` iteration attribute to a specific
  server.
- `assertSuccessOrTypedError(target, extract, allowedErrors):
  <success-body>` — asserts on client-library behaviour uniformly
  across targets. When the server implements the surface, the body
  runs against the parsed result (bound as `success`); when the
  server returns a typed JMAP error, the error type must be in
  `allowedErrors`. Both arms are positive client-library contract
  assertions.

The module also exposes seeding helpers for richer MIME shapes
(multipart/alternative, multipart/mixed, message/rfc822 forwards),
threading helpers, EmailSubmission corpus helpers, polling
helpers, and a Stalwart-only SMTP-queue-drain barrier
(`awaitSmtpQueueDrain`). These belong to Phases B–L and are out of
scope for this doc.

### `tests/integration/live/mcapture.nim`

Optional wire-fixture capture. When `JMAP_TEST_CAPTURE=1`,
`captureIfRequested(client, "<name>-<target>")` writes
`client.lastRawResponseBody` to
`tests/testdata/captured/<name>-<target>.json`. Existing fixtures
are preserved unless `JMAP_TEST_CAPTURE_FORCE=1` is set —
committed fixtures are the source of truth.

`just capture-fixtures` runs `JMAP_TEST_CAPTURE=1 testament pat
"tests/integration/live/*_live.nim"` so a single invocation
captures fixtures from every configured target.

Captured fixtures feed the always-on parser-only replay tests
under `tests/serde/captured/`. The `tcaptured_round_trip_integrity`
meta-test asserts every committed `<base>-<server>.json`
round-trips through `fromJson` / `toJson` without raising.

## Phase 1 — Five foundational live tests

Each test lives under `tests/integration/live/` and follows this
shape:

1. Import `./mconfig`, `./mlive`, and (if capturing)
   `./mcapture`.
2. Wrap the body in `block <name>:` + `forEachLiveTarget(target):`.
3. Init `JmapClient` via `initJmapClient(target.sessionUrl,
   target.aliceToken, authScheme = target.authScheme)`.
4. Issue requests; assert via `assertOn target, …` and
   `assertSuccessOrTypedError target, …` for typed-error sites.
5. `client.close()`.

Tests use `block <name>:` + `doAssert` (per
`docs/design/12-mail-G2-design.md` §8.1). `std/unittest`'s `suite`
/ `test` templates trip `warningAsError:BareExcept`
(`config.nims`).

All foundational tests are listed in `tests/testament_skip.txt`,
so `just test` stays deterministic; they run via
`just test-integration` after `just jmap-up` (or a per-server
variant). The runtime guard inside `forEachLiveTarget` keeps every
file joinable into testament's megatest under `just test-full`
even when no server is running — the body is a no-op when env vars
are absent.

### Step 3: `tcore_echo_live.nim`

Scope: the simplest possible JMAP method. Proves end-to-end
request / response envelope plumbing with zero mail semantics.

Body:

- Build `initRequestBuilder().addEcho(%*{"hello": true, "n": 42,
  …})`.
- Send and assert `Ok`.
- Extract the echo response and assert its arguments equal the
  request arguments.
- Assert `resp.sessionState` is non-empty.

What this proves:

- The request envelope (`using`, `methodCalls`, `createdIds`)
  serialises to what every configured server accepts.
- Invocation tuple `[name, args, callId]` round-trips.
- Pre-flight validation (`maxSizeRequest`, `maxCallsInRequest`)
  respects session limits.

### Step 4: `tmailbox_get_all_live.nim`

Scope: `Mailbox/get` with `ids: null`, fetching every mailbox in
Alice's account.

Body:

- Resolve mail account id via `resolveMailAccountId(session)`.
- `addGet[Mailbox](b, mailAccountId)` (no ids → all).
- Send and extract the typed `MailboxGetResponse`.
- Assert `gr.list.len >= 1`.
- Assert every mailbox has a non-empty `name`,
  `myRights.mayReadItems == true`, and at least one mailbox has
  `role == roleInbox`.

What this proves:

- `urn:ietf:params:jmap:mail` capability URI is auto-injected
  into `using`.
- Mailbox deserialisation handles each target's real output (role
  enum, `MailboxRights`, count fields).
- IANA role strings match the `MailboxRole` enum across every
  target.

### Step 5: `tidentity_get_live.nim`

Scope: `Identity/set` + `Identity/get` chained in one request,
proving the submission capability pipeline separately from the
mail pipeline. If Steps 3–4 pass and this one fails, the bug is
specific to the submission URI wiring, not the mail pipeline.

Body:

- Resolve submission account via
  `resolveSubmissionAccountId(session)`.
- `parseIdentityCreate(email = "alice@example.com", name =
  "Alice")` → `addIdentitySet(create = …)` →
  `addIdentityGet(...)`. Both invocations in one request.
- Send.
- Assert `Identity/set` succeeded *or* surfaced as
  `metUnknownMethod` (the typed-error arm of the Cat-B pattern).
- Assert `Identity/get` returns at least one identity. If
  `Identity/set` succeeded, assert one identity has `email ==
  "alice@example.com"`.

Wire-format quirks the test absorbs:

- **Cyrus has no `Identity/set`.** Identity is "read-only from
  config" (`imap/jmap_mail_submission.c:116-120`); Cyrus returns
  `metUnknownMethod`. Stalwart and James both implement it. The
  `assertSuccessOrTypedError` shape is the canonical Cat-B
  pattern.
- **Cyrus emits empty `email` for config-derived identities.**
  RFC 8621 §6.1 declares `email` as `String`; the parser handles
  both empty and populated values. The wire-shape parse is the
  universal client-library contract.
- **Domain choice: `example.com`.** Stalwart's identity validator
  rejects `.local` and `.test` (RFC 6761/6762 special-use TLDs)
  as "Invalid e-mail address." `example.com` (RFC 2606
  reserved-for-documentation) is accepted by every target.
- **`Identity/set`'s `created[cid]` is the bare `{"id":"<id>"}`
  partial** per RFC 8620 §5.3 (server-set subset). The library
  parses this via `IdentityCreatedItem`, mirroring
  `EmailCreatedItem`.

### Step 6: `temail_query_get_chain_live.nim`

Scope: two chained method calls via a result reference (RFC 8620
§3.7). The single most error-prone JMAP feature — the JSON
Pointer syntax must agree with every server's evaluator.

Prerequisite: Alice's inbox needs at least one message.

#### Options for seeding a message

| Path | Mechanism | Status |
|---|---|---|
| A | Stalwart admin-API mail injection (`/api/email`, `/api/message`, …) | **Rejected** — endpoints do not exist (return 404). |
| B | SMTP helper (Nim) | **Rejected** — Nim 2.2.8 has no `std/smtpclient`; adding a Nimble package violates the devcontainer-parity rule (every host-installed package must also be declared in `.devcontainer/`). |
| C | Use the library — `Email/set create` with an `EmailBlueprint` | **Selected** — no new dependencies, exercises the create path as a side benefit, works against every configured target. |

Path C funnels through `mlive.seedSimpleEmail`, so the boilerplate
lives in one place.

Body:

- Resolve mail account id and inbox id (mlive helpers).
- Seed one Email with subject containing the byte-disjoint
  discriminator token `chainquery6`. The token is a single
  contiguous unique string across every `*_live.nim` seed; the
  query filter pins the result set to this test's seeds even on
  an accumulated server instance.
- `pollEmailQueryIndexed` until the seed surfaces. Cyrus 3.12.2's
  Xapian rolling indexer settles asynchronously; Stalwart and
  James are unaffected.
- Build chained calls:
  1. `addEmailQuery(b, accountId, filter = subject contains
     "chainquery6", limit = 50)`.
  2. `addEmailGet(b, accountId, ids =
     queryHandle.idsRef(), properties = ["id", "subject", "from",
     "receivedAt"])`.
- Send the combined request. Assert query and get list lengths
  match; assert the seeded subject appears in the get list.
- Cleanup: `Email/set destroy` for the seed so re-runs stay
  bounded.

What this proves:

- Result-reference resolution: every target's JSON Pointer
  evaluator agrees with the library's `/ids` path.
- `EmailAddress[]` parsing works against MIME-encoded addresses.
- `Date` parsing for `receivedAt` handles each target's date
  format.
- Auto-injected capability URIs satisfy a multi-method request.

This is the first foundational test that touches each server's
mail store.

### Step 7: `temail_set_keywords_live.nim`

Scope: `Email/set` with `ifInState`, flipping `$seen` on a
seeded Email. Exercises both happy path and conflict path in one
test.

Body:

- Resolve inbox + seed a fresh Email via mlive helpers.
- Capture pre-update state via `Email/get`.
- **Happy path.** `Email/set` with matching `ifInState`,
  `update = {seedId: markRead()}`. Assert the update succeeded.
  Re-fetch via `Email/get` and assert `kwSeen in
  email.keywords.unsafeGet`.
- **Conflict path.** Same `Email/set` issued again with the
  now-stale `ifInState`. Assert via `assertSuccessOrTypedError(target,
  extract, {metStateMismatch}): discard success`.

The conflict path is Cat-B: RFC 8620 §5.3 mandates that
`ifInState` on `/set` MUST abort with a `stateMismatch` SetError
when the state has advanced. Stalwart 0.15.5 and Cyrus 3.12.2
enforce this (Cyrus at `imap/jmap_mail.c:13990-13996`); James 3.9
ignores `ifInState` and accepts the update unconditionally. The
success arm covers the no-gate case; the typed-error arm
exercises the client's `metStateMismatch` projection.

What this proves:

- `ifInState` state-guard happy path.
- `metStateMismatch` error projection through the L3 error rail
  (sad path, where the server enforces).
- `PatchObject` with a JSON Pointer targeting `keywords/$seen` is
  accepted by every target.
- Keyword canonicalisation: `$seen` round-trips as `$seen`, not
  `$Seen`.

After Step 7, every JMAP request shape (echo, get, query, set
with patch), every envelope feature (result references, state
guards), and both error rails (transport, method-level) have
been exercised end-to-end against every configured target.

## Predictable wire-format divergences

A catalogue of what live testing typically reveals. The
strict / lenient boundary in serde is the right place to fix
each — `fromJson` is lenient on receive, `toJson` is
RFC-canonical on send. The client absorbs server divergence so
mail-client application developers don't have to.

1. **Date normalisation (RFC 8620 §1.4).** Spec mandates
   `time-secfrac` omitted if zero; real servers emit fractional
   seconds anyway. `fromJson` is lenient on receive.
2. **Keyword case (RFC 8621 §4.1.1).** Lowercase on the wire,
   case-insensitive semantics. Equality checks against constants
   (`kwSeen`, `kwFlagged`) go through canonicalising parsers.
3. **Empty-vs-null.** `notFound: []` vs absent, `keywords: {}`
   vs `null`, `mailboxIds: {}` as an empty set. `Opt[T]` plus
   lenient `fromJson` handles both shapes.
4. **RFC 2047 encoded-word round-trip.** `EmailAddress.name`
   containing `=?UTF-8?Q?...?=` decodes on receive per RFC 8621
   §4.1.2.3.
5. **Capability URI auto-injection.** Builders in
   `src/jmap_client/builder.nim` deduplicate by design;
   entity-specific builders in `mail/mail_builders.nim` call the
   deduplicating path. `urn:ietf:params:jmap:core` is
   pre-declared per RFC 8620 §3.2.
6. **`Identity/set created[cid]` partial response (RFC 8620
   §5.3).** The bare `{"id":"<id>"}` server-set subset is parsed
   via `IdentityCreatedItem`, mirroring `EmailCreatedItem`.
7. **Optional informational capability fields (RFC 8621
   §1.3.1).** `maxSizeMailboxName` and `emailQuerySortOptions`
   are `Opt[T]` to absorb absent-from-capability cases (Cyrus
   omits both).
8. **`ifInState` enforcement (RFC 8620 §5.3).** Spec mandates
   `stateMismatch` on advance; James ignores. The
   `assertSuccessOrTypedError` Cat-B helper covers both.

## Success criteria

- [x] `just <server>-up` succeeds deterministically from a clean
  devcontainer for each of Stalwart, James, Cyrus.
- [x] `just test-integration` exits 0 with the six foundational
  tests (`tsession_discovery_live`, `tcore_echo_live`,
  `tmailbox_get_all_live`, `tidentity_get_live`,
  `temail_query_get_chain_live`, `temail_set_keywords_live`)
  passing against every configured target via
  `forEachLiveTarget`.
- [x] Every wire-format divergence discovered is root-caused at
  the `fromJson` layer, not papered over in tests.
- [x] The six tests run quickly enough not to dominate the
  integration suite's wall-clock; cumulative cost stays in the
  same order as a single `Email/set` round-trip per target.

## Operational test for every Phase A test design decision

> *"If a mail-client application developer linked this library and
> ran my test code against any RFC-conformant JMAP server, would
> the assertion be a valid client-library contract assertion?"*

Yes ⇒ test is well-formed. No ⇒ refactor with
`assertSuccessOrTypedError` so the assertion is on the client
library's behaviour, not on a specific server's quirks.

## Out of scope for Phase A

Explicitly deferred to later phases (B–L; see
`docs/plan/0[2-9]*.md`, `1[0-2]*.md`):

- Push notifications (RFC 8620 §7, EmailDelivery pseudo-type)
- Blob upload and download (RFC 8620 §6) — `UriTemplate`s parse
  but no convenience methods are exposed
- EmailSubmission end-to-end (Phases F–G)
- `Email/parse` round-trips for attached `message/rfc822` blobs
  (Phase D)
- Query pagination and `queryChanges` delta correctness (Phases
  E, H)
- Multi-account shared-access scenarios — the bob principal seed
  is laid in Phase A (every seed script provisions both alice and
  bob), but cross-account testing happens in Phase G
- Layer 5 C ABI (a separate plan entirely)
- Performance, concurrency, and resource exhaustion
