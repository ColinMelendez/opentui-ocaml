open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Renderables = Core.Renderables
module Types = Core.Lib.Tree_sitter_types
module Client = Core.Lib.Tree_sitter_client
module Background = Core.Platform.Eio_runtime.Background

exception Callback_failure

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_background result =
  match result with
  | Ok value -> value
  | Error error -> fail (Background.message error)

let require_multiple_domains () =
  if Int.compare (Domain.recommended_domain_count ()) 2 < 0 then
    skip ~reason:"requires a parser executor domain" ()

let wait_until env predicate =
  let clock = Eio.Stdenv.clock env in
  let start = Eio.Time.now clock in
  let rec spin () =
    if predicate () then ()
    else if Float.compare (Eio.Time.now clock -. start) 30.0 >= 0 then
      fail "Code streaming operation did not complete"
    else begin
      Eio.Time.sleep clock 0.001;
      spin ()
    end
  in
  spin ()

let parser ~worker_safety highlight =
  {
    Types.filetype = "test";
    aliases = [];
    worker_safety;
    highlight;
  }

let highlight_for content =
  [ { Types.start = 0; end_ = String.length content; group = content; meta = None } ]

let register client value =
  match Client.register_parser client value with
  | Ok () -> ()
  | Error (Types.Failed message) -> fail message
  | Error (Types.No_parser message) -> fail message

let make_renderer () = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:40l ~height:8l ())

let make_background env sw =
  expect_background
    (Background.create ~sw ~domain_mgr:(Eio.Stdenv.domain_mgr env)
       ~worker_count:1)

let code_text code =
  expect_ok
    (Renderables.Text_buffer_renderable.text
       (Renderables.Code.text_buffer_renderable code))

let await_done code = Eio.Promise.await (Renderables.Code.highlighting_done code)

let test_initial_visibility () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let renderer = make_renderer () in
  let background = make_background env sw in
  let submitter = expect_background (Background.bind background ~sw) in
  let client = Client.create () in
  let started = Atomic.make false in
  let release = Atomic.make false in
  let highlight content =
    Atomic.set started true;
    while not (Atomic.get release) do Domain.cpu_relax () done;
    Ok (highlight_for content)
  in
  register client (parser ~worker_safety:Types.Worker_safe highlight);
  let visible =
    expect_ok
      (Renderables.Code.create (Renderer.context renderer) ~content:"initial"
         ~filetype:"test" ~tree_sitter_client:client ~background:submitter
         ~draw_unstyled_text:true ~streaming:true ())
  in
  wait_until env (fun () -> Atomic.get started);
  equal string "initial" (code_text visible);
  Atomic.set release true;
  await_done visible;
  equal string "initial" (code_text visible);
  Renderables.Code.destroy visible;
  Atomic.set started false;
  Atomic.set release false;
  let hidden =
    expect_ok
      (Renderables.Code.create (Renderer.context renderer) ~content:"hidden"
         ~filetype:"test" ~tree_sitter_client:client ~background:submitter
         ~draw_unstyled_text:false ~streaming:true ())
  in
  wait_until env (fun () -> Atomic.get started);
  equal string "" (code_text hidden);
  Atomic.set release true;
  await_done hidden;
  equal string "hidden" (code_text hidden);
  Renderables.Code.destroy hidden;
  Client.destroy client;
  Renderer.destroy renderer

let test_streaming_coalescing_and_contexts () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let renderer = make_renderer () in
  let background = make_background env sw in
  let submitter = expect_background (Background.bind background ~sw) in
  let client = Client.create () in
  let calls = Atomic.make 0 in
  let first_release = Atomic.make false in
  let second_started = Atomic.make false in
  let second_release = Atomic.make false in
  let third_started = Atomic.make false in
  let third_release = Atomic.make false in
  let highlight content =
    let call = Atomic.fetch_and_add calls 1 + 1 in
    (match call with
    | 1 ->
        while not (Atomic.get first_release) do Domain.cpu_relax () done
    | 2 ->
        Atomic.set second_started true;
        while not (Atomic.get second_release) do Domain.cpu_relax () done
    | 3 ->
        Atomic.set third_started true;
        while not (Atomic.get third_release) do Domain.cpu_relax () done
    | _ -> ());
    Ok (highlight_for content)
  in
  register client (parser ~worker_safety:Types.Worker_safe highlight);
  let syntax_style = Core.Syntax_style.create () in
  let highlight_contexts = ref [] in
  let chunks_contexts = ref [] in
  let on_highlight highlights context =
    highlight_contexts := context :: !highlight_contexts;
    Ok highlights
  in
  let on_chunks styled context =
    chunks_contexts := context :: !chunks_contexts;
    Ok styled
  in
  let code =
    expect_ok
      (Renderables.Code.create (Renderer.context renderer) ~content:"initial"
         ~filetype:"test" ~syntax_style ~tree_sitter_client:client
         ~background:submitter ~streaming:true ~draw_unstyled_text:false
         ~on_highlight ~on_chunks ())
  in
  wait_until env (fun () -> Int.equal (Atomic.get calls) 1);
  (match Renderables.Code.highlight_state code with
  | Renderables.Code.Pending -> ()
  | Renderables.Code.Idle | Renderables.Code.Applied
  | Renderables.Code.Fallback _ -> fail "initial streaming parse was not pending");
  Atomic.set first_release true;
  await_done code;
  equal string "initial" (code_text code);
  expect_ok (Renderables.Code.set_content code "second");
  wait_until env (fun () -> Atomic.get second_started);
  equal string "initial" (code_text code);
  let superseded_done = Renderables.Code.highlighting_done code in
  expect_ok (Renderables.Code.set_content code "third");
  let current_done = Renderables.Code.highlighting_done code in
  let superseded_resolved = Atomic.make false in
  Eio.Fiber.fork ~sw (fun () ->
      Eio.Promise.await superseded_done;
      Atomic.set superseded_resolved true);
  wait_until env (fun () -> Atomic.get superseded_resolved);
  Atomic.set second_release true;
  wait_until env (fun () -> Atomic.get third_started);
  equal string "initial" (code_text code);
  (match Renderables.Code.highlight_state code with
  | Renderables.Code.Pending -> ()
  | Renderables.Code.Idle | Renderables.Code.Applied
  | Renderables.Code.Fallback _ -> fail "coalesced streaming parse was not pending");
  Atomic.set third_release true;
  Eio.Promise.await current_done;
  equal string "third" (code_text code);
  equal int 3 (Atomic.get calls);
  let highlight_contexts = List.rev !highlight_contexts in
  let chunks_contexts = List.rev !chunks_contexts in
  (match highlight_contexts, chunks_contexts with
  | [ highlight_context; final_highlight_context ],
    [ chunks_context; final_chunks_context ] ->
      equal string "initial" highlight_context.content;
      equal string "third" final_highlight_context.content;
      equal string "test" final_highlight_context.filetype;
      equal bool true (highlight_context.syntax_style == syntax_style);
      equal bool true (final_highlight_context.syntax_style == syntax_style);
      equal string "initial" chunks_context.content;
      equal string "third" final_chunks_context.content;
      equal int 1 (List.length final_chunks_context.highlights)
  | _ -> fail "stale streaming callbacks were not suppressed");
  expect_ok (Renderables.Code.set_streaming code false);
  equal string "" (code_text code);
  await_done code;
  expect_ok (Renderables.Code.set_streaming code true);
  await_done code;
  Renderables.Code.destroy code;
  Core.Syntax_style.destroy syntax_style;
  Client.destroy client;
  Renderer.destroy renderer

let test_plain_and_typed_fallback_settlement () =
  Eio_main.run @@ fun env ->
  ignore env;
  Eio.Switch.run @@ fun sw ->
  ignore sw;
  let renderer = make_renderer () in
  let client = Client.create () in
  register client
    (parser ~worker_safety:Types.Owner_only (fun content ->
         Ok (highlight_for content)));
  let typed_fallback =
    expect_ok
      (Renderables.Code.create (Renderer.context renderer) ~content:"fallback"
         ~filetype:"test" ~tree_sitter_client:client
         ~on_highlight:(fun highlights context ->
           equal string "fallback" context.content;
           Error (Types.Failed "typed callback failure")) ())
  in
  await_done typed_fallback;
  (match Renderables.Code.highlight_state typed_fallback with
  | Renderables.Code.Fallback (Types.Failed message) ->
      equal string "typed callback failure" message
  | Renderables.Code.Idle | Renderables.Code.Pending | Renderables.Code.Applied
  | Renderables.Code.Fallback (Types.No_parser _) ->
      fail "typed callback error did not settle as fallback");
  equal string "fallback" (code_text typed_fallback);
  let plain =
    expect_ok
      (Renderables.Code.create (Renderer.context renderer) ~content:"plain"
         ~filetype:"unknown" ())
  in
  await_done plain;
  (match Renderables.Code.highlight_state plain with
  | Renderables.Code.Fallback (Types.No_parser "unknown") -> ()
  | Renderables.Code.Idle | Renderables.Code.Pending | Renderables.Code.Applied
  | Renderables.Code.Fallback (Types.No_parser _ | Types.Failed _) ->
      fail "plain parser fallback did not settle");
  Renderables.Code.destroy plain;
  Renderables.Code.destroy typed_fallback;
  Client.destroy client;
  Renderer.destroy renderer

let test_non_streaming_draw_policy () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let renderer = make_renderer () in
  let background = make_background env sw in
  let submitter = expect_background (Background.bind background ~sw) in
  let client = Client.create () in
  let started = Atomic.make false in
  let release = Atomic.make false in
  register client
    (parser ~worker_safety:Types.Worker_safe (fun content ->
         Atomic.set started true;
         while not (Atomic.get release) do Domain.cpu_relax () done;
         Atomic.set started false;
         Ok (highlight_for content)));
  let visible =
    expect_ok
      (Renderables.Code.create (Renderer.context renderer) ~content:"raw-one"
         ~filetype:"test" ~tree_sitter_client:client ~background:submitter
         ~draw_unstyled_text:true ())
  in
  wait_until env (fun () -> Atomic.get started);
  equal string "raw-one" (code_text visible);
  Atomic.set release true;
  await_done visible;
  Atomic.set release false;
  expect_ok (Renderables.Code.set_content visible "raw-two");
  wait_until env (fun () -> Atomic.get started);
  equal string "raw-two" (code_text visible);
  Atomic.set release true;
  await_done visible;
  Renderables.Code.destroy visible;
  Atomic.set started false;
  Atomic.set release false;
  let hidden =
    expect_ok
      (Renderables.Code.create (Renderer.context renderer) ~content:"hidden-one"
         ~filetype:"test" ~tree_sitter_client:client ~background:submitter
         ~draw_unstyled_text:false ())
  in
  wait_until env (fun () -> Atomic.get started);
  equal string "" (code_text hidden);
  Atomic.set release true;
  await_done hidden;
  Atomic.set release false;
  expect_ok (Renderables.Code.set_content hidden "hidden-two");
  wait_until env (fun () -> Atomic.get started);
  equal string "" (code_text hidden);
  Atomic.set release true;
  await_done hidden;
  equal string "hidden-two" (code_text hidden);
  Renderables.Code.destroy hidden;
  Client.destroy client;
  Renderer.destroy renderer

let test_destruction_resolves_settlement () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let renderer = make_renderer () in
  let background = make_background env sw in
  let submitter = expect_background (Background.bind background ~sw) in
  let client = Client.create () in
  let started = Atomic.make false in
  let release = Atomic.make false in
  register client
    (parser ~worker_safety:Types.Worker_safe (fun content ->
         Atomic.set started true;
         while not (Atomic.get release) do Domain.cpu_relax () done;
         Atomic.set started false;
         Ok (highlight_for content)));
  let code =
    expect_ok
      (Renderables.Code.create (Renderer.context renderer) ~content:"destroy"
         ~filetype:"test" ~tree_sitter_client:client ~background:submitter
         ~streaming:true ())
  in
  wait_until env (fun () -> Atomic.get started);
  let done_promise = Renderables.Code.highlighting_done code in
  Renderables.Code.destroy code;
  Eio.Promise.await done_promise;
  Atomic.set release true;
  wait_until env (fun () -> not (Atomic.get started));
  Client.destroy client;
  Renderer.destroy renderer

let test_plain_supersedes_running_highlight_immediately () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let renderer = make_renderer () in
  let background = make_background env sw in
  let submitter = expect_background (Background.bind background ~sw) in
  let client = Client.create () in
  let started = Atomic.make false in
  let release = Atomic.make false in
  register client
    (parser ~worker_safety:Types.Worker_safe (fun content ->
         Atomic.set started true;
         while not (Atomic.get release) do Domain.cpu_relax () done;
         Atomic.set started false;
         Ok (highlight_for content)));
  let code =
    expect_ok
      (Renderables.Code.create (Renderer.context renderer) ~content:"highlight"
         ~filetype:"test" ~tree_sitter_client:client ~background:submitter
         ~streaming:true ~draw_unstyled_text:false ())
  in
  wait_until env (fun () -> Atomic.get started);
  let superseded_done = Renderables.Code.highlighting_done code in
  expect_ok (Renderables.Code.set_content code "plain");
  expect_ok (Renderables.Code.set_filetype code None);
  await_done code;
  equal string "plain" (code_text code);
  (match Renderables.Code.highlight_state code with
  | Renderables.Code.Idle -> ()
  | Renderables.Code.Pending | Renderables.Code.Applied
  | Renderables.Code.Fallback _ ->
      fail "plain content waited for a superseded highlight worker");
  Eio.Promise.await superseded_done;
  Atomic.set release true;
  wait_until env (fun () -> not (Atomic.get started));
  equal string "plain" (code_text code);
  (match Renderables.Code.highlight_state code with
  | Renderables.Code.Idle -> ()
  | Renderables.Code.Pending | Renderables.Code.Applied
  | Renderables.Code.Fallback _ ->
      fail "stale highlight completion changed the plain generation");
  Renderables.Code.destroy code;
  Client.destroy client;
  Renderer.destroy renderer

let test_pending_callback_exception_cleans_state () =
  require_multiple_domains ();
  let release = Atomic.make false in
  let observed_failure = ref false in
  let code_ref = ref None in
  (try
     Eio_main.run @@ fun env ->
     Eio.Switch.run @@ fun sw ->
     let renderer = make_renderer () in
     let background = make_background env sw in
     let submitter = expect_background (Background.bind background ~sw) in
     let client = Client.create () in
     let started = Atomic.make false in
     register client
       (parser ~worker_safety:Types.Worker_safe (fun content ->
            if String.equal content "first" then begin
              Atomic.set started true;
              while not (Atomic.get release) do Domain.cpu_relax () done
            end;
            Ok (highlight_for content)));
     let code =
       expect_ok
         (Renderables.Code.create (Renderer.context renderer) ~content:"first"
            ~filetype:"test" ~tree_sitter_client:client ~background:submitter
            ~on_highlight:(fun highlights context ->
              if String.equal context.content "queued" then raise Callback_failure;
              Ok highlights) ())
     in
     code_ref := Some code;
     wait_until env (fun () -> Atomic.get started);
     expect_ok (Renderables.Code.set_content code "queued");
     Atomic.set release true;
     Eio.Time.Mono.sleep (Eio.Stdenv.mono_clock env) 0.02;
     Client.destroy client;
     Renderer.destroy renderer
   with
   | Callback_failure -> observed_failure := true);
  equal bool true !observed_failure;
  match !code_ref with
  | None -> fail "Code was not created before callback failure"
  | Some code ->
      (match Renderables.Code.highlight_state code with
      | Renderables.Code.Pending ->
          fail "callback exception stranded Code in Pending"
      | Renderables.Code.Idle | Renderables.Code.Applied
      | Renderables.Code.Fallback _ -> ());
      Eio_main.run @@ fun env ->
      ignore env;
      Eio.Switch.run @@ fun sw ->
      ignore sw;
      Eio.Promise.await (Renderables.Code.highlighting_done code)

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let found = ref false in
  if needle_length <= haystack_length then
    for index = 0 to haystack_length - needle_length do
      if String.equal (String.sub haystack index needle_length) needle then
        found := true
    done;
  !found

let frame renderer =
  let buffer = expect_ok (Renderer.current_buffer renderer) in
  let output = Bytes.create 4096 in
  let written =
    expect_ok
      (Core.Buffer.write_resolved_chars buffer ~output ~add_line_breaks:false)
  in
  Bytes.sub_string output 0 (Int32.to_int written)

let test_markdown_streaming_visibility_forwarding () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let renderer = make_renderer () in
  let background = make_background env sw in
  let submitter = expect_background (Background.bind background ~sw) in
  let client = Client.create () in
  let started = Atomic.make false in
  let release = Atomic.make false in
  register client
    (parser ~worker_safety:Types.Worker_safe (fun content ->
         Atomic.set started true;
         while not (Atomic.get release) do Domain.cpu_relax () done;
         Ok (highlight_for content)));
  let markdown =
    expect_ok
      (Renderables.Markdown.create (Renderer.context renderer)
         ~content:"```test\nSTREAMING_CODE\n```" ~streaming:true
         ~tree_sitter_client:client ~background:submitter ())
  in
  ignore (expect_ok
    (Core.Layout_children.add (Renderer.children renderer)
       (Renderables.Markdown.as_renderable markdown)));
  ignore (expect_ok (Renderer.render renderer ~force:true));
  wait_until env (fun () -> Atomic.get started);
  if contains (frame renderer) "STREAMING_CODE" then
    fail "streaming Markdown exposed raw fenced Code text";
  Atomic.set release true;
  Eio.Time.Mono.sleep (Eio.Stdenv.mono_clock env) 0.01;
  ignore (expect_ok (Renderer.render renderer ~force:true));
  if not (contains (frame renderer) "STREAMING_CODE") then
    fail "streaming Markdown did not expose settled Code text";
  Renderables.Markdown.destroy markdown;
  Client.destroy client;
  Renderer.destroy renderer

let () =
  run "opentui-core-code-streaming"
    [
      test "initial streaming visibility obeys draw_unstyled_text"
        test_initial_visibility;
      test "streaming coalesces latest content and supplies callback contexts"
        test_streaming_coalescing_and_contexts;
      test "plain and typed callback fallback generations settle"
        test_plain_and_typed_fallback_settlement;
      test "non-streaming generations obey draw_unstyled_text"
        test_non_streaming_draw_policy;
      test "destruction resolves the active highlighting settlement"
        test_destruction_resolves_settlement;
      test "plain content immediately supersedes a running highlight"
        test_plain_supersedes_running_highlight_immediately;
      test "callback exceptions preserve switch failure and clear Pending"
        test_pending_callback_exception_cleans_state;
      test "Markdown forwards streaming visibility to fenced Code"
        test_markdown_streaming_visibility_forwarding;
    ]
