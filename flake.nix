{
  description = "Native OCaml foundations for OpenTUI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # The pinned official wgpu-native release. Archive names and hashes are
      # the implementation source of truth for the three-renderer artifact
      # policy; upgrading the pin is an explicit, auditable change to this map.
      wgpuNativeRelease = {
        version = "29.0.1.1";
        archives = {
          "aarch64-darwin" = {
            url = "https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.1.1/wgpu-macos-aarch64-release.zip";
            hash = "sha256-pXl6N7Gt9yC81dz/spHtu9W3sUvgo4dMKOY5OmVaej4=";
            sharedLibrary = "libwgpu_native.dylib";
          };
          "aarch64-linux" = {
            url = "https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.1.1/wgpu-linux-aarch64-release.zip";
            hash = "sha256-AV/N8duuguYUp4PMOAF+U5muCSeoif6bacm2ZLxhtHo=";
            sharedLibrary = "libwgpu_native.so";
          };
          "x86_64-linux" = {
            url = "https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.1.1/wgpu-linux-x86_64-release.zip";
            hash = "sha256-laTZDAcQBamNA+qzSL6qawfhbrANHc25+DSPdeuX7Fo=";
            sharedLibrary = "libwgpu_native.so";
          };
        };
      };

      makeWgpuNative = { pkgs, system }:
        let
          inherit (wgpuNativeRelease) version;
          tag = "v${version}";
          archive =
            wgpuNativeRelease.archives.${system}
            or (throw "wgpu-native ${tag}: no release archive pinned for target ${system}");
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "wgpu-native";
          inherit version;

          src = pkgs.fetchurl { inherit (archive) url hash; };

          nativeBuildInputs = [ pkgs.unzip ];

          sourceRoot = ".";

          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall

            required="
              include/webgpu/webgpu.h
              include/webgpu/wgpu.h
              lib/libwgpu_native.a
              lib/${archive.sharedLibrary}
              wgpu-native-meta/webgpu.yml
              wgpu-native-meta/wgpu-native-git-tag
            "
            for path in $required; do
              if [ ! -f "$path" ]; then
                echo "wgpu-native ${tag} layout drift: missing $path" >&2
                exit 1
              fi
            done

            recordedTag="$(tr -d '[:space:]' < wgpu-native-meta/wgpu-native-git-tag)"
            if [ "$recordedTag" != "${tag}" ]; then
              echo "wgpu-native archive metadata tag '$recordedTag' does not match pin '${tag}'" >&2
              exit 1
            fi

            mkdir -p "$out/include" "$out/lib/pkgconfig" "$out/share/wgpu-native-meta"

            cp -R include/. "$out/include/"
            install -m 0444 lib/libwgpu_native.a "$out/lib/libwgpu_native.a"
            install -m 0444 "lib/${archive.sharedLibrary}" "$out/lib/${archive.sharedLibrary}"
            install -m 0444 wgpu-native-meta/webgpu.yml "$out/share/wgpu-native-meta/webgpu.yml"
            printf '%s\n' "$recordedTag" > "$out/share/wgpu-native-meta/wgpu-native-git-tag"

            cat > "$out/lib/pkgconfig/wgpu-native.pc" <<EOF_PC
            prefix=$out
            Name: wgpu-native
            Description: Native WebGPU implementation based on wgpu-core (pinned official release)
            Version: ${version}
            Libs: -L$out/lib -lwgpu_native
            Cflags: -I$out/include/webgpu
            EOF_PC

            runHook postInstall
          '';

          passthru.tag = tag;

          meta = with pkgs.lib; {
            description = "Pinned official wgpu-native ${tag} release (WebGPU C API)";
            license = with licenses; [ mit asl20 ];
          };
        };
    in {
      packages = forAllSystems (system: {
        wgpu-native = makeWgpuNative {
          pkgs = import nixpkgs { inherit system; };
          inherit system;
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          wgpu-native = self.packages.${system}.wgpu-native;
          # Headless CI needs a software Vulkan implementation so adapter
          # requests succeed without a display or physical GPU.
          linuxVulkan = nixpkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.vulkan-loader
            pkgs.mesa.drivers
            pkgs.vulkan-tools
            pkgs.binutils
          ];
          # ICD manifest names are not stable across Mesa packaging (some
          # carry an architecture suffix, some do not), so resolve the
          # lavapipe manifest at shell startup instead of hardcoding one.
          vkShellHook =
            nixpkgs.lib.optionalString pkgs.stdenv.isLinux ''
              export VK_DRIVER_FILES="$(echo ${pkgs.mesa.drivers}/share/vulkan/icd.d/lvp_icd.*.json 2>/dev/null | head -n1)"
              export VK_ICD_FILENAMES="$VK_DRIVER_FILES"
            '';
          # wgpu-native dlopens libvulkan.so.1 by soname; runpath inheritance
          # from the test executable cannot be relied upon for that lookup.
          linuxLdLibraryPath =
            nixpkgs.lib.optionalString pkgs.stdenv.isLinux
              (pkgs.lib.makeLibraryPath [
                pkgs.vulkan-loader
                pkgs.mesa.drivers
              ]);
        in {
          # Keep CI and repeatable test runs free of editor-only tools while
          # retaining the same compiler, Dune, and native toolchain.
          test = pkgs.mkShell {
            LC_ALL = "C";
            PKG_CONFIG_PATH = "${wgpu-native}/lib/pkgconfig";
            LD_LIBRARY_PATH = linuxLdLibraryPath;
            shellHook = vkShellHook;
            packages = with pkgs;
              [
                cmake
                curl
                git
                libffi
                pkg-config
                wgpu-native
                zig_0_16
              ]
              ++ linuxVulkan
              ++ (with ocamlPackages_latest; [
                ocaml
                dune_3
              ]);
          };

          # mkShell (rather than mkShellNoCC) keeps a C/C++ compiler available
          # for Dune package builds and the native OpenTUI/Yoga boundary.
          default = pkgs.mkShell {
            LC_ALL = "C";
            PKG_CONFIG_PATH = "${wgpu-native}/lib/pkgconfig";
            LD_LIBRARY_PATH = linuxLdLibraryPath;
            shellHook = vkShellHook;
            packages = with pkgs;
              [
                cmake
                curl
                git
                libffi
                pkg-config
                wgpu-native
                zig_0_16
              ]
              ++ linuxVulkan
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
