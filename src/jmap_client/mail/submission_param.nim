# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Typed SMTP-parameter algebra carried on each ``Envelope.Address`` entry —
## payload leaves (``BodyEncoding``, ``DsnRetType``, ``DsnNotifyFlag``,
## ``DeliveryByMode``, ``HoldForSeconds``, ``MtPriority``), the
## ``SubmissionParam`` case-object variant with its twelve smart
## constructors, the identity-key projection ``SubmissionParamKey``, and the
## duplicate-free bag ``SubmissionParams``.
##
## Lifts each parameter's subordinate-RFC structural invariants into the
## type so detection and serialisation share a single source of truth
## (RFC 1652 / RFC 6152, RFC 1870, RFC 2852, RFC 3461, RFC 4865, RFC 6531,
## RFC 6710, RFC 8621 §7).
##
## Design authority: ``docs/design/12-mail-G1-design.md`` §2.3–2.4.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sets
import std/tables

import ../primitives
import ../validation

import ./submission_atoms

# ===========================================================================
# SMTP parameter payload leaves — design §2.3
# ===========================================================================

type BodyEncoding* = enum
  ## RFC 1652 / RFC 6152 ``BODY=`` parameter values. Selects whether the
  ## submission MTA treats the message as 7-bit, 8-bit-clean MIME, or
  ## binary MIME. Backing strings are the IANA-registered tokens.
  beSevenBit = "7BIT"
  beEightBitMime = "8BITMIME"
  beBinaryMime = "BINARYMIME"

type DsnRetType* = enum
  ## RFC 3461 §4.3 ``RET=`` parameter value. ``FULL`` requests return of
  ## the whole message on failure; ``HDRS`` requests return of headers
  ## only.
  retFull = "FULL"
  retHdrs = "HDRS"

type DsnNotifyFlag* = enum
  ## RFC 3461 §4.1 ``NOTIFY=`` parameter flag. A non-empty ``set`` of
  ## these flags forms the wire value; ``dnfNever`` is mutually exclusive
  ## with the other three — enforced by ``notifyParam``.
  dnfNever = "NEVER"
  dnfSuccess = "SUCCESS"
  dnfFailure = "FAILURE"
  dnfDelay = "DELAY"

type DeliveryByMode* = enum
  ## RFC 2852 §3 ``BY=`` parameter mode suffix. ``R`` / ``N`` request
  ## return-on-deadline / notify-on-deadline; the ``T`` variants also
  ## request trace-header insertion on deadline expiry.
  dbmReturn = "R"
  dbmNotify = "N"
  dbmReturnTrace = "RT"
  dbmNotifyTrace = "NT"

# ===========================================================================
# HoldForSeconds — RFC 4865 FUTURERELEASE delay form
# ===========================================================================

type HoldForSeconds* = distinct UnsignedInt
  ## Delay-in-seconds payload for the RFC 4865 ``HOLDFOR=`` extension.
  ## Narrows ``UnsignedInt`` at the type level so mixing an arbitrary
  ## ``UnsignedInt`` with a HOLDFOR value at the call site is a compile
  ## error.

defineIntDistinctOps(HoldForSeconds)

func parseHoldForSeconds*(raw: UnsignedInt): Result[HoldForSeconds, ValidationError] =
  ## Infallible typed wrap — ``UnsignedInt`` already enforces the JSON-
  ## safe bound ``0 .. 2^53 - 1`` at its own smart constructor, so there
  ## is nothing left to reject here. The ``Result``-returning signature
  ## mirrors the other ``parse*`` functions so callers compose uniformly
  ## with ``?`` / ``valueOr:``.
  return ok(HoldForSeconds(raw))

# ===========================================================================
# MtPriority — RFC 6710 MT-PRIORITY
# ===========================================================================

type MtPriority* = distinct int
  ## RFC 6710 §2 ``MT-PRIORITY=`` parameter value, constrained to the
  ## inclusive range ``-9 .. 9``. A raw ``int`` field would let an out-
  ## of-range value slip past construction; ``range[int]`` was rejected
  ## because ``RangeDefect`` is fatal under ``--panics:on``
  ## (``.claude/rules/nim-type-safety.md``).

defineIntDistinctOps(MtPriority)

func parseMtPriority*(raw: int): Result[MtPriority, ValidationError] =
  ## Strict: enforces the inclusive ``-9 .. 9`` bound of RFC 6710 §2.
  if raw < -9 or raw > 9:
    return err(validationError("MtPriority", "must be in range -9..9", $raw))
  return ok(MtPriority(raw))

# ===========================================================================
# SubmissionParam — typed SMTP parameter algebra (design §2.3)
# ===========================================================================

type SubmissionParamKind* = enum
  ## Discriminator for ``SubmissionParam``. Eleven well-known variants
  ## cover IANA-registered RFC 5321 / RFC 3461 / RFC 1652 / RFC 6152 /
  ## RFC 1870 / RFC 2852 / RFC 6710 / RFC 4865 / RFC 6531 extensions;
  ## ``spkExtension`` is the open-world escape hatch for unregistered or
  ## vendor tokens (RFC 8621 §7 ¶5). Backing strings match the wire key
  ## preserved upper-case per SMTP convention.
  spkBody = "BODY"
  spkSmtpUtf8 = "SMTPUTF8"
  spkSize = "SIZE"
  spkEnvid = "ENVID"
  spkRet = "RET"
  spkNotify = "NOTIFY"
  spkOrcpt = "ORCPT"
  spkHoldFor = "HOLDFOR"
  spkHoldUntil = "HOLDUNTIL"
  spkBy = "BY"
  spkMtPriority = "MT-PRIORITY"
  spkExtension

type SubmissionParam* {.ruleOff: "objects".} = object
  ## Validated SMTP parameter value as carried on an
  ## ``EmailSubmission.Envelope.Address`` entry. Twelve variants — eleven
  ## well-known plus one open-world ``spkExtension`` — lift each
  ## parameter's subordinate-RFC structural invariants into the type so
  ## detection and serialisation share a single source of truth.
  case kind*: SubmissionParamKind
  of spkBody:
    bodyEncoding*: BodyEncoding
  of spkSmtpUtf8:
    discard
  of spkSize:
    sizeOctets*: UnsignedInt
  of spkEnvid:
    envid*: string
  of spkRet:
    retType*: DsnRetType
  of spkNotify:
    notifyFlags*: set[DsnNotifyFlag]
  of spkOrcpt:
    orcptAddrType*: OrcptAddrType
    orcptOrigRecipient*: string
  of spkHoldFor:
    holdFor*: HoldForSeconds
  of spkHoldUntil:
    holdUntil*: UTCDate
  of spkBy:
    byDeadline*: JmapInt
    byMode*: DeliveryByMode
  of spkMtPriority:
    mtPriority*: MtPriority
  of spkExtension:
    extName*: RFC5321Keyword
    extValue*: Opt[string]

# ---------------------------------------------------------------------------
# Smart constructors (alphabetical by SubmissionParamKind for reviewability)
# ---------------------------------------------------------------------------

func bodyParam*(e: BodyEncoding): SubmissionParam =
  ## ``BODY=7BIT|8BITMIME|BINARYMIME`` — RFC 1652 / RFC 6152.
  SubmissionParam(kind: spkBody, bodyEncoding: e)

func byParam*(deadline: JmapInt, mode: DeliveryByMode): SubmissionParam =
  ## ``BY=<deadline>;<mode>`` — RFC 2852 §3 deliver-by parameter.
  SubmissionParam(kind: spkBy, byDeadline: deadline, byMode: mode)

func envidParam*(envid: string): SubmissionParam =
  ## ``ENVID=`` — RFC 3461 §4.4 envelope identifier. The xtext wire
  ## encoding belongs to the serde layer (design §7.2); L1 carries the
  ## decoded bytes.
  SubmissionParam(kind: spkEnvid, envid: envid)

func extensionParam*(name: RFC5321Keyword, value: Opt[string]): SubmissionParam =
  ## Open-world escape hatch for unregistered / vendor SMTP parameters
  ## (RFC 8621 §7 ¶5). ``name`` already carries esmtp-keyword invariants;
  ## ``value`` is ``Opt.none`` for valueless tokens.
  SubmissionParam(kind: spkExtension, extName: name, extValue: value)

func holdForParam*(seconds: HoldForSeconds): SubmissionParam =
  ## ``HOLDFOR=<seconds>`` — RFC 4865 FUTURERELEASE delay form.
  SubmissionParam(kind: spkHoldFor, holdFor: seconds)

func holdUntilParam*(d: UTCDate): SubmissionParam =
  ## ``HOLDUNTIL=<RFC 3339 Zulu>`` — RFC 4865 FUTURERELEASE absolute-time
  ## form.
  SubmissionParam(kind: spkHoldUntil, holdUntil: d)

func mtPriorityParam*(p: MtPriority): SubmissionParam =
  ## ``MT-PRIORITY=<-9..9>`` — RFC 6710 §2.
  SubmissionParam(kind: spkMtPriority, mtPriority: p)

func notifyParam*(flags: set[DsnNotifyFlag]): Result[SubmissionParam, ValidationError] =
  ## ``NOTIFY=<flag[,flag...]>`` — RFC 3461 §4.1. Rejects the empty set
  ## and the mutually-exclusive combination ``NEVER`` with any of
  ## ``SUCCESS``/``FAILURE``/``DELAY``.
  if flags == {}:
    return err(validationError("SubmissionParam", "NOTIFY flags must not be empty", ""))
  if dnfNever in flags and flags != {dnfNever}:
    return err(
      validationError(
        "SubmissionParam",
        "NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY", "",
      )
    )
  return ok(SubmissionParam(kind: spkNotify, notifyFlags: flags))

func orcptParam*(at: OrcptAddrType, origRecipient: string): SubmissionParam =
  ## ``ORCPT=<addr-type>;<orig-recipient>`` — RFC 3461 §4.2. The
  ## original-recipient xtext encoding belongs to the serde layer; L1
  ## carries the decoded bytes.
  SubmissionParam(kind: spkOrcpt, orcptAddrType: at, orcptOrigRecipient: origRecipient)

func retParam*(t: DsnRetType): SubmissionParam =
  ## ``RET=FULL|HDRS`` — RFC 3461 §4.3.
  SubmissionParam(kind: spkRet, retType: t)

func sizeParam*(octets: UnsignedInt): SubmissionParam =
  ## ``SIZE=<octets>`` — RFC 1870 advisory octet count.
  SubmissionParam(kind: spkSize, sizeOctets: octets)

func smtpUtf8Param*(): SubmissionParam =
  ## ``SMTPUTF8`` — RFC 6531 §3.4 valueless parameter.
  SubmissionParam(kind: spkSmtpUtf8)

func `==`*(a, b: SubmissionParam): bool =
  ## Structural equality across the twelve variants. Nim's auto-derived
  ## tuple/object ``==`` uses a parallel ``fields`` iterator that rejects
  ## case objects, so this dispatches on the shared discriminator and
  ## compares only the fields valid for the matched arm.
  ##
  ## Nested case on both operands — strict doesn't propagate ``a.kind ==
  ## b.kind`` from an outer if-guard into each ``of`` branch, so b's
  ## discriminator must be proved independently before reading b's
  ## variant fields.
  case a.kind
  of spkBody:
    case b.kind
    of spkBody:
      a.bodyEncoding == b.bodyEncoding
    else:
      false
  of spkSmtpUtf8:
    case b.kind
    of spkSmtpUtf8: true
    else: false
  of spkSize:
    case b.kind
    of spkSize:
      a.sizeOctets == b.sizeOctets
    else:
      false
  of spkEnvid:
    case b.kind
    of spkEnvid:
      a.envid == b.envid
    else:
      false
  of spkRet:
    case b.kind
    of spkRet:
      a.retType == b.retType
    else:
      false
  of spkNotify:
    case b.kind
    of spkNotify:
      a.notifyFlags == b.notifyFlags
    else:
      false
  of spkOrcpt:
    case b.kind
    of spkOrcpt:
      a.orcptAddrType == b.orcptAddrType and a.orcptOrigRecipient == b.orcptOrigRecipient
    else:
      false
  of spkHoldFor:
    case b.kind
    of spkHoldFor:
      a.holdFor == b.holdFor
    else:
      false
  of spkHoldUntil:
    case b.kind
    of spkHoldUntil:
      a.holdUntil == b.holdUntil
    else:
      false
  of spkBy:
    case b.kind
    of spkBy:
      a.byDeadline == b.byDeadline and a.byMode == b.byMode
    else:
      false
  of spkMtPriority:
    case b.kind
    of spkMtPriority:
      a.mtPriority == b.mtPriority
    else:
      false
  of spkExtension:
    case b.kind
    of spkExtension:
      a.extName == b.extName and a.extValue == b.extValue
    else:
      false

# ---------------------------------------------------------------------------
# SubmissionParamKey — identity key for structural uniqueness
# ---------------------------------------------------------------------------

type SubmissionParamKey* {.ruleOff: "objects".} = object
  ## Structural identity of a ``SubmissionParam`` — the wire-key axis on
  ## which uniqueness is enforced by ``SubmissionParams``. Eleven well-
  ## known arms are nullary; ``spkExtension`` carries the validated
  ## ``RFC5321Keyword`` name so two extensions with distinct names remain
  ## distinct keys.
  case kind*: SubmissionParamKind
  of spkExtension:
    extName*: RFC5321Keyword
  of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
      spkHoldUntil, spkBy, spkMtPriority:
    discard

func `==`*(a, b: SubmissionParamKey): bool =
  ## Equal iff the discriminators agree and, for ``spkExtension``, the
  ## keyword names are case-insensitively equal (delegated to
  ## ``RFC5321Keyword.==``).
  ##
  ## Nested case for strictCaseObjects: b.kind must be proved
  ## independently before reading b.extName.
  case a.kind
  of spkExtension:
    case b.kind
    of spkExtension:
      a.extName == b.extName
    of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
        spkHoldUntil, spkBy, spkMtPriority:
      false
  of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
      spkHoldUntil, spkBy, spkMtPriority:
    case b.kind
    of spkExtension:
      false
    of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
        spkHoldUntil, spkBy, spkMtPriority:
      a.kind == b.kind

func hash*(k: SubmissionParamKey): Hash =
  ## Delegates the ``spkExtension`` payload to ``hash(RFC5321Keyword)``,
  ## which case-folds before hashing — otherwise two keys that compare
  ## equal case-insensitively would land in different buckets and silently
  ## break ``Table.contains`` / ``[]=`` lookups (Table contract:
  ## ``a == b`` ⇒ ``hash(a) == hash(b)``).
  case k.kind
  of spkExtension:
    var h: Hash = 0
    h = h !& hash(spkExtension.ord)
    h = h !& hash(k.extName)
    !$h
  of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
      spkHoldUntil, spkBy, spkMtPriority:
    hash(k.kind.ord)

func paramKey*(p: SubmissionParam): SubmissionParamKey =
  ## Derives the identity key for a ``SubmissionParam``. Nullary arms
  ## collapse to a kind-only key; ``spkExtension`` carries its validated
  ## keyword name. Functional-core Pattern 6 "derived-not-stored" —
  ## one source of truth per fact.
  case p.kind
  of spkExtension:
    SubmissionParamKey(kind: spkExtension, extName: p.extName)
  of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
      spkHoldUntil, spkBy, spkMtPriority:
    SubmissionParamKey(kind: p.kind)

# ---------------------------------------------------------------------------
# SubmissionParams — structural uniqueness with wire-order fidelity
# ---------------------------------------------------------------------------

type SubmissionParams* = distinct OrderedTable[SubmissionParamKey, SubmissionParam]
  ## Validated, duplicate-free collection of ``SubmissionParam`` values
  ## carrying a single ``Envelope.Address`` parameter bag. Construction
  ## is gated by ``parseSubmissionParams`` — the raw distinct constructor
  ## is not part of the public surface. Serde (Step 10) and per-address
  ## lookups (Step 3) cast back to the underlying ``OrderedTable`` at
  ## use sites; accessors are intentionally not borrowed because mutable
  ## stdlib containers don't borrow subscripts cleanly.

func `==`*(a, b: SubmissionParams): bool {.borrow.}
  ## Structural equality delegated to the underlying ``OrderedTable``.

func `$`*(a: SubmissionParams): string {.borrow.}
  ## Textual form delegated to the underlying ``OrderedTable`` —
  ## diagnostic only; serde (Step 10) owns the wire form.

func detectDuplicateParamKeys(items: openArray[SubmissionParam]): seq[ValidationError] =
  ## One ``ValidationError`` per repeated ``SubmissionParamKey``, each
  ## key reported at most once. Empty input is accepted —
  ## ``parseSubmissionParams`` does not reject an empty
  ## ``SubmissionParams``. Functional-core Pattern 7 "imperative kernel
  ## inside a functional shell": two local ``HashSet``s are invisible
  ## outside the call.
  var seen = initHashSet[SubmissionParamKey]()
  var reported = initHashSet[SubmissionParamKey]()
  result = @[]
  for item in items:
    let k = paramKey(item)
    if seen.containsOrIncl(k):
      if not reported.containsOrIncl(k):
        let label =
          case k.kind
          of spkExtension:
            "extension " & $k.extName
          of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt,
              spkHoldFor, spkHoldUntil, spkBy, spkMtPriority:
            $k.kind
        result.add(
          validationError("SubmissionParams", "duplicate parameter key", label)
        )

func parseSubmissionParams*(
    items: openArray[SubmissionParam]
): Result[SubmissionParams, seq[ValidationError]] =
  ## Strict client-side constructor (design §2.4 G8a): rejects duplicate
  ## keys accumulatingly — every repeated key produces exactly one
  ## ``ValidationError``. Empty input is accepted — an empty
  ## ``SubmissionParams`` represents the wire JSON object ``{}`` and is
  ## distinct from ``Opt.none(SubmissionParams)`` representing ``null``
  ## (design §2.4 G34).
  let errs = detectDuplicateParamKeys(items)
  if errs.len > 0:
    return err(errs)
  var t = initOrderedTable[SubmissionParamKey, SubmissionParam]()
  for item in items:
    t[paramKey(item)] = item
  return ok(SubmissionParams(t))
