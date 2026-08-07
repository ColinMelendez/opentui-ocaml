(lang dune 3.22)
(name opentui-raw)

(package
 (name opentui-raw)
 (synopsis "Typed low-level OCaml boundary for OpenTUI's native ABI")
 (description
  "The first lower-level package in the OpenTUI OCaml monorepo. It will expose typed native handles and bindings without depending on JavaScript.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  (windtrap :with-test)))

(package
 (name opentui-terminal)
 (synopsis "Reusable OCaml terminal input foundations for OpenTUI")
 (description
  "A terminal-side package for bounded reusable input storage, protocol framing, and semantic key and mouse decoding. Terminal modes and output policy remain separate until their ownership contracts are stable.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  (windtrap :with-test)))

(package
 (name opentui-native)
 (synopsis "Imperative native renderer foundation for OpenTUI")
 (description
  "A small renderer and frame-lifecycle composition over opentui-raw. Retained scenes, Yoga renderables, terminal policy, and reactive bindings remain separate layers.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  opentui-raw
  (windtrap :with-test)))
