(lang dune 3.22)
(name opentui-raw)

(pin
 (url
  "git+https://github.com/invariant-hq/thumper.git#0d42dc6964e30525b0595b6d5be04a1eda76c90e")
 (package (name thumper)))

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
 (name opentui-core)
 (synopsis "Eio-native OpenTUI core and source-tree correspondence")
 (description
  "The Eio-native OpenTUI core. Its source tree mirrors the upstream core package and contains the renderer, retained renderables, terminal libraries, and Eio/Unix platform integrations. The audited OCaml-to-Zig ABI remains in opentui-raw.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  opentui-raw
  eio
  cstruct
  mtime
  (eio_main :with-test)
  (windtrap :with-test)))

(package
 (name opentui-wgpu)
 (synopsis "Typed webgpu.h boundary over the pinned wgpu-native release")
 (description
  "The typed low-level WebGPU boundary for the OpenTUI OCaml monorepo. It owns audited webgpu.h C stubs and foreign resource lifetimes over the pinned official wgpu-native release, consumed through Nix and pkg-config only.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  dune-configurator
  (windtrap :with-test)))

(package
 (name opentui-three)
 (synopsis "Three.js-shaped 3D scenes rendered into terminal cells")
 (description
  "The OCaml replacement for the reference @opentui/three package: an imperative scene graph, WebGPU render pipelines over opentui-wgpu, and cell-conversion output composed with the opentui-core renderer.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  opentui-core
  opentui-wgpu
  (windtrap :with-test)))

(package
 (name opentui-bench)
 (synopsis "Benchmark and tracing harnesses for OpenTUI")
 (description
  "Development-only benchmark and tracing entry points for OpenTUI. The harnesses depend on the public package layers but tracing tools do not enter the runtime libraries.")
 (license ISC)
 (authors "Colin <cwrmcolin@gmail.com>")
 (maintainers "Colin <cwrmcolin@gmail.com>")
 (depends
  (ocaml (>= 5.2))
  opentui-core
  eio_main
  mtime
  runtime_events_tools
  thumper))
