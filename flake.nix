{
  description = "Native OCaml foundations for OpenTUI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          # Keep CI and repeatable test runs free of editor-only tools while
          # retaining the same compiler, Dune, and native toolchain.
          test = pkgs.mkShell {
            packages = with pkgs;
              [
                curl
                git
                pkg-config
                zig_0_16
              ]
              ++ (with ocamlPackages_latest; [
                ocaml
                dune_3
              ]);
          };

          # mkShell (rather than mkShellNoCC) keeps a C/C++ compiler available
          # for Dune package builds and the native OpenTUI/Yoga boundary.
          default = pkgs.mkShell {
            packages = with pkgs;
              [
                curl
                git
                pkg-config
                zig_0_16
              ]
              ++ (with ocamlPackages_latest; [
                ocaml
                dune_3
                odoc
                ocaml-lsp
                ocamlformat
              ]);
          };
        });
    };
}
