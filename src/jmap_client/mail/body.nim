# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Body sub-types for RFC 8621 (JMAP Mail) sections 4.1.4 and 4.6.
## PartId, EmailBodyPart (read model), EmailBodyValue, BlueprintPartSource,
## and BlueprintBodyPart (creation model).

{.push raises: [].}

import std/hashes
import std/sequtils
import std/tables

import ../validation
import ../primitives
import ./headers

# =============================================================================
# PartId
# =============================================================================

type PartId* = distinct string
  ## Body part identifier, unique within an Email (RFC 8621 §4.1.4).
  ## Typed as ``String`` (not ``Id``), so no length limit applies.

defineStringDistinctOps(PartId)

func parsePartIdFromServer*(raw: string): Result[PartId, ValidationError] =
  ## Lenient parser for server-provided part identifiers. Validates non-empty
  ## and rejects control characters (< 0x20) as a defensive measure.
  if raw.len == 0:
    return err(validationError("PartId", "must not be empty", raw))
  if raw.anyIt(ord(it) < 0x20):
    return err(validationError("PartId", "contains control characters", raw))
  let pid = PartId(raw)
  doAssert pid.len > 0
  return ok(pid)

# =============================================================================
# EmailBodyPart
# =============================================================================

type EmailBodyPart* {.ruleOff: "objects".} = object
  ## MIME body structure as received from the server (RFC 8621 §4.1.4).
  ## Recursive case object: multipart nodes carry children, leaf nodes carry
  ## a PartId and blob reference. ``isMultipart`` is derived from
  ## ``contentType`` at the parsing boundary.
  headers*: seq[EmailHeader] ## Raw MIME headers; @[] if absent.
  name*: Opt[string] ## Decoded filename.
  contentType*: string ## e.g. "text/plain", "multipart/mixed".
  charset*: Opt[string] ## Server-provided or implicit "us-ascii" for text/*.
  disposition*: Opt[string] ## "inline", "attachment", or none.
  cid*: Opt[string] ## Content-Id without angle brackets.
  language*: Opt[seq[string]] ## Content-Language tags.
  location*: Opt[string] ## Content-Location URI.
  size*: UnsignedInt ## RFC unconditional — all parts.
  case isMultipart*: bool
  of true:
    subParts*: seq[EmailBodyPart] ## Recursive children.
  of false:
    partId*: PartId ## Unique within the Email.
    blobId*: Id ## Reference to content blob.

# =============================================================================
# EmailBodyValue
# =============================================================================

type EmailBodyValue* {.ruleOff: "objects".} = object
  ## Decoded text content for a body part (RFC 8621 §4.1.4).
  ## All field combinations are valid for the read model.
  value*: string ## Decoded text content.
  isEncodingProblem*: bool ## Default false.
  isTruncated*: bool ## Default false.

# =============================================================================
# BlueprintPartSource
# =============================================================================

type BlueprintPartSource* = enum
  ## Discriminant for creation body part content source (RFC 8621 §4.6).
  bpsInline ## partId → bodyValues lookup.
  bpsBlobRef ## blobId → uploaded blob reference.

# =============================================================================
# BlueprintBodyPart
# =============================================================================

type BlueprintBodyPart* {.ruleOff: "objects".} = object
  ## Body structure for Email creation (RFC 8621 §4.6). Nested case object:
  ## outer ``isMultipart`` separates containers from leaves; inner ``source``
  ## separates inline from blob-referenced parts.
  contentType*: string
  name*: Opt[string]
  disposition*: Opt[string]
  cid*: Opt[string]
  language*: Opt[seq[string]]
  location*: Opt[string]
  extraHeaders*: Table[HeaderPropertyKey, HeaderValue]
  case isMultipart*: bool
  of true:
    subParts*: seq[BlueprintBodyPart] ## Recursive children.
  of false:
    case source*: BlueprintPartSource
    of bpsInline:
      partId*: PartId ## Key into bodyValues.
    of bpsBlobRef:
      blobId*: Id
      size*: Opt[UnsignedInt] ## Optional, ignored by server.
      charset*: Opt[string]
