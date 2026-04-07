# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Mail-specific set error types and typed accessor functions for extracting
## structured data from SetError.extras (RFC 8621 sections 4-7).

{.push raises: [].}

import std/strutils
import std/json

import ../validation
import ../primitives
import ../errors

type MailSetErrorType* = enum
  ## Mail-specific set error types from RFC 8621.
  msetMailboxHasChild = "mailboxHasChild"
  msetMailboxHasEmail = "mailboxHasEmail"
  msetBlobNotFound = "blobNotFound"
  msetTooManyKeywords = "tooManyKeywords"
  msetTooManyMailboxes = "tooManyMailboxes"
  msetInvalidEmail = "invalidEmail"
  msetTooManyRecipients = "tooManyRecipients"
  msetNoRecipients = "noRecipients"
  msetInvalidRecipients = "invalidRecipients"
  msetForbiddenMailFrom = "forbiddenMailFrom"
  msetForbiddenFrom = "forbiddenFrom"
  msetForbiddenToSend = "forbiddenToSend"
  msetCannotUnsend = "cannotUnsend"
  msetUnknown

func parseMailSetErrorType*(rawType: string): MailSetErrorType =
  ## Total function: always succeeds. Unknown types map to msetUnknown.
  return strutils.parseEnum[MailSetErrorType](rawType, msetUnknown)

func notFoundBlobIds*(se: SetError): Opt[seq[Id]] =
  ## Extracts the list of unfound blob IDs from a blobNotFound set error (RFC 8621 section 4.6).
  for extras in se.extras:
    if extras.kind != JObject:
      return Opt.none(seq[Id])
    let field = extras{"notFound"}
    if field.isNil or field.kind != JArray:
      return Opt.none(seq[Id])
    var ids: seq[Id] = @[]
    for elem in field.getElems(@[]):
      if elem.kind != JString:
        return Opt.none(seq[Id])
      let r = parseIdFromServer(elem.getStr(""))
      if r.isErr:
        return Opt.none(seq[Id])
      ids.add(r.get())
    return Opt.some(ids)
  return Opt.none(seq[Id])

func maxSize*(se: SetError): Opt[UnsignedInt] =
  ## Extracts the maximum size from a tooLarge set error (RFC 8621 section 7.5).
  for extras in se.extras:
    if extras.kind != JObject:
      return Opt.none(UnsignedInt)
    let field = extras{"maxSize"}
    if field.isNil or field.kind != JInt:
      return Opt.none(UnsignedInt)
    let r = parseUnsignedInt(field.getBiggestInt(0))
    if r.isErr:
      return Opt.none(UnsignedInt)
    return Opt.some(r.get())
  return Opt.none(UnsignedInt)

func maxRecipients*(se: SetError): Opt[UnsignedInt] =
  ## Extracts the maximum recipient count from a tooManyRecipients set error (RFC 8621 section 7.5).
  for extras in se.extras:
    if extras.kind != JObject:
      return Opt.none(UnsignedInt)
    let field = extras{"maxRecipients"}
    if field.isNil or field.kind != JInt:
      return Opt.none(UnsignedInt)
    let r = parseUnsignedInt(field.getBiggestInt(0))
    if r.isErr:
      return Opt.none(UnsignedInt)
    return Opt.some(r.get())
  return Opt.none(UnsignedInt)

func invalidRecipientAddresses*(se: SetError): Opt[seq[string]] =
  ## Extracts invalid recipient addresses from an invalidRecipients set error (RFC 8621 section 7.5).
  for extras in se.extras:
    if extras.kind != JObject:
      return Opt.none(seq[string])
    let field = extras{"invalidRecipients"}
    if field.isNil or field.kind != JArray:
      return Opt.none(seq[string])
    var strs: seq[string] = @[]
    for elem in field.getElems(@[]):
      if elem.kind != JString:
        return Opt.none(seq[string])
      strs.add(elem.getStr(""))
    return Opt.some(strs)
  return Opt.none(seq[string])

func invalidEmailProperties*(se: SetError): Opt[seq[string]] =
  ## Extracts invalid property names from an invalidEmail set error (RFC 8621 section 7.5).
  for extras in se.extras:
    if extras.kind != JObject:
      return Opt.none(seq[string])
    let field = extras{"properties"}
    if field.isNil or field.kind != JArray:
      return Opt.none(seq[string])
    var strs: seq[string] = @[]
    for elem in field.getElems(@[]):
      if elem.kind != JString:
        return Opt.none(seq[string])
      strs.add(elem.getStr(""))
    return Opt.some(strs)
  return Opt.none(seq[string])
