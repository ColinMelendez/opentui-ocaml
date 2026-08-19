(** Typed [webgpu.h] boundary over the pinned official wgpu-native release.

    The binding modules, audited C stubs, and tests land with the
    three-renderer phases
    ({e docs/major-features/in-progress/three-renderer/feature.md}). The
    pinned release is fetched and validated by the repository Nix flake and
    discovered through pkg-config; this library never downloads artifacts or
    searches unpinned system locations. *)

val pinned_release_tag : string
(** The upstream wgpu-native tag whose headers this binding compiles against.
    Cross-check against [pkg-config --modversion wgpu-native] at build time. *)

val pinned_release_version : string
(** The same pin without the leading v. *)
