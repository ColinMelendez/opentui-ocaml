open Windtrap
module Size_source = Opentui_core.Platform.Eio_unix_runtime.Terminal_size_source

let () =
  run "opentui-core-platform-eio-unix"
    [
      test "reports a structured error for a non-terminal descriptor" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let source, sink = Eio_unix.pipe sw in
          Eio.Flow.close sink;
          let backend = Eio.Stdenv.backend_id env in
          match Size_source.get (Eio_unix.Resource.fd source) with
          | Error
              (Size_source.Unix_error ((Unix.ENOTTY | Unix.EOPNOTSUPP), _, _))
            ->
              ()
          | Error (Size_source.Unix_error (error, _, _)) ->
              fail (Unix.error_message error)
          | Error Size_source.Invalid_dimensions ->
              fail "a pipe returned invalid dimensions instead of a Unix error"
          | Ok _ ->
              fail
                (Printf.sprintf "a pipe was reported as a terminal on %s"
                   backend));
    ]
