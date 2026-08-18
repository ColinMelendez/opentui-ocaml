# Renderer output transport

Status: implemented for the current Core/raw transport; zero-copy feed
delivery remains a future optimization.

This feature defines how a native renderer presents complete terminal frames
and how that presentation is composed with the Eio terminal output owner. The
transport is selected when the native renderer is created. It is not a mutable
renderer property and it is not inferred from the process environment by the
portable Core API.

## Purpose

The native OpenTUI renderer owns cell diffing, ANSI encoding, cursor
positioning, and terminal presentation. A memory-backed renderer is useful for
tests and inspection, but its `writeResolvedChars` operation is intentionally a
plain-character cell dump. It cannot be used to present styled frames.

The OCaml port therefore exposes the native output choice as an explicit
creation contract. A terminal application can use a native stdout backend or
route complete native frames through an application-owned sink. The latter is
the intended Eio integration because terminal setup, queries, frame bytes, and
shutdown bytes then share one serialized output owner.

## Reference correspondence

| Reference source | OCaml correspondence | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/zig/lib.zig` `createRenderer` | Typed `opentui-raw` renderer creation options and the checked C stub | Preserve buffered-destination, remote-mode, and feed selection at the ABI boundary. |
| `vendor/opentui/packages/core/src/zig/renderer.zig` `OutputTarget` | `Renderer.Output.target` and the raw renderer's owned/borrowed feed seam | Select `Memory`, `Stdout`, or feed-backed presentation once at construction. |
| `vendor/opentui/packages/core/src/zig/renderer-output.zig` `BufferedBackend` | Native `Memory` and `Stdout` targets | Keep ANSI generation and buffered diff presentation native. |
| `vendor/opentui/packages/core/src/zig/renderer-output.zig` `FeedBackend` | `Renderer.Output.Sink` plus `Native_span_feed` | Publish complete native frames before the application sink consumes them. |
| `vendor/opentui/packages/core/src/renderer.ts` custom `Writable` path | Eio `Output_flow` frame sink | Route frame chunks through the same terminal-output serialization boundary as mode and query writes. |
| `vendor/opentui/packages/core/src/renderer.ts` renderer destruction | Renderer shutdown drain followed by terminal-session restoration | Ensure any native cleanup/control sequences reach the sink before the feed and terminal output owner close. Eio terminal-session restoration remains authoritative for modes established outside the native renderer. |

## Public Core contract

The intended high-level shape is:

```ocaml
module Renderer.Output : sig
  type remote_mode = Auto | Local | Remote

  type sink
  val sink :
    write_frame:(bytes list -> (unit, Error.t) result) -> sink

  type target =
    | Memory
    | Stdout
    | Sink of sink
end

val create :
  output:Renderer.Output.target ->
  ?remote_mode:Renderer.Output.remote_mode ->
  width:int32 ->
  height:int32 ->
  unit ->
  (Renderer.t, Error.t) result
```

The clock-aware constructor accepts the same output contract and trailing
unit argument. The output
target is explicit rather than silently defaulting to memory:

- `Memory` selects the native retained output used by headless tests and
  diagnostics. `Buffer.write_resolved_chars` remains an inspection API and is
  not a styled terminal serializer.
- `Stdout` selects the native process-stdout backend. This is the direct,
  reference-compatible low-level path and is appropriate only when the
  application has established that fd 1 is its sole terminal-output owner.
- `Sink` selects the native feed backend. The renderer owns the feed and
  delivers complete, ordered frame chunks to the borrowed sink. The caller
  never receives a native feed pointer or is responsible for feed lifetime.

The sink receives a list rather than independent callbacks so the renderer can
publish the native feed spans as one logical frame. A sink must consume the
chunks before returning. The Eio `Output_flow` adapter coalesces multiple spans
into one contiguous write before handing them to the terminal; this adds one
copy at that boundary, but removes native-span write boundaries on terminals
without synchronized-update support. It does not make an unsupported terminal
display a large ANSI write atomically; terminals that honor `DEC 2026` provide
that presentation guarantee. Custom sinks may preserve the list
representation when their transport already provides an equivalent frame
boundary. The renderer never closes the sink; the application owns the
underlying terminal resource.

`remote_mode` maps to the native reference values `Auto = 0`, `Local = 1`, and
`Remote = 2`. When omitted, `Stdout` and `Memory` use `Auto`; `Sink` uses
`Remote`, matching the reference custom-`Writable` default. An explicit value
always wins.

## Frame delivery

For `Memory` and `Stdout`, native render completion is the presentation
boundary. For `Sink`, the native backend first commits a complete frame to the
feed. The Core renderer then drains the feed and invokes `write_frame` before
the synchronous render operation returns.

This gives one frame the following invariant:

```text
retained tree -> native diff/ANSI staging -> feed commit -> sink write_frame
```

No sink callback observes a partially encoded native frame. A skipped frame
does not invent output, but any already-published control or shutdown chunks
are drained in their original order.

Sink failure is an output failure, not a retained-tree rendering failure. The
sink is poisoned by its owning output adapter when a write cannot be completed;
the renderer must not hot-loop retry a frame after bytes may already have
reached the terminal. The scheduler reports the failure and stops ordinary
frame production until the application closes or replaces the terminal
output owner.

The current copy-first `Native_span_feed` wrapper is an internal safety seam:
it copies each drained payload into OCaml-owned bytes and releases the native
span after delivery. The public sink contract does not depend on that copy.
A future zero-copy span implementation may replace it without changing the
renderer or Eio APIs, provided the sink keeps each span alive until its write
completes.

## Eio terminal ownership

`Eio_runtime.Output_flow` is the serialized terminal byte owner. Terminal mode
transitions, capability/palette/theme queries, renderer frame chunks, and
shutdown output all use the same output boundary. Frame delivery uses one
`write_frame` operation, coalesces native spans, and then performs one sink
transaction so control bytes cannot interleave between chunks of a single
native frame.

The renderer scheduler remains the owner-domain frame driver. It does not
create a second output fiber or expose the feed as an independent application
queue. The normal Eio application composition is:

```text
Terminal_session + Output_flow
             │
             ├── setup, queries, mode transitions
             │
             └── Renderer.Output.Sink
                       │
                 Renderer_scheduler
                       │
                 native feed backend
```

The application creates the output flow before the renderer, passes an
`Output_flow`-backed sink to renderer creation, and runs the scheduler in the
same owner domain. Direct `Stdout` remains available for callers that do not
need this composed Eio boundary.

## Shutdown and ownership

The output lifetime is ordered and explicit:

1. Stop the renderer scheduler and prevent new frame attempts.
2. Run renderer-owned teardown callbacks and native renderer destruction.
3. Drain all native cleanup/control bytes produced by destruction through the
   sink. This may be empty when terminal setup was owned by Eio rather than the
   native renderer.
4. Close the renderer-owned feed.
5. Restore terminal modes through `Terminal_session`.

The terminal-facing close operation is result-bearing so a final frame or
cleanup write cannot be silently discarded. Native finalizers remain
idempotent, but the application-level close path reports output failures after
all owned resources have been made inert.

The renderer owns its native renderer, borrowed buffers, and feed-backed
transport. A `Sink` is borrowed and never closed by Core. The terminal session
owns the Eio file descriptors and `Output_flow`; it must remain alive until
renderer shutdown output has been delivered.

## Raw ABI boundary

The C ABI retains the reference creation shape:

```text
createRenderer(width, height, buffered_destination_kind,
               remote_mode, feed_ptr)
```

The OCaml raw binding maps typed variants to the destination and remote
discriminants and passes a validated typed feed handle when the Core sink path
is selected. It does not expose an arbitrary pointer or integer destination to
Core callers. Feed attachment is borrowed for native renderer lifetime and is
closed only by the owning high-level renderer after final output drain.

## Non-goals

- Automatically detecting interactive stdout inside `opentui-core`.
- Changing the native memory buffer into a styled serializer.
- Adding a process-global output singleton.
- Moving terminal setup, input ownership, or terminal-mode policy into
  per-cell rendering code.
- Implementing reference split-footer replay, external-output capture, or
  scrollback surfaces.

## Acceptance criteria

- Raw creation tests prove the three target mappings and all remote-mode
  discriminants reach the native creation seam.
- Memory creation remains free of terminal-output side effects.
- A feed-backed render delivers styled ANSI bytes, preserves frame chunk order,
  and releases drained spans.
- Eio `Output_flow` serializes mode writes and complete renderer frames.
- A renderer shutdown drains any native cleanup bytes before feed closure and
  terminal restoration; the Eio terminal session remains the owner of the
  modes it established.
- Sink failures are reported structurally and do not cause unbounded scheduler
  retries.
- The vertical demo uses the feed-backed Eio sink path rather than a
  full-screen visual workaround or plain resolved-character dumping.
