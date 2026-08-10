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
 (name opentui-terminal-eio-unix)
 (synopsis "Unix terminal runtime boundary for the OpenTUI Eio layer")
 (description
  "A Unix-only terminal runtime boundary over Eio_unix. It provides a validated size probe, scoped SIGWINCH source, and saved-termios terminal session without closing caller-owned resources.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  opentui-terminal
  opentui-terminal-eio
  eio))

(package
 (name opentui-terminal)
 (synopsis "Reusable OCaml terminal input foundations for OpenTUI")
 (description
  "A terminal-side package for bounded reusable input storage, protocol framing, semantic key and mouse decoding, writer-free mode transitions, input-event composition, and deadline coordination. Output policy remains separate until its ownership contract is stable.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  (windtrap :with-test)))

(package
 (name opentui-terminal-eio)
 (synopsis "Eio flow adapter for the OpenTUI terminal foundation")
 (description
  "A separate Eio/Cstruct runtime boundary over opentui-terminal. It supplies reusable input storage, caller-clocked timeout coordination, revision wakeups, and caller-run dispatch without moving Eio into the parser package or owning terminal resources.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  opentui-terminal
  eio
  cstruct
  mtime
  (eio_main :with-test)
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
