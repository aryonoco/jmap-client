# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Capture helper for the live integration suite. Persists the raw bytes
## of a Stalwart wire response into ``tests/testdata/captured/<name>.json``
## when the operator opts in via env var. The captured fixtures feed the
## always-on parser-only replay tests under ``tests/serde/captured/``.
## ``testdata`` is hardcoded into testament's category skip-list, so the
## directory is silently ignored when ``just test`` enumerates test
## categories — fixtures may sit there as bare ``.json`` files.
##
## Behaviour:
##   - When ``JMAP_TEST_CAPTURE`` is unset (or any value other than "1"),
##     ``captureIfRequested`` is a no-op — ``just test-integration`` runs
##     byte-for-byte unchanged.
##   - When ``JMAP_TEST_CAPTURE == "1"`` and the destination file does
##     NOT yet exist, the bytes from ``client.lastRawResponseBody`` are
##     written.
##   - When ``JMAP_TEST_CAPTURE == "1"`` and the destination file DOES
##     exist, the write is skipped — the committed fixture is the source
##     of truth. Set ``JMAP_TEST_CAPTURE_FORCE == "1"`` to force overwrite
##     after a deliberate Stalwart change.
##
## ``proc`` (not ``func``) because every operation in the body — env
## lookup, ``createDir``, ``fileExists``, ``writeFile`` — is IO. Lives
## under ``tests/integration/live/`` alongside ``mlive.nim``, the existing
## L4-style helper module for live tests.

{.push raises: [].}

import std/os

import results

import jmap_client/client

const capturedFixturesDir* = "tests/testdata/captured"
  ## Workspace-relative directory holding the committed Stalwart wire
  ## payloads. Both ``captureIfRequested`` (write side) and
  ## ``mloader.loadCapturedFixture`` (read side) anchor on this path.

proc captureIfRequested*(client: JmapClient, name: string): Result[void, string] =
  ## Writes ``client.lastRawResponseBody`` to
  ## ``tests/testdata/captured/<name>.json`` when the operator has opted
  ## in. See module docstring for the env-var contract.
  if getEnv("JMAP_TEST_CAPTURE") != "1":
    return ok()
  let body = client.lastRawResponseBody
  if body.len == 0:
    return err("captureIfRequested: empty body for " & name)
  let path = capturedFixturesDir & "/" & name & ".json"
  if fileExists(path) and getEnv("JMAP_TEST_CAPTURE_FORCE") != "1":
    return ok() # committed fixture is source of truth
  try:
    createDir(capturedFixturesDir)
    writeFile(path, body)
    ok()
  except IOError, OSError:
    err("captureIfRequested: write failed for " & path)
