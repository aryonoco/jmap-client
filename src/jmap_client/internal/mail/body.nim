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

import ../types/validation
import ../types/primitives
import ../types/identifiers
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

type PartId* {.ruleOff: "objects".} = object
  ## Body part identifier, unique within an Email (RFC 8621 §4.1.4).
  ## Typed as ``String`` (not ``Id``), so no length limit applies.
  ## Sealed Pattern-A object — ``rawValue`` is module-private.
  rawValue: string

defineSealedStringOps(PartId)

func parsePartIdFromServer*(raw: string): Result[PartId, ValidationError] =
  ## Lenient parser for server-provided part identifiers. Validates non-empty
  ## and rejects control characters (< 0x20) as a defensive measure.
  if raw.len == 0:
    return err(validationError("PartId", "must not be empty", raw))
  if raw.anyIt(ord(it) < 0x20):
    return err(validationError("PartId", "contains control characters", raw))
  return ok(PartId(rawValue: raw))

func parseFromString*(
    T: typedesc[PartId], raw: string
): Result[PartId, ValidationError] =
  ## ``parseFromString`` typedesc-overload adapter consumed by the generic
  ## ``Table[K, V].fromJson`` in ``serialisation/serde.nim``. Delegates to
  ## ``parsePartIdFromServer`` — server-emitted ``PartId`` keys take the
  ## lenient path on the receive side (Postel's law).
  discard $T
  return parsePartIdFromServer(raw)

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
  ##
  ## Fully sealed: every field including the ``rawSource`` discriminator is
  ## module-private, so neither a payload literal nor a discriminator-only
  ## one is constructible elsewhere. Leaves are minted by ``inlinePart`` /
  ## ``blobRefPart`` and read through the accessors below.
  case rawSource: BlueprintPartSource
  of bpsInline:
    rawPartId: PartId
    rawValue: BlueprintBodyValue
  of bpsBlobRef:
    rawBlobId: BlobId
    rawSize: Opt[UnsignedInt]
    rawCharset: Opt[string]

type BlueprintBodyPart* {.ruleOff: "objects".} = object
  ## Body structure for Email creation (RFC 8621 §4.6). The outer
  ## ``isMultipart`` separates containers from leaves; leaves carry a
  ## ``BlueprintLeafPart`` whose own case discriminates inline vs
  ## blob-referenced content.
  ##
  ## Fully sealed like ``BlueprintLeafPart``: the three total constructors
  ## ``inlinePart`` / ``blobRefPart`` / ``multipartPart`` are the only way
  ## in, and the same-name accessors the only way out. A part carries no
  ## invariant of its own — it is a shape. Whether a tree of them is a
  ## legal Email body is judged once, by ``parseEmailBlueprint``.
  rawContentType: string
  rawName: Opt[string]
  rawDisposition: Opt[ContentDisposition]
  rawCid: Opt[string]
  rawLanguage: Opt[seq[string]]
  rawLocation: Opt[string]
  rawExtraHeaders: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]
  case rawIsMultipart: bool
  of true:
    rawSubParts: seq[BlueprintBodyPart]
  of false:
    rawLeaf: BlueprintLeafPart

func source*(leaf: BlueprintLeafPart): BlueprintPartSource =
  ## Where the leaf's content comes from: carried inline in the blueprint,
  ## or referenced as a previously uploaded blob.
  leaf.rawSource

func partId*(leaf: BlueprintLeafPart): Opt[PartId] =
  ## Creation-time identifier under which an inline leaf's content travels
  ## in the top-level ``bodyValues`` object. ``Opt.none`` for a blob-ref
  ## leaf, which names its content by ``blobId`` instead.
  case leaf.rawSource
  of bpsInline:
    Opt.some(leaf.rawPartId)
  of bpsBlobRef:
    Opt.none(PartId)

func value*(leaf: BlueprintLeafPart): Opt[BlueprintBodyValue] =
  ## Content co-located with the ``partId`` that carries it; ``Opt.none``
  ## for a blob-ref leaf, whose content is already on the server.
  case leaf.rawSource
  of bpsInline:
    Opt.some(leaf.rawValue)
  of bpsBlobRef:
    Opt.none(BlueprintBodyValue)

func blobId*(leaf: BlueprintLeafPart): Opt[BlobId] =
  ## Reference to the uploaded blob holding the content; ``Opt.none`` for
  ## an inline leaf.
  case leaf.rawSource
  of bpsInline:
    Opt.none(BlobId)
  of bpsBlobRef:
    Opt.some(leaf.rawBlobId)

func size*(leaf: BlueprintLeafPart): Opt[UnsignedInt] =
  ## Octet count declared alongside a blob reference — advisory, the server
  ## may ignore it. ``Opt.none`` for an inline leaf, which declares none.
  case leaf.rawSource
  of bpsInline:
    Opt.none(UnsignedInt)
  of bpsBlobRef:
    leaf.rawSize

func charset*(leaf: BlueprintLeafPart): Opt[string] =
  ## Character set declared alongside a blob reference. ``Opt.none`` for an
  ## inline leaf, whose content is carried as decoded text.
  case leaf.rawSource
  of bpsInline:
    Opt.none(string)
  of bpsBlobRef:
    leaf.rawCharset

func contentType*(part: BlueprintBodyPart): string =
  ## MIME type of the part, e.g. ``text/plain`` or ``multipart/mixed``.
  part.rawContentType

func name*(part: BlueprintBodyPart): Opt[string] =
  ## Filename to suggest to the recipient (RFC 8621 §4.1.4).
  part.rawName

func disposition*(part: BlueprintBodyPart): Opt[ContentDisposition] =
  ## RFC 2183 §2.1 disposition, or ``Opt.none`` to leave the choice to the
  ## receiving client.
  part.rawDisposition

func cid*(part: BlueprintBodyPart): Opt[string] =
  ## Content-Id without angle brackets — the target of a ``cid:`` URL in a
  ## sibling HTML part.
  part.rawCid

func language*(part: BlueprintBodyPart): Opt[seq[string]] =
  ## Content-Language tags for the part.
  part.rawLanguage

func location*(part: BlueprintBodyPart): Opt[string] =
  ## Content-Location URI for the part.
  part.rawLocation

func extraHeaders*(
    part: BlueprintBodyPart
): lent Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue] =
  ## Part headers set verbatim, keyed by typed name. Borrowed view
  ## (``lent``) — read-only, no per-call copy of the table.
  part.rawExtraHeaders

func isMultipart*(part: BlueprintBodyPart): bool =
  ## Whether the part is a container (children in ``subParts``) rather than
  ## a leaf (content in ``leaf``).
  part.rawIsMultipart

func subParts*(part: BlueprintBodyPart): seq[BlueprintBodyPart] =
  ## Children of a container part; empty for a leaf, which holds content
  ## rather than children. Returns a copy — the sealed subtree is never
  ## aliased out. Traversal belongs to the ``subParts`` iterator below,
  ## which costs nothing per node.
  case part.rawIsMultipart
  of true:
    part.rawSubParts
  of false:
    @[]

iterator subParts*(part: BlueprintBodyPart): lent BlueprintBodyPart =
  ## Children of a container part, borrowed one at a time; a leaf yields
  ## nothing. A ``for`` loop resolves here in preference to the accessor
  ## above, which matters because a recursive walk over the seq form would
  ## copy the whole subtree once per node visited.
  case part.rawIsMultipart
  of true:
    for child in part.rawSubParts:
      yield child
  of false:
    discard

func leaf*(part: BlueprintBodyPart): Opt[BlueprintLeafPart] =
  ## Content half of a leaf part; ``Opt.none`` for a container, whose
  ## content lives in the leaves below it. Returns a copy; the ``leaf``
  ## iterator below is the reading form.
  case part.rawIsMultipart
  of true:
    Opt.none(BlueprintLeafPart)
  of false:
    Opt.some(part.rawLeaf)

iterator leaf*(part: BlueprintBodyPart): lent BlueprintLeafPart =
  ## Content half of a leaf part, borrowed; a container yields nothing.
  ## Same arity as iterating the ``Opt`` the accessor returns — zero or one
  ## yield — but an inline leaf carries its entire body value, so the
  ## copying form is the wrong default for a tree walk.
  case part.rawIsMultipart
  of true:
    discard
  of false:
    yield part.rawLeaf

func inlinePart*(
    partId: PartId,
    contentType: string,
    value: string,
    name: Opt[string] = Opt.none(string),
    disposition: Opt[ContentDisposition] = Opt.none(ContentDisposition),
    cid: Opt[string] = Opt.none(string),
    language: Opt[seq[string]] = Opt.none(seq[string]),
    location: Opt[string] = Opt.none(string),
    extraHeaders: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue] =
      initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
): BlueprintBodyPart =
  ## A leaf whose content travels inside the creation request: ``value`` is
  ## harvested to the top-level ``bodyValues`` object under ``partId``
  ## (RFC 8621 §4.6). Total — every combination of the arguments is a
  ## representable part; whether the surrounding tree is legal is
  ## ``parseEmailBlueprint``'s question.
  BlueprintBodyPart(
    rawContentType: contentType,
    rawName: name,
    rawDisposition: disposition,
    rawCid: cid,
    rawLanguage: language,
    rawLocation: location,
    rawExtraHeaders: extraHeaders,
    rawIsMultipart: false,
    rawLeaf: BlueprintLeafPart(
      rawSource: bpsInline,
      rawPartId: partId,
      rawValue: BlueprintBodyValue(value: value),
    ),
  )

func blobRefPart*(
    blobId: BlobId,
    contentType: string,
    size: Opt[UnsignedInt] = Opt.none(UnsignedInt),
    charset: Opt[string] = Opt.none(string),
    name: Opt[string] = Opt.none(string),
    disposition: Opt[ContentDisposition] = Opt.none(ContentDisposition),
    cid: Opt[string] = Opt.none(string),
    language: Opt[seq[string]] = Opt.none(seq[string]),
    location: Opt[string] = Opt.none(string),
    extraHeaders: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue] =
      initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
): BlueprintBodyPart =
  ## A leaf whose content is an already-uploaded blob (RFC 8621 §4.6).
  ## ``size`` and ``charset`` are what the client believes about that blob;
  ## the server is free to ignore both. Total, for the same reason as
  ## ``inlinePart``.
  BlueprintBodyPart(
    rawContentType: contentType,
    rawName: name,
    rawDisposition: disposition,
    rawCid: cid,
    rawLanguage: language,
    rawLocation: location,
    rawExtraHeaders: extraHeaders,
    rawIsMultipart: false,
    rawLeaf: BlueprintLeafPart(
      rawSource: bpsBlobRef, rawBlobId: blobId, rawSize: size, rawCharset: charset
    ),
  )

func multipartPart*(
    contentType: string,
    subParts: seq[BlueprintBodyPart],
    name: Opt[string] = Opt.none(string),
    disposition: Opt[ContentDisposition] = Opt.none(ContentDisposition),
    cid: Opt[string] = Opt.none(string),
    language: Opt[seq[string]] = Opt.none(seq[string]),
    location: Opt[string] = Opt.none(string),
    extraHeaders: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue] =
      initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
): BlueprintBodyPart =
  ## A container holding ``subParts`` children, e.g. ``multipart/mixed`` or
  ## ``multipart/alternative`` (RFC 8621 §4.6). Total: an empty child list
  ## and a non-multipart ``contentType`` are both representable here and
  ## judged by ``parseEmailBlueprint``, which sees the whole tree.
  BlueprintBodyPart(
    rawContentType: contentType,
    rawName: name,
    rawDisposition: disposition,
    rawCid: cid,
    rawLanguage: language,
    rawLocation: location,
    rawExtraHeaders: extraHeaders,
    rawIsMultipart: true,
    rawSubParts: subParts,
  )
