# opentui-terminal

This package is the terminal-side foundation kept beside `opentui-native`. It
does not depend on the renderer or `opentui-raw`.

The first slice contains `Byte_queue`, `Stdin_parser`, `Key_decoder`, and
`Mouse_decoder`.
`Byte_queue` is a
reusable `Bigarray.Array1`-backed queue for stdin bytes. It advances logical
cursors without copying on every consume, compacts before growing, and rejects
an append that would exceed its configured maximum atomically. `append` accepts
an existing byte bigarray so an eventual Eio reader can reuse its input storage.

`Stdin_parser` is the byte-framing layer above the queue. It emits owned
complete ground bytes as `Key`, raw CSI/SS3/OSC/DCS/APC units as `Sequence`, and
bracketed paste bodies as `Paste`. The caller's timer coordinator invokes
`flush_timeout` for incomplete ESC/protocol prefixes.

`Key_decoder` is a pure semantic layer above the framing events. It maps common
control, UTF-8, meta, CSI, SS3, modifier, and modifyOtherKeys sequences to named
keys or owned character bytes. It preserves and copies sequences it does not
recognize, including mouse frames and terminal responses, so protocol policy
can remain separate.

`Mouse_decoder` is the next semantic layer for complete CSI mouse frames. It
decodes the pinned SGR and X10 encodings, preserves high X10 coordinate bytes,
tracks SGR button state for drag classification, and returns `None` for frames
that are not valid mouse events. It does not own terminal mode negotiation or
event dispatch.

The package does not yet own terminal mode transitions, event dispatch, output
lifecycle, Eio integration, or native zero-copy views.
