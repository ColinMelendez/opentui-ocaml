import { readFileSync } from "node:fs"

import { StdinParser, type StdinEvent } from "../../../vendor/opentui/packages/core/src/lib/stdin-parser.ts"

function fail(message: string): never {
  throw new Error(message)
}

function hexValue(value: string): number {
  const parsed = Number.parseInt(value, 16)
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 15) {
    fail(`invalid hexadecimal digit: ${JSON.stringify(value)}`)
  }
  return parsed
}

function bytesFromHex(value: string): Uint8Array {
  if (value.length % 2 !== 0) fail(`hex input has odd length: ${JSON.stringify(value)}`)
  const bytes = new Uint8Array(value.length / 2)
  for (let index = 0; index < bytes.length; index++) {
    bytes[index] = (hexValue(value[index * 2]!) << 4) | hexValue(value[index * 2 + 1]!)
  }
  return bytes
}

function hexFromBytes(bytes: Uint8Array): string {
  let result = ""
  for (const byte of bytes) result += byte.toString(16).padStart(2, "0")
  return result
}

function latin1Bytes(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length)
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index)
    if (code > 0xff) fail(`non-latin1 sequence byte: ${JSON.stringify(value)}`)
    bytes[index] = code
  }
  return bytes
}

function protocolFromEscape(bytes: Uint8Array): string {
  if (bytes.length >= 2 && bytes[0] === 0x1b) {
    switch (bytes[1]) {
      case 0x5b:
        return "csi"
      case 0x4f:
        return "ss3"
      case 0x5d:
        return "osc"
      case 0x50:
        return "dcs"
      case 0x5f:
        return "apc"
      default:
        return "unknown"
    }
  }
  return "unknown"
}

function emit(name: string, kind: string, protocol: string, bytes: Uint8Array): void {
  console.log(`${name}\t${kind}\t${protocol}\t${hexFromBytes(bytes)}`)
}

function normalizeResponseProtocol(protocol: string, sequence: string): string {
  const bytes = latin1Bytes(sequence)
  return bytes[0] === 0x1b ? protocolFromEscape(bytes) : protocol
}

function emitEvent(name: string, event: StdinEvent): void {
  switch (event.type) {
    case "paste":
      emit(name, "paste", "-", event.bytes)
      return
    case "mouse":
      emit(name, "sequence", "csi", latin1Bytes(event.raw))
      return
    case "response":
      emit(
        name,
        "sequence",
        normalizeResponseProtocol(event.protocol, event.sequence),
        latin1Bytes(event.sequence),
      )
      return
    case "key": {
      const bytes = new TextEncoder().encode(event.raw)
      if (bytes[0] === 0x1b) {
        emit(name, "sequence", protocolFromEscape(bytes), latin1Bytes(event.raw))
      } else {
        emit(name, "key", "ground", bytes)
      }
    }
  }
}

function runCase(line: string): void {
  const fields = line.split("\t")
  if (fields.length !== 3) fail(`expected three tab-separated fields: ${JSON.stringify(line)}`)
  const [name, flush, chunks] = fields
  if (flush !== "0" && flush !== "1") fail(`invalid flush flag for ${name}: ${flush}`)

  const parser = new StdinParser({ armTimeouts: false })
  try {
    for (const chunk of chunks.split(";")) parser.push(bytesFromHex(chunk))
    if (flush === "1") parser.flushTimeout(Number.MAX_SAFE_INTEGER)

    const events: StdinEvent[] = []
    parser.drain((event) => events.push(event))
    if (events.length === 0) emit(name, "empty", "-", new Uint8Array())
    for (const event of events) emitEvent(name, event)
  } finally {
    parser.destroy()
  }
}

for (const rawLine of readFileSync(0, "utf8").split(/\r?\n/)) {
  const line = rawLine.trimEnd()
  if (line.length === 0 || line.startsWith("#")) continue
  runCase(line)
}
