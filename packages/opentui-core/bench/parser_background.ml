module Types = Opentui_core.Lib.Tree_sitter_types
module Client = Opentui_core.Lib.Tree_sitter_client
module Background = Opentui_core.Platform.Eio_runtime.Background

let fail message =
  prerr_endline message;
  Stdlib.exit 1

let expect_background result =
  match result with
  | Ok value -> value
  | Error error -> fail (Background.message error)

let expect_parser result =
  match result with
  | Ok value -> value
  | Error (Types.No_parser message) -> fail ("no parser: " ^ message)
  | Error (Types.Failed message) -> fail ("parser failed: " ^ message)

let measure operation =
  let start = Mtime_clock.elapsed_ns () in
  operation ();
  Int64.sub (Mtime_clock.elapsed_ns ()) start

let repeat count operation =
  let remaining = ref count in
  while Int.compare !remaining 0 > 0 do
    decr remaining;
    operation ()
  done

let run_sync ~iterations parser ~content =
  measure (fun () ->
      repeat iterations (fun () ->
        ignore (expect_parser (Client.run_parser parser ~content))
      ))

let run_background ~iterations submitter parser ~content =
  measure (fun () ->
      repeat iterations (fun () ->
        let result, resolver = Eio.Promise.create () in
        let work () = Client.run_parser parser ~content in
        let on_complete value = Eio.Promise.resolve resolver value in
        ignore
          (expect_background
             (Background.submit submitter ~work ~on_complete));
        ignore (expect_parser (Eio.Promise.await result))
      ))

let () =
  if Int.compare (Domain.recommended_domain_count ()) 2 < 0 then
    print_endline "parser_background skipped: at least two recommended domains are required"
  else
    let iterations = 64 in
    let content = String.init 16384 (fun index -> Char.chr (65 + (index mod 26))) in
    let parser : Types.parser =
      {
        filetype = "benchmark";
        aliases = [];
        worker_safety = Types.Worker_safe;
        highlight = (fun content ->
          let checksum = ref 0 in
          for index = 0 to String.length content - 1 do
            checksum := (!checksum + Char.code content.[index]) land 0x3fffffff
          done;
          Ok
            [
              {
                Types.start = 0;
                end_ = String.length content;
                group = string_of_int !checksum;
                meta = None;
              };
            ]);
      }
    in
    Eio_main.run @@ fun env ->
    Eio.Switch.run @@ fun sw ->
    let background =
      expect_background
        (Background.create ~sw
           ~domain_mgr:(Eio.Stdenv.domain_mgr env) ~worker_count:1)
    in
    let submitter = expect_background (Background.bind background ~sw) in
    let sync_ns = run_sync ~iterations parser ~content in
    let background_ns = run_background ~iterations submitter parser ~content in
    Printf.printf
      "parser_background iterations=%d bytes=%d sync_ns=%Ld background_ns=%Ld\n%!"
      iterations (String.length content) sync_ns background_ns
