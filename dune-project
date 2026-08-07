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
  "A terminal-side package for bounded reusable input storage. Terminal modes and protocol decoding are added only after their ownership contracts are stable.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  (windtrap :with-test)))
