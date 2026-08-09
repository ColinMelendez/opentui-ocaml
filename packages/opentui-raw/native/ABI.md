# Phase 1 native ABI audit

The audit targets parent revision `de64d210e4f0163720fc1fbfa838d4d1aad47d53`
of the `vendor/opentui` submodule. The TypeScript declarations in
`vendor/opentui/packages/core/src/zig.ts` are a cross-check only; the Zig
definitions are authoritative.

## Selected probe surface

The checked-in C declarations in [`opentui_abi.h`](opentui_abi.h) cover the
first link seam and the typed raw renderer/buffer/event/Yoga/capability slice:

| Symbol | Zig definition | ABI shape | Ownership or lifetime |
| --- | --- | --- | --- |
| `createEventSink` / `destroyEventSink` | `lib.zig:147`, `lib.zig:219` | `u32` handle; callback is a C function pointer with four borrowed pointer/`u32` pairs | The sink owns its registration. The callback receives synchronous borrowed bytes and must copy them before returning. |
| `createEditBuffer` / `destroyEditBuffer` | `lib.zig:1975`, `lib.zig:2004` | `u8, u32 -> u32`; `u32 -> void` | The edit buffer borrows the event sink and owns its child text buffer. Destroy the edit buffer before its sink. |
| `editBufferInsertText` | `lib.zig:2017` | `u32, nullable byte pointer + u32 -> void` | The text is consumed synchronously and emits native events synchronously when an event sink is attached. |
| `createRenderer` | `lib.zig:648` | `u32, u32, u8, u8, nullable pointer -> u32` | A zero dimension or invalid destination returns handle `0`. The renderer owns its current/next buffers. |
| `setUseThread` | `lib.zig:711` | `u32, bool -> void` | Phase 1 always passes `false`; all raw entrypoints remain on one native owner. |
| `resizeRenderer` | `lib.zig:1497` | `u32, u32, u32 -> void` | The pinned export resizes the renderer's current and next buffers in place, so their borrowed handles remain valid on success. It catches and discards `CliRenderer.resize` errors; the raw facade validates positive dimensions and reads both buffer dimensions back, but hidden hit-grid or other internal allocation failures remain unobservable from this upstream signature. |
| `destroyRenderer` | `lib.zig:721` | `u32 -> void` | Destruction invalidates renderer-owned borrowed buffer handles before renderer deinitialization. |
| `getCurrentBuffer` / `getNextBuffer` | `lib.zig:808`, `lib.zig:813` | `u32 -> u32` | Returned optimized-buffer handles are borrowed children of the renderer. |
| `render` | `lib.zig:845` | `u32, bool -> u8` | The renderer returns the pinned `rendered`/`skipped`/`failed` values `0`/`1`/`2`; the OCaml facade maps them to a typed result without exposing the native enum. |
| `bufferClear` | `lib.zig:1168` | `u32, pointer to four u16 values -> void` | The color pointer is consumed synchronously. |
| `bufferDrawText` | `lib.zig:1228` | `u32, nullable byte pointer/u32, coordinates, two color pointers, u32 attributes -> void` | Text and colors are synchronous caller-owned input. |
| `bufferSetCell` | `lib.zig:1245` | `u32, coordinates, u32 character, two color pointers, u32 attributes -> void` | The cell is written in native SoA storage; no native cell view crosses the boundary. |
| `bufferWriteResolvedChars` | `lib.zig:1219` | `u32, nullable caller output pointer, `u32` capacity, `bool` -> `u32` | Native writes into caller-owned bounded storage and returns the byte count; a capacity smaller than the resolved output returns `0`. |
| `getRenderStats` | `lib.zig:788` | `u32, pointer to ExternalRenderStats -> void` | Caller supplies output storage; the Zig probe checks the nine-field C-compatible layout. |
| `getAllocatorStats` | `lib.zig:617` | `pointer to ExternalAllocatorStats -> void` | Active allocation counters are sampled for a diagnostic baseline. `total_requested_bytes` is valid only when the build enables GPA safe stats. |
| `yogaConfigCreate` / `yogaConfigFree` | `yoga.zig` | `void pointer -> void pointer`; `void pointer -> void` | The C facade owns one config per Yoga tree and frees it after recursive node destruction. The raw `YGConfigRef` never reaches OCaml. |
| `yogaNodeCreateWithConfig` / `yogaNodeFreeRecursive` | `yoga.zig` | `const void pointer -> void pointer`; `void pointer -> void` | The C facade owns the root and all descendants. Closing a tree invalidates every associated abstract node token before freeing the native tree. |
| `yogaNodeInsertChild` / `yogaNodeGetChildCount` | `yoga.zig` | `void pointer, void pointer, u32 -> void`; `const void pointer -> u32` | Children are created with the tree's config and inserted synchronously under a node from the same tree. Cross-tree parents are rejected by the facade. |
| `yogaNodeCalculateLayout` / `yogaNodeGetComputedLayout` | `yoga.zig` | `void pointer, f32, f32, u32 -> void`; `const void pointer, pointer to six-f32 output -> void` | Dimensions and direction are checked at the C boundary. Layout is copied into an OCaml tuple; no Yoga output pointer escapes. |
| `yogaNodeStyleSetValue` | `yoga.zig` | `void pointer, u32, u32, u32, f32 -> void` | The current typed surface binds point-valued width and height only. Measure callbacks, packed style values, and native renderable configuration remain deferred. |
| `getTerminalCapabilities` | `lib.zig:986` | `u32, pointer to 64-byte ExternalCapabilities -> void` on supported 64-bit hosts | Zig returns borrowed terminal-name/version pointers and `usize` lengths. The C shim checks the lengths and copies both strings before returning to OCaml. |
| `processCapabilityResponse` | `lib.zig:1017` | `u32, nullable byte pointer, u32 -> void` | The response is caller-owned and consumed synchronously. An empty OCaml string crosses as a null pointer with length zero. |
| `createNativeSpanFeed` / `attachNativeSpanFeed` / `destroyNativeSpanFeed` | `lib.zig:358`, `native-span-feed.zig` | pointer to `Options` -> nullable stream pointer; stream pointer -> `i32`/`void` | The raw facade owns the feed behind an abstract generation-checked token and destroys it only after a successful close. The pinned vendor source is copied into a generated build directory before the tracked export patch is applied. |
| `streamWrite` / `streamCommit` | `native-span-feed.zig` | stream pointer, nullable byte pointer, `u32` -> `i32`; stream pointer -> `i32` | Input bytes are copied synchronously into native chunks. Commit publishes the pending span; it does not expose the chunk address to OCaml. |
| `streamReserve` / `streamCommitReserved` / `streamCancelReserved` | `native-span-feed.zig` | stream pointer, `u32`, pointer to 16-byte `ReserveInfo` -> `i32`; stream pointer, `u32` -> `i32`; stream pointer -> `i32` | The C facade keeps the native reserve pointer private and stages OCaml bytes before commit. Cancellation clears the reservation without advancing the write cursor; close reports `Busy` while it is active. |
| `streamDrainSpans` / `streamMarkSpanConsumed` | `native-span-feed.zig` | stream pointer, pointer to 24-byte `SpanInfo`, `u32` -> count; stream pointer, pointer to `SpanInfo` -> `i32` | Drained span records contain borrowed chunk addresses. The facade copies each payload into OCaml bytes and holds a generation-checked release token. Release validates chunk pointer, index, offset, and length before decrementing the native chunk refcount. |
| `streamGetStats` | `native-span-feed.zig` | stream pointer, pointer to 24-byte `Stats` -> `i32` | The four counters are copied into an OCaml record. The callback surface is not used by `opentui-raw`. |

The first smoke records the selected failure behavior: zero dimensions, an
invalid buffered destination, and a null event callback return handle `0`;
invalid or stale renderer/buffer handles are no-ops or return `0`; nullable
empty spans are accepted without writing; and a caller-owned output capacity
that is too small returns `0` without exposing a native error object. These
cases are boundary evidence for the raw seam, not the final typed OCaml error
API.

`NativeHandle` is a `u32` packed by the upstream registry: a 16-bit slot
index, 12-bit generation, and 4-bit kind. Zero is invalid. The packed fields
remain private to Zig. The C facade uses a separate generation-checked token
registry for Yoga because Yoga pointers are not entries in the upstream
registry: `Yoga_tree.t` and `Yoga_node.t` are abstract OCaml domains, and every
node token records its owning tree token. The registry rejects stale tokens,
cross-tree parents, invalid dimensions, and invalid directions before calling
Yoga.

`ExternalYogaLayout` is six consecutive `f32` values in the pinned order
`left`, `top`, `right`, `bottom`, `width`, `height`, for 24 bytes. The
`ExternalCapabilities` struct is 64 bytes on the supported 64-bit targets;
the fixed-width one-byte booleans and enum codes occupy the first 20 bytes,
followed by two borrowed pointer/`size_t` pairs and the final one-byte flags.
The source-importing Zig probe and the C header both assert these layouts and
the exact function-pointer signatures.

The capability facade maps the pinned enum codes to typed OCaml variants. It
does not preserve borrowed terminal pointers: names and versions are copied
into the returned snapshot, and an invalid or stale renderer produces a
structured raw error.

The output-feed facade asserts the 24-byte `Options`, `Stats`, and `SpanInfo`
layouts and the 16-byte `ReserveInfo` layout. `Span_feed.drain` returns copied
payloads paired with explicit, idempotent release tokens; `Span_feed.Reservation`
exposes a caller-owned staging buffer with explicit commit or cancel. This is
the safe ownership proof for the pinned feed, not the eventual zero-copy
Bigarray/Cstruct view. A closed feed invalidates outstanding copied tokens.

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

The output smoke also allocates an OCaml-owned `bytes` value in the test shim,
passes its storage directly to `bufferWriteResolvedChars`, and checks `A` and
`B` from OCaml without converting the result to a string.

## Build and link

The pinned upstream dynamic library is built with Zig 0.16.0 in
`vendor/opentui/packages/core/src/zig` using `ReleaseSafe`. Its Phase 1
memory-output invocation uses `createRenderer(width, height, 1, 2, NULL)` and
leaves `setUseThread` off. `ReleaseSafe` is intentional: the upstream Debug
allocator captures stack traces that are not compatible with the OCaml C-call
frame used by the runtime smoke. The compile-only ABI probe remains Debug.
The Dune rule verifies the audited SHA-256 of the pinned
`native-span-feed.zig`, copies the source into a generated build directory,
applies the tracked `span_feed_exports.patch`, runs the ReleaseSafe build and
source-importing Zig probe against that generated tree, copies the host
artifact into the Dune native output directory, and links the C facade against
it with `-lopentui`.

The upstream build pulls Yoga's C++ sources and, on macOS, CoreFoundation,
CoreAudio, and AudioToolbox. Linux uses the upstream `dl`, `pthread`, and `m`
dependencies. The Dune rule accepts only the host target names already
selected by the pinned build (`aarch64-macos`, `x86_64-macos`,
`aarch64-linux`, and `x86_64-linux`).

## Phase 2 typed raw extension

The first Phase 2 extension is implemented in `opentui-raw`. It adds
generation-checked, owner-scoped Yoga tree/node operations, a copied
capability snapshot, and the audited NativeSpanFeed ownership protocol while
preserving the original renderer/buffer/event ownership model. The OCaml API
exposes `Yoga.create`, `Yoga.add_child`, `Yoga.calculate`, typed layout
readback, `Span_feed.drain`, and explicit reservation commit/cancel; it does not
expose `YGNodeRef`, `YGConfigRef`, packed style values, native span pointers,
Bigarray/Cstruct views, or callbacks. Capability responses are processed
synchronously and can be read as a typed `Capabilities.t` record.

Black-box tests cover exact six-field layout readback, invalid dimensions,
cross-tree parent rejection, owner invalidation after close, XTVERSION string
copying, enum decoding, closed-renderer behavior, copied output spans,
release-driven chunk reuse, and reservation busy/cancel/commit behavior.

## Deferred from this probe

Yoga custom measurement and native renderable integration, the complete stdin
parser, native-owned zero-copy `NativeSpanFeed` views, raw cell pointers,
native renderables, audio, image, editor, and all high-level packages remain
outside this seam. The feed's copied payload and reservation ownership protocol
is implemented here; mapping native chunks into Bigarray/Cstruct views remains
deferred until a separate lifetime and benchmark decision.
