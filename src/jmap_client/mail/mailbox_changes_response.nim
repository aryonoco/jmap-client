# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Extended Mailbox/changes response (RFC 8621 §2.2). Composes the
## standard ``ChangesResponse[Mailbox]`` with the Mailbox-specific
## ``updatedProperties`` extension field.
##
## Extracted into its own leaf module so ``mail_entities.nim`` can declare
## ``changesResponseType(Mailbox) = MailboxChangesResponse`` without
## creating an import cycle with ``mail_builders.nim`` (which now imports
## this leaf for its ``addMailboxChanges`` wrapper).

{.push raises: [], noSideEffect.}

import std/json

import ../types
import ../serialisation
import ../methods
import ./mailbox

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
    R: typedesc[MailboxChangesResponse],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[MailboxChangesResponse, SerdeViolation] =
  ## Deserialise JSON to MailboxChangesResponse. Reuses
  ## ``ChangesResponse[Mailbox].fromJson`` for the 7 standard fields, then
  ## extracts the Mailbox-specific ``updatedProperties`` extension.
  discard $R # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let base = ?ChangesResponse[Mailbox].fromJson(node, path)
  let upNode = node{"updatedProperties"}
  let updatedProperties =
    if upNode.isNil or upNode.kind == JNull:
      Opt.none(seq[string])
    elif upNode.kind == JArray:
      var props: seq[string] = @[]
      for i, elem in upNode.getElems(@[]):
        if elem.kind != JString:
          return err(
            SerdeViolation(
              kind: svkWrongKind,
              path: path / "updatedProperties" / i,
              expectedKind: JString,
              actualKind: elem.kind,
            )
          )
        props.add(elem.getStr(""))
      Opt.some(props)
    else:
      return err(
        SerdeViolation(
          kind: svkWrongKind,
          path: path / "updatedProperties",
          expectedKind: JArray,
          actualKind: upNode.kind,
        )
      )
  return ok(MailboxChangesResponse(base: base, updatedProperties: updatedProperties))
