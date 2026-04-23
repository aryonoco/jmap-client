# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Body sub-types for RFC 8621 (JMAP Mail) sections 4.1.4 and 4.6.
## PartId, EmailBodyPart (read model), EmailBodyValue, BlueprintPartSource,
## and BlueprintBodyPart (creation model).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sequtils
import std/strutils
import std/tables

import ../validation
import ../primitives
import ../identifiers
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
  return ok(PartId(raw))

# =============================================================================
# ContentDisposition
# =============================================================================

type ContentDispositionKind* = enum
  ## Discriminator for ``ContentDisposition``. Backing strings are the
  ## RFC 2183 §2.1 IANA-registered disposition types; ``cdExtension``
  ## carries a vendor-extension or x-token whose raw identifier lives
  ## alongside.
  cdInline = "inline"
  cdAttachment = "attachment"
  cdExtension

type ContentDisposition* {.ruleOff: "objects".} = object
  ## Validated RFC 2183 §2.1 disposition-type.
  ##
  ## Construction sealed: ``rawKind`` and ``rawIdentifier`` are
  ## module-private, so direct literal construction from outside this
  ## module is rejected. Use ``parseContentDisposition`` for untrusted
  ## input, or the named ``dispositionInline`` / ``dispositionAttachment``
  ## constants for the two well-known IANA values.
  ##
  ## Lowercase-normalised: RFC 2183 §2.1 states "values are not
  ## case-sensitive", and §2.8 mandates handling unknowns — the
  ## ``cdExtension`` arm is the escape hatch. Round-trips losslessly
  ## over the wire as the lowercased token.
  case rawKind: ContentDispositionKind
  of cdExtension:
    rawIdentifier: string
  of cdInline, cdAttachment:
    discard

func kind*(d: ContentDisposition): ContentDispositionKind =
  ## Returns the discriminator — ``cdInline``, ``cdAttachment``, or
  ## ``cdExtension`` for vendor extensions.
  return d.rawKind

func identifier*(d: ContentDisposition): string =
  ## Returns the wire identifier string. For the two well-known kinds,
  ## this is the enum's backing string; for ``cdExtension`` it is the
  ## vendor-extension identifier captured at parse time.
  case d.rawKind
  of cdExtension:
    return d.rawIdentifier
  of cdInline, cdAttachment:
    return $d.rawKind

func `$`*(d: ContentDisposition): string =
  ## Wire-form string — equivalent to ``identifier``.
  return d.identifier

func `==`*(a, b: ContentDisposition): bool =
  ## Structural equality. Two values are equal iff their kinds agree and,
  ## for ``cdExtension``, their raw identifiers match byte-for-byte.
  ##
  ## Nested case on both operands for strictCaseObjects compatibility.
  case a.rawKind
  of cdExtension:
    case b.rawKind
    of cdExtension:
      a.rawIdentifier == b.rawIdentifier
    of cdInline, cdAttachment:
      false
  of cdInline, cdAttachment:
    case b.rawKind
    of cdExtension:
      false
    of cdInline, cdAttachment:
      a.rawKind == b.rawKind

func hash*(d: ContentDisposition): Hash =
  ## Hash mixing the kind ordinal with the raw identifier for
  ## ``cdExtension``. Consistent with ``==``.
  var h: Hash = 0
  h = h !& hash(ord(d.rawKind))
  case d.rawKind
  of cdExtension:
    h = h !& hash(d.rawIdentifier)
  of cdInline, cdAttachment:
    discard
  result = !$h

const
  dispositionInline* = ContentDisposition(rawKind: cdInline)
    ## RFC 2183 §2.1 well-known disposition.
  dispositionAttachment* = ContentDisposition(rawKind: cdAttachment)
    ## RFC 2183 §2.1 well-known disposition.

func parseContentDisposition*(
    raw: string
): Result[ContentDisposition, ValidationError] =
  ## Validates and constructs a ``ContentDisposition``. Rejects empty
  ## input and control characters; lowercase-normalises (§2.1: values
  ## are not case-sensitive) and classifies against the two well-known
  ## IANA types, falling back to ``cdExtension`` for §2.8 vendor-
  ## extension and x-tokens. Lossless round-trip over the wire.
  ## Single parser — no strict/lenient pair (same rationale as
  ## ``parseMailboxRole``).
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "ContentDisposition", raw))
  let normalised = raw.toLowerAscii()
  let parsed = parseEnum[ContentDispositionKind](normalised, cdExtension)
  case parsed
  of cdInline:
    return ok(dispositionInline)
  of cdAttachment:
    return ok(dispositionAttachment)
  of cdExtension:
    return ok(ContentDisposition(rawKind: cdExtension, rawIdentifier: normalised))

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
  disposition*: Opt[ContentDisposition]
    ## RFC 2183 §2.1 disposition or none. Parsed at wire boundary.
  cid*: Opt[string] ## Content-Id without angle brackets.
  language*: Opt[seq[string]] ## Content-Language tags.
  location*: Opt[string] ## Content-Location URI.
  size*: UnsignedInt ## RFC unconditional — all parts.
  case isMultipart*: bool
  of true:
    subParts*: seq[EmailBodyPart] ## Recursive children.
  of false:
    partId*: PartId ## Unique within the Email.
    blobId*: BlobId ## Reference to content blob.

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

type BlueprintLeafPart* {.ruleOff: "objects".} = object
  ## The content half of a non-multipart ``BlueprintBodyPart``. Extracted
  ## from what was previously an inner case-object branch of
  ## ``BlueprintBodyPart`` so strict-flow-analysis can track each
  ## discriminator independently: the outer ``BlueprintBodyPart.isMultipart``
  ## and the inner ``BlueprintLeafPart.source``.
  ##
  ## Nim's strictCaseObjects flow analysis does not propagate nested
  ## case-object facts (empirically verified — see CLAUDE.md under the
  ## strict section). Hoisting the inner case into its own type is the
  ## structural fix.
  case source*: BlueprintPartSource
  of bpsInline:
    partId*: PartId ## Co-located reference to the body value (R3-3).
    value*: BlueprintBodyValue ## Co-located content (Design §5.1, R3-3).
  of bpsBlobRef:
    blobId*: BlobId
    size*: Opt[UnsignedInt] ## Optional, ignored by server.
    charset*: Opt[string]

type BlueprintBodyPart* {.ruleOff: "objects".} = object
  ## Body structure for Email creation (RFC 8621 §4.6). The outer
  ## ``isMultipart`` separates containers from leaves; leaves carry a
  ## ``BlueprintLeafPart`` whose own case discriminates inline vs
  ## blob-referenced content.
  contentType*: string
  name*: Opt[string]
  disposition*: Opt[ContentDisposition]
  cid*: Opt[string]
  language*: Opt[seq[string]]
  location*: Opt[string]
  extraHeaders*: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]
  case isMultipart*: bool
  of true:
    subParts*: seq[BlueprintBodyPart] ## Recursive children.
  of false:
    leaf*: BlueprintLeafPart
