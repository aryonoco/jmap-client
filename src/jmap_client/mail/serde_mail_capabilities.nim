# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for MailCapabilities and SubmissionCapabilities.
## These parse functions take a ServerCapability (case object) and extract
## typed capability data from its rawData JSON field.

{.push raises: [].}

import std/json
import std/sets
import std/tables

import ../serde
import ../types
import ../capabilities
import ./mail_capabilities

# =============================================================================
# MailCapabilities
# =============================================================================

func parseMailCapabilities*(
    cap: ServerCapability
): Result[MailCapabilities, ValidationError] =
  ## Parses mail capability data from a ServerCapability with kind ckMail.
  ## Validates RFC constraints: maxMailboxesPerEmail >= 1 (when present),
  ## maxSizeMailboxName >= 100.
  if cap.kind != ckMail:
    return err(parseError("MailCapabilities", "expected ckMail capability"))
  ?checkJsonKind(cap.rawData, JObject, "MailCapabilities")

  # maxMailboxesPerEmail: nullable UnsignedInt, >= 1 when present
  let mmpeFld = cap.rawData{"maxMailboxesPerEmail"}
  let maxMailboxesPerEmail =
    if mmpeFld.isNil or mmpeFld.kind == JNull:
      Opt.none(UnsignedInt)
    else:
      ?checkJsonKind(
        mmpeFld, JInt, "MailCapabilities", "maxMailboxesPerEmail must be integer"
      )
      let val = ?UnsignedInt.fromJson(mmpeFld)
      if int64(val) < 1:
        return err(
          parseError(
            "MailCapabilities", "maxMailboxesPerEmail must be >= 1 when present"
          )
        )
      Opt.some(val)

  # maxMailboxDepth: nullable UnsignedInt, no minimum constraint
  let mmdFld = cap.rawData{"maxMailboxDepth"}
  let maxMailboxDepth =
    if mmdFld.isNil or mmdFld.kind == JNull:
      Opt.none(UnsignedInt)
    else:
      ?checkJsonKind(
        mmdFld, JInt, "MailCapabilities", "maxMailboxDepth must be integer"
      )
      let val = ?UnsignedInt.fromJson(mmdFld)
      Opt.some(val)

  # maxSizeMailboxName: required UnsignedInt, >= 100
  let msmnFld = cap.rawData{"maxSizeMailboxName"}
  ?checkJsonKind(
    msmnFld, JInt, "MailCapabilities", "missing or invalid maxSizeMailboxName"
  )
  let maxSizeMailboxName = ?UnsignedInt.fromJson(msmnFld)
  if int64(maxSizeMailboxName) < 100:
    return err(parseError("MailCapabilities", "maxSizeMailboxName must be >= 100"))

  # maxSizeAttachmentsPerEmail: required UnsignedInt
  let msapeFld = cap.rawData{"maxSizeAttachmentsPerEmail"}
  ?checkJsonKind(
    msapeFld, JInt, "MailCapabilities", "missing or invalid maxSizeAttachmentsPerEmail"
  )
  let maxSizeAttachmentsPerEmail = ?UnsignedInt.fromJson(msapeFld)

  # emailQuerySortOptions: required JArray of JString
  let eqsoNode = cap.rawData{"emailQuerySortOptions"}
  ?checkJsonKind(
    eqsoNode, JArray, "MailCapabilities", "missing or invalid emailQuerySortOptions"
  )
  var opts: seq[string] = @[]
  for elem in eqsoNode.getElems(@[]):
    ?checkJsonKind(
      elem, JString, "MailCapabilities", "emailQuerySortOptions element must be string"
    )
    opts.add(elem.getStr(""))
  let emailQuerySortOptions = toHashSet(opts)

  # mayCreateTopLevelMailbox: required JBool
  let mctlmFld = cap.rawData{"mayCreateTopLevelMailbox"}
  ?checkJsonKind(
    mctlmFld, JBool, "MailCapabilities", "missing or invalid mayCreateTopLevelMailbox"
  )
  let mayCreateTopLevelMailbox = mctlmFld.getBool(false)

  return ok(
    MailCapabilities(
      maxMailboxesPerEmail: maxMailboxesPerEmail,
      maxMailboxDepth: maxMailboxDepth,
      maxSizeMailboxName: maxSizeMailboxName,
      maxSizeAttachmentsPerEmail: maxSizeAttachmentsPerEmail,
      emailQuerySortOptions: emailQuerySortOptions,
      mayCreateTopLevelMailbox: mayCreateTopLevelMailbox,
    )
  )

# =============================================================================
# SubmissionCapabilities
# =============================================================================

func parseSubmissionCapabilities*(
    cap: ServerCapability
): Result[SubmissionCapabilities, ValidationError] =
  ## Parses submission capability data from a ServerCapability with kind
  ## ckSubmission. Validates field types and structure.
  if cap.kind != ckSubmission:
    return err(parseError("SubmissionCapabilities", "expected ckSubmission capability"))
  ?checkJsonKind(cap.rawData, JObject, "SubmissionCapabilities")

  # maxDelayedSend: required UnsignedInt (0 is valid — means not supported)
  let mdsFld = cap.rawData{"maxDelayedSend"}
  ?checkJsonKind(
    mdsFld, JInt, "SubmissionCapabilities", "missing or invalid maxDelayedSend"
  )
  let maxDelayedSend = ?UnsignedInt.fromJson(mdsFld)

  # submissionExtensions: required JObject of string -> array of strings
  let extNode = cap.rawData{"submissionExtensions"}
  ?checkJsonKind(
    extNode, JObject, "SubmissionCapabilities",
    "missing or invalid submissionExtensions",
  )
  var extensions = initOrderedTable[string, seq[string]]()
  for key, val in extNode.pairs:
    ?checkJsonKind(
      val,
      JArray,
      "SubmissionCapabilities",
      "submissionExtensions." & key & " must be array",
    )
    var args: seq[string] = @[]
    for elem in val.getElems(@[]):
      ?checkJsonKind(
        elem,
        JString,
        "SubmissionCapabilities",
        "submissionExtensions." & key & " element must be string",
      )
      args.add(elem.getStr(""))
    extensions[key] = args

  return ok(
    SubmissionCapabilities(
      maxDelayedSend: maxDelayedSend, submissionExtensions: extensions
    )
  )
