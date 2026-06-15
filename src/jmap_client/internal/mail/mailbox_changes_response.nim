# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Extended Mailbox/changes response (RFC 8621 §2.2). Composes the
## standard ``ChangesResponse[Mailbox]`` with the Mailbox-specific
## ``updatedProperties`` extension field. The standard change fields are
## read directly through the public ``base`` (``r.base.created`` etc.) —
## one source of truth, no per-field forwarders to drift from it.
##
## Extracted into its own leaf module so ``mail_entities.nim`` can declare
## ``changesResponseType(Mailbox) = MailboxChangesResponse`` without
## creating an import cycle with ``mail_builders.nim`` (which now imports
## this leaf for its ``addMailboxChanges`` wrapper).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../types
import ../serialisation/serde
import ../serialisation/serde_diagnostics
import ../serialisation/serde_helpers
import ../protocol/methods
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
