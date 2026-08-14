# Native ABI audit

This audit targets revision `de64d210e4f0163720fc1fbfa838d4d1aad47d53` of the
`vendor/opentui` reference source. The TypeScript declarations in
`vendor/opentui/packages/core/src/zig.ts` are a cross-check only; the Zig
definitions are authoritative.

The native build verifies the audited `native-span-feed.zig` and `buffer.zig`
source hashes before copying the sources. It applies the tracked
`text-buffer-negative-origin.patch` to preserve the signed-coordinate
clipping contract for one-column glyphs whose origin is just outside the
destination buffer. The unpatched reference loop can cast that negative
coordinate to an unsigned cell index.

## Selected probe surface

The checked-in C declarations in [`opentui_abi.h`](opentui_abi.h) cover the
typed raw renderer, buffer, event, Yoga, and capability boundary:

| Symbol | Zig definition | ABI shape | Ownership or lifetime |
| --- | --- | --- | --- |
| `createEventSink` / `destroyEventSink` | `lib.zig:147`, `lib.zig:219` | `u32` handle; callback is a C function pointer with four borrowed pointer/`u32` pairs | The sink owns its registration. The callback receives synchronous borrowed bytes and must copy them before returning. |
| `createEditBuffer` / `destroyEditBuffer` | `lib.zig:1975`, `lib.zig:2004` | `u8, u32 -> u32`; `u32 -> void` | The edit buffer borrows the event sink and owns its child text buffer. Destroy the edit buffer before its sink. |
| `editBufferInsertText` | `lib.zig:2017` | `u32, nullable byte pointer + u32 -> void` | The text is consumed synchronously and emits native events synchronously when an event sink is attached. |
| `createRenderer` | `lib.zig:648` | `u32, u32, u8, u8, nullable pointer -> u32` | A zero dimension or invalid destination returns handle `0`. The renderer owns its current/next buffers. |
| `setUseThread` | `lib.zig:711` | `u32, bool -> void` | The raw package passes `false`; all raw entrypoints remain on one native owner. |
| `resizeRenderer` | `lib.zig:1497` | `u32, u32, u32 -> void` | The reference export resizes the renderer's current and next buffers in place, so their borrowed handles remain valid on success. It catches and discards `CliRenderer.resize` errors; the raw facade validates positive dimensions and reads both buffer dimensions back, but hidden hit-grid or other internal allocation failures remain unobservable from this reference signature. |
| `destroyRenderer` | `lib.zig:721` | `u32 -> void` | Destruction invalidates renderer-owned borrowed buffer handles before renderer deinitialization. |
| `getCurrentBuffer` / `getNextBuffer` | `lib.zig:808`, `lib.zig:813` | `u32 -> u32` | Returned optimized-buffer handles are borrowed children of the renderer. |
| `render` | `lib.zig:845` | `u32, bool -> u8` | The renderer returns the reference `rendered`/`skipped`/`failed` values `0`/`1`/`2`; the OCaml facade maps them to a typed result without exposing the native enum. |
| `bufferClear` | `lib.zig:1168` | `u32, pointer to four u16 values -> void` | The color pointer is consumed synchronously. |
| `bufferDrawText` | `lib.zig:1228` | `u32, nullable byte pointer/u32, coordinates, two color pointers, u32 attributes -> void` | Text and colors are synchronous caller-owned input. |
| `bufferSetCell` | `lib.zig:1245` | `u32, coordinates, u32 character, two color pointers, u32 attributes -> void` | The cell is written in native SoA storage; no native cell view crosses the boundary. |
| `bufferDrawTextBufferView` | `lib.zig:2634` | `u32, u32, i32, i32 -> void` | The buffer and text-buffer-view handles are borrowed for the synchronous draw. Coordinates are signed so clipping can handle a view whose origin is outside the destination buffer. |
| `bufferWriteResolvedChars` | `lib.zig:1219` | `u32, nullable caller output pointer, `u32` capacity, `bool` -> `u32` | Native writes into caller-owned bounded storage and returns the byte count; a capacity smaller than the resolved output returns `0`. |
| `getRenderStats` | `lib.zig:788` | `u32, pointer to ExternalRenderStats -> void` | Caller supplies output storage; the Zig probe checks the nine-field C-compatible layout. |
| `getAllocatorStats` | `lib.zig:617` | `pointer to ExternalAllocatorStats -> void` | Active allocation counters are sampled for a diagnostic baseline. `total_requested_bytes` is valid only when the build enables GPA safe stats. |
| `yogaConfigCreate` / `yogaConfigFree` | `yoga.zig` | `void pointer -> void pointer`; `void pointer -> void` | These reference exports remain part of the ABI audit. `yogaNodeCreateForOpenTUI` acquires the shared OpenTUI configuration inside Zig, so the raw facade does not create or own a configuration object. |
| `yogaNodeCreateForOpenTUI` / `yogaNodeFree` / `yogaNodeFreeRecursive` | `yoga.zig:332`, `yoga.zig:340`, `yoga.zig:345` | `void pointer`; `void pointer -> void`; `void pointer -> void` | Each node is created independently with the reference OpenTUI configuration. Single-node free requires a detached node with no children; recursive free requires a detached root and releases its descendants. The C facade invalidates the corresponding generation-checked tokens. |
| `yogaNodeInsertChild` / `yogaNodeRemoveChild` / `yogaNodeGetChildCount` | `yoga.zig:359`, `yoga.zig:363`, `yoga.zig:375` | `void pointer, void pointer, u32 -> void`; `void pointer, void pointer -> void`; `const void pointer -> u32` | The raw facade validates that the child is detached, that the relationship does not create a cycle, and that removal names the direct parent. Insert and remove update only the native relationship; they do not free the child. The raw `Yoga.move_child` seam uses the same-parent remove/insert pair without freeing the node or descendants, after validating the final zero-based index. |
| `yogaNodeIsDirty` / `yogaNodeMarkDirty` / `yogaNodeGetHasNewLayout` / `yogaNodeSetHasNewLayout` | `yoga.zig:387-400` | `const void pointer -> bool`; `void pointer -> void`; `const void pointer -> bool`; `void pointer, bool -> void` | These read and update Yoga's native invalidation flags. The raw facade permits explicit dirtying only while a native measure owner is attached, which satisfies the pinned Yoga precondition for `YGNodeMarkDirty`. |
| `yogaNodeCalculateLayout` / `yogaNodeGetComputedLayout` | `yoga.zig:383`, `yoga.zig:419` | `void pointer, f32, f32, u32 -> void`; `const void pointer, pointer to six-f32 output -> void` | Dimensions and direction are checked at the C boundary. Layout is copied into an OCaml tuple; no Yoga output pointer escapes. |
| `yogaNodeStyleSetEnum` / `yogaNodeStyleSetFloat` / `yogaNodeStyleSetBorder` / `yogaNodeStyleSetValue` | `yoga.zig:439`, `yoga.zig:471`, `yoga.zig:489`, `yoga.zig:497` | Enum/float/border: `void pointer, u32, u32|f32 -> void`; value: `void pointer, u32, u32, u32, f32 -> void` | The typed surface binds the reference Yoga enum groups, float groups, border edges, and value groups. Value operations use the reference kind, edge/gutter, and unit codes; the C facade validates finite numeric inputs and code ranges before calling the exports. The Zig probe asserts the public kind, unit, and direction discriminants used by the OCaml mapping. |
| `createNativeRenderable` / `destroyNativeRenderable` / `nativeRenderableAttachYogaNode` / `nativeRenderableSetMeasureTarget` | `lib.zig:166-226`, `native-renderable.zig` | `void -> u32`; `u32 -> void`; `u32, Yoga node pointer -> bool`; `u32, u32, u32 -> bool` | A native renderable owns the synchronous Yoga measure callback. The OCaml owner borrows one independent Yoga node and one text-buffer view, retains both until the callback is cleared, and closes them in the order native renderable, view, buffer, and Yoga node. The raw facade rejects teardown that would invalidate an attached callback. |
| `createTextBuffer` / `destroyTextBuffer` / `textBufferGetLength` / `textBufferGetByteSize` / `textBufferClear` / `textBufferAppend` | `lib.zig:1637-1736` | `u8 -> u32`; `u32 -> void`; `u32 -> u32`; `u32 -> u32`; `u32 -> void`; `u32, nullable byte pointer, u32 -> void` | Text-buffer append registers the supplied byte span as non-owned native memory. The OCaml wrapper copies input bytes into stable Bigarray storage and retains each backing value until native buffer destruction. Clear removes text but does not release the native memory registry, so the retained backing values remain live. The pinned registry has 255 slots per buffer; each non-empty append consumes one slot and reports `Native_failure` after exhaustion rather than accepting an unappended input. |
| `textBufferRegisterMemBuffer` / `textBufferReplaceMemBuffer` / `textBufferSetTextFromMem` | `lib.zig:1708-1730` | `u32, nullable byte pointer, u32, bool -> u16`; `u32, u8, nullable byte pointer, u32, bool -> bool`; `u32, u8 -> void` | The OCaml `set_text` path follows the reference replace-then-register fallback and roots every non-owned Bigarray that the native registry may reference. The registry borrows those pointers; it does not free or own them. Because the pinned setter is a void function that catches native errors, the raw wrapper checks the resulting normalized byte size and reports `Native_failure` when the postcondition is not met. |
| `createTextBufferView` / `destroyTextBufferView` / `textBufferViewSetWrapWidth` / `textBufferViewSetWrapMode` / `textBufferViewSetFirstLineOffset` / `textBufferViewMeasureForDimensions` | `lib.zig:1789-1957` | `u32 -> u32`; `u32 -> void`; `u32, u32 -> void`; `u32, u8 -> void`; `u32, u32 -> void`; `u32, u32, u32, pointer to 8-byte result -> bool` | A view borrows its text buffer. The raw wrapper tracks the parent and rejects buffer close while a view remains open. A native measure target holds a view-use claim, so view close is rejected until the native renderable clears its callback. |
| `getTerminalCapabilities` | `lib.zig:986` | `u32, pointer to 64-byte ExternalCapabilities -> void` on supported 64-bit hosts | Zig returns borrowed terminal-name/version pointers and `usize` lengths. The C shim checks the lengths and copies both strings before returning to OCaml. |
| `processCapabilityResponse` | `lib.zig:1017` | `u32, nullable byte pointer, u32 -> void` | The response is caller-owned and consumed synchronously. An empty OCaml string crosses as a null pointer with length zero. |
| `createNativeSpanFeed` / `attachNativeSpanFeed` / `destroyNativeSpanFeed` | `lib.zig:358`, `native-span-feed.zig` | pointer to `Options` -> nullable stream pointer; stream pointer -> `i32`/`void` | The raw facade owns the feed behind an abstract generation-checked token and destroys it only after a successful close. The reference source is copied into a generated build directory before the tracked export patch is applied. |
| `streamWrite` / `streamCommit` | `native-span-feed.zig` | stream pointer, nullable byte pointer, `u32` -> `i32`; stream pointer -> `i32` | Input bytes are copied synchronously into native chunks. Commit publishes the pending span; it does not expose the chunk address to OCaml. |
| `streamReserve` / `streamCommitReserved` / `streamCancelReserved` | `native-span-feed.zig` | stream pointer, `u32`, pointer to 16-byte `ReserveInfo` -> `i32`; stream pointer, `u32` -> `i32`; stream pointer -> `i32` | The C facade keeps the native reserve pointer private and stages OCaml bytes before commit. Cancellation clears the reservation without advancing the write cursor; close reports `Busy` while it is active. |
| `streamDrainSpans` / `streamMarkSpanConsumed` | `native-span-feed.zig` | stream pointer, pointer to 24-byte `SpanInfo`, `u32` -> count; stream pointer, pointer to `SpanInfo` -> `i32` | Drained span records contain borrowed chunk addresses. The facade copies each payload into OCaml bytes and holds a generation-checked release token. Release validates chunk pointer, index, offset, and length before decrementing the native chunk refcount. |
| `streamGetStats` | `native-span-feed.zig` | stream pointer, pointer to 24-byte `Stats` -> `i32` | The four counters are copied into an OCaml record. The callback surface is not used by `opentui-raw`. |

The ABI smoke test records the selected failure behavior: zero dimensions, an
invalid buffered destination, and a null event callback return handle `0`;
invalid or stale renderer/buffer handles are no-ops or return `0`; nullable
empty spans are accepted without writing; and a caller-owned output capacity
that is too small returns `0` without exposing a native error object. These
cases are boundary evidence for the raw seam, not the final typed OCaml error
API.

`NativeHandle` is a `u32` packed by the reference registry: a 16-bit slot
index, 12-bit generation, and 4-bit kind. Zero is invalid. The packed fields
remain private to Zig. The C facade uses a separate generation-checked token
registry for Yoga because Yoga pointers are not entries in the reference
registry: `Yoga.Node.t` is an abstract OCaml domain backed by a packed,
generation-checked node token. Each token records its direct parent token when
attached. The registry rejects stale tokens, non-detached insertion, invalid
parent relationships, invalid dimensions, and invalid directions before
calling Yoga.

`ExternalYogaLayout` is six consecutive `f32` values in the specified order
`left`, `top`, `right`, `bottom`, `width`, `height`, for 24 bytes. The
`ExternalCapabilities` struct is 64 bytes on the supported 64-bit targets;
the fixed-width one-byte booleans and enum codes occupy the first 20 bytes,
followed by two borrowed pointer/`size_t` pairs and the final one-byte flags.
The source-importing Zig probe and the C header both assert these layouts and
the exact function-pointer signatures.

The capability facade maps the reference enum codes to typed OCaml variants. It
does not preserve borrowed terminal pointers: names and versions are copied
into the returned snapshot, and an invalid or stale renderer produces a
structured raw error.

The output-feed facade asserts the 24-byte `Options`, `Stats`, and `SpanInfo`
layouts and the 16-byte `ReserveInfo` layout. `Span_feed.drain` returns copied
payloads paired with explicit, idempotent release tokens; `Span_feed.Reservation`
exposes a caller-owned staging buffer with explicit commit or cancel. This is
the safe ownership proof for the reference feed, not a zero-copy
Bigarray/Cstruct view. A closed feed invalidates outstanding copied tokens.

The probe also checks `RGBA = [4]u16`, one-byte Zig `bool`, the callback
signature, the selected function types, and the offsets and size of
`ExternalBuildOptions`, `ExternalAllocatorStats`, and the nine-field
`ExternalRenderStats`. The C header repeats the fixed-width and layout
assertions and uses `_Generic` function-pointer checks so the C compiler cannot
silently accept a declaration with a different calling shape.

## Repeated update baseline

The native smoke test samples `getAllocatorStats` around 1,024 ASCII
`bufferSetCell` calls on an 8x1 memory renderer followed by one
`bufferWriteResolvedChars` call. It reports the native-call counts and both
active-allocation samples to OCaml, verifies the resolved `C` through `J`
output, and requires the active-allocation count to remain stable. This is
diagnostic evidence rather than a fixed allocation threshold; the ReleaseSafe
runtime artifact leaves `requested_bytes_valid` false.

The output smoke also allocates an OCaml-owned `bytes` value in the test shim,
passes its storage directly to `bufferWriteResolvedChars`, and checks `A` and
`B` from OCaml without converting the result to a string.

## Build and link

The reference dynamic library is built with Zig 0.16.0 in
`vendor/opentui/packages/core/src/zig` using `ReleaseSafe`. Its
memory-output invocation uses `createRenderer(width, height, 1, 2, NULL)` and
leaves `setUseThread` off. `ReleaseSafe` is required here because the reference Debug
allocator captures stack traces that are not compatible with the OCaml C-call
frame used by the runtime smoke. The compile-only ABI probe remains Debug.
The Dune rule verifies the audited SHA-256 of the reference
`native-span-feed.zig`, copies the source into a generated build directory,
applies the tracked `span_feed_exports.patch`, runs the ReleaseSafe build and
source-importing Zig probe against that generated tree, copies the host
artifact into the Dune native output directory, and links the C facade against
it with `-lopentui`.

The reference build pulls Yoga's C++ sources and, on macOS, CoreFoundation,
CoreAudio, and AudioToolbox. Linux uses the reference `dl`, `pthread`, and `m`
dependencies. The Dune rule accepts only the host target names already
selected by the reference build (`aarch64-macos`, `x86_64-macos`,
`aarch64-linux`, and `x86_64-linux`).

## Typed raw operations

The typed raw operations in `opentui-raw` provide
generation-checked independent Yoga-node operations, native text measurement,
a copied capability snapshot, and the audited NativeSpanFeed ownership
protocol while preserving the reference renderer/buffer/event ownership model.
The OCaml API exposes `Yoga.Node.create`, explicit child attach/detach/free
operations, typed style operations, typed layout readback,
`Text_buffer`/`Text_buffer_view`, `Native_renderable`, `Span_feed.drain`, and
explicit reservation commit/cancel. It does not expose `YGNodeRef`,
`YGConfigRef`, packed style values, native span pointers, raw native pointers,
or callbacks. Capability responses are processed synchronously and can be
read as a typed `Capabilities.t` record.

Black-box tests cover exact six-field layout readback, non-destructive detach,
single-node and recursive free, invalid dimensions, invalid style values,
native text measurement through Yoga, stable text storage across compaction,
repeated text replacement, explicit native dirtying, protected native-measure
teardown, and Yoga leaf enforcement,
XTVERSION string copying, enum decoding, closed-renderer behavior, copied
output spans, release-driven chunk reuse, and reservation
busy/cancel/commit behavior.

## Outside this ABI contract

The complete stdin parser, native-owned zero-copy `NativeSpanFeed` views, raw
cell pointers, audio, image, editor, and all high-level packages are outside
this boundary. The feed's copied payload and reservation ownership protocol is
implemented here. Mapping native chunks into Bigarray/Cstruct views requires a
separate lifetime and benchmark contract.
