# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Semantically distinct identifier types built on Id validation rules. Separate
## from primitives.nim because these omit `len` — length is meaningless for
## opaque server tokens.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/[hashes, strutils]

import ./validation

type AccountId* {.ruleOff: "objects".} = object
  ## Server-assigned account identifier (RFC 8620 §2). Sealed Pattern-A
  ## object; ``rawValue`` is module-private. Distinct from ``Id`` to
  ## prevent cross-use.
  rawValue: string

defineSealedStringOps(AccountId)

type JmapState* {.ruleOff: "objects".} = object
  ## Opaque server state token for change tracking (RFC 8620 §5.3).
  ## Sealed Pattern-A object — no ``len`` accessor because the underlying
  ## byte length carries no domain meaning.
  rawValue: string

defineSealedOpaqueStringOps(JmapState)

type MethodCallId* {.ruleOff: "objects".} = object
  ## Client-assigned tag correlating requests with responses in a batch
  ## (RFC 8620 §3.2). Sealed Pattern-A object — opaque token, no ``len``.
  rawValue: string

defineSealedOpaqueStringOps(MethodCallId)

type CreationId* {.ruleOff: "objects".} = object
  ## Client-assigned temporary ID for back-references within a /set call
  ## (RFC 8620 §5.3). Wire format prefixes with '#'. Sealed Pattern-A
  ## object — opaque token, no ``len``.
  rawValue: string

defineSealedOpaqueStringOps(CreationId)

type BlobId* {.ruleOff: "objects".} = object
  ## Server-assigned opaque blob identifier (RFC 8620 §3.2). Sealed
  ## Pattern-A object — opaque token, no ``len``. Callers that need
  ## length must explicitly project the underlying string (e.g.
  ## ``($blobId).len``), making opacity explicit at the call site.
  rawValue: string

defineSealedOpaqueStringOps(BlobId)

type BuilderId* {.ruleOff: "objects".} = object
  ## Per-builder dispatch brand. Minted by ``JmapClient.newBuilder``;
  ## carried by every handle and by the ``DispatchedResponse`` returned
  ## from ``send``. Composite:
  ## - ``clientBrand`` identifies the issuing ``JmapClient`` (random,
  ##   64-bit; minted once at ``JmapClient`` construction via
  ##   ``std/sysrand.urandom``).
  ## - ``serial`` identifies the builder within that client (monotonic
  ##   ``uint64`` counter incremented inside ``JmapClient.newBuilder``).
  ## No wire form — internal-only.
  rawClientBrand: uint64
  rawSerial: uint64

func initBuilderId*(clientBrand, serial: uint64): BuilderId =
  ## Sole construction path for ``BuilderId``. Exported with ``*`` so
  ## internal callers (``client.nim``, builders, dispatch, tests under
  ## ``tests/``) can construct it, while ``types.nim`` filters this
  ## symbol from the hub re-export to keep it unreachable through
  ## ``import jmap_client``.
  BuilderId(rawClientBrand: clientBrand, rawSerial: serial)

func clientBrand*(b: BuilderId): uint64 =
  ## Diagnostic accessor — the ``clientBrand`` half of the composite.
  b.rawClientBrand

func serial*(b: BuilderId): uint64 =
  ## Diagnostic accessor — the ``serial`` half of the composite.
  b.rawSerial

func `==`*(a, b: BuilderId): bool =
  ## Structural equality across both halves.
  a.rawClientBrand == b.rawClientBrand and a.rawSerial == b.rawSerial

func hash*(a: BuilderId): Hash =
  ## Hash combining both halves via ``std/hashes`` ``!&`` / ``!$``
  ## mixer.
  !$(hash(a.rawClientBrand) !& hash(a.rawSerial))

func `$`*(a: BuilderId): string =
  ## Diagnostic textual form. Fixed layout — tests assert on the
  ## prefix.
  "BuilderId(brand=0x" & toHex(a.rawClientBrand.int64, 16) & ", serial=" & $a.rawSerial &
    ")"

func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## AccountIds are server-assigned Id[Account] values (§1.6.2, §2) —
  ## same lenient rules as parseIdFromServer.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "AccountId", raw))
  return ok(AccountId(rawValue: raw))

func parseJmapState*(raw: string): Result[JmapState, ValidationError] =
  ## Non-empty, no control characters. Server-assigned — same defensive
  ## checks as other server-assigned identifiers.
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "JmapState", raw))
  return ok(JmapState(rawValue: raw))

func parseMethodCallId*(raw: string): Result[MethodCallId, ValidationError] =
  ## Non-empty. Client-generated.
  detectNonEmpty(raw).isOkOr:
    return err(toValidationError(error, "MethodCallId", raw))
  return ok(MethodCallId(rawValue: raw))

func parseCreationId*(raw: string): Result[CreationId, ValidationError] =
  ## Non-empty. Must not start with '#' (the prefix is a wire-format concern).
  detectNonEmptyNoPrefix(raw).isOkOr:
    return err(toValidationError(error, "CreationId", raw))
  return ok(CreationId(rawValue: raw))

func parseBlobId*(raw: string): Result[BlobId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## Server-assigned — same lenient rules as parseIdFromServer.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "BlobId", raw))
  return ok(BlobId(rawValue: raw))
