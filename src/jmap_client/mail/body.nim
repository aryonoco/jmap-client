# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Body sub-types for RFC 8621 (JMAP Mail) sections 4.1.4 and 4.6.
## PartId, EmailBodyPart (read model), EmailBodyValue, BlueprintPartSource,
## and BlueprintBodyPart (creation model).

{.push raises: [], noSideEffect.}

import std/hashes
import std/sequtils
import std/tables

import ../validation
import ../primitives
import ./headers

# =============================================================================
# Type-level invariants
# =============================================================================

const MaxBodyPartDepth* = 128
  ## Maximum nesting depth of a ``BlueprintBodyPart`` tree. Carried as a
  ## type-level invariant by ``parseEmailBlueprint`` — trees exceeding this
  ## depth are rejected at construction via ``ebcBodyPartDepthExceeded``,
  ## so the serialiser can recurse unconditionally. ``EmailBodyPart``
  ## (server-received) uses the same bound defensively at the wire-in
  ## boundary in ``serde_body.fromJson`` per Postel's law.

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
# BlueprintBodyValue
# =============================================================================

type BlueprintBodyValue* {.ruleOff: "objects".} = object
  ## Creation-time body-value carrier (RFC 8621 §4.1.4 / §4.6
  ## constraint 6). Strips ``isEncodingProblem`` and ``isTruncated`` from
  ## ``EmailBodyValue`` — both flags are mandated false on creation, so the
  ## stripped type makes the illegal state unrepresentable.
  value*: string ## Decoded body content.

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
  extraHeaders*: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]
  case isMultipart*: bool
  of true:
    subParts*: seq[BlueprintBodyPart] ## Recursive children.
  of false:
    case source*: BlueprintPartSource
    of bpsInline:
      partId*: PartId ## Co-located reference to the body value (R3-3).
      value*: BlueprintBodyValue ## Co-located content (Design §5.1, R3-3).
    of bpsBlobRef:
      blobId*: Id
      size*: Opt[UnsignedInt] ## Optional, ignored by server.
      charset*: Opt[string]
