# Reference comparisons

This directory contains optional differential checks against the TypeScript
implementation in `vendor/opentui`. That implementation is a behavioral
reference, not an ABI specification. The checks are outside `dune runtest`
because they require Bun and the reference source, while the OCaml test suite
must remain reproducible from the Nix/Dune environment alone.

The parser comparison targets the common typed-event contract of
`StdinParser`. The shared vectors feed identical chunks to the reference parser
and `opentui-core.Lib.Stdin_parser`; each runner emits a normalized line of

```text
case<TAB>kind<TAB>protocol<TAB>payload-as-hex
```

Both parsers emit typed key, mouse, paste, and response events. The normalized
format represents key and mouse wire payloads as `sequence`, ordinary keys as
`key`, responses as `sequence`, and paste bodies as `paste`. This preserves
wire-level comparison while retaining the parser's typed event boundary.

Run the comparison from the repository root:

```sh
sh packages/opentui-core/reference/compare_terminal_parser.sh
```

The vectors are deterministic and cover split UTF-8, split CSI/SS3, response
framing, SGR/X10 mouse wire forms, OSC/DCS/APC termination, bracketed paste,
and timeout flushing. A mismatch is a contract review item. Do not update
either side without first determining whether the difference is an intentional
layer boundary, a reference behavior change, or an OCaml bug.

The reference revision is the Git link recorded in
[`vendor/README.md`](../../../vendor/README.md). Performance measurements stay
separate: identical workloads may be useful for context, but TypeScript/Bun
and OCaml/native latencies are not a single cross-runtime gate.

## Comparative performance

The optional parser comparison uses the same deterministic byte workloads at
the terminal-parser boundary. The OCaml and Bun runners measure their typed
parser events and normalize them to the same wire-oriented output. This is a
contextual comparison of equivalent parser responsibilities.
`perf_manifest.tsv` carries the
pattern bytes, event multiplicity, payload size, and chunk shape so neither
runner needs a private pattern table.

Run it from the repository root:

```sh
sh packages/opentui-core/reference/compare_terminal_perf.sh
```

The protocol and shape fields are checked before timings are displayed, and
timing rows are joined by case name rather than by preamble line position.
OCaml timed GC words/collections and Bun retained post-GC heap/ArrayBuffer
deltas are different diagnostics, not a cross-runtime allocation rate. Run
comparisons on the same host with the same compiler/runtime and the same
`vendor/opentui` revision, and treat the output as a diagnostic baseline rather than
a regression gate.

The reference `bench:layout`, `bench:js`, and `bench:native` suites provide
additional context, but their tree sizes, scheduler, renderer, and native
optimization boundaries differ from this repository's retained scene. A
retained-core side-by-side benchmark requires an equivalent workload manifest
that states those differences explicitly.
