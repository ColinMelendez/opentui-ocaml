# Phase 1 native ABI audit

The audit targets parent revision `de64d210e4f0163720fc1fbfa838d4d1aad47d53`
of the `vendor/opentui` submodule. The TypeScript declarations in
`vendor/opentui/packages/core/src/zig.ts` are a cross-check only; the Zig
definitions are authoritative.

## Selected probe surface

The checked-in C declarations in [`opentui_abi.h`](opentui_abi.h) cover the
first link seam and the smallest renderer/buffer/event slice:

| Symbol | Zig definition | ABI shape | Ownership or lifetime |
| --- | --- | --- | --- |
| `createEventSink` / `destroyEventSink` | `lib.zig:147`, `lib.zig:219` | `u32` handle; callback is a C function pointer with four borrowed pointer/`u32` pairs | The sink owns its registration. The callback receives synchronous borrowed bytes and must copy them before returning. |
| `createEditBuffer` / `destroyEditBuffer` | `lib.zig:1975`, `lib.zig:2004` | `u8, u32 -> u32`; `u32 -> void` | The edit buffer borrows the event sink and owns its child text buffer. Destroy the edit buffer before its sink. |
| `editBufferInsertText` | `lib.zig:2017` | `u32, nullable byte pointer + u32 -> void` | The text is consumed synchronously and emits native events synchronously when an event sink is attached. |
| `createRenderer` | `lib.zig:648` | `u32, u32, u8, u8, nullable pointer -> u32` | A zero dimension or invalid destination returns handle `0`. The renderer owns its current/next buffers. |
| `setUseThread` | `lib.zig:711` | `u32, bool -> void` | Phase 1 always passes `false`; all raw entrypoints remain on one native owner. |
| `destroyRenderer` | `lib.zig:721` | `u32 -> void` | Destruction invalidates renderer-owned borrowed buffer handles before renderer deinitialization. |
| `getCurrentBuffer` / `getNextBuffer` | `lib.zig:808`, `lib.zig:813` | `u32 -> u32` | Returned optimized-buffer handles are borrowed children of the renderer. |
| `bufferClear` | `lib.zig:1168` | `u32, pointer to four u16 values -> void` | The color pointer is consumed synchronously. |
| `bufferDrawText` | `lib.zig:1228` | `u32, nullable byte pointer/u32, coordinates, two color pointers, u32 attributes -> void` | Text and colors are synchronous caller-owned input. |
| `bufferSetCell` | `lib.zig:1245` | `u32, coordinates, u32 character, two color pointers, u32 attributes -> void` | The cell is written in native SoA storage; no native cell view crosses the boundary. |
| `bufferWriteResolvedChars` | `lib.zig:1219` | `u32, nullable caller output pointer, `u32` capacity, `bool` -> `u32` | Native writes into caller-owned bounded storage and returns the byte count; a capacity smaller than the resolved output returns `0`. |
| `getRenderStats` | `lib.zig:788` | `u32, pointer to ExternalRenderStats -> void` | Caller supplies output storage; the Zig probe checks the nine-field C-compatible layout. |
| `getAllocatorStats` | `lib.zig:617` | `pointer to ExternalAllocatorStats -> void` | Active allocation counters are sampled for a diagnostic baseline. `total_requested_bytes` is valid only when the build enables GPA safe stats. |

The first smoke records the selected failure behavior: zero dimensions, an
invalid buffered destination, and a null event callback return handle `0`;
invalid or stale renderer/buffer handles are no-ops or return `0`; nullable
empty spans are accepted without writing; and a caller-owned output capacity
that is too small returns `0` without exposing a native error object. These
cases are boundary evidence for the raw seam, not the final typed OCaml error
API.

`NativeHandle` is a `u32` packed by the upstream registry: a 16-bit slot
index, 12-bit generation, and 4-bit kind. Zero is invalid. The packed fields
remain private to Zig and are not represented by the OCaml placeholder handle
module in this patch.

The probe also checks `RGBA = [4]u16`, one-byte Zig `bool`, the callback
signature, the selected function types, and the offsets and size of
`ExternalBuildOptions`, `ExternalAllocatorStats`, and the nine-field
`ExternalRenderStats`. The C header repeats the fixed-width and layout
assertions and uses `_Generic` function-pointer checks so the C compiler cannot
silently accept a declaration with a different calling shape.

## Repeated update baseline

The native smoke also samples `getAllocatorStats` around 1,024 ASCII
`bufferSetCell` calls on an 8x1 memory renderer followed by one
`bufferWriteResolvedChars` call. It reports the native-call counts and both
active-allocation samples to OCaml, verifies the resolved `C` through `J`
output, and requires the active-allocation count to remain stable. This is
diagnostic evidence rather than a fixed allocation threshold; the ReleaseSafe
runtime artifact intentionally leaves `requested_bytes_valid` false.

## Build and link

The pinned upstream dynamic library is built with Zig 0.16.0 in
`vendor/opentui/packages/core/src/zig` using `ReleaseSafe`. Its Phase 1
memory-output invocation uses `createRenderer(width, height, 1, 2, NULL)` and
leaves `setUseThread` off. `ReleaseSafe` is intentional: the upstream Debug
allocator captures stack traces that are not compatible with the OCaml C-call
frame used by the runtime smoke. The compile-only ABI probe remains Debug.
The Dune rule runs the pinned build, runs the source-importing Zig probe, copies
the host artifact into the Dune native output directory, and links the C smoke
stub against it with `-lopentui`.

The upstream build pulls Yoga's C++ sources and, on macOS, CoreFoundation,
CoreAudio, and AudioToolbox. Linux uses the upstream `dl`, `pthread`, and `m`
dependencies. The Dune rule accepts only the host target names already
selected by the pinned build (`aarch64-macos`, `x86_64-macos`,
`aarch64-linux`, and `x86_64-linux`).

## Deferred from this probe

The public Yoga pointer API, terminal capability strings with `usize` lengths,
the complete stdin parser, native-owned `NativeSpanFeed` views and
reserve/commit cancellation, raw cell pointers, native renderables, audio,
image, editor, and all high-level packages remain outside this first seam.
