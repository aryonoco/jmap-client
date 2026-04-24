# Integration Testing Plan — Phase A

## Context

The project has been developed in isolation for over a month: roughly
17,000 lines of application code and 40,000 lines of test code. Every
existing test validates the library against itself. Unit tests exercise
pure functions. Serde tests round-trip JSON through internally
constructed types. Property tests fuzz parsers against their own
output. Compliance tests feed RFC-quoted example JSON into parsers and
inspect the resulting values.

None of this establishes what the library does against a real JMAP
server.

A Stalwart JMAP devcontainer service and a single session-discovery
smoke test were added in commit `9c0935b` on 2026-04-22. Neither has
been exercised since. `docker compose` tooling is available inside the
devcontainer (confirmed by `which docker`), but `/tmp/stalwart-env.sh`
does not exist — meaning `just stalwart-up` has never been run.

RFC 8620 (Core) and RFC 8621 (Mail) client-side coverage is
approximately 95% and 90% respectively. Push notifications (§7 of both
RFCs) and blob upload/download helpers are deferred. Layer 5 (C ABI) is
likewise deferred.

## Strategy

Stop writing tests. Start running what you have.

Two layers of untested code are stacked: the Stalwart orchestration
(`docker-compose.yml`, `seed-stalwart.sh`, the `authScheme` wiring in
`client.nim`) and the JMAP client library itself. Writing a live test
for `Mailbox/get` before validating the orchestration layer means every
failure is ambiguous — is the bug in the transport, the auth header,
the JSON shape Stalwart emits, or the client's parser?

Validate the layers bottom-up. When Step N fails, Steps 1..N-1 have
been proven, so the bug is isolated.

## Phase 0 — Validate the orchestration layer

### Step 1: Boot Stalwart

    just stalwart-up

Observable success:

- `docker compose up` pulls `stalwartlabs/stalwart:v0.15` and starts
  the container
- `seed-stalwart.sh` polling loop prints `Stalwart is ready (attempt N)`
- Three `curl` calls to `/api/principal` each print `HTTP 200` (or
  `HTTP 409` on a re-run — acceptable; the script suppresses via `|| true`)
- `/tmp/stalwart-env.sh` exists with four `export JMAP_TEST_*=...` lines
- The summary block prints the seeded credentials

Failure modes to expect:

1. **Admin creds wrong (`HTTP 401`).** Stalwart v0.15 typically requires
   the admin password to be set via `STALWART_ADMIN_PASSWORD` in
   `docker-compose.yml` or via a first-run bootstrap. The seed script
   hardcodes `admin:jmapdev`. If compose doesn't seed this, configure
   it in compose.
2. **Principal API schema mismatch (`HTTP 400`).** The JSON bodies in
   `seed-stalwart.sh` are guesses at v0.15's admin API. Consult
   Stalwart's `/api` docs for the running version.
3. **Health endpoint missing.** `GET /healthz/live` may not exist in
   v0.15. Substitute `GET /api/principal` with admin auth as a liveness
   probe.
4. **Compose network collision.** If a stale `jmap-net` exists,
   `docker network rm jmap-net` clears it.

Do not proceed to Step 2 until Step 1 is deterministic.

### Step 2: Run the existing live session-discovery test

    . /tmp/stalwart-env.sh
    just test-integration

Observable success:

- Testament builds and runs `tests/integration/live/tsession_discovery.nim`
- `loadLiveTestConfig` returns `Ok` (all four env vars present)
- `initJmapClient(sessionUrl, aliceToken, authScheme="Basic")` returns `Ok`
- `client.fetchSession()` returns `Ok` with a populated `Session`
- `session.accounts.len > 0` and `session.apiUrl.len > 0`
- The test exits 0

What this proves (first time over the wire):

- HTTP keep-alive and connection reuse work
- Basic auth with base64 `user@domain:password` is accepted by Stalwart
- The `authScheme` parameter added in commit `9c0935b` correctly
  substitutes `"Basic"` for the default `"Bearer"`
- Stalwart's Session JSON satisfies the shape `Session.fromJson` expects
- `UriTemplate` parsing succeeds for Stalwart's actual `downloadUrl`,
  `uploadUrl`, `eventSourceUrl` values

Failure modes to expect:

1. **Session URL path wrong (`404`).** The seed script sets
   `JMAP_TEST_SESSION_URL=http://stalwart:8080/jmap/session`. RFC 8620
   §2.2 suggests `/.well-known/jmap`. If 404, inspect Stalwart's JMAP
   docs and update the env var in the seed script.
2. **`authScheme="Basic"` not wired through (`401`).** Commit `9c0935b`'s
   change to `setBearerToken` is unexercised. A 401 response from a
   correct path means the header is being built incorrectly — verify
   `setBearerToken` reads the stored scheme instead of defaulting to
   `"Bearer"`.
3. **Session JSON rejects.** Stalwart may omit fields the strict parser
   expects, or emit fields with unexpected types (e.g.
   `primaryAccounts: null` instead of absent, `accountCapabilities: []`
   instead of `{}`). Fix at the `fromJson` layer per the Postel's-law
   convention in `.claude/rules/nim-conventions.md`.

Once Step 2 is green, the foundation is real.

## Phase 1 — Five foundational live tests

Each test lives under `tests/integration/live/` and follows the
`tsession_discovery.nim` idiom: load config, guard on `isOk`, execute a
`block`, `doAssert` the invariants. All tests are added to
`tests/testament_skip.txt` so `just test` stays deterministic.

Write them in order. Each builds on the wire-format discoveries of the
previous.

### Step 3: `tcore_echo_live.nim`

Scope: the simplest possible JMAP method. Proves end-to-end
request/response envelope plumbing with zero mail semantics.

Body:

- Fetch session via `client.fetchSession()`
- Build `initRequestBuilder().addEcho(%*{"hello": true, "n": 42})`
- Send via `client.send(builder)`
- Assert response is `Ok`
- Extract the echo response from `methodResponses[0]`
- Assert its arguments equal the request arguments

What this proves:

- Request envelope (`using`, `methodCalls`, `createdIds`) serialises to
  what Stalwart accepts
- Invocation tuple `[name, args, callId]` round-trips through Stalwart
- `Response.sessionState` is populated
- Pre-flight validation (`maxSizeRequest`, `maxCallsInRequest`) respects
  session limits

### Step 4: `tmailbox_get_all_live.nim`

Scope: `Mailbox/get` with `ids: null`, fetching every mailbox in
Alice's seeded account.

Body:

- Fetch session
- Extract Alice's mail account via
  `session.primaryAccounts["urn:ietf:params:jmap:mail"]`
- Build `addMailboxGet(accountId=alice, ids=Opt.none)`
- Send
- Extract the typed response via `resp.get(mailboxHandle)`
- Assert `list.len >= 1`
- Assert at least one mailbox has a non-null `role` equal to the inbox
  role
- For each mailbox, assert `myRights` is populated

What this proves:

- `urn:ietf:params:jmap:mail` capability URI is auto-included in `using`
- Mailbox deserialisation handles Stalwart's real output (role enum,
  `MailboxRights` shape, count fields)
- IANA role strings from Stalwart match the `MailboxRole` enum exactly

Most likely first real bug: a field-name mismatch or empty-vs-null
divergence in `myRights`.

### Step 5: `tidentity_get_live.nim`

Scope: `Identity/get`, proving the submission capability pipeline
separately from the mail pipeline.

Body:

- Fetch session
- Extract submission account via
  `session.primaryAccounts["urn:ietf:params:jmap:submission"]`
- Build `addIdentityGet(accountId, ids=Opt.none)`
- Send
- Assert `list.len >= 1`
- Assert one identity has `email == "alice@test.local"`
- Assert `mayDelete` is populated

What this proves:

- Submission capability URI is auto-included
- `EmailAddress` parsing works for the `email` field
- Identity boolean permission fields deserialise correctly

If Step 4 passes and Step 5 fails, the bug is specific to the
submission URI wiring, not the mail pipeline.

### Step 6: `temail_query_get_chain_live.nim`

Scope: two chained method calls via a result reference. The single
most error-prone JMAP feature — your JSON Pointer syntax must agree
with Stalwart's evaluator.

Prerequisite: Alice's inbox needs at least one message. Either seed
one via the admin API during `seed-stalwart.sh`, or have the test
deliver via SMTP first. Prefer the SMTP helper (~20 lines) over
extending the seed script.

Body:

- Fetch session, resolve Alice's mail account
- Build two chained calls:
  1. `addEmailQuery(accountId, filter=Opt.none, sort=Opt.none, limit=Opt.some(10u))`
  2. `addEmailGet(accountId, ids=Opt.some(queryHandle.idsRef()), properties=Opt.some(["id","subject","from","receivedAt"]))`
- Send the combined request
- Assert both responses are `Ok`
- Assert `Email/get` list length matches `Email/query` ids length
- Assert every email has non-null `id`, `from`, `subject`

What this proves:

- Result reference resolution: Stalwart's JSON Pointer evaluator agrees
  with your `/ids` path
- `EmailAddress[]` parsing works against real MIME-encoded addresses
- `Date` parsing for `receivedAt` handles Stalwart's date format
- Auto-injected capability URIs satisfy a multi-method request

This is the first test that touches Stalwart's actual mail store.

### Step 7: `temail_set_keywords_live.nim`

Scope: `Email/set` with `ifInState`, flipping `$seen` on an email.

Body:

- Run Step 6's query-then-get flow; capture the `Email/get` response's
  `state`
- Pick one email id; build `Email/set` with `ifInState=Opt.some(state)`
  and `update={emailId: PatchObject({"keywords/$seen": true})}`
- Send
- Assert `updated` contains the email id
- Build another `Email/get` for the same id; verify
  `keywords[$seen] == true`
- Build a second `Email/set` with the now-stale `ifInState`; verify
  it returns a `stateMismatch` method error

What this proves:

- `ifInState` state-guard happy path
- `stateMismatch` error projection surfaces through the `Result` error
  rail (sad path)
- `PatchObject` with a JSON Pointer targeting `keywords/$seen` is
  accepted by Stalwart
- Keyword canonicalisation: `$seen` round-trips as `$seen`, not
  `$Seen`

After Step 7: every JMAP request shape (echo, get, query, set with
patch), every envelope feature (result references, state guards), and
both error rails (transport, method-level) have been exercised
end-to-end.

## Predictable wire-format divergences

Catalogue of what live testing typically reveals. The strict/lenient
boundary in serde is the right place to fix each.

1. **Date normalisation (RFC 8620 §1.4).** Spec mandates `time-secfrac`
   omitted if zero; real servers emit fractional seconds anyway.
   `fromJson` must be lenient on receive.
2. **Keyword case (RFC 8621 §4.1.1).** Lowercase on the wire,
   case-insensitive semantics. Equality checks against constants
   (`kwSeen`, `kwFlagged`) must go through a canonicalising parser.
3. **Empty-vs-null.** `notFound: []` vs absent, `keywords: {}` vs
   `null`, `mailboxIds: {}` as an empty set. `Opt[T]` plus lenient
   `fromJson` handles both.
4. **RFC 2047 encoded-word round-trip.** `EmailAddress.name` containing
   `=?UTF-8?Q?...?=` must decode on receive per RFC 8621 §4.1.2.3.
5. **Capability URI auto-injection.** If `addMailboxGet` doesn't
   auto-inject `urn:ietf:params:jmap:mail`, Stalwart returns
   `unknownCapability`. Builders in `src/jmap_client/builder.nim`
   deduplicate by design — verify entity-specific builders in
   `mail/mail_builders.nim` call the deduplicating path.

## Success criteria

Phase A is complete when:

- `just stalwart-up` succeeds deterministically from a clean
  devcontainer
- `just test-integration` exits 0 with all six live tests (discovery +
  five new) passing
- Every wire-format divergence discovered has been root-caused and
  fixed at the `fromJson` layer, not papered over in the test
- The six tests run in under 30 seconds total (baseline for regression
  tracking)

## Out of scope for Phase A

Explicitly deferred to later plan phases:

- Push notifications (RFC 8620 §7, EmailDelivery pseudo-type)
- Blob upload and download (RFC 8620 §6) — templates parse but no
  convenience methods exposed
- EmailSubmission end-to-end (requires outbound SMTP routing)
- Email/parse round-trips for attached `message/rfc822` blobs
- Query pagination and `queryChanges` delta correctness (requires a
  larger seeded corpus)
- Multi-account shared-access scenarios (requires ACL setup between
  alice and bob)
- Layer 5 C ABI (a separate plan entirely)
- Performance, concurrency, and resource exhaustion

Phase B will expand coverage to EmailSubmission and blob operations
once Phase A establishes the foundation.
