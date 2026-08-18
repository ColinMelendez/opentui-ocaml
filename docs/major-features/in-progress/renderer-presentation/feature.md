# Renderer presentation

Status: in progress.

This feature records the renderer-owned terminal presentation boundary for
global background color and terminal cursor control. It restores the
reference API surface without moving terminal state into a second OCaml
cache. Debug overlays, hit-grid dumps, and native arena introspection remain
separate diagnostic work.

## Purpose

The retained tree draws into native current/next buffers, but the reference
renderer also owns presentation state that is not a cell in either buffer. A
full-screen background box can approximate the background visually, but it
cannot establish the renderer backdrop used when clearing, blending, and
recovering a failed frame. Likewise, an editor's in-buffer cursor is not the
terminal cursor rendered by the native terminal output path.

The OCaml port therefore exposes these operations through the same owner that
owns the native buffers and hit grid:

```text
Renderer.t / Render_context.t
        │ typed, owner-scoped forwarding
        ▼
opentui-raw Renderer.t
        │ checked C ABI calls
        ▼
native CliRenderer and Terminal
```

## Reference correspondence

| Reference source | OCaml correspondence | Ownership |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/renderer.ts` `setBackgroundColor` | `Renderer.set_background_color` | Core retains the logical backdrop used to seed the next buffer; native owns the renderer backdrop. |
| `vendor/opentui/packages/core/src/zig/lib.zig` `setBackgroundColor` | `opentui-raw/native/opentui_abi.h`, `raw_stubs.c`, and `Raw.Renderer.set_background_color` | The RGBA pointer is borrowed only for the synchronous native call. |
| `vendor/opentui/packages/core/src/types.ts` `setCursorPosition` | `Renderer.set_cursor_position` and `Render_context.set_cursor_position` | Native terminal state is authoritative. |
| `vendor/opentui/packages/core/src/types.ts` `setCursorStyle` and `CursorStyleOptions` | `cursor_style_options`, `set_cursor_style`, `set_cursor_color`, and `set_mouse_pointer` | Native preserves fields omitted by an update; Core does not mirror the resulting cursor state. |
| `vendor/opentui/packages/core/src/zig/lib.zig` `getCursorState` | `Raw.Renderer.cursor_state` and `Renderer.cursor_state` | State is copied out for diagnostics and tests; the returned value is not a control cache. |

The raw ABI includes compile-time C and Zig checks for the cursor option and
state structs. The vendored native source already provides the reference
exports, so this feature adds no generated-source patch.

## Background contract

`Renderer.set_background_color` performs one owner-local update:

1. Set the native renderer backdrop.
2. Clear the renderer's next buffer with the same validated `Color.t`.
3. Store that color as Core's logical backdrop for failed-frame recovery.
4. Coalesce a render request through the existing renderer scheduler.

The current buffer is not rewritten immediately. The next successful native
frame remains the presentation boundary, matching the reference's
`nextRenderBuffer.clear` and `requestRender` behavior. A failed Core frame
also clears the next buffer with this backdrop, so partial drawing cannot
leak into the retry.

The default logical backdrop is transparent black. A caller that wants a
terminal-wide opaque color supplies an opaque `Color.t`; a full-screen box is
not required.

## Cursor contract

The cursor style mapping is fixed to the native reference discriminants:

| OCaml constructor | Native code |
| --- | ---: |
| `Block` | 0 |
| `Line` | 1 |
| `Underline` | 2 |
| `Default` | 3 |

Mouse-pointer styles use the reference codes 0 through 5 in the order
`default`, `pointer`, `text`, `crosshair`, `move`, and `not-allowed`.

`cursor_style_options` has optional `style`, `blinking`, `color`, and
`cursor` fields. An absent field is encoded as the reference `255` sentinel
or null color pointer, which means “leave the native value unchanged.”
`set_cursor_color` is the corresponding convenience operation for changing
only the color. `set_cursor_position` defaults visibility to true and passes
coordinates to the native reference operation, which clamps them to its
one-based terminal coordinate space.

Cursor operations are synchronous owner-local presentation updates. They do
not request a render frame: the native terminal state is already updated, and
the next native presentation observes it. `Render_context` exposes the same
forwarding operations so a renderable does not need to depend on the concrete
`Renderer.t` representation.

`cursor_state` reports the native one-based position, visibility, style,
blinking flag, and copied RGBA color. It is an observation API, not a second
source of truth. After renderer close, all checked operations report
`Error.Closed`.

## Lifecycle and failure rules

- The raw renderer capability borrows the renderer owner and rejects every
  presentation operation after close.
- Color pointers and cursor option structs are stack-backed only for the
  synchronous C-to-Zig call; no native pointer is retained by OCaml.
- Background updates use the existing coalesced request bit and never start a
  fiber themselves.
- Cursor updates do not affect retained layout, hit-grid production, or the
  renderer's pending-request bit.
- Native resize preserves presentation state while clamping the cursor to the
  new terminal dimensions, as in the reference renderer.

## Non-goals

This feature does not add debug overlay toggles, hit-grid dumps, arena byte
introspection, automatic start/stop/auto rendering modes, or a new terminal
output owner. Session-wide terminal mode setup remains in the Eio terminal
output boundary; native renderer cursor presentation remains below the Core
capability boundary.

## Acceptance evidence

The raw presentation integration test covers native ownership, default state,
one-based coordinate clamping, optional-field persistence, resize clamping,
and closed handles. The Core presentation integration test covers logical
background state, next-buffer clearing, coalesced repaint requests, direct
renderer controls, context forwarding, mouse-pointer option encoding, and
closed renderer/context behavior.
