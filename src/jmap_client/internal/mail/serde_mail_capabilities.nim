# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for MailCapabilities and SubmissionCapabilities.
## These parse functions take a ServerCapability (case object) and extract
## typed capability data from its rawData JSON field.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/sets
import std/tables

import ../serialisation/serde
import ../serialisation/serde_diagnostics
import ../serialisation/serde_helpers
import ../serialisation/serde_primitives
import ../types
import ../types/capabilities
import ./mail_capabilities
import ./submission_atoms

# =============================================================================
# MailCapabilities
# =============================================================================

func parseOptUnsignedIntField(
    node: JsonNode, fieldName: string, path: JsonPath, minValue: int64
): Result[Opt[UnsignedInt], SerdeViolation] =
  ## Parses an optional ``UnsignedInt`` field with a minimum-value
  ## constraint applied only when present. Used by the optional
  ## informational fields in RFC 8621 §1.3.1 (``maxMailboxesPerEmail``
  ## must be >= 1 when present; ``maxSizeMailboxName`` must be >= 100
  ## when present). Absent or null projects to ``Opt.none``.
  let fld = node{fieldName}
  if fld.isNil or fld.kind == JNull:
    return ok(Opt.none(UnsignedInt))
  ?expectKind(fld, JInt, path / fieldName)
  let val = ?UnsignedInt.fromJson(fld, path / fieldName)
  if val.toInt64 < minValue:
    return err(
      SerdeViolation(
        kind: svkEmptyRequired,
        path: path / fieldName,
        emptyFieldLabel: fieldName & " (must be >= " & $minValue & ")",
      )
    )
  ok(Opt.some(val))

func parseOptUnsignedIntFieldUnconstrained(
    node: JsonNode, fieldName: string, path: JsonPath
): Result[Opt[UnsignedInt], SerdeViolation] =
  ## Parses an optional ``UnsignedInt`` field without a value
  ## constraint (RFC 8621 §1.3.1 ``maxMailboxDepth``).
  let fld = node{fieldName}
  if fld.isNil or fld.kind == JNull:
    return ok(Opt.none(UnsignedInt))
  ?expectKind(fld, JInt, path / fieldName)
  let val = ?UnsignedInt.fromJson(fld, path / fieldName)
  ok(Opt.some(val))

func parseOptStringSetField(
    node: JsonNode, fieldName: string, path: JsonPath
): Result[HashSet[string], SerdeViolation] =
  ## Parses an optional JArray-of-JString into a ``HashSet[string]``.
  ## Absent or null projects to an empty set (RFC 8621 §1.3.1 lists
  ## ``emailQuerySortOptions`` as informational; Cyrus 3.12.2 emits a
  ## divergent label, accepted here as absence).
  let fld = node{fieldName}
  if fld.isNil or fld.kind == JNull:
    return ok(initHashSet[string]())
  ?expectKind(fld, JArray, path / fieldName)
  var opts: seq[string] = @[]
  for i, elem in fld.getElems(@[]):
    ?expectKind(elem, JString, path / fieldName / i)
    opts.add(elem.getStr(""))
  ok(toHashSet(opts))

func parseMailCapabilities*(
    cap: ServerCapability, path: JsonPath = emptyJsonPath()
): Result[MailCapabilities, SerdeViolation] =
  ## Parses mail capability data from a ServerCapability with kind ckMail.
  ## Validates RFC constraints: maxMailboxesPerEmail >= 1 (when present),
  ## maxSizeMailboxName >= 100 (when present).
  ##
  ## Under strictCaseObjects, `rawData` (declared in the else: branch of
  ## ServerCapability) is only accessible when the use-site case also goes
  ## through else:. The outer `of ckCore:` arm handles the sole explicit
  ## of-branch; the else: arm is where all non-ckCore kinds (including
  ## ckMail) flow.
  case cap.kind
  of ckCore:
    err(
      SerdeViolation(
        kind: svkEnumNotRecognised,
        path: path,
        enumTypeLabel: "capability kind",
        rawValue: $cap.kind,
      )
    )
  else:
    if cap.kind != ckMail:
      return err(
        SerdeViolation(
          kind: svkEnumNotRecognised,
          path: path,
          enumTypeLabel: "capability kind",
          rawValue: $cap.kind,
        )
      )
    ?expectKind(cap.rawData, JObject, path)

    let maxMailboxesPerEmail =
      ?parseOptUnsignedIntField(cap.rawData, "maxMailboxesPerEmail", path, 1)
    let maxMailboxDepth =
      ?parseOptUnsignedIntFieldUnconstrained(cap.rawData, "maxMailboxDepth", path)
    let maxSizeMailboxName =
      ?parseOptUnsignedIntField(cap.rawData, "maxSizeMailboxName", path, 100)

    # maxSizeAttachmentsPerEmail: required UnsignedInt
    let msapeFld = ?fieldJInt(cap.rawData, "maxSizeAttachmentsPerEmail", path)
    let maxSizeAttachmentsPerEmail =
      ?UnsignedInt.fromJson(msapeFld, path / "maxSizeAttachmentsPerEmail")

    let emailQuerySortOptions =
      ?parseOptStringSetField(cap.rawData, "emailQuerySortOptions", path)

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

# =============================================================================
# SubmissionCapabilities
# =============================================================================

func parseSubmissionCapabilities*(
    cap: ServerCapability, path: JsonPath = emptyJsonPath()
): Result[SubmissionCapabilities, SerdeViolation] =
  ## Parses submission capability data from a ServerCapability with kind
  ## ckSubmission. Validates field types and structure.
  ##
  ## Strict else-branch shape mirrors parseMailCapabilities — see the
  ## docstring there for the rationale.
  case cap.kind
  of ckCore:
    err(
      SerdeViolation(
        kind: svkEnumNotRecognised,
        path: path,
        enumTypeLabel: "capability kind",
        rawValue: $cap.kind,
      )
    )
  else:
    if cap.kind != ckSubmission:
      return err(
        SerdeViolation(
          kind: svkEnumNotRecognised,
          path: path,
          enumTypeLabel: "capability kind",
          rawValue: $cap.kind,
        )
      )
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
        submissionExtensions: initSubmissionExtensionMap(extensions),
      )
    )
