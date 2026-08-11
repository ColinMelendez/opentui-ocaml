# Performance profile

`profile.exe` is a small repeatable native benchmark for the current public
seams. It reports monotonic elapsed nanoseconds and OCaml GC words for:

- retained text updates and caller-owned resolved-character output;
- full 80x24 native frame updates and resolved-character output;
- Eio input reads through the terminal coordinator; and
- repeated writes through the Eio output sink.

Run it from the Nix development environment:

```sh
nix develop --command dune exec ./bench/profile.exe
```

The values are diagnostic baselines, not absolute gates. Compare runs using
the same compiler, native revision, host, and benchmark parameters. The
profile intentionally does not cover Lwd, widgets, or native-owned span
views; those require their own contracts first.
