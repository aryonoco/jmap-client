# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## EmailBlueprint creation aggregate (RFC 8621 §4.6). The creation-model
## counterpart to ``Email``: a validated payload ready for ``Email/set``.
## Provides the smart constructor ``parseEmailBlueprint`` with an
## accumulating error rail, the error triad
## (``EmailBlueprintConstraint`` / ``EmailBlueprintError`` /
## ``EmailBlueprintErrors``), the body-shape case object
## ``EmailBlueprintBody``, body-part locator types
## (``BodyPartLocation`` / ``BodyPartPath``), Pattern A sealed accessors,
## and the derived ``bodyValues`` accessor. Layer 1 — pure and total.

{.push raises: [], noSideEffect.}

import std/hashes
import std/sets
import std/tables

import ../primitives
import ../identifiers
import ../validation
import ./addresses
import ./body
import ./headers
import ./keyword
import ./mailbox

# =============================================================================
# BodyPartPath
# =============================================================================

type BodyPartPath* = distinct seq[int]
  ## Zero-indexed tree path locating a ``BlueprintBodyPart`` within an
  ## ``EmailBlueprintBody``. For ``ebkStructured`` the path walks the
  ## ``bodyStructure`` subParts tree from the root. For ``ebkFlat`` the
  ## first index is 0 (textBody), 1 (htmlBody), or 2+i (attachments[i]);
  ## subsequent indices walk sub-parts of that entry.

func `==`*(a, b: BodyPartPath): bool {.borrow.}
  ## Element-wise equality delegated to the underlying seq.

func `$`*(a: BodyPartPath): string {.borrow.}
  ## String representation delegated to the underlying seq.

func hash*(a: BodyPartPath): Hash {.borrow.} ## Hash delegated to the underlying seq.

func len*(a: BodyPartPath): int {.borrow.}
  ## Length delegated to the underlying seq (may be zero for the root path).

func `[]`*(a: BodyPartPath, i: Natural): int =
  ## Indexed access into the path. Explicit unwrap because indexing
  ## through ``{.borrow.}`` hits ``ArrGet`` (compiler magic).
  seq[int](a)[i]

iterator items*(a: BodyPartPath): int =
  ## Yields each index in the path.
  for x in seq[int](a):
    yield x

iterator pairs*(a: BodyPartPath): (int, int) =
  ## Yields (position, index) tuples.
  for p in pairs(seq[int](a)):
    yield p

# =============================================================================
# BodyPartLocation
# =============================================================================

type BodyPartLocationKind* = enum
  ## Discriminant for ``BodyPartLocation``: names the identifier axis
  ## used to locate a body part (inline / blob-ref / multipart).
  bplInline ## Located by partId (inline leaf).
  bplBlobRef ## Located by blobId (uploaded-blob leaf).
  bplMultipart ## Located by tree path (multipart container, no identifier).

type BodyPartLocation* = object
  ## Names the ``BlueprintBodyPart`` at which a constraint was violated.
  ## Discriminant mirrors Part C's body-part structure: leaves carry their
  ## own identifier; multipart containers carry only a tree path.
  case kind*: BodyPartLocationKind
  of bplInline:
    partId*: PartId
  of bplBlobRef:
    blobId*: BlobId
  of bplMultipart:
    path*: BodyPartPath

func `==`*(a, b: BodyPartLocation): bool =
  ## Hand-rolled equality: auto-``==`` uses a parallel ``fields`` iterator
  ## that refuses case objects. Discriminant-first, then variant-specific.
  if a.kind != b.kind:
    return false
  case a.kind
  of bplInline:
    a.partId == b.partId
  of bplBlobRef:
    a.blobId == b.blobId
  of bplMultipart:
    a.path == b.path

# =============================================================================
# EmailBlueprintConstraint / EmailBlueprintError
# =============================================================================

type EmailBlueprintConstraint* = enum
  ## Runtime constraint-violation variants for ``parseEmailBlueprint``.
  ## Three "HeaderDuplicate" variants cover RFC §4.6's three cross-axis
  ## duplicate rules (Email top-level, bodyStructure root ↔ top-level,
  ## within-body-part). Within-extraHeaders duplicates and key/value
  ## form-mismatch are type-level and have no runtime variant.
  ebcEmailTopLevelHeaderDuplicate
  ebcBodyStructureHeaderDuplicate
  ebcBodyPartHeaderDuplicate
  ebcTextBodyNotTextPlain
  ebcHtmlBodyNotTextHtml
  ebcAllowedFormRejected
  ebcBodyPartDepthExceeded

type EmailBlueprintError* = object
  ## A single constraint violation. Payload fields are variant-specific:
  ## the discriminant selects which field carries the failing-input
  ## information.
  case constraint*: EmailBlueprintConstraint
  of ebcEmailTopLevelHeaderDuplicate:
    dupName*: string ## Lowercase header name duplicated across top level.
  of ebcBodyStructureHeaderDuplicate:
    bodyStructureDupName*: string
      ## Lowercase header name on bodyStructure root duplicating top-level.
  of ebcBodyPartHeaderDuplicate:
    where*: BodyPartLocation ## Which body-part in the tree.
    bodyPartDupName*: string ## Lowercase domain-field header name duplicated.
  of ebcTextBodyNotTextPlain:
    actualTextType*: string ## Observed contentType on textBody leaf.
  of ebcHtmlBodyNotTextHtml:
    actualHtmlType*: string ## Observed contentType on htmlBody leaf.
  of ebcAllowedFormRejected:
    rejectedName*: string ## Lowercase header name whose form is disallowed.
    rejectedForm*: HeaderForm ## The form that isn't permitted for this name.
  of ebcBodyPartDepthExceeded:
    observedDepth*: int ## Depth of the first subtree exceeding ``MaxBodyPartDepth``.
    depthLocation*: BodyPartLocation ## Location of the offending subtree root.

func `==`*(a, b: EmailBlueprintError): bool =
  ## Hand-rolled equality for the case object. Discriminant first, then
  ## variant-specific payload fields. Required because Nim's auto-``==``
  ## relies on a parallel ``fields`` iterator that cannot traverse case
  ## objects (same rationale as ``BodyPartLocation.==``).
  if a.constraint != b.constraint:
    return false
  case a.constraint
  of ebcEmailTopLevelHeaderDuplicate:
    a.dupName == b.dupName
  of ebcBodyStructureHeaderDuplicate:
    a.bodyStructureDupName == b.bodyStructureDupName
  of ebcBodyPartHeaderDuplicate:
    a.where == b.where and a.bodyPartDupName == b.bodyPartDupName
  of ebcTextBodyNotTextPlain:
    a.actualTextType == b.actualTextType
  of ebcHtmlBodyNotTextHtml:
    a.actualHtmlType == b.actualHtmlType
  of ebcAllowedFormRejected:
    a.rejectedName == b.rejectedName and a.rejectedForm == b.rejectedForm
  of ebcBodyPartDepthExceeded:
    a.observedDepth == b.observedDepth and a.depthLocation == b.depthLocation

# =============================================================================
# EmailBlueprintErrors (sealed — Pattern A)
# =============================================================================

type EmailBlueprintErrors* {.ruleOff: "objects".} = object
  ## Aggregate of constraint violations carried on the ``err`` rail of
  ## ``parseEmailBlueprint``. Pattern A sealed: the underlying seq is
  ## module-private so the only construction path is
  ## ``parseEmailBlueprint``; callers observe read-only via the
  ## ``len`` / ``items`` / ``pairs`` / ``[]`` / ``==`` / ``$`` surface.
  ## Non-empty whenever carried on the error rail — enforced by the
  ## constructor (empty seq would mean "no errors", which is the ok
  ## rail's job).
  errors: seq[EmailBlueprintError]

func len*(e: EmailBlueprintErrors): int =
  ## Number of constraint violations. Always ≥ 1 on the err rail.
  e.errors.len

iterator items*(e: EmailBlueprintErrors): EmailBlueprintError =
  ## Yields each error in insertion order.
  for x in e.errors:
    yield x

iterator pairs*(e: EmailBlueprintErrors): (int, EmailBlueprintError) =
  ## Yields (index, error) tuples in insertion order.
  for p in e.errors.pairs:
    yield p

func `[]`*(e: EmailBlueprintErrors, i: Natural): EmailBlueprintError =
  ## Indexed access into the aggregate. Out-of-range raises
  ## ``IndexDefect`` (a ``Defect``, not a ``CatchableError``).
  e.errors[i]

func `==`*(a, b: EmailBlueprintErrors): bool =
  ## Ordered element-wise equality. Delegates to the underlying seq.
  a.errors == b.errors

func `$`*(e: EmailBlueprintErrors): string =
  ## Delegates to ``$seq[EmailBlueprintError]``. Fine for diagnostics;
  ## structured rendering is the caller's responsibility.
  $e.errors

func capacity*(e: EmailBlueprintErrors): int {.inline.} =
  ## Underlying seq capacity — exposed for amortised-growth regression
  ## gates (Step 22 scenarios 101a, 101c). Reads through the sealed
  ## container without exposing a mutable handle.
  e.errors.capacity

# =============================================================================
# message — bounded, NUL-stripped rendering
# =============================================================================

func clipForMessage(s: string, max: int = 512): string =
  ## Renders a user-provided payload string into a bounded, FFI- and
  ## log-safe form: truncates to ``max`` bytes and replaces each NUL byte
  ## with the literal escape ``\x00``. Each ``message`` invocation
  ## composes at most six clipped slots, keeping the total well within
  ## the 8 KiB budget that scenario 11b audits.
  var buf = newStringOfCap(min(s.len, max) + 8)
  let limit = min(s.len, max)
  for i in 0 ..< limit:
    if s[i] == '\x00':
      buf.add("\\x00")
    else:
      buf.add(s[i])
  if s.len > max:
    buf.add("...")
  buf

func message*(e: EmailBlueprintError): string =
  ## Human-readable rendering, derived from the (constraint, payload)
  ## pair. All user-provided payload slots pass through
  ## ``clipForMessage`` so the output is bounded and free of NUL bytes
  ## regardless of caller inputs.
  case e.constraint
  of ebcEmailTopLevelHeaderDuplicate:
    "duplicate header representation at Email top level: convenience " &
      "field and extraHeaders entry for " & clipForMessage(e.dupName) &
      " cannot both be set"
  of ebcBodyStructureHeaderDuplicate:
    "bodyStructure root extraHeaders entry for " & clipForMessage(
      e.bodyStructureDupName
    ) & " duplicates a header already defined on the Email top level"
  of ebcBodyPartHeaderDuplicate:
    "body part carries duplicate representations of header " &
      clipForMessage(e.bodyPartDupName) & " (domain field and extraHeaders entry)"
  of ebcTextBodyNotTextPlain:
    "ebkFlat textBody must be text/plain; found " & clipForMessage(e.actualTextType)
  of ebcHtmlBodyNotTextHtml:
    "ebkFlat htmlBody must be text/html; found " & clipForMessage(e.actualHtmlType)
  of ebcAllowedFormRejected:
    "header form " & $e.rejectedForm & " not allowed for header name " &
      clipForMessage(e.rejectedName)
  of ebcBodyPartDepthExceeded:
    "body part tree depth " & $e.observedDepth & " exceeds maximum " & $MaxBodyPartDepth

# =============================================================================
# EmailBlueprintBody
# =============================================================================

type EmailBodyKind* = enum
  ## Discriminant for ``EmailBlueprintBody``: encodes the
  ## "bodyStructure XOR flat-list" choice at the type level.
  ebkStructured ## Client provides full ``bodyStructure`` tree.
  ebkFlat ## Client provides ``textBody`` / ``htmlBody`` / ``attachments``.

type EmailBlueprintBody* = object
  ## The body-shape carrier: a case object whose discriminant encodes
  ## the "bodyStructure XOR flat-list" choice at the type level.
  ## Public fields on both variants — the case discriminant is the seal;
  ## there are no further invariants to defend here.
  case kind*: EmailBodyKind
  of ebkStructured:
    bodyStructure*: BlueprintBodyPart
  of ebkFlat:
    textBody*: Opt[BlueprintBodyPart] ## At most one text/plain leaf.
    htmlBody*: Opt[BlueprintBodyPart] ## At most one text/html leaf.
    attachments*: seq[BlueprintBodyPart] ## Zero or more attachments.

func flatBody*(
    textBody: Opt[BlueprintBodyPart] = Opt.none(BlueprintBodyPart),
    htmlBody: Opt[BlueprintBodyPart] = Opt.none(BlueprintBodyPart),
    attachments: seq[BlueprintBodyPart] = @[],
): EmailBlueprintBody =
  ## Total constructor for the flat-list body variant. Defaults to an
  ## empty flat body (no text, no html, no attachments) — a valid state.
  EmailBlueprintBody(
    kind: ebkFlat, textBody: textBody, htmlBody: htmlBody, attachments: attachments
  )

func structuredBody*(bodyStructure: BlueprintBodyPart): EmailBlueprintBody =
  ## Total constructor for the structured body variant. The caller is
  ## responsible for the tree shape; only content-type and header
  ## duplicate rules are checked by ``parseEmailBlueprint``.
  EmailBlueprintBody(kind: ebkStructured, bodyStructure: bodyStructure)

# =============================================================================
# EmailBlueprint (aggregate — Pattern A sealed)
# =============================================================================

type EmailBlueprint* {.ruleOff: "objects".} = object
  ## The Email creation aggregate. Fields are module-private with a
  ## ``raw*`` prefix; construction is gated by ``parseEmailBlueprint``
  ## and access is via same-name UFCS accessors (§3.5). Direct brace
  ## construction outside this module is a compile error — Pattern A
  ## sealing forces the smart constructor to be the sole boundary.
  rawMailboxIds: NonEmptyMailboxIdSet
  rawKeywords: KeywordSet
  rawReceivedAt: Opt[UTCDate]
  rawFromAddr: Opt[seq[EmailAddress]]
  rawTo: Opt[seq[EmailAddress]]
  rawCc: Opt[seq[EmailAddress]]
  rawBcc: Opt[seq[EmailAddress]]
  rawReplyTo: Opt[seq[EmailAddress]]
  rawSender: Opt[EmailAddress]
  rawSubject: Opt[string]
  rawSentAt: Opt[Date]
  rawMessageId: Opt[seq[string]]
  rawInReplyTo: Opt[seq[string]]
  rawReferences: Opt[seq[string]]
  rawExtraHeaders: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]
  rawBody: EmailBlueprintBody

# =============================================================================
# Validation helpers — private, decomposed for nimalyzer complexity
# =============================================================================

func checkFlatBodyContentTypes(body: EmailBlueprintBody): seq[EmailBlueprintError] =
  ## Constraint 5a/5b: flat-list textBody is text/plain, htmlBody is text/html.
  result = @[]
  if body.kind != ebkFlat:
    return
  for tb in body.textBody:
    if tb.contentType != "text/plain":
      result.add EmailBlueprintError(
        constraint: ebcTextBodyNotTextPlain, actualTextType: tb.contentType
      )
  for hb in body.htmlBody:
    if hb.contentType != "text/html":
      result.add EmailBlueprintError(
        constraint: ebcHtmlBodyNotTextHtml, actualHtmlType: hb.contentType
      )

func addAddressConvenienceNames(bp: EmailBlueprint, s: var HashSet[string]) =
  ## Adds lowercase header names for the six RFC 5322 address
  ## convenience fields that are ``Opt.some``.
  if bp.rawFromAddr.isSome:
    s.incl("from")
  if bp.rawTo.isSome:
    s.incl("to")
  if bp.rawCc.isSome:
    s.incl("cc")
  if bp.rawBcc.isSome:
    s.incl("bcc")
  if bp.rawReplyTo.isSome:
    s.incl("reply-to")
  if bp.rawSender.isSome:
    s.incl("sender")

func addScalarConvenienceNames(bp: EmailBlueprint, s: var HashSet[string]) =
  ## Adds lowercase header names for the five non-address convenience
  ## fields that are ``Opt.some``.
  if bp.rawSubject.isSome:
    s.incl("subject")
  if bp.rawSentAt.isSome:
    s.incl("date")
  if bp.rawMessageId.isSome:
    s.incl("message-id")
  if bp.rawInReplyTo.isSome:
    s.incl("in-reply-to")
  if bp.rawReferences.isSome:
    s.incl("references")

func topLevelHeaderNames(bp: EmailBlueprint): HashSet[string] =
  ## Set of lowercase header names implied by the Email top level:
  ## every populated convenience field plus every ``extraHeaders`` key.
  ## Decomposed into two halves to stay under the nimalyzer complexity
  ## budget.
  result = initHashSet[string]()
  addAddressConvenienceNames(bp, result)
  addScalarConvenienceNames(bp, result)
  for k in bp.rawExtraHeaders.keys:
    result.incl(string(k))

func domainHeaderNames(part: BlueprintBodyPart): HashSet[string] =
  ## Set of lowercase header names implied by this body part's domain
  ## fields. ``contentType`` is unconditional (non-optional string);
  ## ``charset`` folds into ``content-type`` so it adds no new name.
  result = initHashSet[string]()
  result.incl("content-type")
  if part.name.isSome or part.disposition.isSome:
    result.incl("content-disposition")
  if part.cid.isSome:
    result.incl("content-id")
  if part.language.isSome:
    result.incl("content-language")
  if part.location.isSome:
    result.incl("content-location")

func dupError(hdr: string): EmailBlueprintError =
  ## Constructs an ``ebcEmailTopLevelHeaderDuplicate`` error for the
  ## given lowercase header name.
  EmailBlueprintError(constraint: ebcEmailTopLevelHeaderDuplicate, dupName: hdr)

func addDupIf(
    present: bool,
    hdr: string,
    extraKeys: HashSet[string],
    acc: var seq[EmailBlueprintError],
) =
  ## Appends a dup error iff ``present`` AND ``hdr`` is in ``extraKeys``.
  ## Factored out so each convenience-field check is a single function
  ## call at the call-site (no branch) rather than a conditional —
  ## keeps the dispatcher helpers under the nimalyzer complexity budget.
  if present and hdr in extraKeys:
    acc.add dupError(hdr)

func addAddressTopLevelDups(
    bp: EmailBlueprint, extraKeys: HashSet[string], acc: var seq[EmailBlueprintError]
) =
  ## Emits one ``ebcEmailTopLevelHeaderDuplicate`` for each address
  ## convenience field that collides with an ``extraHeaders`` key.
  addDupIf(bp.rawFromAddr.isSome, "from", extraKeys, acc)
  addDupIf(bp.rawTo.isSome, "to", extraKeys, acc)
  addDupIf(bp.rawCc.isSome, "cc", extraKeys, acc)
  addDupIf(bp.rawBcc.isSome, "bcc", extraKeys, acc)
  addDupIf(bp.rawReplyTo.isSome, "reply-to", extraKeys, acc)
  addDupIf(bp.rawSender.isSome, "sender", extraKeys, acc)

func addScalarTopLevelDups(
    bp: EmailBlueprint, extraKeys: HashSet[string], acc: var seq[EmailBlueprintError]
) =
  ## Emits one ``ebcEmailTopLevelHeaderDuplicate`` for each non-address
  ## convenience field that collides with an ``extraHeaders`` key.
  addDupIf(bp.rawSubject.isSome, "subject", extraKeys, acc)
  addDupIf(bp.rawSentAt.isSome, "date", extraKeys, acc)
  addDupIf(bp.rawMessageId.isSome, "message-id", extraKeys, acc)
  addDupIf(bp.rawInReplyTo.isSome, "in-reply-to", extraKeys, acc)
  addDupIf(bp.rawReferences.isSome, "references", extraKeys, acc)

func checkEmailTopLevelDuplicates(bp: EmailBlueprint): seq[EmailBlueprintError] =
  ## Constraint 3a: convenience-field ↔ extraHeaders name collision.
  ## Emits one error per collision; order mirrors convenience-field
  ## declaration order. Decomposed into address / scalar halves to
  ## stay under the nimalyzer complexity budget.
  result = @[]
  var extraKeys = initHashSet[string]()
  for k in bp.rawExtraHeaders.keys:
    extraKeys.incl(string(k))
  addAddressTopLevelDups(bp, extraKeys, result)
  addScalarTopLevelDups(bp, extraKeys, result)

func checkBodyStructureDuplicates(bp: EmailBlueprint): seq[EmailBlueprintError] =
  ## Constraint 3b: bodyStructure root's extraHeaders cannot duplicate
  ## any Email top-level header (convenience or extraHeaders). Scope is
  ## ROOT only — sub-parts are covered by 3c.
  result = @[]
  if bp.rawBody.kind != ebkStructured:
    return
  let topNames = topLevelHeaderNames(bp)
  for k in bp.rawBody.bodyStructure.extraHeaders.keys:
    let name = string(k)
    if name in topNames:
      result.add EmailBlueprintError(
        constraint: ebcBodyStructureHeaderDuplicate, bodyStructureDupName: name
      )

func locationOf(part: BlueprintBodyPart, path: seq[int]): BodyPartLocation =
  ## Computes the ``BodyPartLocation`` for a part at the given path.
  ## Multipart containers are located by path; leaves carry their
  ## identifier directly.
  if part.isMultipart:
    return BodyPartLocation(kind: bplMultipart, path: BodyPartPath(path))
  case part.source
  of bpsInline:
    BodyPartLocation(kind: bplInline, partId: part.partId)
  of bpsBlobRef:
    BodyPartLocation(kind: bplBlobRef, blobId: part.blobId)

func walkBodyPartDuplicates(
    part: BlueprintBodyPart, path: seq[int]
): seq[EmailBlueprintError] =
  ## Constraint 3c: walks the subtree rooted at ``part``, emitting one
  ## ``ebcBodyPartHeaderDuplicate`` per extraHeaders entry that collides
  ## with the part's own domain-field header set.
  result = @[]
  let domainNames = domainHeaderNames(part)
  for k in part.extraHeaders.keys:
    let name = string(k)
    if name in domainNames:
      result.add EmailBlueprintError(
        constraint: ebcBodyPartHeaderDuplicate,
        where: locationOf(part, path),
        bodyPartDupName: name,
      )
  if part.isMultipart:
    for i, child in part.subParts:
      result.add walkBodyPartDuplicates(child, path & @[i])

func checkBodyPartDuplicates(body: EmailBlueprintBody): seq[EmailBlueprintError] =
  ## Dispatches the tree walk: ebkStructured starts at the root with an
  ## empty path; ebkFlat wraps textBody at [0], htmlBody at [1], and
  ## attachments[i] at [2+i], each walked recursively.
  result = @[]
  case body.kind
  of ebkStructured:
    result.add walkBodyPartDuplicates(body.bodyStructure, @[])
  of ebkFlat:
    for tb in body.textBody:
      result.add walkBodyPartDuplicates(tb, @[0])
    for hb in body.htmlBody:
      result.add walkBodyPartDuplicates(hb, @[1])
    for i, att in body.attachments:
      result.add walkBodyPartDuplicates(att, @[2 + i])

func checkTopLevelAllowedForms(bp: EmailBlueprint): seq[EmailBlueprintError] =
  ## Constraint 7 at the Email top level: each ``extraHeaders`` entry's
  ## form must be permitted for its header name per ``allowedForms``.
  result = @[]
  for k, v in bp.rawExtraHeaders:
    let name = string(k)
    if v.form notin allowedForms(name):
      result.add EmailBlueprintError(
        constraint: ebcAllowedFormRejected, rejectedName: name, rejectedForm: v.form
      )

func walkBodyTreeAllowedForms(part: BlueprintBodyPart): seq[EmailBlueprintError] =
  ## Recursively applies constraint 7 to a body-part subtree. Emits one
  ## ``ebcAllowedFormRejected`` per disallowed (name, form) pair.
  result = @[]
  for k, v in part.extraHeaders:
    let name = string(k)
    if v.form notin allowedForms(name):
      result.add EmailBlueprintError(
        constraint: ebcAllowedFormRejected, rejectedName: name, rejectedForm: v.form
      )
  if part.isMultipart:
    for child in part.subParts:
      result.add walkBodyTreeAllowedForms(child)

func checkBodyTreeAllowedForms(body: EmailBlueprintBody): seq[EmailBlueprintError] =
  ## Dispatches the allowed-form tree walk over the body, mirroring the
  ## duplicate-check dispatcher's structure.
  result = @[]
  case body.kind
  of ebkStructured:
    result.add walkBodyTreeAllowedForms(body.bodyStructure)
  of ebkFlat:
    for tb in body.textBody:
      result.add walkBodyTreeAllowedForms(tb)
    for hb in body.htmlBody:
      result.add walkBodyTreeAllowedForms(hb)
    for att in body.attachments:
      result.add walkBodyTreeAllowedForms(att)

func walkBodyPartDepth(
    part: BlueprintBodyPart, depth: int, path: seq[int]
): seq[EmailBlueprintError] =
  ## Recurses through ``part.subParts`` carrying the current ancestor-count
  ## depth (root = 0). When ``depth`` exceeds ``MaxBodyPartDepth`` one error
  ## is emitted for the offending subtree root and recursion halts there —
  ## a 1000-leaf subtree at depth 130 reports once, not 1000 times.
  result = @[]
  if depth > MaxBodyPartDepth:
    result.add EmailBlueprintError(
      constraint: ebcBodyPartDepthExceeded,
      observedDepth: depth,
      depthLocation: locationOf(part, path),
    )
    return
  if part.isMultipart:
    for i, child in part.subParts:
      result.add walkBodyPartDepth(child, depth + 1, path & @[i])

func checkBodyPartDepth(body: EmailBlueprintBody): seq[EmailBlueprintError] =
  ## Enforces ``MaxBodyPartDepth`` as a construction-time invariant on the
  ## body tree. Each entry point (bodyStructure root, or one of textBody /
  ## htmlBody / each attachment in ebkFlat) starts with depth 0.
  result = @[]
  case body.kind
  of ebkStructured:
    result.add walkBodyPartDepth(body.bodyStructure, 0, @[])
  of ebkFlat:
    for tb in body.textBody:
      result.add walkBodyPartDepth(tb, 0, @[0])
    for hb in body.htmlBody:
      result.add walkBodyPartDepth(hb, 0, @[1])
    for i, att in body.attachments:
      result.add walkBodyPartDepth(att, 0, @[2 + i])

# =============================================================================
# parseEmailBlueprint — smart constructor
# =============================================================================

func parseEmailBlueprint*(
    mailboxIds: NonEmptyMailboxIdSet,
    body: EmailBlueprintBody = flatBody(),
    keywords: KeywordSet = initKeywordSet(@[]),
    receivedAt: Opt[UTCDate] = Opt.none(UTCDate),
    fromAddr: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    to: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    cc: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    bcc: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    replyTo: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    sender: Opt[EmailAddress] = Opt.none(EmailAddress),
    subject: Opt[string] = Opt.none(string),
    sentAt: Opt[Date] = Opt.none(Date),
    messageId: Opt[seq[string]] = Opt.none(seq[string]),
    inReplyTo: Opt[seq[string]] = Opt.none(seq[string]),
    references: Opt[seq[string]] = Opt.none(seq[string]),
    extraHeaders: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue] =
      initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue](),
): Result[EmailBlueprint, EmailBlueprintErrors] =
  ## Accumulating smart constructor: runs every applicable check and
  ## returns ``err(EmailBlueprintErrors)`` carrying every violation,
  ## not the first. A caller with three problems sees all three.
  ##
  ## Signature-level invariants (already guaranteed by input types):
  ##   1  mailboxIds ≥ 1        — ``NonEmptyMailboxIdSet``
  ##   2  no headers array      — field absent
  ##   4  no Content-* top      — ``BlueprintEmailHeaderName``
  ##   5  bodyStructure XOR flat — ``EmailBlueprintBody`` discriminant
  ##   6  flags-false on values — ``BlueprintBodyValue``
  ##   9  no CTE                — ``BlueprintBodyHeaderName``
  let bp = EmailBlueprint(
    rawMailboxIds: mailboxIds,
    rawKeywords: keywords,
    rawReceivedAt: receivedAt,
    rawFromAddr: fromAddr,
    rawTo: to,
    rawCc: cc,
    rawBcc: bcc,
    rawReplyTo: replyTo,
    rawSender: sender,
    rawSubject: subject,
    rawSentAt: sentAt,
    rawMessageId: messageId,
    rawInReplyTo: inReplyTo,
    rawReferences: references,
    rawExtraHeaders: extraHeaders,
    rawBody: body,
  )
  var errs: seq[EmailBlueprintError] = @[]
  errs.add checkFlatBodyContentTypes(body)
  errs.add checkEmailTopLevelDuplicates(bp)
  errs.add checkBodyStructureDuplicates(bp)
  errs.add checkBodyPartDuplicates(body)
  errs.add checkTopLevelAllowedForms(bp)
  errs.add checkBodyTreeAllowedForms(body)
  errs.add checkBodyPartDepth(body)
  if errs.len == 0:
    return ok(bp)
  return err(EmailBlueprintErrors(errors: errs))

# =============================================================================
# UFCS accessors (Pattern A unseal)
# =============================================================================

func mailboxIds*(bp: EmailBlueprint): NonEmptyMailboxIdSet =
  ## Mailbox set; always non-empty by type.
  bp.rawMailboxIds

func keywords*(bp: EmailBlueprint): KeywordSet =
  ## Keyword set; may be empty.
  bp.rawKeywords

func receivedAt*(bp: EmailBlueprint): Opt[UTCDate] =
  ## ``Opt.none`` means "defer to the server's clock" (R2-4).
  bp.rawReceivedAt

func fromAddr*(bp: EmailBlueprint): Opt[seq[EmailAddress]] =
  ## Named ``fromAddr`` because ``from`` is a Nim keyword (R2-2).
  bp.rawFromAddr

func to*(bp: EmailBlueprint): Opt[seq[EmailAddress]] =
  ## To-address list.
  bp.rawTo

func cc*(bp: EmailBlueprint): Opt[seq[EmailAddress]] =
  ## Cc-address list.
  bp.rawCc

func bcc*(bp: EmailBlueprint): Opt[seq[EmailAddress]] =
  ## Bcc-address list.
  bp.rawBcc

func replyTo*(bp: EmailBlueprint): Opt[seq[EmailAddress]] =
  ## Reply-To address list.
  bp.rawReplyTo

func sender*(bp: EmailBlueprint): Opt[EmailAddress] =
  ## Singular per RFC 5322 §3.6.2 (R2-3).
  bp.rawSender

func subject*(bp: EmailBlueprint): Opt[string] =
  ## Subject text.
  bp.rawSubject

func sentAt*(bp: EmailBlueprint): Opt[Date] =
  ## Authored timestamp.
  bp.rawSentAt

func messageId*(bp: EmailBlueprint): Opt[seq[string]] =
  ## Message-Id list.
  bp.rawMessageId

func inReplyTo*(bp: EmailBlueprint): Opt[seq[string]] =
  ## In-Reply-To list.
  bp.rawInReplyTo

func references*(bp: EmailBlueprint): Opt[seq[string]] =
  ## References list.
  bp.rawReferences

func extraHeaders*(
    bp: EmailBlueprint
): Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue] =
  ## Dynamic headers (typed keys forbid Content-* top-level).
  bp.rawExtraHeaders

func body*(bp: EmailBlueprint): EmailBlueprintBody =
  ## Body case object — callers navigate via ``bp.body.kind``.
  bp.rawBody

func bodyKind*(bp: EmailBlueprint): EmailBodyKind =
  ## Convenience pass-through; equivalent to ``bp.body.kind``.
  bp.rawBody.kind

# =============================================================================
# Derived bodyValues accessor
# =============================================================================

func collectInlineValues(
    part: BlueprintBodyPart, acc: var Table[PartId, BlueprintBodyValue]
) =
  ## Walks the body subtree rooted at ``part`` and populates ``acc``
  ## with one ``(partId, value)`` entry per inline leaf. Multipart
  ## containers recurse; blob-ref leaves contribute no entry.
  ## Duplicate partIds across the tree are a documented gap (§7 E30);
  ## ``Table`` insert-last-wins applies here.
  if part.isMultipart:
    for child in part.subParts:
      collectInlineValues(child, acc)
  elif part.source == bpsInline:
    acc[part.partId] = part.value

func bodyValues*(bp: EmailBlueprint): Table[PartId, BlueprintBodyValue] =
  ## Derived accessor: walks the body tree collecting inline-leaf
  ## ``(partId, value)`` entries. One source of truth — ``bodyValues``
  ## IS the tree projected, so the two cannot disagree.
  var acc = initTable[PartId, BlueprintBodyValue]()
  case bp.rawBody.kind
  of ebkStructured:
    collectInlineValues(bp.rawBody.bodyStructure, acc)
  of ebkFlat:
    for tb in bp.rawBody.textBody:
      collectInlineValues(tb, acc)
    for hb in bp.rawBody.htmlBody:
      collectInlineValues(hb, acc)
    for att in bp.rawBody.attachments:
      collectInlineValues(att, acc)
  acc
