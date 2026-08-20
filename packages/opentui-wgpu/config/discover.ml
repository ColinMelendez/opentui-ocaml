open Configurator.V1

(* Keep in lockstep with packages/opentui-wgpu/src/wgpu.ml; the build fails
   here when the pinned release is not exactly what pkg-config resolves. *)
let pinned_version = "29.0.1.1"

let rpath_flags libs =
  List.filter_map
    (fun flag ->
      if String.length flag > 2 && String.starts_with ~prefix:"-L" flag then
        Some ("-Wl,-rpath," ^ String.sub flag 2 (String.length flag - 2))
      else None)
    libs

let () =
  main ~name:"opentui_wgpu_discover" (fun conf ->
      let pkg_config =
        match Pkg_config.get conf with
        | Some pkg_config -> pkg_config
        | None -> die "pkg-config was not found in PATH"
      in
      let expr = "wgpu-native = " ^ pinned_version in
      match Pkg_config.query_expr_err pkg_config ~package:"wgpu-native" ~expr with
      | Error message ->
          die "wgpu-native is not discoverable as %s through pkg-config: %s"
            expr message
      | Ok { cflags; libs } ->
          Flags.write_sexp "../src/c_flags.sexp" cflags;
          Flags.write_sexp "../src/c_library_flags.sexp" (libs @ rpath_flags libs))
