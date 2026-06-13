# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## URL reference resolution for JMAP session document URLs (RFC 3986
## §5). Internal to the client because URL semantics are an
## implementation detail of how JMAP talks to HTTP; not part of the
## public commitment.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/strutils
import std/uri

func resolveAgainstSession*(sessionUrl, urlOrPath: string): string =
  ## Resolves ``urlOrPath`` against the session URL per RFC 3986 §5.
  ##
  ## RFC 8620 §2 defines the session document URLs (apiUrl,
  ## downloadUrl, uploadUrl, eventSourceUrl) as URLs without explicitly
  ## mandating absolute form. Some conformant servers (Cyrus 3.12.2,
  ## ``imap/jmap_api.c``) emit relative references (``"/jmap/"``) so the
  ## client resolves any reference against the known-absolute session
  ## URL — Postel-tolerant on receive.
  ##
  ## When ``urlOrPath`` already carries a scheme, it is returned
  ## unchanged. When it is relative, ``std/uri.combine`` performs the
  ## RFC 3986 §5 resolution against ``sessionUrl``.
  if urlOrPath.startsWith("http://") or urlOrPath.startsWith("https://"):
    return urlOrPath
  $combine(parseUri(sessionUrl), parseUri(urlOrPath))
