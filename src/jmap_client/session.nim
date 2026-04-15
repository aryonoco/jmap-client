# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP Session resource types (RFC 8620 section 2). Account capability entries,
## accounts, URI templates, and the Session aggregate with structural validation.

{.push raises: [], noSideEffect.}

import std/hashes
import std/parseutils
import std/sets
import std/strutils
import std/tables
from std/json import JsonNode

import ./validation
import ./identifiers
import ./capabilities

type AccountCapabilityEntry* = object
  ## Per-account capability data. Flat object storing raw JSON; may evolve to a
  ## case object when typed account-level capabilities are added (e.g. RFC 8621).
  kind*: CapabilityKind ## parsed from URI
  rawUri*: string ## original URI string -- lossless
  data*: JsonNode ## capability-specific properties

type Account* = object
  ## A JMAP account the user has access to (RFC 8620 section 2). Contains a
  ## display name, access flags, and per-account capability information.
  name*: string ## user-friendly display name
  isPersonal*: bool ## true if belongs to authenticated user
  isReadOnly*: bool ## true if entire account is read-only
  accountCapabilities*: seq[AccountCapabilityEntry] ## per-account capability data

type UriPartKind* = enum
  ## Discriminator for ``UriPart``: a literal segment or a variable reference.
  upLiteral
  upVariable

type UriPart* {.ruleOff: "objects".} = object
  ## A single segment of a parsed RFC 6570 Level 1 URI template — either
  ## a literal run of bytes or a ``{name}`` variable reference.
  case kind*: UriPartKind
  of upLiteral:
    text*: string
  of upVariable:
    name*: string ## variable name without braces

type UriTemplate* {.ruleOff: "objects".} = object
  ## RFC 6570 Level 1 URI template parsed once into an alternating
  ## sequence of literal segments and variable references. Sealed:
  ## ``rawParts``, ``rawVariables``, and ``rawSource`` are module-private;
  ## ``parseUriTemplate`` is the only path in. ``rawSource`` preserves
  ## the original text for lossless ``$`` round-trip; ``rawVariables``
  ## supports O(1) ``hasVariable`` lookup.
  rawParts: seq[UriPart]
  rawVariables: HashSet[string]
  rawSource: string

func parts*(t: UriTemplate): seq[UriPart] =
  ## Parsed token sequence. Alternates ``upLiteral`` and ``upVariable``
  ## arms in source order.
  return t.rawParts

func variables*(t: UriTemplate): HashSet[string] =
  ## Set of variable names referenced by the template. Derived at parse
  ## time — O(1) per membership check.
  return t.rawVariables

func `$`*(t: UriTemplate): string =
  ## Byte-for-byte round-trip with the input string accepted by
  ## ``parseUriTemplate``.
  return t.rawSource

func hash*(t: UriTemplate): Hash =
  ## Hash derived from ``rawSource`` — consistent with ``==``.
  return hash(t.rawSource)

func `==`*(a, b: UriTemplate): bool =
  ## Structural equality via raw source comparison. Two parsed
  ## templates are equal iff they round-trip to the same string.
  return a.rawSource == b.rawSource

const CoreCapabilityUri* = "urn:ietf:params:jmap:core"
  ## RFC 8620 §2 canonical URI for the ``urn:ietf:params:jmap:core``
  ## capability. Session synthesises a ``ServerCapability`` with this URI
  ## on every accessor call — the core arm is stored once as a typed
  ## ``CoreCapabilities`` field, not as a case-object entry in the list.

# nimalyzer: Session intentionally has no public fields. Fields are
# module-private to enforce construction via parseSession (which guarantees
# ckCore is present and apiUrl is non-empty). Public accessor funcs below
# provide read access; UFCS makes s.field syntax work unchanged for callers.
type Session* {.ruleOff: "objects".} = object
  ## The JMAP Session resource (RFC 8620 section 2). Contains server
  ## capabilities, user accounts, API endpoint URLs, and session state.
  ## Fields are module-private; external access via UFCS accessor funcs.
  ##
  ## ``rawCore`` stores the RFC-required core capability as typed data
  ## (not a case-object arm) — parseSession extracts it from the input
  ## capability list, so the MUST invariant lifts from a runtime panic
  ## (previous ``raiseAssert`` in ``coreCapabilities``) into the type.
  ## ``rawAdditional`` holds the remaining capabilities; the ``capabilities``
  ## accessor synthesises the core entry on demand for API symmetry and
  ## byte-identical wire serialisation.
  rawCore: CoreCapabilities
  rawAdditional: seq[ServerCapability]
  rawAccounts: Table[AccountId, Account]
  rawPrimaryAccounts: Table[string, AccountId]
  rawUsername: string
  rawApiUrl: string
  rawDownloadUrl: UriTemplate
  rawUploadUrl: UriTemplate
  rawEventSourceUrl: UriTemplate
  rawState: JmapState

func capabilities*(s: Session): seq[ServerCapability] =
  ## Server-level capabilities, core entry synthesised from ``rawCore``
  ## and prepended so the list is RFC-conformant and byte-identical to
  ## the wire format.
  result = @[ServerCapability(rawUri: CoreCapabilityUri, kind: ckCore, core: s.rawCore)]
  for cap in s.rawAdditional:
    result.add(cap)

func accounts*(s: Session): Table[AccountId, Account] =
  ## Accounts keyed by AccountId.
  return s.rawAccounts

func primaryAccounts*(s: Session): Table[string, AccountId] =
  ## Primary accounts keyed by raw capability URI (not CapabilityKind).
  return s.rawPrimaryAccounts

func username*(s: Session): string =
  ## Authenticated username, or empty string if none.
  return s.rawUsername

func apiUrl*(s: Session): string =
  ## URL for JMAP API requests.
  return s.rawApiUrl

func downloadUrl*(s: Session): UriTemplate =
  ## RFC 6570 Level 1 template for blob downloads.
  return s.rawDownloadUrl

func uploadUrl*(s: Session): UriTemplate =
  ## RFC 6570 Level 1 template for uploads.
  return s.rawUploadUrl

func eventSourceUrl*(s: Session): UriTemplate =
  ## RFC 6570 Level 1 template for event source.
  return s.rawEventSourceUrl

func state*(s: Session): JmapState =
  ## Session state token.
  return s.rawState

func findCapability*(
    account: Account, kind: CapabilityKind
): Opt[AccountCapabilityEntry] =
  ## Finds the first account capability matching the given kind.
  for _, entry in account.accountCapabilities:
    if entry.kind == kind:
      return Opt.some(entry)
  return Opt.none(AccountCapabilityEntry)

func findCapabilityByUri*(account: Account, uri: string): Opt[AccountCapabilityEntry] =
  ## Looks up an account capability by its raw URI string. Use this instead of
  ## findCapability when looking up vendor extensions (which all map to ckUnknown
  ## and would be ambiguous via findCapability).
  for _, entry in account.accountCapabilities:
    if entry.rawUri == uri:
      return Opt.some(entry)
  return Opt.none(AccountCapabilityEntry)

func hasCapability*(account: Account, kind: CapabilityKind): bool =
  ## Checks whether the account has a capability of the given kind.
  return account.findCapability(kind).isSome

type UriTemplateViolationKind = enum
  ## Internal structural-failure vocabulary for ``parseUriTemplate``.
  ## Single-site translation to ``ValidationError`` — adding a variant
  ## forces a compile error at ``toValidationError``.
  utkEmpty
  utkUnmatchedOpenBrace
  utkEmptyVariable
  utkInvalidVariableChar

type UriTemplateViolation {.ruleOff: "objects".} = object
  case kind: UriTemplateViolationKind
  of utkEmpty:
    discard
  of utkUnmatchedOpenBrace, utkEmptyVariable:
    position: int
  of utkInvalidVariableChar:
    invalidPosition: int
    badChar: char

func toValidationError(v: UriTemplateViolation, raw: string): ValidationError =
  ## Sole domain-to-wire translator for ``UriTemplateViolation``.
  case v.kind
  of utkEmpty:
    validationError("UriTemplate", "must not be empty", raw)
  of utkUnmatchedOpenBrace:
    validationError("UriTemplate", "unmatched '{' at position " & $v.position, raw)
  of utkEmptyVariable:
    validationError(
      "UriTemplate", "empty variable '{}' at position " & $v.position, raw
    )
  of utkInvalidVariableChar:
    validationError(
      "UriTemplate",
      "invalid variable character '" & $v.badChar & "' at position " & $v.invalidPosition,
      raw,
    )

func isValidVariableChar(c: char): bool =
  ## Conservative RFC 6570 §2.3 varname charset: ASCII alphanumerics plus
  ## underscore. Every JMAP-required variable (``accountId``, ``blobId``,
  ## ``type``, ``name``, ``types``, ``closeafter``, ``ping``) qualifies;
  ## percent-encoded varnames are not used by JMAP templates.
  return c.isAlphaNumeric or c == '_'

func detectInvalidVariableChar(
    name: string, startPos: int
): Result[void, UriTemplateViolation] =
  ## Walks the captured variable name and fires on the first disallowed byte.
  for offset, c in name:
    if not isValidVariableChar(c):
      return err(
        UriTemplateViolation(
          kind: utkInvalidVariableChar, invalidPosition: startPos + offset, badChar: c
        )
      )
  ok()

func parseUriTemplate*(raw: string): Result[UriTemplate, ValidationError] =
  ## Parses an RFC 6570 Level 1 URI template into a token sequence.
  ## Rejects empty input, unmatched ``{``, empty ``{}`` variables, and
  ## variable names containing disallowed characters. Stray ``}`` not
  ## preceded by ``{`` is treated as a literal byte, preserving the
  ## pre-refactor ``replace``-based expander's lenient behaviour.
  if raw.len == 0:
    return err(toValidationError(UriTemplateViolation(kind: utkEmpty), raw))
  var parts: seq[UriPart] = @[]
  var variables = initHashSet[string]()
  var i = 0
  while i < raw.len:
    var literal = ""
    let consumed = parseUntil(raw, literal, '{', i)
    if literal.len > 0:
      parts.add(UriPart(kind: upLiteral, text: literal))
    i += consumed
    if i >= raw.len:
      break
    # positioned at '{'
    let openBrace = i
    inc i
    var name = ""
    let nameConsumed = parseUntil(raw, name, '}', i)
    if i + nameConsumed >= raw.len:
      return err(
        toValidationError(
          UriTemplateViolation(kind: utkUnmatchedOpenBrace, position: openBrace), raw
        )
      )
    if name.len == 0:
      return err(
        toValidationError(
          UriTemplateViolation(kind: utkEmptyVariable, position: openBrace), raw
        )
      )
    detectInvalidVariableChar(name, i).isOkOr:
      return err(toValidationError(error, raw))
    parts.add(UriPart(kind: upVariable, name: name))
    variables.incl(name)
    i += nameConsumed + 1 # step past '}'
  ok(UriTemplate(rawParts: parts, rawVariables: variables, rawSource: raw))

func hasVariable*(tmpl: UriTemplate, name: string): bool =
  ## O(1) membership test against the pre-built variable set.
  return name in tmpl.rawVariables

func expandUriTemplate*(
    tmpl: UriTemplate, variables: openArray[(string, string)]
): string =
  ## Folds the parsed parts into a string. Variables not found in
  ## ``variables`` are emitted unexpanded as ``{name}`` (matches the
  ## pre-refactor ``replace``-based expander). Caller is responsible
  ## for percent-encoding values that require it
  ## (``std/uri.encodeUrl(value, usePlus=false)``). Pure.
  result = ""
  for part in tmpl.rawParts:
    case part.kind
    of upLiteral:
      result.add(part.text)
    of upVariable:
      var found = false
      for i in 0 ..< variables.len:
        if variables[i][0] == part.name:
          result.add(variables[i][1])
          found = true
          break
      if not found:
        result.add("{")
        result.add(part.name)
        result.add("}")

type UriRole = enum
  ## Tags the three RFC 8620 section 2 URI templates advertised by the server
  ## Session object. Backing string matches the field name used in the wire
  ## error message (e.g. ``"downloadUrl missing {accountId}"``).
  urDownload = "downloadUrl"
  urUpload = "uploadUrl"
  urEventSource = "eventSourceUrl"

type SessionViolationKind = enum
  svMissingCoreCapability
  svEmptyApiUrl
  svApiUrlControlChar
  svUriMissingVariable

type SessionViolation {.ruleOff: "objects".} = object
  case kind: SessionViolationKind
  of svMissingCoreCapability, svEmptyApiUrl:
    discard
  of svApiUrlControlChar:
    apiUrl: string
  of svUriMissingVariable:
    role: UriRole
    variable: string
    rawUri: string

func requiredVariables(role: UriRole): seq[string] =
  ## Single source of truth for the RFC 8620 section 2 required URI variables
  ## per template role. Iteration order is the message-reporting order
  ## (first-missing wins), preserving pre-refactor behaviour.
  case role
  of urDownload:
    @["accountId", "blobId", "type", "name"]
  of urUpload:
    @["accountId"]
  of urEventSource:
    @["types", "closeafter", "ping"]

func toValidationError(v: SessionViolation): ValidationError =
  ## Sole domain-to-wire translator for ``SessionViolation``. Adding a new
  ## ``SessionViolationKind`` variant forces a compile error here.
  case v.kind
  of svMissingCoreCapability:
    validationError(
      "Session", "capabilities must include urn:ietf:params:jmap:core", ""
    )
  of svEmptyApiUrl:
    validationError("Session", "apiUrl must not be empty", "")
  of svApiUrlControlChar:
    validationError("Session", "apiUrl must not contain newline characters", v.apiUrl)
  of svUriMissingVariable:
    validationError("Session", $v.role & " missing {" & v.variable & "}", v.rawUri)

type CorePartition = object
  ## Internal helper: the core capability extracted from the input list,
  ## plus the remainder. Constructed only via ``partitionCore``; consumed
  ## only by ``parseSession``. Kept private so the split is an
  ## implementation detail of Session construction.
  core: CoreCapabilities
  additional: seq[ServerCapability]

func partitionCore(
    caps: openArray[ServerCapability]
): Result[CorePartition, SessionViolation] =
  ## Splits ``caps`` into the unique core arm plus everything else.
  ## RFC 8620 §2 says the capability list MUST include
  ## ``urn:ietf:params:jmap:core``; absence returns
  ## ``svMissingCoreCapability``. Duplicate ``ckCore`` entries — which
  ## the RFC does not contemplate — retain the first-seen core arm and
  ## silently drop the rest, preserving the pre-refactor
  ## ``hasKind``/linear-scan behaviour.
  var coreOpt = Opt.none(CoreCapabilities)
  var additional: seq[ServerCapability] = @[]
  for cap in caps:
    case cap.kind
    of ckCore:
      if coreOpt.isNone:
        coreOpt = Opt.some(cap.core)
    else:
      additional.add(cap)
  for core in coreOpt:
    return ok(CorePartition(core: core, additional: additional))
  err(SessionViolation(kind: svMissingCoreCapability))

func detectApiUrl(apiUrl: string): Result[void, SessionViolation] =
  ## RFC 8620 section 2: apiUrl MUST be a non-empty URL free of embedded
  ## newline characters (which would break HTTP request-line framing).
  if apiUrl.len == 0:
    return err(SessionViolation(kind: svEmptyApiUrl))
  if apiUrl.contains({'\c', '\L'}):
    return err(SessionViolation(kind: svApiUrlControlChar, apiUrl: apiUrl))
  ok()

func detectUriVariables(
    role: UriRole, tmpl: UriTemplate
): Result[void, SessionViolation] =
  ## Short-circuits on the first required variable missing from ``tmpl``.
  ## Iteration order matches ``requiredVariables(role)`` — that is the
  ## reporting order the existing tests pin down.
  for variable in requiredVariables(role):
    if not tmpl.hasVariable(variable):
      return err(
        SessionViolation(
          kind: svUriMissingVariable, role: role, variable: variable, rawUri: $tmpl
        )
      )
  ok()

func detectSession(
    capabilities: openArray[ServerCapability],
    apiUrl: string,
    downloadUrl, uploadUrl, eventSourceUrl: UriTemplate,
): Result[CorePartition, SessionViolation] =
  ## Composes the five structural sub-detectors with ``?`` short-circuit,
  ## returning the extracted core partition so ``parseSession`` can feed
  ## ``rawCore`` / ``rawAdditional`` without a second traversal. First-
  ## error ordering matches the pre-refactor behaviour.
  let partition = ?partitionCore(capabilities)
  ?detectApiUrl(apiUrl)
  ?detectUriVariables(urDownload, downloadUrl)
  ?detectUriVariables(urUpload, uploadUrl)
  ?detectUriVariables(urEventSource, eventSourceUrl)
  ok(partition)

func parseSession*(
    capabilities: seq[ServerCapability],
    accounts: Table[AccountId, Account],
    primaryAccounts: Table[string, AccountId],
    username: string,
    apiUrl: string,
    downloadUrl: UriTemplate,
    uploadUrl: UriTemplate,
    eventSourceUrl: UriTemplate,
    state: JmapState,
): Result[Session, ValidationError] =
  ## Validates structural invariants:
  ## 1. capabilities includes ckCore (RFC section 2: MUST)
  ## 2. apiUrl is non-empty and free of newlines
  ## 3. downloadUrl contains {accountId}, {blobId}, {type}, {name} (RFC section 2)
  ## 4. uploadUrl contains {accountId} (RFC section 2)
  ## 5. eventSourceUrl contains {types}, {closeafter}, {ping} (RFC section 2)
  ## Deliberately omits cross-reference validation (Decision D7).
  let partition = detectSession(
    capabilities, apiUrl, downloadUrl, uploadUrl, eventSourceUrl
  ).valueOr:
    return err(toValidationError(error))
  ok(
    Session(
      rawCore: partition.core,
      rawAdditional: partition.additional,
      rawAccounts: accounts,
      rawPrimaryAccounts: primaryAccounts,
      rawUsername: username,
      rawApiUrl: apiUrl,
      rawDownloadUrl: downloadUrl,
      rawUploadUrl: uploadUrl,
      rawEventSourceUrl: eventSourceUrl,
      rawState: state,
    )
  )

func coreCapabilities*(session: Session): CoreCapabilities =
  ## Total function: ``rawCore`` is stored as a typed field at Session
  ## construction time, so the RFC 8620 §2 MUST invariant is enforced by
  ## the type — no panic path, no runtime assertion.
  return session.rawCore

func findCapability*(session: Session, kind: CapabilityKind): Opt[ServerCapability] =
  ## Finds the first server capability matching the given kind. ``ckCore``
  ## short-circuits to the synthesised core arm — ``rawCore`` is stored
  ## directly, not in ``rawAdditional``.
  if kind == ckCore:
    return Opt.some(
      ServerCapability(rawUri: CoreCapabilityUri, kind: ckCore, core: session.rawCore)
    )
  for _, cap in session.rawAdditional:
    if cap.kind == kind:
      return Opt.some(cap)
  return Opt.none(ServerCapability)

func findCapabilityByUri*(session: Session, uri: string): Opt[ServerCapability] =
  ## Looks up a server capability by its raw URI string. Use this instead of
  ## findCapability when looking up vendor extensions (which all map to ckUnknown
  ## and would be ambiguous via findCapability).
  if uri == CoreCapabilityUri:
    return Opt.some(
      ServerCapability(rawUri: CoreCapabilityUri, kind: ckCore, core: session.rawCore)
    )
  for _, cap in session.rawAdditional:
    if cap.rawUri == uri:
      return Opt.some(cap)
  return Opt.none(ServerCapability)

func primaryAccount*(session: Session, kind: CapabilityKind): Opt[AccountId] =
  ## Returns the primary account for a known capability kind.
  ## Returns none if kind == ckUnknown (no canonical URI) or no primary designated.
  let uri = ?capabilityUri(kind)
  for key, val in session.rawPrimaryAccounts:
    if key == uri:
      return Opt.some(val)
  return Opt.none(AccountId)

func findAccount*(session: Session, id: AccountId): Opt[Account] =
  ## Looks up an account by its AccountId.
  for key, val in session.rawAccounts:
    if key == id:
      return Opt.some(val)
  return Opt.none(Account)
