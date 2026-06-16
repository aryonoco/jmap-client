<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# S3 — Complete the core: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`)
> syntax. Design spec: `docs/superpowers/specs/2026-06-16-s3-complete-the-core-design.md`.
> Campaign orientation: `docs/superpowers/plans/2026-06-15-CAMPAIGN-HANDOFF.md`.
> **Authority rule:** the RFC text in `docs/rfcs/` governs every protocol question;
> the design docs are fallible (memory `rfc-is-authoritative`).

**Goal:** Add the missing total readers / predicates / smart constructors on the
final S2 types so a consumer reads an `Email`, a `Mailbox`, and a `Session`, and
builds a plain-text send body, without `import std/tables`, a hand-walked case
object, or a hand-rolled capability preflight — clearing root cause R2.

**Architecture:** Pure additive L1 `func`/`iterator`s on existing entity modules
(`mail/email.nim`, `mail/mailbox.nim`, `mail/email_blueprint.nim`,
`types/framework.nim`) plus pure L3 preflight `func`s on `protocol/preflight.nim`.
No new modules, **no new types** — every signature uses an existing type. The S1
`requirePrimaryAccount` is left strict and unchanged; `require*` get their own
RFC-faithful soft resolution via a module-private helper.

**Tech Stack:** Nim, nim-results (`Result`/`Opt`/`valueOr`), testament
(`doAssert`-based via `mtestblock`/`massertions`), nph formatting, nimalyzer,
the compiler-oracle wire-contract snapshot.

---

## STATE / HANDOFF (update as each task lands)

- **Branch:** `api/s3-complete-the-core` (off `main`). Created.
- **Per-task gate:** `just build` (keeps `src/` green). Both full gates at the end
  (Task 8). Linux-kernel commits, the three trailers (see Conventions).
- **Status:** 🔄 IN PROGRESS.
  - [x] Task 1 — Email body readers (`bodyValue`, `leafTextParts`, `decodedTextBody`, `textBodies`) — case-insensitive text/plain match (RFC 2045 §5.1) folded in per review
  - **Last verified myself:** `nim c -r` test (exit 0), `just build`, `just fmt-check`, `just analyse` (hasdoc clean) all green.
  - [x] Task 2 — Mailbox role predicates (`isInbox`, `hasRole`) — + `mrOther` vendor-extension coverage per review
  - [x] Task 3 — `plainTextBody` send-body constructor — comment/docstring de-cross-referenced (no Pattern-8/S4 refs) per review
  - [x] Task 4 — `require*` capability preflight (RFC 8620 §2 verified by impl + independent reviewer) — + designated-primary-preference test; module docstring de-campaigned; `requirePrimaryAccount` unchanged
  - [x] Task 5 — `limit` query-window helper (no field/func ambiguity; both reviews ✅)
  - [x] Task 6 — Regenerate the public-API snapshot + `just ci` — +12 lines public-api.txt only (no type-shape change); full `just ci` GREEN
  - [x] Task 7 — Re-bench `examples/jmap-cli/`; update `AUDIT.md` + `docs/design/16` — 6 CLI files adopt S3 symbols; CLI builds + public-only + REUSE green (I verified). requireSubmission/requireVacation honestly not forced (CLI routes one shared mail account; documented as siblings)
  - [ ] Task 8 — Both full gates (`just ci`; `just clean && just jmap-reset && just test-full`)

## Conventions (every task)

- **Layers:** all S3 readers/predicates/constructors are L1 (`mail/*`, `types/framework`)
  or L3 (`protocol/preflight`) — `{.push raises: [], noSideEffect.}`, `func`/`iterator`
  only, `{.experimental: "strictCaseObjects".}` already present in each file.
- **strictCaseObjects:** read a variant field only inside a `case` that proves the
  discriminator (Rule 1 — `if` is NOT enough). Reading `EmailBodyPart.partId`
  requires `case part.isMultipart of false:`.
- **`.get()` on a `Result`** needs an adjacent invariant comment proving Ok
  (Pattern 8). Used once, in `plainTextBody`.
- **British-English** docstrings, explain *why*; **RFC-section refs only** in
  comments (no design-doc cross-refs). Every public `func` needs a docstring
  (nimalyzer `hasdoc`, fires in `just ci`).
- **Commit format** (Linux-kernel), end EVERY body with exactly:
  ```
  Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
  Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
  Assisted-by: Claude:claude-4.8-opus
  ```
- **Stage explicit paths**; never `git add -A`.
- New tests are testament files: `{.push raises: [].}`, `import` internal modules
  directly (tests are exempt from public-only), `testCase <name>:` from
  `mtestblock`, assertions from `massertions`. New `t*.nim` files auto-join the
  megatest.

## File structure

| File | Change | Responsibility |
|---|---|---|
| `src/jmap_client/internal/mail/email.nim` | modify | add `bodyValue`, `leafTextParts`, `decodedTextBody`, `textBodies` |
| `src/jmap_client/internal/mail/mailbox.nim` | modify | add `hasRole`, `isInbox` |
| `src/jmap_client/internal/mail/email_blueprint.nim` | modify | add `plainTextBody` |
| `src/jmap_client/internal/protocol/preflight.nim` | modify | add `usableAccount` (private) + `requireMail`/`requireSubmission`/`requireVacation` |
| `src/jmap_client/internal/types/framework.nim` | modify | add `limit` |
| `tests/unit/mail/temail_body_readers.nim` | create | Task 1 tests |
| `tests/unit/mail/tmailbox_role_predicates.nim` | create | Task 2 tests |
| `tests/unit/mail/tplain_text_body.nim` | create | Task 3 tests |
| `tests/unit/tpreflight.nim` | create | Task 4 tests |
| `tests/unit/tframework_limit.nim` | create | Task 5 tests |
| `tests/wire_contract/public-api.txt` | regenerate | Task 6 (`just freeze-api`) |
| `examples/jmap-cli/**`, `examples/jmap-cli/AUDIT.md`, `docs/design/16-…` | modify | Task 7 |

---

## Task 1: Email body readers — `bodyValue`, `leafTextParts`, `decodedTextBody`, `textBodies`

**Files:**
- Modify: `src/jmap_client/internal/mail/email.nim` (add after `isLeaf`, ~line 530, and `textBodies` near `EmailBodyFetchOptions` ~line 447)
- Create: `tests/unit/mail/temail_body_readers.nim`

Context (verified in source): `Email.bodyValues*: Table[PartId, EmailBodyValue]`;
`Email.textBody*: seq[EmailBodyPart]`; `EmailBodyPart` is a case object on
`isMultipart` (`of false:` carries `partId*: PartId`, `blobId*: BlobId`; shared
`contentType*: string`); `EmailBodyValue*` has `value*: string`,
`isEncodingProblem*: bool`, `isTruncated*: bool`; `EmailBodyFetchOptions*` has
`fetchBodyValues*: BodyValueScope` and `maxBodyValueBytes*: Opt[UnsignedInt]`;
`bvsText` = fetch text-body values. `email.nim` already imports `std/tables` and
`std/strutils`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/mail/temail_body_readers.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the S3 Email body readers: bodyValue, leafTextParts,
## decodedTextBody, and the textBodies fetch-options helper (RFC 8621 §4.1.4).

{.push raises: [].}

import std/tables

import jmap_client/internal/mail/email
import jmap_client/internal/mail/body
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/validation # re-exports nim-results (Opt/.get)

import ../../massertions
import ../../mtestblock

proc pid(s: string): PartId =
  parsePartIdFromServer(s).get()

proc textLeaf(contentType, partId: string): EmailBodyPart =
  ## A non-multipart leaf with the given content type and partId.
  EmailBodyPart(
    headers: @[],
    contentType: contentType,
    size: parseUnsignedInt(0).get(),
    isMultipart: false,
    partId: pid(partId),
    blobId: parseBlobId("b" & partId).get(),
  )

proc emailWith(
    textBody: seq[EmailBodyPart], values: seq[(PartId, EmailBodyValue)]
): Email =
  Email(textBody: textBody, bodyValues: values.toTable)

testCase bodyValuePresent:
  let p = pid("1")
  let e = emailWith(@[textLeaf("text/plain", "1")], @[(p, EmailBodyValue(value: "hello"))])
  assertSomeEq e.bodyValue(p), EmailBodyValue(value: "hello")

testCase bodyValueAbsentIsNone:
  let e = emailWith(
    @[textLeaf("text/plain", "1")], @[(pid("1"), EmailBodyValue(value: "hello"))]
  )
  assertNone e.bodyValue(pid("missing"))

testCase decodedTextBodyJoinsTextPlain:
  let e = emailWith(
    @[textLeaf("text/plain", "1"), textLeaf("text/plain", "2")],
    @[(pid("1"), EmailBodyValue(value: "foo")), (pid("2"), EmailBodyValue(value: "bar"))],
  )
  assertSomeEq e.decodedTextBody(), "foobar"

testCase decodedTextBodySkipsHtml:
  let e = emailWith(
    @[textLeaf("text/html", "1")], @[(pid("1"), EmailBodyValue(value: "<p>hi</p>"))]
  )
  assertNone e.decodedTextBody()

testCase decodedTextBodyNoneWhenNotFetched:
  let e = emailWith(
    @[textLeaf("text/plain", "1")], @[(pid("other"), EmailBodyValue(value: "x"))]
  )
  assertNone e.decodedTextBody()

testCase leafTextPartsYieldsTextBodyLeaves:
  let e = emailWith(
    @[textLeaf("text/plain", "1"), textLeaf("text/html", "2")],
    newSeq[(PartId, EmailBodyValue)](),
  )
  var seen: seq[string] = @[]
  for part in e.leafTextParts():
    case part.isMultipart
    of false:
      seen.add($part.partId)
    of true:
      discard
  assertEq seen, @["1", "2"]

testCase textBodiesSetsTextScopeAndCap:
  let opts = textBodies(parseUnsignedInt(1024).get())
  assertEq opts.fetchBodyValues, bvsText
  assertSomeEq opts.maxBodyValueBytes, parseUnsignedInt(1024).get()

testCase textBodiesNoCap:
  let opts = textBodies()
  assertEq opts.fetchBodyValues, bvsText
  assertNone opts.maxBodyValueBytes
```

- [ ] **Step 2: Run the test, confirm it fails to compile**

Run: `nim c -r tests/unit/mail/temail_body_readers.nim`
Expected: FAIL — `undeclared identifier: 'bodyValue'` (and `leafTextParts`,
`decodedTextBody`, `textBodies`). If `parseBlobId` is the wrong spelling, check
`src/jmap_client/internal/types/identifiers.nim` for the exact name and adjust.

- [ ] **Step 3: Implement the readers in `email.nim`**

Add immediately after `func isLeaf*` (~line 530):

```nim
func bodyValue*(e: Email, pid: PartId): Opt[EmailBodyValue] =
  ## The decoded value for the body part identified by ``pid`` (RFC 8621
  ## §4.1.4), or ``Opt.none`` when no value was fetched for it. A total,
  ## ``std/tables``-free lookup into ``bodyValues`` — the consumer never imports
  ## ``std/tables`` nor risks the ``KeyError`` of ``bodyValues[pid]``. Carries
  ## the per-part ``isTruncated`` / ``isEncodingProblem`` signals.
  if e.bodyValues.hasKey(pid):
    Opt.some(e.bodyValues.getOrDefault(pid))
  else:
    Opt.none(EmailBodyValue)

iterator leafTextParts*(e: Email): EmailBodyPart =
  ## Yields the leaf parts of ``textBody`` — the RFC 8621 §4.1.4 plain-text
  ## representation list, already flat (every entry is a non-multipart leaf).
  ## Filters defensively to leaves so a non-conformant server that nests a
  ## multipart in ``textBody`` is skipped rather than yielded.
  for part in e.textBody:
    case part.isMultipart
    of false:
      yield part
    of true:
      discard

func decodedTextBody*(e: Email): Opt[string] =
  ## The decoded plain-text body: the ``value``s of every ``text/plain`` leaf in
  ## ``textBody``, concatenated in order (RFC 8621 §4.1.4 sequential rendering).
  ## ``Opt.none`` when there is no ``text/plain`` content or none was fetched;
  ## ``Opt.some`` otherwise. Library policy (RFC-permitted, not RFC-mandated):
  ## filters to ``text/plain`` and skips a part whose value was not fetched.
  ## Per-part ``isTruncated`` / ``isEncodingProblem`` are read via ``bodyValue`` —
  ## deliberately not folded into this convenience.
  var pieces: seq[string] = @[]
  for part in e.textBody:
    case part.isMultipart
    of false:
      if part.contentType == "text/plain":
        for v in e.bodyValue(part.partId):
          pieces.add(v.value)
    of true:
      discard
  if pieces.len == 0:
    Opt.none(string)
  else:
    Opt.some(pieces.join(""))
```

Add `textBodies` immediately after the `EmailBodyFetchOptions` type (~line 447):

```nim
func textBodies*(maxBytes: UnsignedInt): EmailBodyFetchOptions =
  ## Fetch options requesting the decoded values of the ``textBody`` parts
  ## (RFC 8621 §4.2 ``fetchTextBodyValues``), truncating each to ``maxBytes``
  ## octets. Removes the ``BodyValueScope`` discovery and the
  ## ``maxBodyValueBytes`` ``Opt`` wrap.
  EmailBodyFetchOptions(fetchBodyValues: bvsText, maxBodyValueBytes: Opt.some(maxBytes))

func textBodies*(): EmailBodyFetchOptions =
  ## ``textBodies`` with no per-value truncation cap (RFC 8621 §4.2 default).
  EmailBodyFetchOptions(fetchBodyValues: bvsText)
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `nim c -r tests/unit/mail/temail_body_readers.nim`
Expected: PASS (all `testCase`s green).

- [ ] **Step 5: Build the library**

Run: `just build`
Expected: success, no warnings.

- [ ] **Step 6: Format and commit**

```bash
just fmt
git add src/jmap_client/internal/mail/email.nim tests/unit/mail/temail_body_readers.nim
git commit
```

Commit subject: `mail/email: add tables-free body readers (R2)`. Body: explain
that `bodyValue`/`leafTextParts`/`decodedTextBody` let a consumer read the message
text without `import std/tables` or a hand-walked `isMultipart` case (RFC 8621
§4.1.4), and `textBodies` removes the fetch-options seal; cite the libcurl/SQLite
primitive-plus-convenience split (`bodyValue` is the rich primitive,
`decodedTextBody` the simple convenience). Append the three trailers.

---

## Task 2: Mailbox role predicates — `isInbox`, `hasRole`

**Files:**
- Modify: `src/jmap_client/internal/mail/mailbox.nim` (add after the `Mailbox` type, ~line 366)
- Create: `tests/unit/mail/tmailbox_role_predicates.nim`

Context: `Mailbox.role*: Opt[MailboxRole]`; `MailboxRole.kind*(): MailboxRoleKind`
accessor; `MailboxRoleKind` values `mrInbox`/`mrDrafts`/…/`mrOther`; named
constants `roleInbox`/… exist.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/mail/tmailbox_role_predicates.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the S3 Mailbox role predicates isInbox / hasRole
## (RFC 8621 §2, §10.5.1).

{.push raises: [].}

import jmap_client/internal/mail/mailbox
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation # re-exports nim-results (Opt/.get)

import ../../massertions
import ../../mtestblock

proc mailboxWithRole(role: Opt[MailboxRole]): Mailbox =
  Mailbox(
    id: parseId("mb1").get(),
    name: "a",
    role: role,
    sortOrder: parseUnsignedInt(0).get(),
    totalEmails: parseUnsignedInt(0).get(),
    unreadEmails: parseUnsignedInt(0).get(),
    totalThreads: parseUnsignedInt(0).get(),
    unreadThreads: parseUnsignedInt(0).get(),
    myRights: MailboxRights(),
    isSubscribed: false,
  )

testCase isInboxTrue:
  let mb = mailboxWithRole(Opt.some(roleInbox))
  assertEq mb.isInbox(), true

testCase isInboxFalseForDrafts:
  let mb = mailboxWithRole(Opt.some(roleDrafts))
  assertEq mb.isInbox(), false

testCase isInboxFalseForNoRole:
  let mb = mailboxWithRole(Opt.none(MailboxRole))
  assertEq mb.isInbox(), false

testCase hasRoleMatches:
  let mb = mailboxWithRole(Opt.some(roleSent))
  assertEq mb.hasRole(mrSent), true
  assertEq mb.hasRole(mrInbox), false

testCase hasRoleNoneIsFalse:
  let mb = mailboxWithRole(Opt.none(MailboxRole))
  assertEq mb.hasRole(mrTrash), false
```

- [ ] **Step 2: Run the test, confirm it fails**

Run: `nim c -r tests/unit/mail/tmailbox_role_predicates.nim`
Expected: FAIL — `undeclared identifier: 'isInbox'` / `'hasRole'`.

- [ ] **Step 3: Implement in `mailbox.nim`** (after the `Mailbox` type, ~line 366)

```nim
func hasRole*(mb: Mailbox, kind: MailboxRoleKind): bool =
  ## ``true`` iff ``mb`` carries the given well-known role (RFC 8621 §2). The
  ## general form: "is this Drafts/Sent/Trash/…?" all reduce to ``hasRole``.
  ## ``hasRole(mb, mrOther)`` matches any vendor-extension role.
  for role in mb.role:
    return role.kind == kind
  false

func isInbox*(mb: Mailbox): bool =
  ## ``true`` iff ``mb`` is the Inbox (RFC 8621 §2 / §10.5.1 ``inbox`` role) —
  ## the one blessed spelling for the most common mailbox question, replacing
  ## the three divergent idioms (``role.kind == mrInbox`` / ``roleInbox`` /
  ## ``parseMailboxRole("inbox")``).
  hasRole(mb, mrInbox)
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `nim c -r tests/unit/mail/tmailbox_role_predicates.nim` — Expected: PASS.

- [ ] **Step 5: Build** — Run: `just build` — Expected: success.

- [ ] **Step 6: Format and commit**

```bash
just fmt
git add src/jmap_client/internal/mail/mailbox.nim tests/unit/mail/tmailbox_role_predicates.nim
git commit
```

Subject: `mail/mailbox: add isInbox/hasRole role predicates (R2)`. Body: one
blessed spelling for the three-idiom "is this the inbox?" friction (RFC 8621 §2 /
§10.5.1); `hasRole` is the general form. Note that no `MailboxRights` roll-ups are
added — the nine `may*` rights are orthogonal (RFC 8621 §2) and a `canWrite`
conjunction would misreport. Three trailers.

---

## Task 3: `plainTextBody` send-body constructor

**Files:**
- Modify: `src/jmap_client/internal/mail/email_blueprint.nim` (after `structuredBody`, ~line 312)
- Create: `tests/unit/mail/tplain_text_body.nim`

Context: `EmailBlueprintBody` is `ebkStructured | ebkFlat`; `flatBody(textBody,
htmlBody, attachments)` builds the `ebkFlat` arm. `BlueprintBodyPart` has shared
`contentType*: string`, `extraHeaders*: Table[BlueprintBodyHeaderName,
BlueprintHeaderMultiValue]`, and `case isMultipart*: bool of false: leaf*:
BlueprintLeafPart`. `BlueprintLeafPart` is `case source*: BlueprintPartSource of
bpsInline: partId*: PartId; value*: BlueprintBodyValue`. `BlueprintBodyValue` has
`value*: string`. `parsePartIdFromServer` is the only `PartId` mint.
`parseEmailBlueprint`'s `checkFlatBodyContentTypes` requires textBody
`contentType == "text/plain"`. All these are imported by `email_blueprint.nim`
(`./body`, `./headers`); `std/tables` is imported.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/mail/tplain_text_body.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for plainTextBody: the S3 plain-text send-body smart
## constructor (RFC 8621 §4.6). Proves the produced body validates through
## parseEmailBlueprint.

{.push raises: [].}

import jmap_client/internal/mail/email_blueprint
import jmap_client/internal/mail/body
import jmap_client/internal/mail/mailbox
import jmap_client/internal/types/primitives # parseId
import jmap_client/internal/types/validation # re-exports nim-results (Opt/.get)

import ../../massertions
import ../../mtestblock

proc oneMailbox(): NonEmptyMailboxIdSet =
  parseNonEmptyMailboxIdSet(@[parseId("mb1").get()]).get()

testCase plainTextBodyShape:
  let body = plainTextBody("hello world")
  assertEq body.kind, ebkFlat
  assertSome body.textBody
  let part = body.textBody.get()
  assertEq part.contentType, "text/plain"
  case part.isMultipart
  of false:
    case part.leaf.source
    of bpsInline:
      assertEq part.leaf.value.value, "hello world"
    of bpsBlobRef:
      assertFalse true, "expected an inline leaf"
  of true:
    assertFalse true, "expected a leaf part"

testCase plainTextBodyValidatesThroughBlueprint:
  let res = parseEmailBlueprint(oneMailbox(), body = plainTextBody("hi"))
  assertOk res
```

- [ ] **Step 2: Run the test, confirm it fails**

Run: `nim c -r tests/unit/mail/tplain_text_body.nim`
Expected: FAIL — `undeclared identifier: 'plainTextBody'`. (Confirm the exact
names of `BlueprintBodyHeaderName`/`BlueprintHeaderMultiValue` in
`src/jmap_client/internal/mail/headers.nim` if the implementation step errors.)

- [ ] **Step 3: Implement in `email_blueprint.nim`** (after `structuredBody`, ~line 312)

```nim
func plainTextBody*(text: string): EmailBlueprintBody =
  ## Smart constructor for the single most common send body: one inline
  ## ``text/plain`` leaf carrying ``text`` (RFC 8621 §4.6). Auto-mints the
  ## creation-time ``partId`` so the caller never touches the 4-layer
  ## ``BlueprintBodyValue`` → ``BlueprintLeafPart`` → ``BlueprintBodyPart`` →
  ## ``flatBody`` chain. The ``text/plain`` content type satisfies
  ## ``parseEmailBlueprint``'s flat-body constraint, so the result passes
  ## straight to its ``body`` parameter. Building block for S4's
  ## ``sendPlainText``.
  let part = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      # The literal "text" is non-empty and control-character-free, so the
      # lenient PartId parser cannot Err here (Pattern 8 invariant .get()).
      partId: parsePartIdFromServer("text").get(),
      value: BlueprintBodyValue(value: text),
    ),
  )
  flatBody(textBody = Opt.some(part))
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `nim c -r tests/unit/mail/tplain_text_body.nim` — Expected: PASS.

- [ ] **Step 5: Build** — Run: `just build` — Expected: success.

- [ ] **Step 6: Format and commit**

```bash
just fmt
git add src/jmap_client/internal/mail/email_blueprint.nim tests/unit/mail/tplain_text_body.nim
git commit
```

Subject: `mail/email_blueprint: add plainTextBody constructor (R2)`. Body: closes
the documented 4-layer plain-text send-body gap with a single smart constructor
that auto-mints the partId (RFC 8621 §4.6); the building block S4's `sendPlainText`
consumes. Three trailers.

---

## Task 4: `require*` capability preflight (RFC-faithful soft resolution)

**Files:**
- Modify: `src/jmap_client/internal/protocol/preflight.nim` (after `requirePrimaryAccount`)
- Create: `tests/unit/tpreflight.nim`

**RFC-verify first (mandatory — methodology lesson):** before writing code, read
RFC 8620 §2 in `docs/rfcs/` (the `primaryAccounts` and per-account
`accountCapabilities` paragraphs) and confirm in the commit body, with a section
cite, that (a) per-account `accountCapabilities` is the load-bearing capability
check and (b) `primaryAccounts` MAY have no entry for a supported capability. If
the RFC text contradicts the soft-fallback design, STOP and report — do not guess.

Context: `requirePrimaryAccount(session, kind): Result[AccountId, JmapError]`
stays **strict and unchanged** (it errs `sfPrimaryAccountAbsent` when no primary).
`Session.accounts*: Table[AccountId, Account]`; `Session.primaryAccount(kind):
Opt[AccountId]`; `Account.hasCapability(kind): bool`; capability enum values
`ckMail` / `ckSubmission` / `ckVacationResponse`; `jmapSession`/`sessionFault`/
`sfCapabilityAbsent` from `jmap_error` (already imported). **Add `import std/tables`**
— the `session.accounts` pairs iterator needs it and `preflight.nim` does not
import it today; no other new imports.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/tpreflight.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the S3 capability preflight sugar requireMail /
## requireSubmission / requireVacation (RFC 8620 §2 per-account capability +
## soft primaryAccounts fallback; RFC 8621 §1.3.1-3 distinct URNs).

{.push raises: [].}

import std/tables

import jmap_client/internal/protocol/preflight
import jmap_client/internal/types/session
import jmap_client/internal/types/identifiers

import ../massertions
import ../mtestblock
import ../mfixtures

proc sessionWith(
    accounts: seq[(string, Account)], primaries: seq[(string, string)]
): Session =
  ## Builds a Session from (accountId, Account) pairs and (capabilityUri,
  ## accountId) primaryAccounts pairs, on top of the minimal fixture session.
  var args = makeSessionArgs()
  var acctTable = initTable[AccountId, Account]()
  for (id, acc) in accounts:
    acctTable[makeAccountId(id)] = acc
  args.accounts = acctTable
  var primaryTable = initTable[string, AccountId]()
  for (uri, id) in primaries:
    primaryTable[uri] = makeAccountId(id)
  args.primaryAccounts = primaryTable
  parseSessionFromArgs(args)

testCase requireMailPrimaryPreferred:
  let s = sessionWith(
    @[("A1", makeAccount(accountCapabilities = @[makeMailAccountEntry()]))],
    @[("urn:ietf:params:jmap:mail", "A1")],
  )
  assertOkEq requireMail(s), makeAccountId("A1")

testCase requireMailSoftFallbackNoPrimary:
  # No primaryAccounts entry, but the account advertises the mail capability.
  let s = sessionWith(
    @[("A1", makeAccount(accountCapabilities = @[makeMailAccountEntry()]))], @[]
  )
  assertOkEq requireMail(s), makeAccountId("A1")

testCase requireVacationSoftFallback:
  # vacationresponse commonly has no primaryAccounts entry.
  let s = sessionWith(
    @[("A1", makeAccount(accountCapabilities = @[makeVacationAccountEntry()]))], @[]
  )
  assertOkEq requireVacation(s), makeAccountId("A1")

testCase requireSubmissionDistinctFromMail:
  # An account with mail but NOT submission must fail requireSubmission.
  let s = sessionWith(
    @[("A1", makeAccount(accountCapabilities = @[makeMailAccountEntry()]))], @[]
  )
  assertOkEq requireMail(s), makeAccountId("A1")
  let res = requireSubmission(s)
  assertErr res

testCase requireMailErrsWhenNoAccountSupports:
  let s = sessionWith(@[("A1", makeAccount(accountCapabilities = @[]))], @[])
  let res = requireMail(s)
  assertErr res
```

- [ ] **Step 2: Run the test, confirm it fails**

Run: `nim c -r tests/unit/tpreflight.nim`
Expected: FAIL — `undeclared identifier: 'requireMail'`. (If `makeSessionArgs`/
`makeAccount`/`makeMailAccountEntry` are missing, confirm their signatures in
`tests/mfixtures.nim:202-300`.)

- [ ] **Step 3: Implement in `preflight.nim`**

First add `import std/tables` to the import block (the `session.accounts` pairs
iterator needs it — verified absent today). Then add, after `requirePrimaryAccount`:

```nim
func usableAccount(
    session: Session, kind: CapabilityKind
): Result[AccountId, JmapError] =
  ## RFC 8620 §2 account resolution for a capability: prefer the designated
  ## primary account, else any account whose ``accountCapabilities`` advertises
  ## the capability — ``primaryAccounts`` MAY legitimately have no entry for a
  ## supported capability (§2). Errs ``sfCapabilityAbsent`` only when no account
  ## supports the capability at all. When several accounts advertise the
  ## capability and none is the designated primary, an unspecified supporting
  ## account is returned — configure ``primaryAccounts`` to disambiguate.
  ## Module-private — the public ``require*`` sugar names each capability.
  for accountId in session.primaryAccount(kind):
    return ok(accountId)
  for accountId, account in session.accounts:
    if account.hasCapability(kind):
      return ok(accountId)
  err(jmapSession(sessionFault(sfCapabilityAbsent, kind)))

func requireMail*(session: Session): Result[AccountId, JmapError] =
  ## Resolves the account to use for ``urn:ietf:params:jmap:mail`` operations
  ## (RFC 8621 §1.3.1), primary-preferred with a per-account fallback (RFC 8620
  ## §2). Folds onto the one rail so a connect flow threads on a single ``?``.
  usableAccount(session, ckMail)

func requireSubmission*(session: Session): Result[AccountId, JmapError] =
  ## Resolves the account for ``urn:ietf:params:jmap:submission`` (RFC 8621
  ## §1.3.2) — a separate capability from mail: a shared account may have mail
  ## but not submission, so this catches the gap before an EmailSubmission/set
  ## round-trip fails.
  usableAccount(session, ckSubmission)

func requireVacation*(session: Session): Result[AccountId, JmapError] =
  ## Resolves the account for ``urn:ietf:params:jmap:vacationresponse``
  ## (RFC 8621 §1.3.3). The soft fallback matters here: vacationresponse
  ## commonly has no ``primaryAccounts`` entry, so a strict primary lookup would
  ## spuriously fail on a genuinely usable account.
  usableAccount(session, ckVacationResponse)
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `nim c -r tests/unit/tpreflight.nim` — Expected: PASS.

- [ ] **Step 5: Build** — Run: `just build` — Expected: success.

- [ ] **Step 6: Format and commit**

```bash
just fmt
git add src/jmap_client/internal/protocol/preflight.nim tests/unit/tpreflight.nim
git commit
```

Subject: `protocol/preflight: add requireMail/Submission/Vacation (R2)`. Body:
**cite RFC 8620 §2** (per-account `accountCapabilities` load-bearing;
`primaryAccounts` may be absent for a supported capability) and RFC 8621
§1.3.1-1.3.3 (three distinct URNs). Explain the uniform bare-`AccountId` resolve
(SQLite-`prepare`/libcurl-`init` shape; capabilities read separately via
`account.mailCapability`), and that `requirePrimaryAccount` stays strict/unchanged
while `require*` use their own soft resolution so `requireVacation` doesn't
spuriously fail. Three trailers.

---

## Task 5: `limit` query-window helper

**Files:**
- Modify: `src/jmap_client/internal/types/framework.nim` (after the `QueryParams` type)
- Create: `tests/unit/tframework_limit.nim`

Context: `QueryParams*` (framework.nim) has `limit*: Opt[UnsignedInt]` (and
`position`/`anchor`/`anchorOffset`/`calculateTotal`, all RFC-default zero-init);
`addEmailQuery(..., queryParams: QueryParams = QueryParams(), ...)` is the consumer.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/tframework_limit.nim`:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit test for the S3 `limit` QueryParams helper (RFC 8620 §5.5).

{.push raises: [].}

import jmap_client/internal/types/framework
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation # re-exports nim-results (Opt/.get)

import ../massertions
import ../mtestblock

testCase limitSetsWindow:
  let qp = limit(parseUnsignedInt(20).get())
  assertSomeEq qp.limit, parseUnsignedInt(20).get()
```

- [ ] **Step 2: Run the test, confirm it fails**

Run: `nim c -r tests/unit/tframework_limit.nim` — Expected: FAIL,
`undeclared identifier: 'limit'`.

- [ ] **Step 3: Implement in `framework.nim`** (after the `QueryParams` type)

```nim
func limit*(count: UnsignedInt): QueryParams =
  ## A ``QueryParams`` window limited to ``count`` results (RFC 8620 §5.5).
  ## ``addEmailQuery(b, acc, queryParams = limit(n))`` replaces
  ## ``QueryParams(limit: Opt.some(n))`` — no field name, no ``Opt`` wrap.
  QueryParams(limit: Opt.some(count))
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `nim c -r tests/unit/tframework_limit.nim` — Expected: PASS.

- [ ] **Step 5: Build** — Run: `just build` — Expected: success.

- [ ] **Step 6: Format and commit**

```bash
just fmt
git add src/jmap_client/internal/types/framework.nim tests/unit/tframework_limit.nim
git commit
```

Subject: `types/framework: add limit query-window helper (R2)`. Body: removes the
`QueryParams(limit: Opt.some(parseUnsignedInt(n).get()))` triple-wrap; an input
constructor is first-class core (libcurl `setopt` / SQLite `bind`), shipped under
the SQLite-minimal bar because it kills a real seal. Three trailers.

---

## Task 6: Regenerate the public-API snapshot + `just ci`

The twelve new `public-api.txt` lines — eleven names (`bodyValue`,
`leafTextParts`, `decodedTextBody`, `textBodies`, `hasRole`, `isInbox`,
`plainTextBody`, `requireMail`, `requireSubmission`, `requireVacation`, `limit`),
where `textBodies` has two overloads and the oracle emits one line per overload —
auto-surface through the hub but must be added to the frozen contract or the H16
lint fails. No new types, so `type-shapes.txt` / `module-paths.txt` /
`error-messages.txt` must NOT change.

- [ ] **Step 1: Regenerate the public-API snapshot**

Run: `just freeze-api`
Expected: `tests/wire_contract/public-api.txt` gains twelve lines (the eleven
names; `textBodies` appears twice for its two overloads).

- [ ] **Step 2: Confirm the other snapshots are unchanged**

```bash
just freeze-type-shapes
git diff --stat tests/wire_contract/
```
Expected: only `public-api.txt` shows changes. If `type-shapes.txt` changed, a new
type leaked into the public surface — investigate before proceeding (S3 adds no
types).

- [ ] **Step 3: Run the full CI battery**

Run: `just ci`
Expected: PASS — reuse, fmt-check, the lint battery (incl. H1/H1b/H16/H17),
nimalyzer (`complexity` ≤10 and `hasdoc`), and the fast `test`. If `hasdoc` fires,
a new `func` lacks a docstring; if `complexity` fires on `decodedTextBody`,
decompose (do NOT suppress).

- [ ] **Step 4: Commit the regenerated snapshot**

```bash
git add tests/wire_contract/public-api.txt
git commit
```

Subject: `wire_contract: freeze S3 public surface (R2)`. Body: the eleven additive
S3 readers/predicates/constructors enter the frozen contract; no type-shape change
(no new types). Three trailers.

---

## Task 7: Re-bench the CLI; update `AUDIT.md` + `docs/design/16`

The `examples/jmap-cli/` bench is the P29 instrument. Demonstrate the S3 symbols
where the AUDIT recorded their absence, then reconcile the findings.

- [ ] **Step 1: Adopt the S3 readers in the CLI** where they replace hand-rolled code:
  - `examples/jmap-cli/commands/email_read.nim` (or equivalent): replace the manual
    `textBody`-walk + `bodyValues`-by-`partId` join with `email.decodedTextBody()`;
    drop the `import std/tables` if it was only for that read.
  - the mailbox command: replace the `role.kind == mrInbox` idiom with `mb.isInbox()`.
  - the session preflight: replace `requirePrimaryAccount(session, ckMail)` (or the
    `primaryAccount(ckMail)` unwrap) with `requireMail(session)`.
  Build the example out-of-tree-style to confirm public-only reach:
  Run: `bash examples/jmap-cli/check-public-only.sh` — Expected: pass.

- [ ] **Step 2: Reconcile the AUDIT findings.** In `examples/jmap-cli/AUDIT.md`,
  add an **"S3 resolution"** section (mirroring the S1/S2 resolution sections)
  mapping each now-fixed finding to its symbol: `mailbox:rightsSummary` (resolved
  as "no roll-up — primitives only, RFC 8621 §2"); `mailbox:mb.role` (→ `isInbox`/
  `hasRole`); `email read:bodyValues` / `email read:decodeText` / `email
  read:isMultipart` (→ `bodyValue`/`leafTextParts`/`decodedTextBody`); `email
  read:maxBodyValueBytes` (→ `textBodies`); `email query:QueryParams.limit` (→
  `limit`); `email send:no-body-helper` (→ `plainTextBody`, the S3 half; the
  `sendPlainText` one-shot remains S4); `session:capability` (→ `requireMail`).

- [ ] **Step 3: Update `docs/design/16-api-from-the-consumers-chair.md`** — turn the
  three "deferred to S3" markers (the Messages and Reading sections) into an "S3
  update" note stating the body readers, role predicate, and preflight sugar
  shipped, with the libcurl/SQLite framing (rich primitive + simple convenience;
  uniform resolve; no rights roll-ups).

- [ ] **Step 4: Commit**

```bash
just fmt
git add examples/jmap-cli examples/jmap-cli/AUDIT.md docs/design/16-api-from-the-consumers-chair.md
git commit
```

Subject: `examples/jmap-cli: adopt S3 readers; reconcile AUDIT (R2)`. Body:
re-benched against the S3 deliverables; the body-reader / role-predicate /
preflight findings are resolved; records the no-roll-up decision. Three trailers.

---

## Task 8: Both full gates

- [ ] **Step 1: `just ci`** — Expected: PASS (re-confirm after Task 7's CLI/doc changes).

- [ ] **Step 2: Live full suite**

Run: `just clean && just jmap-reset && just test-full` (exact order)
Expected: "All shards passed" against Stalwart / James / Cyrus. On any failure,
fix, then **re-run the whole sequence** until green. Sweep ALL of `tests/`
(including `tests/testament_skip.txt` files — a refactor ripple can hide there;
none expected here since S3 is purely additive, but verify).

- [ ] **Step 3: Update the STATE block** in this plan (mark every task ✅ with its
  commit SHA) and commit.

```bash
git add docs/superpowers/plans/2026-06-16-s3-complete-the-core-plan.md
git commit
```

- [ ] **Step 4: Hand back to the user** for the push / PR / merge decision (confirm
  before any outward-facing action). Then `finishing-a-development-branch`.

---

## Self-review (run before dispatching)

**Spec coverage:** §3.1 → Task 1; §3.2 → Task 2; §3.3 → Task 3; §3.4 → Task 4;
§3.5 `limit` → Task 5, `textBodies` → Task 1; §7 contract → Task 6; §6 testing →
every task (TDD); re-bench → Task 7; gates → Task 8. The §4 exclusions are
asserted by *absence* + the AUDIT note in Task 7. No spec requirement is unmapped.

**Type consistency:** every signature uses verified current types —
`Email`/`PartId`/`EmailBodyValue`/`EmailBodyPart`/`EmailBodyFetchOptions`/
`BodyValueScope.bvsText`/`UnsignedInt`/`Opt`/`Table` (Task 1);
`Mailbox`/`MailboxRoleKind`/`mrInbox` (Task 2);
`EmailBlueprintBody`/`BlueprintBodyPart`/`BlueprintLeafPart`/`BlueprintBodyValue`/
`bpsInline`/`flatBody`/`parsePartIdFromServer`/`BlueprintBodyHeaderName`/
`BlueprintHeaderMultiValue` (Task 3);
`Session`/`Account`/`AccountId`/`CapabilityKind.{ckMail,ckSubmission,ckVacationResponse}`/
`JmapError`/`sessionFault`/`sfCapabilityAbsent` (Task 4); `QueryParams` (Task 5).

**No placeholders:** every code step shows complete code; every test step shows
the full test; every run step gives the exact command + expected output.

**Risk notes for the implementer:** (1) confirm `parseBlobId` spelling in
`identifiers.nim` (Task 1 test helper). (2) Task 4 MUST RFC-verify before coding.
(3) if `nim c -r` on a single test file complains about megatest joinability,
run the file standalone — these are joinable unit tests, but a stray top-level
statement breaks the join; keep everything inside `testCase` blocks or `proc`s.
