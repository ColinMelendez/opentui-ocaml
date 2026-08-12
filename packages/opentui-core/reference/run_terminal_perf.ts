import { readFileSync } from "node:fs"

import { StdinParser, type StdinEvent } from "../../../vendor/opentui/packages/core/src/lib/stdin-parser.ts"

interface Workload {
  name: string
  workloadVersion: number
  pattern: string
  patternHex: string
  eventsPerPeriod: number
  payloadBytes: number
  chunkBytes: number
  expectedEvents: number
  chunks: Uint8Array[]
}

interface MemorySample {
  heapUsed: number
  arrayBuffers: number
}

const WARMUP_BATCHES = 5
const MEASURED_BATCHES = 20
const BATCH_ITERATIONS = 8

function fail(message: string): never {
  throw new Error(message)
}

function positiveInteger(value: string, label: string): number {
  const parsed = Number.parseInt(value, 10)
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    fail(label + " must be a positive integer: " + value)
  }
  return parsed
}

function bytesFromHex(value: string): number[] {
  if (value.length === 0 || value.length % 2 !== 0) {
    fail("pattern hex must have a positive even length: " + JSON.stringify(value))
  }
  const bytes: number[] = []
  for (let index = 0; index < value.length; index += 2) {
    const byte = Number.parseInt(value.slice(index, index + 2), 16)
    if (!Number.isSafeInteger(byte) || byte < 0 || byte > 0xff) {
      fail("invalid pattern hex byte: " + value.slice(index, index + 2))
    }
    bytes.push(byte)
  }
  return bytes
}

function makePayload(patternBytes: readonly number[], length: number): Uint8Array {
  if (length % patternBytes.length !== 0) {
    fail("payload length " + length + " is not aligned to the pattern")
  }

  const payload = new Uint8Array(length)
  for (let offset = 0; offset < length; offset += 1) {
    payload[offset] = patternBytes[offset % patternBytes.length]!
  }
  return payload
}

function makeChunks(payload: Uint8Array, chunkBytes: number): Uint8Array[] {
  const chunks: Uint8Array[] = []
  for (let offset = 0; offset < payload.length; offset += chunkBytes) {
    chunks.push(payload.slice(offset, Math.min(payload.length, offset + chunkBytes)))
  }
  return chunks
}

function parseWorkload(fields: string[]): Workload {
  if (fields.length !== 8) fail("expected eight tab-separated benchmark fields")
  const [name, versionText, patternText, patternHex, eventsText, payloadText, chunkText, expectedText] = fields
  if (!name) fail("benchmark name must not be empty")
  if (!patternText) fail("benchmark pattern must not be empty")
  const patternBytes = bytesFromHex(patternHex!)
  const workloadVersion = positiveInteger(versionText!, "workload version")
  const eventsPerPeriod = positiveInteger(eventsText!, "events per period")
  const payloadBytes = positiveInteger(payloadText!, "payload bytes")
  const chunkBytes = positiveInteger(chunkText!, "chunk bytes")
  const expectedEvents = positiveInteger(expectedText!, "expected events")
  if (payloadBytes % patternBytes.length !== 0) {
    fail(name + ": payload is not pattern-aligned")
  }
  const computedEvents = (payloadBytes / patternBytes.length) * eventsPerPeriod
  if (expectedEvents !== computedEvents) {
    fail(name + ": expected " + expectedEvents + " events, pattern produces " + computedEvents)
  }
  const payload = makePayload(patternBytes, payloadBytes)
  return {
    name,
    workloadVersion,
    pattern: patternText,
    patternHex: patternHex!,
    eventsPerPeriod,
    payloadBytes,
    chunkBytes,
    expectedEvents,
    chunks: makeChunks(payload, chunkBytes),
  }
}

function readManifest(path: string): Workload[] {
  const workloads: Workload[] = []
  for (const rawLine of readFileSync(path, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line || line.startsWith("#")) continue
    workloads.push(parseWorkload(line.split("\t")))
  }
  if (workloads.length === 0) fail("terminal performance manifest contains no workloads")
  return workloads
}

function forceCollection(): void {
  const runtime = globalThis as unknown as { Bun?: { gc?: (force?: boolean) => void } }
  runtime.Bun?.gc?.(true)
}

function memorySample(): MemorySample {
  const memory = process.memoryUsage()
  return { heapUsed: memory.heapUsed, arrayBuffers: memory.arrayBuffers }
}

function runBatch(
  parser: StdinParser,
  workload: Workload,
  onEvent: (event: StdinEvent) => void,
  completedEvents: { value: number },
): number {
  const eventsBefore = completedEvents.value
  const start = process.hrtime.bigint()
  for (let iteration = 0; iteration < BATCH_ITERATIONS; iteration += 1) {
    for (let chunkIndex = 0; chunkIndex < workload.chunks.length; chunkIndex += 1) {
      parser.push(workload.chunks[chunkIndex]!)
    }
    parser.drain(onEvent)
    parser.reset()
  }
  const elapsed = Number(process.hrtime.bigint() - start)
  const events = completedEvents.value - eventsBefore
  const expected = BATCH_ITERATIONS * workload.expectedEvents
  if (events !== expected) fail(workload.name + ": produced " + events + " events, expected " + expected)
  return elapsed
}

function median(values: readonly number[]): number {
  const sorted = [...values].sort((left, right) => left - right)
  const middle = Math.floor(sorted.length / 2)
  if (sorted.length % 2 === 1) return sorted[middle]!
  return ((sorted[middle - 1] ?? 0) + sorted[middle]!) / 2
}

function percentile(values: readonly number[], percentileValue: number): number {
  const sorted = [...values].sort((left, right) => left - right)
  const rank = Math.ceil((percentileValue / 100) * sorted.length)
  return sorted[Math.max(0, rank - 1)]!
}

function rsdPpm(values: readonly number[]): number {
  const mean = values.reduce((total, value) => total + value, 0) / values.length
  const variance = values.reduce((total, value) => total + (value - mean) ** 2, 0) / (values.length - 1)
  return Math.round((Math.sqrt(variance) / mean) * 1_000_000)
}

function runWorkload(workload: Workload): {
  times: number[]
  memoryBefore: MemorySample
  memoryAfter: MemorySample
} {
  const parser = new StdinParser({ armTimeouts: false })
  const completedEvents = { value: 0 }
  const onEvent = (event: StdinEvent): void => {
    switch (event.type) {
      case "key":
      case "mouse":
      case "paste":
      case "response":
        completedEvents.value += 1
        return
    }
  }

  try {
    for (let batch = 0; batch < WARMUP_BATCHES; batch += 1) {
      runBatch(parser, workload, onEvent, completedEvents)
    }
    forceCollection()
    const memoryBefore = memorySample()
    const times: number[] = []
    for (let batch = 0; batch < MEASURED_BATCHES; batch += 1) {
      times.push(runBatch(parser, workload, onEvent, completedEvents))
    }
    forceCollection()
    return { times, memoryBefore, memoryAfter: memorySample() }
  } finally {
    parser.destroy()
  }
}

function printHeader(): void {
  console.log("# schema_version=1")
  console.log("# runner=bun")
  console.log("# runtime_version=" + (process.versions.bun ?? process.version))
  console.log(
    "# warmup_batches=" +
      WARMUP_BATCHES +
      " measured_batches=" +
      MEASURED_BATCHES +
      " batch_iterations=" +
      BATCH_ITERATIONS,
  )
  console.log(
    "case\tworkload_version\tpattern\tpattern_hex\tevents_per_period\tpayload_bytes\tchunk_bytes\texpected_events\tmedian_ns_per_op\tp95_ns_per_op\trsd_ppm\theap_used_delta_after_gc_bytes_per_op\tarray_buffers_delta_after_gc_bytes_per_op",
  )
}

function printWorkload(workload: Workload, result: ReturnType<typeof runWorkload>): void {
  const operations = BATCH_ITERATIONS * MEASURED_BATCHES
  const heapDelta = (result.memoryAfter.heapUsed - result.memoryBefore.heapUsed) / operations
  const arrayBuffersDelta = (result.memoryAfter.arrayBuffers - result.memoryBefore.arrayBuffers) / operations
  console.log(
    [
      workload.name,
      workload.workloadVersion,
      workload.pattern,
      workload.patternHex,
      workload.eventsPerPeriod,
      workload.payloadBytes,
      workload.chunkBytes,
      workload.expectedEvents,
      (median(result.times) / BATCH_ITERATIONS).toFixed(3),
      (percentile(result.times, 95) / BATCH_ITERATIONS).toFixed(3),
      rsdPpm(result.times),
      heapDelta.toFixed(3),
      arrayBuffersDelta.toFixed(3),
    ].join("\t"),
  )
}

const manifestPath = process.argv[2]
if (!manifestPath) fail("usage: run_terminal_perf.ts MANIFEST")
const workloads = readManifest(manifestPath)
printHeader()
for (const workload of workloads) printWorkload(workload, runWorkload(workload))
