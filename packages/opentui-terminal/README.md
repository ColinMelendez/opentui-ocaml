# opentui-terminal

This package is the terminal-side foundation kept beside `opentui-native`. It
does not depend on the renderer or `opentui-raw`.

The first slice contains `Byte_queue` and `Stdin_parser`. `Byte_queue` is a
reusable `Bigarray.Array1`-backed queue for stdin bytes. It advances logical
cursors without copying on every consume, compacts before growing, and rejects
an append that would exceed its configured maximum atomically. `append` accepts
an existing byte bigarray so an eventual Eio reader can reuse its input storage.

`Stdin_parser` is the byte-framing layer above the queue. It emits owned
complete ground bytes as `Key`, raw CSI/SS3/OSC/DCS/APC units as `Sequence`, and
bracketed paste bodies as `Paste`. The caller's timer coordinator invokes
`flush_timeout` for incomplete ESC/protocol prefixes.

Semantic key naming/modifiers, mouse decoding, terminal mode transitions, event
dispatch, output lifecycle, Eio integration, and native zero-copy views are
intentionally outside this first package slice.
