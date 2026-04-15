# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP Session resource types (RFC 8620 section 2). Account capability entries,
## accounts, URI templates, and the Session aggregate with structural validation.

{.push raises: [], noSideEffect.}

import std/hashes
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

type UriTemplate* = distinct string
  ## RFC 6570 Level 1 URI template stored as validated string. Template expansion
  ## is Layer 4 (IO); Layer 1 stores the template and provides structural checks.

defineStringDistinctOps(UriTemplate)

# nimalyzer: Session intentionally has no public fields. Fields are
# module-private to enforce construction via parseSession (which guarantees
# ckCore is present and apiUrl is non-empty). Public accessor funcs below
# provide read access; UFCS makes s.field syntax work unchanged for callers.
type Session* {.ruleOff: "objects".} = object
  ## The JMAP Session resource (RFC 8620 section 2). Contains server capabilities,
  ## user accounts, API endpoint URLs, and session state.
  ## Fields are module-private; external access via UFCS accessor funcs.
  rawCapabilities: seq[ServerCapability]
  rawAccounts: Table[AccountId, Account]
  rawPrimaryAccounts: Table[string, AccountId]
  rawUsername: string
  rawApiUrl: string
  rawDownloadUrl: UriTemplate
  rawUploadUrl: UriTemplate
  rawEventSourceUrl: UriTemplate
  rawState: JmapState

func capabilities*(s: Session): seq[ServerCapability] =
  ## Server-level capabilities.
  return s.rawCapabilities

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

func hasKind(caps: openArray[ServerCapability], kind: CapabilityKind): bool =
  ## Checks whether any capability matches the given kind. Used by parseSession
  ## before a Session object exists (so Session.findCapability is unavailable).
  for _, cap in caps:
    if cap.kind == kind:
      return true
  return false

func expandUriTemplate*(
    tmpl: UriTemplate, variables: openArray[(string, string)]
): string =
  ## Expands an RFC 6570 Level 1 URI template by replacing ``{name}`` with
  ## the corresponding value. Variables not found in ``variables`` are left
  ## unexpanded. Caller is responsible for percent-encoding values that
  ## require it (``std/uri.encodeUrl(value, usePlus=false)``). Pure.
  var tmplStr = string(tmpl)
  for i in 0 ..< variables.len:
    tmplStr = tmplStr.replace("{" & variables[i][0] & "}", variables[i][1])
  return tmplStr

func parseUriTemplate*(raw: string): Result[UriTemplate, ValidationError] =
  ## Non-empty validation. No RFC 6570 parsing — template expansion is Layer 4.
  if raw.len == 0:
    return err(validationError("UriTemplate", "must not be empty", raw))
  return ok(UriTemplate(raw))

func hasVariable*(tmpl: UriTemplate, name: string): bool =
  ## Checks whether the template contains {name}. Simple substring search.
  let target = "{" & name & "}"
  return target in string(tmpl)

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

func detectCoreCapability(
    caps: openArray[ServerCapability]
): Result[void, SessionViolation] =
  ## RFC 8620 section 2: server capability list MUST include the JMAP core
  ## capability identifier (``urn:ietf:params:jmap:core``).
  if caps.hasKind(ckCore):
    return ok()
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
          kind: svUriMissingVariable,
          role: role,
          variable: variable,
          rawUri: string(tmpl),
        )
      )
  ok()

func detectSession(
    capabilities: openArray[ServerCapability],
    apiUrl: string,
    downloadUrl, uploadUrl, eventSourceUrl: UriTemplate,
): Result[void, SessionViolation] =
  ## Composes the five structural sub-detectors with ``?`` short-circuit,
  ## mirroring the original ``parseSession`` ordering so first-error
  ## reporting is byte-identical to the pre-refactor behaviour.
  ?detectCoreCapability(capabilities)
  ?detectApiUrl(apiUrl)
  ?detectUriVariables(urDownload, downloadUrl)
  ?detectUriVariables(urUpload, uploadUrl)
  ?detectUriVariables(urEventSource, eventSourceUrl)
  ok()

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
  detectSession(capabilities, apiUrl, downloadUrl, uploadUrl, eventSourceUrl).isOkOr:
    return err(toValidationError(error))
  ok(
    Session(
      rawCapabilities: capabilities,
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
  ## Returns the core capabilities. Total function (no Result) because
  ## parseSession guarantees ckCore is present and rawCapabilities is
  ## module-private (Pattern A — direct construction from outside this
  ## module is refused by the compiler).
  for _, cap in session.rawCapabilities:
    case cap.kind
    of ckCore:
      return cap.core
    else:
      discard
  raiseAssert "Session missing ckCore: violated parseSession invariant"

func findCapability*(session: Session, kind: CapabilityKind): Opt[ServerCapability] =
  ## Finds the first server capability matching the given kind.
  for _, cap in session.rawCapabilities:
    if cap.kind == kind:
      return Opt.some(cap)
  return Opt.none(ServerCapability)

func findCapabilityByUri*(session: Session, uri: string): Opt[ServerCapability] =
  ## Looks up a server capability by its raw URI string. Use this instead of
  ## findCapability when looking up vendor extensions (which all map to ckUnknown
  ## and would be ambiguous via findCapability).
  for _, cap in session.rawCapabilities:
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
