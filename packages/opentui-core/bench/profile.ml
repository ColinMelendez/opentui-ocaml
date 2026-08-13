module Buffer = Opentui_core.Buffer
module Renderer = Opentui_core.Renderer

type sample = {
  elapsed_ns : int64;
  minor_words : int64;
  major_words : int64;
  minor_collections : int;
  major_collections : int;
}

let fail message =
  prerr_endline message;
  Stdlib.exit 1

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_core.Error.message error)

let words value = Int64.of_float value

let measure operation =
  Gc.full_major ();
  let before = Gc.quick_stat () in
  let start = Mtime_clock.elapsed_ns () in
  operation ();
  let elapsed_ns = Int64.sub (Mtime_clock.elapsed_ns ()) start in
  let after = Gc.quick_stat () in
  {
    elapsed_ns;
    minor_words = Int64.sub (words after.minor_words) (words before.minor_words);
    major_words = Int64.sub (words after.major_words) (words before.major_words);
    minor_collections = after.minor_collections - before.minor_collections;
    major_collections = after.major_collections - before.major_collections;
  }

let print_sample name ~iterations sample =
  Printf.printf
    "%s iterations=%d elapsed_ns=%Ld minor_words=%Ld major_words=%Ld minor_collections=%d major_collections=%d\n%!"
    name iterations sample.elapsed_ns sample.minor_words sample.major_words
    sample.minor_collections sample.major_collections

let run ~iterations ~name =
  let width = 80l in
  let height = 24l in
  let renderer = expect_ok (Renderer.create ~width ~height) in
  let buffer = expect_ok (Renderer.next_buffer renderer) in
  let output = Bytes.create (Int32.to_int width * Int32.to_int height) in
  let sample =
    measure (fun () ->
        for iteration = 0 to iterations - 1 do
          ignore
            (expect_ok
               (Buffer.clear buffer ~background:Opentui_core.Color.black));
          ignore
            (expect_ok
               (Buffer.draw_text buffer ~text:"OpenTUI" ~x:0l
                  ~y:(Int32.of_int (iteration mod Int32.to_int height))
                  ~foreground:Opentui_core.Color.white
                  ~background:Opentui_core.Color.black ~attributes:0l));
          let written =
            expect_ok
              (Buffer.write_resolved_chars buffer ~output
                 ~add_line_breaks:false)
          in
          if not (Int32.equal written (Int32.of_int (Bytes.length output))) then
            fail "renderer buffer profile wrote an unexpected byte count";
          ignore (expect_ok (Renderer.request_render renderer));
          match expect_ok (Renderer.render renderer ~force:true) with
          | Renderer.Rendered -> ()
          | Renderer.Skipped -> fail "renderer buffer profile unexpectedly skipped"
          | Renderer.Failed -> fail "renderer buffer profile failed"
        done)
  in
  print_sample name ~iterations sample;
  Renderer.destroy renderer

let () =
  match Array.to_list (Array.sub Sys.argv 1 (Array.length Sys.argv - 1)) with
  | [] -> run ~iterations:64 ~name:"renderer_buffers"
  | [ "--workload"; "warmed" ] -> run ~iterations:512 ~name:"renderer_buffers_warmed"
  | _ -> fail "usage: profile.exe [--workload warmed]"
