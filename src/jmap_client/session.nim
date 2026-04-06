# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP Session resource types (RFC 8620 section 2). Account capability entries,
## accounts, URI templates, and the Session aggregate with structural validation.

{.push raises: [].}

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

type Session* = object
  ## The JMAP Session resource (RFC 8620 section 2). Contains server capabilities,
  ## user accounts, API endpoint URLs, and session state.
  capabilities*: seq[ServerCapability] ## server-level capabilities
  accounts*: Table[AccountId, Account] ## keyed by AccountId
  primaryAccounts*: Table[string, AccountId]
    ## keyed by raw capability URI (not CapabilityKind)
  username*: string ## or empty string if none
  apiUrl*: string ## URL for JMAP API requests
  downloadUrl*: UriTemplate ## RFC 6570 Level 1 template
  uploadUrl*: UriTemplate ## RFC 6570 Level 1 template
  eventSourceUrl*: UriTemplate ## RFC 6570 Level 1 template
  state*: JmapState ## session state token

func findCapability*(
    account: Account, kind: CapabilityKind
): Opt[AccountCapabilityEntry] =
  ## Finds the first account capability matching the given kind.
  for _, entry in account.accountCapabilities:
    if entry.kind == kind:
      return Opt.some(entry)
  Opt.none(AccountCapabilityEntry)

func findCapabilityByUri*(account: Account, uri: string): Opt[AccountCapabilityEntry] =
  ## Looks up an account capability by its raw URI string. Use this instead of
  ## findCapability when looking up vendor extensions (which all map to ckUnknown
  ## and would be ambiguous via findCapability).
  for _, entry in account.accountCapabilities:
    if entry.rawUri == uri:
      return Opt.some(entry)
  Opt.none(AccountCapabilityEntry)

func hasCapability*(account: Account, kind: CapabilityKind): bool =
  ## Checks whether the account has a capability of the given kind.
  account.findCapability(kind).isSome

func hasKind(caps: openArray[ServerCapability], kind: CapabilityKind): bool =
  ## Checks whether any capability matches the given kind. Used by parseSession
  ## before a Session object exists (so Session.findCapability is unavailable).
  for _, cap in caps:
    if cap.kind == kind:
      return true
  false

func expandUriTemplate*(
    tmpl: UriTemplate, variables: openArray[(string, string)]
): string =
  ## Expands an RFC 6570 Level 1 URI template by replacing ``{name}`` with
  ## the corresponding value. Variables not found in ``variables`` are left
  ## unexpanded. Caller is responsible for percent-encoding values that
  ## require it (``std/uri.encodeUrl(value, usePlus=false)``). Pure.
  result = string(tmpl)
  for (name, value) in variables:
    result = result.replace("{" & name & "}", value)

func parseUriTemplate*(raw: string): Result[UriTemplate, ValidationError] =
  ## Non-empty validation. No RFC 6570 parsing — template expansion is Layer 4.
  if raw.len == 0:
    return err(validationError("UriTemplate", "must not be empty", raw))
  ok(UriTemplate(raw))

func hasVariable*(tmpl: UriTemplate, name: string): bool =
  ## Checks whether the template contains {name}. Simple substring search.
  let target = "{" & name & "}"
  target in string(tmpl)

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
  ## 2. apiUrl is non-empty
  ## 3. downloadUrl contains {accountId}, {blobId}, {type}, {name} (RFC section 2)
  ## 4. uploadUrl contains {accountId} (RFC section 2)
  ## 5. eventSourceUrl contains {types}, {closeafter}, {ping} (RFC section 2)
  ## Deliberately omits cross-reference validation (Decision D7).
  if not capabilities.hasKind(ckCore):
    return err(
      validationError(
        "Session", "capabilities must include urn:ietf:params:jmap:core", ""
      )
    )
  if apiUrl.len == 0:
    return err(validationError("Session", "apiUrl must not be empty", ""))
  if apiUrl.contains({'\c', '\L'}):
    return err(
      validationError("Session", "apiUrl must not contain newline characters", apiUrl)
    )
  for variable in ["accountId", "blobId", "type", "name"]:
    if not downloadUrl.hasVariable(variable):
      return err(
        validationError(
          "Session", "downloadUrl missing {" & variable & "}", string(downloadUrl)
        )
      )
  if not uploadUrl.hasVariable("accountId"):
    return err(
      validationError("Session", "uploadUrl missing {accountId}", string(uploadUrl))
    )
  for variable in ["types", "closeafter", "ping"]:
    if not eventSourceUrl.hasVariable(variable):
      return err(
        validationError(
          "Session", "eventSourceUrl missing {" & variable & "}", string(eventSourceUrl)
        )
      )
  let session = Session(
    capabilities: capabilities,
    accounts: accounts,
    primaryAccounts: primaryAccounts,
    username: username,
    apiUrl: apiUrl,
    downloadUrl: downloadUrl,
    uploadUrl: uploadUrl,
    eventSourceUrl: eventSourceUrl,
    state: state,
  )
  doAssert session.capabilities.hasKind(ckCore)
  doAssert session.apiUrl.len > 0
  ok(session)

func coreCapabilities*(session: Session): CoreCapabilities =
  ## Returns the core capabilities. Total function (no Result) because
  ## parseSession guarantees ckCore is present. Raises AssertionDefect if
  ## the invariant is violated by direct construction.
  for _, cap in session.capabilities:
    case cap.kind
    of ckCore:
      return cap.core
    else:
      discard
  raiseAssert "Session missing ckCore: violated parseSession invariant"

func findCapability*(session: Session, kind: CapabilityKind): Opt[ServerCapability] =
  ## Finds the first server capability matching the given kind.
  for _, cap in session.capabilities:
    if cap.kind == kind:
      return Opt.some(cap)
  Opt.none(ServerCapability)

func findCapabilityByUri*(session: Session, uri: string): Opt[ServerCapability] =
  ## Looks up a server capability by its raw URI string. Use this instead of
  ## findCapability when looking up vendor extensions (which all map to ckUnknown
  ## and would be ambiguous via findCapability).
  for _, cap in session.capabilities:
    if cap.rawUri == uri:
      return Opt.some(cap)
  Opt.none(ServerCapability)

func primaryAccount*(session: Session, kind: CapabilityKind): Opt[AccountId] =
  ## Returns the primary account for a known capability kind.
  ## Returns none if kind == ckUnknown (no canonical URI) or no primary designated.
  let uri = ?capabilityUri(kind)
  for key, val in session.primaryAccounts:
    if key == uri:
      return Opt.some(val)
  Opt.none(AccountId)

func findAccount*(session: Session, id: AccountId): Opt[Account] =
  ## Looks up an account by its AccountId.
  for key, val in session.accounts:
    if key == id:
      return Opt.some(val)
  Opt.none(Account)
