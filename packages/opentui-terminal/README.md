# opentui-terminal

This package is the terminal-side foundation kept beside `opentui-native`. It
does not depend on the renderer or `opentui-raw`.

The first slice is `Byte_queue`: a reusable `Bigarray.Array1`-backed queue for
stdin bytes. It advances logical cursors without copying on every consume,
compacts before growing, and rejects an append that would exceed its configured
maximum atomically. `append` accepts an existing byte bigarray so an eventual
Eio reader can reuse its input storage.

Terminal mode transitions, the full escape-sequence parser, event dispatch,
output lifecycle, Eio integration, and native zero-copy views are intentionally
outside this first package slice.
