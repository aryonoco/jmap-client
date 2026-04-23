# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for MailCapabilities and SubmissionCapabilities.
## These parse functions take a ServerCapability (case object) and extract
## typed capability data from its rawData JSON field.

{.push raises: [], noSideEffect.}

import std/json
import std/sets
import std/tables

import ../serde
import ../types
import ../capabilities
import ./mail_capabilities
import ./submission_atoms

# =============================================================================
# MailCapabilities
# =============================================================================

func parseMailCapabilities*(
    cap: ServerCapability, path: JsonPath = emptyJsonPath()
): Result[MailCapabilities, SerdeViolation] =
  ## Parses mail capability data from a ServerCapability with kind ckMail.
  ## Validates RFC constraints: maxMailboxesPerEmail >= 1 (when present),
  ## maxSizeMailboxName >= 100.
  case cap.kind
  of ckMail:
    ?expectKind(cap.rawData, JObject, path)

    # maxMailboxesPerEmail: nullable UnsignedInt, >= 1 when present
    let mmpeFld = cap.rawData{"maxMailboxesPerEmail"}
    let maxMailboxesPerEmail =
      if mmpeFld.isNil or mmpeFld.kind == JNull:
        Opt.none(UnsignedInt)
      else:
        ?expectKind(mmpeFld, JInt, path / "maxMailboxesPerEmail")
        let val = ?UnsignedInt.fromJson(mmpeFld, path / "maxMailboxesPerEmail")
        if int64(val) < 1:
          return err(
            SerdeViolation(
              kind: svkEmptyRequired,
              path: path / "maxMailboxesPerEmail",
              emptyFieldLabel: "maxMailboxesPerEmail (must be >= 1)",
            )
          )
        Opt.some(val)

    # maxMailboxDepth: nullable UnsignedInt, no minimum constraint
    let mmdFld = cap.rawData{"maxMailboxDepth"}
    let maxMailboxDepth =
      if mmdFld.isNil or mmdFld.kind == JNull:
        Opt.none(UnsignedInt)
      else:
        ?expectKind(mmdFld, JInt, path / "maxMailboxDepth")
        let val = ?UnsignedInt.fromJson(mmdFld, path / "maxMailboxDepth")
        Opt.some(val)

    # maxSizeMailboxName: required UnsignedInt, >= 100
    let msmnFld = ?fieldJInt(cap.rawData, "maxSizeMailboxName", path)
    let maxSizeMailboxName = ?UnsignedInt.fromJson(msmnFld, path / "maxSizeMailboxName")
    if int64(maxSizeMailboxName) < 100:
      return err(
        SerdeViolation(
          kind: svkEmptyRequired,
          path: path / "maxSizeMailboxName",
          emptyFieldLabel: "maxSizeMailboxName (must be >= 100)",
        )
      )

    # maxSizeAttachmentsPerEmail: required UnsignedInt
    let msapeFld = ?fieldJInt(cap.rawData, "maxSizeAttachmentsPerEmail", path)
    let maxSizeAttachmentsPerEmail =
      ?UnsignedInt.fromJson(msapeFld, path / "maxSizeAttachmentsPerEmail")

    # emailQuerySortOptions: required JArray of JString
    let eqsoNode = ?fieldJArray(cap.rawData, "emailQuerySortOptions", path)
    var opts: seq[string] = @[]
    for i, elem in eqsoNode.getElems(@[]):
      ?expectKind(elem, JString, path / "emailQuerySortOptions" / i)
      opts.add(elem.getStr(""))
    let emailQuerySortOptions = toHashSet(opts)

    # mayCreateTopLevelMailbox: required JBool
    let mctlmFld = ?fieldJBool(cap.rawData, "mayCreateTopLevelMailbox", path)
    let mayCreateTopLevelMailbox = mctlmFld.getBool(false)

    ok(
      MailCapabilities(
        maxMailboxesPerEmail: maxMailboxesPerEmail,
        maxMailboxDepth: maxMailboxDepth,
        maxSizeMailboxName: maxSizeMailboxName,
        maxSizeAttachmentsPerEmail: maxSizeAttachmentsPerEmail,
        emailQuerySortOptions: emailQuerySortOptions,
        mayCreateTopLevelMailbox: mayCreateTopLevelMailbox,
      )
    )
  else:
    err(
      SerdeViolation(
        kind: svkEnumNotRecognised,
        path: path,
        enumTypeLabel: "capability kind",
        rawValue: $cap.kind,
      )
    )

# =============================================================================
# SubmissionCapabilities
# =============================================================================

func parseSubmissionCapabilities*(
    cap: ServerCapability, path: JsonPath = emptyJsonPath()
): Result[SubmissionCapabilities, SerdeViolation] =
  ## Parses submission capability data from a ServerCapability with kind
  ## ckSubmission. Validates field types and structure.
  case cap.kind
  of ckSubmission:
    ?expectKind(cap.rawData, JObject, path)

    # maxDelayedSend: required UnsignedInt (0 is valid — means not supported)
    let mdsFld = ?fieldJInt(cap.rawData, "maxDelayedSend", path)
    let maxDelayedSend = ?UnsignedInt.fromJson(mdsFld, path / "maxDelayedSend")

    # submissionExtensions: required JObject; keys are RFC 5321 esmtp-keywords,
    # values are arrays of strings.
    let extNode = ?fieldJObject(cap.rawData, "submissionExtensions", path)
    var extensions = initOrderedTable[RFC5321Keyword, seq[string]]()
    for key, val in extNode.pairs:
      let kw = ?wrapInner(parseRFC5321Keyword(key), path / "submissionExtensions" / key)
      ?expectKind(val, JArray, path / "submissionExtensions" / key)
      var args: seq[string] = @[]
      for i, elem in val.getElems(@[]):
        ?expectKind(elem, JString, path / "submissionExtensions" / key / i)
        args.add(elem.getStr(""))
      extensions[kw] = args

    ok(
      SubmissionCapabilities(
        maxDelayedSend: maxDelayedSend,
        submissionExtensions: SubmissionExtensionMap(extensions),
      )
    )
  else:
    err(
      SerdeViolation(
        kind: svkEnumNotRecognised,
        path: path,
        enumTypeLabel: "capability kind",
        rawValue: $cap.kind,
      )
    )
