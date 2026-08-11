# Reference comparisons

This directory contains optional differential checks against the pinned
OpenTUI TypeScript source. The reference is a behavioral oracle, not an ABI
specification, and these checks are deliberately outside `dune runtest`: they
require Bun and the upstream submodule, while the OCaml test suite must remain
reproducible from the Nix/Dune environment alone.

The first comparison targets the common byte-framing contract of
`StdinParser`. The shared vectors feed identical chunks to the upstream parser
and `opentui-terminal.Stdin_parser`; each runner emits a normalized line of

```text
case<TAB>kind<TAB>protocol<TAB>payload-as-hex
```

The comparison intentionally stops before semantic key and mouse decoding.
OpenTUI's parser emits typed key/mouse events, while the OCaml design keeps
framing, key decoding, mouse decoding, and event handoff in separate layers.
Escape-shaped reference key and mouse events are therefore normalized back to
their wire sequence, while ordinary keys and paste bodies remain byte events.

Run the comparison from the repository root:

```sh
sh reference/compare_terminal_parser.sh
```

The vectors are deterministic and cover split UTF-8, split CSI/SS3, response
framing, SGR/X10 mouse wire forms, OSC/DCS/APC termination, bracketed paste,
and timeout flushing. A mismatch is a contract review item: update neither
side by reflex. First determine whether the difference is an intentional layer
boundary, an upstream behavior change, or an OCaml bug.

The reference source revision remains the parent repository's pinned
`vendor/opentui` gitlink. Performance measurements stay separate: identical
workloads may be useful for context, but TypeScript/Bun and OCaml/native
latencies are not a single cross-runtime gate.
