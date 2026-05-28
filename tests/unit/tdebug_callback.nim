# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A31: per-handle debug callback wire-inspection. Locks the contract
## that ``setDebugCallback`` installs, replaces, and detaches a
## per-handle callback that fires once per direction (``wdSend``
## then ``wdReceive``) on every transport exchange, with byte-
## identity to the request and response bodies. Nil detaches; the
## library does not provide a separate ``clearDebugCallback``.

{.push raises: [].}

import std/json

import results

import jmap_client
import jmap_client/internal/protocol/builder

import ../massertions
import ../mfixtures
import ../mtestblock
import ../mtransport

type DebugRecord = object
  direction*: WireDirection
  bytes*: string

proc bytesToString(b: openArray[byte]): string =
  ## Copies the borrowed openArray[byte] into a string for capture
  ## across the callback return.
  result = newString(b.len)
  for i in 0 ..< b.len:
    result[i] = char(b[i])

proc makeRecordingClient(
    responseJson: string = DefaultPostResponseJson
): (JmapClient, RecordingTransportState) =
  ## Realistic-caps session ensures the addEcho call survives the
  ## pre-flight ``maxCallsInRequest`` check.
  let sessionJson = makeSessionJsonWithCoreCaps(realisticCoreCaps())
  let inner = newCannedTransport(sessionJson, responseJson)
  let (transport, state) = newRecordingTransport(inner)
  let client = initJmapClient(
      transport = transport,
      sessionUrl = "https://example.com/jmap",
      bearerToken = "test-token",
    )
    .get()
  (client, state)

# ---------------------------------------------------------------------------

testCase a31NilClears:
  ## ``setDebugCallback(nil)`` detaches; no further callbacks fire.
  let (client, _) = makeRecordingClient()
  var counter = 0
  let counterRef = addr counter
  client.setDebugCallback(
    proc(d: WireDirection, b: openArray[byte]) {.closure, gcsafe, raises: [].} =
      discard d
      discard b
      counterRef[] += 1
  )
  discard client.fetchSession().get()
  doAssert counter > 0, "callback should have fired during fetchSession"
  let before = counter
  client.setDebugCallback(nil)
  discard client.fetchSession().get()
  doAssert counter == before, "callback should not fire after detach"

testCase a31WdSendBytesByteIdenticalToReqBody:
  ## ``wdSend`` payload equals the transport's last request body.
  let (client, state) = makeRecordingClient()
  var records {.global.}: seq[DebugRecord]
  records = @[]
  let recordsRef = addr records
  client.setDebugCallback(
    proc(d: WireDirection, b: openArray[byte]) {.closure, gcsafe, raises: [].} =
      recordsRef[].add DebugRecord(direction: d, bytes: bytesToString(b))
  )
  discard client.fetchSession().get()
  let builder = client.newBuilder().addEcho(%*{"hello": "world"})
  let (b1, _) = builder
  let br = b1.freeze()
  discard client.send(br).get()
  doAssert records.len >= 4, "two exchanges => at least four records"
  let sendRecord = records[^2]
  doAssert sendRecord.direction == wdSend
  assertEq sendRecord.bytes, state.lastRequest.body

testCase a31WdReceiveBytesByteIdenticalToHttpRespBody:
  ## ``wdReceive`` payload equals the transport's last response body.
  let (client, state) = makeRecordingClient()
  var records {.global.}: seq[DebugRecord]
  records = @[]
  let recordsRef = addr records
  client.setDebugCallback(
    proc(d: WireDirection, b: openArray[byte]) {.closure, gcsafe, raises: [].} =
      recordsRef[].add DebugRecord(direction: d, bytes: bytesToString(b))
  )
  discard client.fetchSession().get()
  let builder = client.newBuilder().addEcho(%*{"hello": "world"})
  let (b1, _) = builder
  let br = b1.freeze()
  discard client.send(br).get()
  let recvRecord = records[^1]
  doAssert recvRecord.direction == wdReceive
  assertEq recvRecord.bytes, state.lastResponseBody

testCase a31FireOrder:
  ## ``wdSend`` immediately precedes ``wdReceive`` for every exchange.
  let (client, _) = makeRecordingClient()
  var records {.global.}: seq[WireDirection]
  records = @[]
  let recordsRef = addr records
  client.setDebugCallback(
    proc(d: WireDirection, b: openArray[byte]) {.closure, gcsafe, raises: [].} =
      discard b
      recordsRef[].add d
  )
  discard client.fetchSession().get()
  let builder = client.newBuilder().addEcho(%*{"hello": "world"})
  let (b1, _) = builder
  let br = b1.freeze()
  discard client.send(br).get()
  doAssert records.len == 4
  doAssert records[0] == wdSend
  doAssert records[1] == wdReceive
  doAssert records[2] == wdSend
  doAssert records[3] == wdReceive

testCase a31FetchSessionFiresBoth:
  ## ``fetchSession`` fires ``wdSend`` (empty body) and ``wdReceive``
  ## (session JSON body).
  let (client, _) = makeRecordingClient()
  var records {.global.}: seq[DebugRecord]
  records = @[]
  let recordsRef = addr records
  client.setDebugCallback(
    proc(d: WireDirection, b: openArray[byte]) {.closure, gcsafe, raises: [].} =
      recordsRef[].add DebugRecord(direction: d, bytes: bytesToString(b))
  )
  discard client.fetchSession().get()
  doAssert records.len == 2
  doAssert records[0].direction == wdSend
  doAssert records[0].bytes.len == 0, "GET session request body is empty"
  doAssert records[1].direction == wdReceive
  doAssert records[1].bytes.len > 0, "session response body must be non-empty"

testCase a31SendFiresBoth:
  ## ``client.send`` fires ``wdSend`` (non-empty JMAP request body) and
  ## ``wdReceive`` (non-empty response body).
  let (client, _) = makeRecordingClient()
  discard client.fetchSession().get()
  var records {.global.}: seq[DebugRecord]
  records = @[]
  let recordsRef = addr records
  client.setDebugCallback(
    proc(d: WireDirection, b: openArray[byte]) {.closure, gcsafe, raises: [].} =
      recordsRef[].add DebugRecord(direction: d, bytes: bytesToString(b))
  )
  let builder = client.newBuilder().addEcho(%*{"hello": "world"})
  let (b1, _) = builder
  let br = b1.freeze()
  discard client.send(br).get()
  doAssert records.len == 2
  doAssert records[0].direction == wdSend
  doAssert records[0].bytes.len > 0
  doAssert records[1].direction == wdReceive
  doAssert records[1].bytes.len > 0

testCase a31Replacement:
  ## Installing a fresh callback replaces the previous one — old
  ## callback receives no further calls; new callback observes only
  ## subsequent exchanges.
  let (client, _) = makeRecordingClient()
  var listA {.global.}: seq[WireDirection]
  var listB {.global.}: seq[WireDirection]
  listA = @[]
  listB = @[]
  let listARef = addr listA
  let listBRef = addr listB
  client.setDebugCallback(
    proc(d: WireDirection, b: openArray[byte]) {.closure, gcsafe, raises: [].} =
      discard b
      listARef[].add d
  )
  discard client.fetchSession().get()
  client.setDebugCallback(
    proc(d: WireDirection, b: openArray[byte]) {.closure, gcsafe, raises: [].} =
      discard b
      listBRef[].add d
  )
  let builder = client.newBuilder().addEcho(%*{"hello": "world"})
  let (b1, _) = builder
  let br = b1.freeze()
  discard client.send(br).get()
  doAssert listA.len == 2, "callback A captured the first exchange"
  doAssert listB.len == 2, "callback B captured the second exchange"
