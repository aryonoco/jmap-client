# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Custom builder functions and response types for Mailbox (RFC 8621 §2).
## ``addGet[Mailbox]`` uses the generic builder (no custom overload needed).
## Custom builders handle methods with extra parameters or custom response
## types: ``addMailboxChanges`` (extended response), ``addMailboxQuery``
## (sortAsTree, filterAsTree), ``addMailboxQueryChanges`` (explicit
## parameter surface), ``addMailboxSet`` (onDestroyRemoveEmails, typed
## MailboxCreate).

{.push raises: [].}

import std/json
import std/tables

import ../types
import ../serialisation
import ../methods
import ../dispatch
import ../builder
import ./mailbox
import ./mail_filters
import ./serde_mailbox

const MailCapUri = "urn:ietf:params:jmap:mail"

# =============================================================================
# MailboxChangesResponse (Decision B9 — composition pattern)
# =============================================================================

{.push ruleOff: "objects".}

type MailboxChangesResponse* = object
  ## Extended Foo/changes response for Mailbox (RFC 8621 §2.2). Composes
  ## the standard ``ChangesResponse[Mailbox]`` with the Mailbox-specific
  ## ``updatedProperties`` extension field.
  base*: ChangesResponse[Mailbox]
  updatedProperties*: Opt[seq[string]]

{.pop.}

# =============================================================================
# UFCS forwarding accessors
# =============================================================================

template forwardChangesFields(T: typedesc) =
  ## Generates UFCS forwarding funcs for the 7 ChangesResponse base fields,
  ## so callers write ``resp.accountId`` instead of ``resp.base.accountId``.
  func accountId*(r: T): AccountId =
    ## Forwarded from ``base.accountId``.
    r.base.accountId

  func oldState*(r: T): JmapState =
    ## Forwarded from ``base.oldState``.
    r.base.oldState

  func newState*(r: T): JmapState =
    ## Forwarded from ``base.newState``.
    r.base.newState

  func hasMoreChanges*(r: T): bool =
    ## Forwarded from ``base.hasMoreChanges``.
    r.base.hasMoreChanges

  func created*(r: T): seq[Id] =
    ## Forwarded from ``base.created``.
    r.base.created

  func updated*(r: T): seq[Id] =
    ## Forwarded from ``base.updated``.
    r.base.updated

  func destroyed*(r: T): seq[Id] =
    ## Forwarded from ``base.destroyed``.
    r.base.destroyed

forwardChangesFields(MailboxChangesResponse)

# =============================================================================
# MailboxChangesResponse fromJson
# =============================================================================

func fromJson*(
    R: typedesc[MailboxChangesResponse], node: JsonNode
): Result[MailboxChangesResponse, ValidationError] =
  ## Deserialise JSON to MailboxChangesResponse. Reuses
  ## ``ChangesResponse[Mailbox].fromJson`` for the 7 standard fields, then
  ## extracts the Mailbox-specific ``updatedProperties`` extension.
  ?checkJsonKind(node, JObject, $R)
  let base = ?ChangesResponse[Mailbox].fromJson(node)
  let upNode = node{"updatedProperties"}
  let updatedProperties =
    if upNode.isNil or upNode.kind == JNull:
      Opt.none(seq[string])
    elif upNode.kind == JArray:
      var props: seq[string] = @[]
      for _, elem in upNode.getElems(@[]):
        if elem.kind != JString:
          return
            err(validationError($R, "updatedProperties elements must be strings", ""))
        props.add(elem.getStr(""))
      Opt.some(props)
    else:
      return err(validationError($R, "updatedProperties must be array or null", ""))
  return ok(MailboxChangesResponse(base: base, updatedProperties: updatedProperties))

# =============================================================================
# addMailboxChanges — Mailbox/changes (RFC 8621 §2.2)
# =============================================================================

func addMailboxChanges*(
    b: var RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): ResponseHandle[MailboxChangesResponse] =
  ## Adds a Mailbox/changes invocation. Returns a handle typed to the
  ## extended ``MailboxChangesResponse`` (which includes ``updatedProperties``).
  let req = ChangesRequest[Mailbox](
    accountId: accountId, sinceState: sinceState, maxChanges: maxChanges
  )
  let args = req.toJson()
  let callId = b.addInvocation("Mailbox/changes", args, MailCapUri)
  ResponseHandle[MailboxChangesResponse](callId)

# =============================================================================
# addMailboxQuery — Mailbox/query (RFC 8621 §2.3)
# =============================================================================

proc addMailboxQuery*(
    b: var RequestBuilder,
    accountId: AccountId,
    filterConditionToJson:
      proc(c: MailboxFilterCondition): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[MailboxFilterCondition]] =
      Opt.none(Filter[MailboxFilterCondition]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    queryParams: QueryParams = QueryParams(),
    sortAsTree: bool = false,
    filterAsTree: bool = false,
): ResponseHandle[QueryResponse[Mailbox]] =
  ## Adds a Mailbox/query invocation with Mailbox-specific tree parameters
  ## (RFC 8621 §2.3, Decision B13). ``sortAsTree`` and ``filterAsTree`` are
  ## always emitted (explicit > defaults).
  let req = QueryRequest[Mailbox, MailboxFilterCondition](
    accountId: accountId,
    filter: filter,
    sort: sort,
    position: queryParams.position,
    anchor: queryParams.anchor,
    anchorOffset: queryParams.anchorOffset,
    limit: queryParams.limit,
    calculateTotal: queryParams.calculateTotal,
  )
  var args = req.toJson(filterConditionToJson)
  args["sortAsTree"] = %sortAsTree
  args["filterAsTree"] = %filterAsTree
  let callId = b.addInvocation("Mailbox/query", args, MailCapUri)
  ResponseHandle[QueryResponse[Mailbox]](callId)

# =============================================================================
# addMailboxQueryChanges — Mailbox/queryChanges (RFC 8621 §2.4)
# =============================================================================

proc addMailboxQueryChanges*(
    b: var RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filterConditionToJson:
      proc(c: MailboxFilterCondition): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[MailboxFilterCondition]] =
      Opt.none(Filter[MailboxFilterCondition]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
): ResponseHandle[QueryChangesResponse[Mailbox]] =
  ## Adds a Mailbox/queryChanges invocation. Standard /queryChanges
  ## parameters only — NO sortAsTree/filterAsTree (Decision B12: RFC 8621
  ## §2.4 specifies no additional request arguments).
  let req = QueryChangesRequest[Mailbox, MailboxFilterCondition](
    accountId: accountId,
    filter: filter,
    sort: sort,
    sinceQueryState: sinceQueryState,
    maxChanges: maxChanges,
    upToId: upToId,
    calculateTotal: calculateTotal,
  )
  let args = req.toJson(filterConditionToJson)
  let callId = b.addInvocation("Mailbox/queryChanges", args, MailCapUri)
  ResponseHandle[QueryChangesResponse[Mailbox]](callId)

# =============================================================================
# addMailboxSet — Mailbox/set (RFC 8621 §2.5)
# =============================================================================

func addMailboxSet*(
    b: var RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, MailboxCreate]] =
      Opt.none(Table[CreationId, MailboxCreate]),
    update: Opt[Table[Id, PatchObject]] = Opt.none(Table[Id, PatchObject]),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    onDestroyRemoveEmails: bool = false,
): ResponseHandle[SetResponse[Mailbox]] =
  ## Adds a Mailbox/set invocation with typed ``MailboxCreate`` creation
  ## models (Decision B21) and ``onDestroyRemoveEmails`` extension
  ## (RFC 8621 §2.5). Always emits ``onDestroyRemoveEmails`` (explicit >
  ## defaults).
  # Convert typed Table[CreationId, MailboxCreate] → Table[CreationId, JsonNode]
  let jsonCreate = block:
    var res = Opt.none(Table[CreationId, JsonNode])
    for createMap in create:
      var tbl = initTable[CreationId, JsonNode](createMap.len)
      for k, v in createMap:
        tbl[k] = v.toJson()
      res = Opt.some(tbl)
    res
  let req = SetRequest[Mailbox](
    accountId: accountId,
    ifInState: ifInState,
    create: jsonCreate,
    update: update,
    destroy: destroy,
  )
  var args = req.toJson()
  args["onDestroyRemoveEmails"] = %onDestroyRemoveEmails
  let callId = b.addInvocation("Mailbox/set", args, MailCapUri)
  ResponseHandle[SetResponse[Mailbox]](callId)
