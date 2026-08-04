# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Build-dispatch-extract one-shots (Layer 4). The easy path: a single call
## that folds construction, dispatch, and extraction of one logical JMAP
## operation onto the one ``JmapError`` rail, so an application developer
## reaches for the library directly without hand-wiring builders and handles.
##
## Each one-shot issues exactly one logical operation and therefore has no
## sibling method whose result must survive as data; it collapses that
## method's ``MethodOutcome`` onto the rail via ``fulfil`` (RFC 8620 §3.6.2 —
## a single-method shortcut, not a reclassification of the data semantics).
## The query-then-get compound dispatches a back-reference chain (RFC 8620
## §3.7) and extracts both halves via the uniform ``getBoth`` before each is
## fulfilled. The send compound dispatches a §5.4 implicit-call pair but
## consumes only the primary EmailSubmission/set outcome: the implicit
## Drafts -> Sent Email/set is a server-side best-effort move (RFC 8621 §7.5 ¶3)
## whose response does not gate send success.
##
## ``connect`` folds the endpoint + credential constructors and
## ``initJmapClient`` onto the rail; the RFC 8620 §2 session stays lazy
## (fetched on first send). The bare-get one-shots return the full
## ``GetResponse[T]`` so ``state`` and ``notFound`` survive. ``sendPlainText``
## encapsulates the RFC 8621 §7.5/§7.5.1 two-mailbox send: a draft created in
## Drafts and an EmailSubmission whose success moves the message to Sent.

{.push raises: [].}
{.experimental: "strictCaseObjects".}

import std/sugar
import std/tables

import ./client
import ./transport
import ./types
import ./mail
import ./mail/thread
import ./protocol/methods
import ./protocol/dispatch
import ./protocol/builder
import ./protocol/jmap_error

# =============================================================================
# connect — one-call client bootstrap (RFC 8620 §2)
# =============================================================================

proc connect*(url, username, password: string): Result[JmapClient, JmapError] =
  ## One-call client bootstrap (RFC 8620 §2 session is fetched lazily on first
  ## send / requireMail). Folds the endpoint + credential constructors and
  ## ``initJmapClient`` onto the one rail.
  let endpoint = ?directEndpoint(url).lift
  let credential = ?basicCredential(username, password).lift
  initJmapClient(endpoint, credential)

proc connect*(
    url, username, password: string, transport: Transport
): Result[JmapClient, JmapError] =
  ## ``connect`` against a caller-supplied ``Transport`` (libcurl wrapper,
  ## in-process mock, recording proxy). Same fold as the default-transport
  ## overload, threading the 3-argument ``initJmapClient`` (RFC 8620 §2).
  let endpoint = ?directEndpoint(url).lift
  let credential = ?basicCredential(username, password).lift
  initJmapClient(endpoint, credential, transport)

# =============================================================================
# Bare-get one-shots — full GetResponse[T] (RFC 8621 §2/§3/§4/§6/§7/§8)
# =============================================================================

proc runGet[T](
    client: JmapClient,
    name: MethodName,
    built: sink (RequestBuilder, ResponseHandle[GetResponse[T]]),
): Result[GetResponse[T], JmapError] =
  ## Internal: freeze -> send -> get -> fulfil for a single ``Foo/get`` one-shot.
  ## The single method's outcome collapses onto the rail (RFC 8620 §3.6.2 — no
  ## sibling to protect), so the caller threads a flat ``GetResponse[T]``.
  let (b, handle) = built
  let dr = ?client.send(b.freeze())
  (?dr.get(handle)).fulfil(name)

proc getMailboxes*(
    client: JmapClient,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): Result[GetResponse[Mailbox], JmapError] =
  ## Full-record Mailbox/get one-shot (RFC 8621 §2.1). ``ids`` defaults to the
  ## whole set; ``GetResponse.state`` / ``notFound`` are preserved.
  runGet[Mailbox](
    client, mnMailboxGet, client.newBuilder().addMailboxGet(accountId, ids)
  )

proc getIdentities*(
    client: JmapClient,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): Result[GetResponse[Identity], JmapError] =
  ## Full-record Identity/get one-shot (RFC 8621 §6.1).
  runGet[Identity](
    client, mnIdentityGet, client.newBuilder().addIdentityGet(accountId, ids)
  )

proc getEmails*(
    client: JmapClient,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): Result[GetResponse[Email], JmapError] =
  ## Full-record Email/get one-shot (RFC 8621 §4.2) with the Email-specific
  ## body-fetch options (RFC 8621 §4.2.2).
  runGet[Email](
    client,
    mnEmailGet,
    client.newBuilder().addEmailGet(accountId, ids, bodyFetchOptions),
  )

proc getThreads*(
    client: JmapClient,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): Result[GetResponse[thread.Thread], JmapError] =
  ## Full-record Thread/get one-shot (RFC 8621 §3.1).
  runGet[thread.Thread](
    client, mnThreadGet, client.newBuilder().addThreadGet(accountId, ids)
  )

proc getEmailSubmissions*(
    client: JmapClient,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): Result[GetResponse[AnyEmailSubmission], JmapError] =
  ## Full-record EmailSubmission/get one-shot (RFC 8621 §7.1).
  runGet[AnyEmailSubmission](
    client,
    mnEmailSubmissionGet,
    client.newBuilder().addEmailSubmissionGet(accountId, ids),
  )

proc getVacationResponse*(
    client: JmapClient, accountId: AccountId
): Result[GetResponse[VacationResponse], JmapError] =
  ## Full-record VacationResponse/get one-shot (RFC 8621 §8.1). The singleton
  ## takes no ``ids`` — the server always returns the one record.
  runGet[VacationResponse](
    client, mnVacationResponseGet, client.newBuilder().addVacationResponseGet(accountId)
  )

proc getEmailState*(
    client: JmapClient, accountId: AccountId
): Result[JmapState, JmapError] =
  ## Current ``Email`` object state — the ``sinceState`` cursor a first
  ## ``syncEmails`` call needs. Issues an ``Email/get`` with an empty ids
  ## list purely for its ``state`` field, so bootstrapping a sync cursor
  ## costs no email payload.
  let resp = ?client.getEmails(accountId, ids = Opt.some(direct(newSeq[Id]())))
  ok(resp.state)

# =============================================================================
# Query-then-get one-shots (RFC 8620 §3.7 back-reference chains)
# =============================================================================

type QueryThenGet*[T] = object
  ## Off-rail result of a query-then-get one-shot (both method outcomes already
  ## collapsed onto the JmapError rail).
  query*: QueryResponse[T]
  get*: GetResponse[T]

proc queryEmails*(
    client: JmapClient,
    accountId: AccountId,
    filter: Opt[Filter[EmailFilterCondition]] = Opt.none(Filter[EmailFilterCondition]),
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = false,
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): Result[QueryThenGet[Email], JmapError] =
  ## Email/query then full-record Email/get one-shot (RFC 8621 §4.4 + §4.2). The
  ## get's ``ids`` back-references the query's ``/ids`` path; both outcomes are
  ## collapsed onto the rail.
  let (b, handles) = client.newBuilder().addEmailQueryThenGet(
      accountId, filter, sort, queryParams, collapseThreads, bodyFetchOptions
    )
  let dr = ?client.send(b.freeze())
  let both = ?dr.getBoth(handles)
  ok(
    QueryThenGet[Email](
      query: ?both.query.fulfil(mnEmailQuery), get: ?both.get.fulfil(mnEmailGet)
    )
  )

proc queryMailboxes*(
    client: JmapClient,
    accountId: AccountId,
    filter: Opt[Filter[MailboxFilterCondition]] =
      Opt.none(Filter[MailboxFilterCondition]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    queryParams: QueryParams = QueryParams(),
    sortAsTree: bool = false,
    filterAsTree: bool = false,
): Result[QueryThenGet[Mailbox], JmapError] =
  ## Mailbox/query then full-record Mailbox/get one-shot (RFC 8621 §2.3 +
  ## §2.1). The get's ``ids`` back-references the query's ``/ids`` path; both
  ## outcomes are collapsed onto the rail.
  let (b, handles) = client.newBuilder().addMailboxQueryThenGet(
      accountId, filter, sort, queryParams, sortAsTree, filterAsTree
    )
  let dr = ?client.send(b.freeze())
  let both = ?dr.getBoth(handles)
  ok(
    QueryThenGet[Mailbox](
      query: ?both.query.fulfil(mnMailboxQuery), get: ?both.get.fulfil(mnMailboxGet)
    )
  )

proc queryEmailSubmissions*(
    client: JmapClient,
    accountId: AccountId,
    filter: Opt[Filter[EmailSubmissionFilterCondition]] =
      Opt.none(Filter[EmailSubmissionFilterCondition]),
    sort: Opt[seq[EmailSubmissionComparator]] = Opt.none(seq[EmailSubmissionComparator]),
    queryParams: QueryParams = QueryParams(),
): Result[QueryThenGet[AnyEmailSubmission], JmapError] =
  ## EmailSubmission/query then full-record EmailSubmission/get one-shot
  ## (RFC 8621 §7.3 + §7.1). The get's ``ids`` back-references the query's
  ## ``/ids`` path; both outcomes are collapsed onto the rail.
  let (b, handles) = client.newBuilder().addEmailSubmissionQueryThenGet(
      accountId, filter, sort, queryParams
    )
  let dr = ?client.send(b.freeze())
  let both = ?dr.getBoth(handles)
  ok(
    QueryThenGet[AnyEmailSubmission](
      query: ?both.query.fulfil(mnEmailSubmissionQuery),
      get: ?both.get.fulfil(mnEmailSubmissionGet),
    )
  )

# =============================================================================
# Email/set write one-shots (RFC 8621 §4.6)
# =============================================================================

proc runSet(
    client: JmapClient, accountId: AccountId, ids: openArray[Id], update: EmailUpdate
): Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError] =
  ## Shared body of the Email/set write one-shots: seal one ``update``
  ## across every id, dispatch, and collapse the method outcome.
  ## Per-id ``SetError``s stay data on the response (``updateResults``
  ## and the projection iterators) — the rail carries only whole-method
  ## failure, so one rejected email never hides its siblings' results.
  let updateSet = ?initEmailUpdateSet(@[update]).lift
  let items = collect(newSeqOfCap(ids.len)):
    for id in ids:
      (id, updateSet)
  let updates = ?parseNonEmptyEmailUpdates(items).lift
  let (b, handle) =
    client.newBuilder().addEmailSet(accountId, update = Opt.some(updates))
  let dr = ?client.send(b.freeze())
  (?dr.get(handle)).fulfil(mnEmailSet)

proc markEmailsRead*(
    client: JmapClient, accountId: AccountId, ids: openArray[Id]
): Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError] =
  ## Sets ``$seen`` on every id in one ``Email/set``. Empty or duplicate
  ## ids reject at the seal (the update set demands distinct, non-empty
  ## targets), so an empty call never reaches the network.
  runSet(client, accountId, ids, markRead())

proc markEmailsUnread*(
    client: JmapClient, accountId: AccountId, ids: openArray[Id]
): Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError] =
  ## Removes ``$seen`` from every id in one ``Email/set``.
  runSet(client, accountId, ids, markUnread())

proc moveEmails*(
    client: JmapClient, accountId: AccountId, ids: openArray[Id], mailboxId: Id
): Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError] =
  ## Moves every id to ``mailboxId`` — a full mailbox-membership replace,
  ## because "move" means the email is in the destination and nowhere
  ## else. Callers wanting additive membership use the builder path's
  ## ``addToMailbox`` update instead. Empty or duplicate ids reject at
  ## the seal (the update set demands distinct, non-empty targets), so
  ## an empty call never reaches the network.
  runSet(client, accountId, ids, moveToMailbox(mailboxId))

proc destroyEmails*(
    client: JmapClient, accountId: AccountId, ids: openArray[Id]
): Result[SetResponse[EmailCreatedItem, PartialEmail], JmapError] =
  ## Destroys every id in one ``Email/set``. Per-id refusals stay data
  ## (``destroyFailures``); the rail carries whole-method failure only.
  ## An empty ids list is legal wire and destroys nothing — the call
  ## still round-trips.
  let (b, handle) = client.newBuilder().addEmailSet(accountId, destroy = directIds(ids))
  let dr = ?client.send(b.freeze())
  (?dr.get(handle)).fulfil(mnEmailSet)

# =============================================================================
# VacationResponse/set write one-shot (RFC 8621 §8)
# =============================================================================

proc setVacationResponse*(
    client: JmapClient, accountId: AccountId, updates: openArray[VacationResponseUpdate]
): Result[SetResponse[NoCreate, PartialVacationResponse], JmapError] =
  ## Updates the vacation singleton in one call, folding the update-set
  ## seal (which rejects empty batches, duplicate properties, and a
  ## backwards window) and the dispatch ceremony. The singleton id is
  ## the library's concern, not the caller's.
  let updateSet = ?initVacationResponseUpdateSet(updates).lift
  let (b, handle) = client.newBuilder().addVacationResponseSet(accountId, updateSet)
  let dr = ?client.send(b.freeze())
  (?dr.get(handle)).fulfil(mnVacationResponseSet)

# =============================================================================
# sendPlainText — create a draft and submit it, moving it to Sent on success
# (RFC 8621 §7.5/§7.5.1, RFC 8620 §5.3/§5.4)
# =============================================================================

type SendMailboxes* {.ruleOff: "objects".} = object
  ## The Drafts and Sent mailboxes for a send: the draft is created in ``drafts``
  ## and, on a successful submission, moved to ``sent`` (RFC 8621 §7.5.1).
  drafts*: Id
  sent*: Id

type PlainTextMessage* {.ruleOff: "objects".} = object
  ## The content of a plain-text message for ``sendPlainText``. Addresses are
  ## strings, parsed onto the rail by ``sendPlainText`` (RFC 5321 envelope +
  ## RFC 8621 §4.1.2 headers). ``cc`` / ``bcc`` default to empty.
  fromAddr*: string
  to*: seq[string]
  subject*: string
  body*: string
  cc*: seq[string]
  bcc*: seq[string]

type SentEmail* = object
  ## Server-assigned ids from a successful ``sendPlainText`` — the sent message
  ## and its EmailSubmission record (RFC 8621 §7.5).
  emailId*: Id ## the sent message (the server's best-effort move files it in Sent)
  submissionId*: Id ## the EmailSubmission record

func emailAddrList(addrs: seq[string]): Result[Opt[seq[EmailAddress]], JmapError] =
  ## Parses a header address list (To/Cc/Bcc). An empty list is ``Opt.none`` —
  ## the single "header absent" representation (RFC 8621 §4.1.2.3).
  if addrs.len == 0:
    return ok(Opt.none(seq[EmailAddress]))
  var parsed: seq[EmailAddress] = @[]
  for a in addrs:
    parsed.add ?parseEmailAddress(a).lift
  ok(Opt.some(parsed))

func submissionAddress(raw: string): Result[SubmissionAddress, JmapError] =
  ## Parses one envelope address (RFC 5321 Mailbox, RFC 8621 §7 envelope), with
  ## no SMTP Mail/Rcpt parameters.
  let mb = ?parseRFC5321Mailbox(raw).lift
  ok(SubmissionAddress(mailbox: mb, parameters: Opt.none(SubmissionParams)))

func buildEnvelope(
    fromAddr: string, recipients: seq[string]
): Result[Envelope, JmapError] =
  ## Builds the RFC 8621 §7 envelope: ``mailFrom`` is the sender's reverse path,
  ## ``rcptTo`` the union of the To/Cc/Bcc recipients (non-empty by type).
  let fromSa = ?submissionAddress(fromAddr)
  var rcpts: seq[SubmissionAddress] = @[]
  for r in recipients:
    rcpts.add ?submissionAddress(r)
  let rcptList = ?parseNonEmptyRcptList(rcpts).lift
  ok(Envelope(mailFrom: reversePath(fromSa), rcptTo: rcptList))

func buildDraftBlueprint(
    draftMailbox: Id, message: PlainTextMessage
): Result[EmailBlueprint, JmapError] =
  ## Builds the draft Email filed in Drafts with the ``$draft`` keyword and a
  ## single inline text/plain body (RFC 8621 §4.6, §7.5.1).
  let mboxIds = ?parseNonEmptyMailboxIdSet(@[draftMailbox]).lift
  let fromA = ?parseEmailAddress(message.fromAddr).lift
  let toList = ?emailAddrList(message.to)
  let ccList = ?emailAddrList(message.cc)
  let bccList = ?emailAddrList(message.bcc)
  let bp = ?parseEmailBlueprint(
    mailboxIds = mboxIds,
    body = plainTextBody(message.body),
    keywords = initKeywordSet(@[kwDraft]),
    fromAddr = Opt.some(@[fromA]),
    to = toList,
    cc = ccList,
    bcc = bccList,
    subject = Opt.some(message.subject),
  ).lift
  ok(bp)

func buildSubmissionBlueprint(
    identityId: Id, draftCid: CreationId, message: PlainTextMessage
): Result[EmailSubmissionBlueprint, JmapError] =
  ## Builds the submission referencing the draft created in the same /set via a
  ## creation reference (RFC 8620 §5.3), with the §7 envelope.
  let env = ?buildEnvelope(message.fromAddr, message.to & message.cc & message.bcc)
  let bp = ?parseEmailSubmissionBlueprint(
    identityId = identityId, emailId = creationRef(draftCid), envelope = Opt.some(env)
  ).lift
  ok(bp)

func buildSendSpec(
    subCid: CreationId, subBp: EmailSubmissionBlueprint, mailboxes: SendMailboxes
): Result[EmailSubmissionSetSpec, JmapError] =
  ## Builds the EmailSubmission/set spec whose ``onSuccessUpdateEmail`` (keyed
  ## by the submission's creation reference) moves the draft out of Drafts into
  ## Sent and drops ``$draft`` once the send succeeds (RFC 8621 §7.5 ¶3).
  let upd = ?initEmailUpdateSet(
    @[
      removeFromMailbox(mailboxes.drafts),
      addToMailbox(mailboxes.sent),
      removeKeyword(kwDraft),
    ]
  ).lift
  let onSucc = ?parseNonEmptyOnSuccessUpdateEmail(@[(creationRef(subCid), upd)]).lift
  var subCreate = initTable[CreationId, EmailSubmissionBlueprint]()
  subCreate[subCid] = subBp
  parseEmailSubmissionSet(
    create = Opt.some(subCreate), onSuccessUpdateEmail = Opt.some(onSucc)
  ).lift

func readCreatedId[T](
    created: Table[CreationId, Result[T, SetError]],
    cid: CreationId,
    methodName: MethodName,
    callId: MethodCallId,
): Result[Id, JmapError] =
  ## Reads the server-assigned id for ``cid`` from a /set ``created`` map. A
  ## create the server refused with a typed SetError (RFC 8620 §5.3) collapses
  ## onto the jeSet rail (the typed reason survives); a create absent from both
  ## the created and notCreated rails is a malformed response.
  created.withValue(cid, entry):
    let item = entry.valueOr:
      # The create key is present on the notCreated rail with a typed SetError;
      # a single-create one-shot lifts that reason onto jeSet (RFC 8620 §5.3).
      return err(jmapSet(setFault(methodName, error)))
    return ok(item.id)
  do:
    # The create key the request named is absent from the response (RFC 8620
    # §5.3 obliges the server to report every requested create on one rail).
    return err(jmapProtocol(protocolMissingCall(callId)))

proc sendPlainText*(
    client: JmapClient,
    accountId: AccountId,
    identityId: Id,
    mailboxes: SendMailboxes,
    message: PlainTextMessage,
): Result[SentEmail, JmapError] =
  ## One-call plain-text send (RFC 8621 §7.5.1). In a single request: create a
  ## draft in ``mailboxes.drafts`` with the ``$draft`` keyword and an inline
  ## text/plain body, then submit it from ``identityId``; on success the server
  ## moves the message into ``mailboxes.sent`` and drops ``$draft`` (RFC 8621
  ## §7.5 ¶3, RFC 8620 §5.3/§5.4). Addresses are taken as strings and parsed
  ## internally onto the rail — ``message.fromAddr``/``to``/``cc``/``bcc``
  ## populate the Email headers, and their RFC 5321 forms populate the
  ## submission envelope.
  let draftCid = ?parseCreationId("draft").lift
  let subCid = ?parseCreationId("sub").lift
  let draftBp = ?buildDraftBlueprint(mailboxes.drafts, message)
  let subBp = ?buildSubmissionBlueprint(identityId, draftCid, message)
  let spec = ?buildSendSpec(subCid, subBp, mailboxes)

  var emailCreate = initTable[CreationId, EmailBlueprint]()
  emailCreate[draftCid] = draftBp
  let (b1, emailHandle) =
    client.newBuilder().addEmailSet(accountId, create = Opt.some(emailCreate))
  let (b2, subHandles) = b1.addEmailSubmissionSet(accountId, spec)

  let dr = ?client.send(b2.freeze())
  let emailOut = ?(?dr.get(emailHandle)).fulfil(mnEmailSet)
  # The onSuccessUpdateEmail Drafts -> Sent move is a server-side best-effort
  # step (RFC 8621 §7.5 ¶3) whose implicit Email/set response the one-shot does
  # not consume; only the primary EmailSubmission/set outcome gates success.
  let subSet = ?(?dr.get(subHandles.primary)).fulfil(mnEmailSubmissionSet)

  let emailId =
    ?readCreatedId(emailOut.createResults, draftCid, mnEmailSet, callId(emailHandle))
  let submissionId = ?readCreatedId(
    subSet.createResults, subCid, mnEmailSubmissionSet, callId(subHandles.primary)
  )
  ok(SentEmail(emailId: emailId, submissionId: submissionId))
