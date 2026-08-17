open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Renderables = Core.Renderables
module Types = Core.Lib.Tree_sitter_types
module Client = Core.Lib.Tree_sitter_client
module Background = Core.Platform.Eio_runtime.Background

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
    skip ~reason:"requires at least one executor domain in addition to the owner" ()

let wait_until predicate =
  let attempts = ref 0 in
  while not (predicate ()) && Int.compare !attempts 2000 < 0 do
    incr attempts;
    Eio.Fiber.yield ()
  done;
  if not (predicate ()) then fail "parser background operation did not complete"

let repeat count operation =
  let remaining = ref count in
  while Int.compare !remaining 0 > 0 do
    decr remaining;
    operation ()
  done

let highlight_for content =
  [
    {
      Types.start = 0;
      end_ = String.length content;
      group = content;
      meta = None;
    };
  ]

let parser ~worker_safety highlight =
  { Types.filetype = "test"; aliases = []; worker_safety; highlight }

let make_renderer () = expect_ok (Renderer.create ~width:40l ~height:8l)

let make_background env sw =
  expect_background
    (Background.create ~sw
       ~domain_mgr:(Eio.Stdenv.domain_mgr env)
       ~worker_count:1)

let register client parser =
  match Client.register_parser client parser with
  | Ok () -> ()
  | Error (Types.Failed message) -> fail message
  | Error (Types.No_parser message) -> fail message

let await_applied code =
  wait_until (fun () ->
      match Renderables.Code.highlight_state code with
      | Renderables.Code.Applied -> true
      | Renderables.Code.Idle | Renderables.Code.Pending
      | Renderables.Code.Fallback _ -> false)

let () =
  run "opentui-core-parser-background"
    [
      test "shared clients keep Code generations independent" (fun () ->
          require_multiple_domains ();
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let renderer = make_renderer () in
          let background = make_background env sw in
          let submitter = expect_background (Background.bind background ~sw) in
          let client = Client.create () in
          let worker_domain = Atomic.make None in
          let completion_domains = Atomic.make [] in
          let highlight content =
            Atomic.set worker_domain (Some (Domain.self () :> int));
            Ok (highlight_for content)
          in
          register client (parser ~worker_safety:Types.Worker_safe highlight);
          let on_highlight highlights context =
            ignore context;
            ignore highlights;
            Atomic.set completion_domains
              ((Domain.self () :> int) :: Atomic.get completion_domains);
            Ok highlights
          in
          let first =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer)
                 ~content:"first" ~filetype:"test"
                 ~tree_sitter_client:client ~background:submitter
                 ~on_highlight ())
          in
          let second =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer)
                 ~content:"second" ~filetype:"test"
                 ~tree_sitter_client:client ~background:submitter
                 ~on_highlight ())
          in
          await_applied first;
          await_applied second;
          equal int 1 (List.length (Renderables.Code.highlights first));
          equal int 1 (List.length (Renderables.Code.highlights second));
          equal int 2 (List.length (Atomic.get completion_domains));
          let owner = (Domain.self () :> int) in
          (match Atomic.get worker_domain with
          | Some domain -> if Int.equal domain owner then fail "parser ran on owner domain"
          | None -> fail "parser worker domain was not recorded");
          List.iter
            (fun domain -> equal int owner domain)
            (Atomic.get completion_domains);
          Renderables.Code.destroy first;
          Renderables.Code.destroy second;
          Client.destroy client;
          Renderer.destroy renderer);
      test "rapid Code updates retain only the latest pending snapshot" (fun () ->
          require_multiple_domains ();
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let renderer = make_renderer () in
          let background = make_background env sw in
          let submitter = expect_background (Background.bind background ~sw) in
          let client = Client.create () in
          let started = Atomic.make false in
          let release = Atomic.make false in
          let calls = Atomic.make 0 in
          let callback_calls = Atomic.make 0 in
          let highlight content =
            ignore (Atomic.fetch_and_add calls 1);
            if String.equal content "first" then begin
              Atomic.set started true;
              while not (Atomic.get release) do Domain.cpu_relax () done
            end;
            Ok (highlight_for content)
          in
          register client (parser ~worker_safety:Types.Worker_safe highlight);
          let on_highlight highlights context =
            ignore context;
            ignore (Atomic.fetch_and_add callback_calls 1);
            Ok highlights
          in
          let code =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer)
                 ~content:"first" ~filetype:"test"
                 ~tree_sitter_client:client ~background:submitter
                 ~on_highlight ())
          in
          wait_until (fun () -> Atomic.get started);
          (match Renderables.Code.highlight_state code with
          | Renderables.Code.Pending -> ()
          | Renderables.Code.Idle | Renderables.Code.Applied
          | Renderables.Code.Fallback _ ->
              fail "admitted parser work was not reported as pending");
          expect_ok (Renderables.Code.set_content code "second");
          expect_ok (Renderables.Code.set_content code "third");
          (match Renderables.Code.highlight_state code with
          | Renderables.Code.Pending -> ()
          | Renderables.Code.Idle | Renderables.Code.Applied
          | Renderables.Code.Fallback _ ->
              fail "queued parser work was not reported as pending");
          Atomic.set release true;
          wait_until (fun () ->
              Int.compare (Atomic.get calls) 2 >= 0
              && match Renderables.Code.highlight_state code with
                 | Renderables.Code.Applied -> true
                 | Renderables.Code.Idle | Renderables.Code.Pending
                 | Renderables.Code.Fallback _ -> false);
          equal string "third" (Renderables.Code.content code);
          (match Renderables.Code.highlights code with
          | [ highlight ] -> equal string "third" highlight.group
          | _ -> fail "latest Code generation did not win");
          equal int 2 (Atomic.get calls);
          equal int 1 (Atomic.get callback_calls);
          Renderables.Code.destroy code;
          Client.destroy client;
          Renderer.destroy renderer);
      test "stale Code completion does not invoke callbacks" (fun () ->
          require_multiple_domains ();
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let renderer = make_renderer () in
          let background = make_background env sw in
          let submitter = expect_background (Background.bind background ~sw) in
          let client = Client.create () in
          let release = Atomic.make false in
          let started = Atomic.make false in
          let callback_calls = Atomic.make 0 in
          let highlight content =
            if String.equal content "old" then begin
              Atomic.set started true;
              while not (Atomic.get release) do Domain.cpu_relax () done
            end;
            Ok (highlight_for content)
          in
          register client (parser ~worker_safety:Types.Worker_safe highlight);
          let on_highlight highlights context =
            ignore context;
            ignore (Atomic.fetch_and_add callback_calls 1);
            Ok highlights
          in
          let code =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer)
                 ~content:"old" ~filetype:"test"
                 ~tree_sitter_client:client ~background:submitter
                 ~on_highlight ())
          in
          wait_until (fun () -> Atomic.get started);
          expect_ok (Renderables.Code.set_content code "new");
          Atomic.set release true;
          wait_until (fun () ->
              Int.equal (Atomic.get callback_calls) 1
              && match Renderables.Code.highlights code with
                 | [ highlight ] -> String.equal highlight.group "new"
                 | _ -> false);
          equal int 1 (Atomic.get callback_calls);
          Renderables.Code.destroy code;
          Client.destroy client;
          Renderer.destroy renderer);
      test "destroying the exposed renderable cleans up Code once" (fun () ->
          require_multiple_domains ();
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let renderer = make_renderer () in
          let background = make_background env sw in
          let submitter = expect_background (Background.bind background ~sw) in
          let client = Client.create () in
          let started = Atomic.make false in
          let release = Atomic.make false in
          let finished = Atomic.make false in
          let parser_calls = Atomic.make 0 in
          let callback_calls = Atomic.make 0 in
          let highlight content =
            ignore content;
            ignore (Atomic.fetch_and_add parser_calls 1);
            Atomic.set started true;
            while not (Atomic.get release) do Domain.cpu_relax () done;
            Atomic.set finished true;
            Ok []
          in
          register client (parser ~worker_safety:Types.Worker_safe highlight);
          let on_highlight highlights context =
            ignore context;
            ignore highlights;
            ignore (Atomic.fetch_and_add callback_calls 1);
            Ok highlights
          in
          let code =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer)
                 ~content:"destroy" ~filetype:"test"
                 ~tree_sitter_client:client ~background:submitter
                 ~on_highlight ())
          in
          let owned_style = Renderables.Code.syntax_style code in
          wait_until (fun () -> Atomic.get started);
          expect_ok (Renderables.Code.set_content code "queued");
          (match Renderables.Code.highlight_state code with
          | Renderables.Code.Pending -> ()
          | Renderables.Code.Idle | Renderables.Code.Applied
          | Renderables.Code.Fallback _ -> fail "queued work was not pending");
          Core.Renderable.destroy (Renderables.Code.as_renderable code);
          equal bool true
            (Core.Renderable.is_destroyed (Renderables.Code.as_renderable code));
          equal bool true (Core.Syntax_style.is_destroyed owned_style);
          (match Renderables.Code.set_content code "after-destroy" with
          | Error Core.Error.Destroyed -> ()
          | Error error -> fail (Core.Error.message error)
          | Ok () -> fail "destroyed Code accepted content");
          Renderables.Code.destroy code;
          Atomic.set release true;
          wait_until (fun () -> Atomic.get finished);
          repeat 100 Eio.Fiber.yield;
          equal int 1 (Atomic.get parser_calls);
          equal int 0 (Atomic.get callback_calls);
          Client.destroy client;
          Renderer.destroy renderer);
      test "failed worker admission does not report Pending" (fun () ->
          require_multiple_domains ();
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun application_sw ->
          let renderer = make_renderer () in
          let background = make_background env application_sw in
          let closed_submitter =
            Eio.Switch.run @@ fun submission_sw ->
            expect_background
              (Background.bind background ~sw:submission_sw)
          in
          let client = Client.create () in
          let parser_calls = Atomic.make 0 in
          let highlight content =
            ignore content;
            ignore (Atomic.fetch_and_add parser_calls 1);
            Ok []
          in
          register client (parser ~worker_safety:Types.Worker_safe highlight);
          let code =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer)
                 ~content:"" ~filetype:"test"
                 ~tree_sitter_client:client ~background:closed_submitter ())
          in
          (match Renderables.Code.set_content code "cannot-submit" with
          | Error Core.Error.Closed -> ()
          | Error error -> fail (Core.Error.message error)
          | Ok () -> fail "closed background submitter admitted parser work");
          (match Renderables.Code.highlight_state code with
          | Renderables.Code.Idle -> ()
          | Renderables.Code.Pending ->
              fail "failed parser admission left a false Pending state"
          | Renderables.Code.Applied | Renderables.Code.Fallback _ ->
              fail "failed parser admission changed the previous state");
          equal int 0 (Atomic.get parser_calls);
          Renderables.Code.destroy code;
          Client.destroy client;
          Renderer.destroy renderer);
      test "owner-only parsers never cross the background boundary" (fun () ->
          require_multiple_domains ();
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let renderer = make_renderer () in
          let background = make_background env sw in
          let submitter = expect_background (Background.bind background ~sw) in
          let client = Client.create () in
          let parser_domain = Atomic.make None in
          let completion_domain = Atomic.make None in
          let highlight content =
            ignore content;
            Atomic.set parser_domain (Some (Domain.self () :> int));
            Ok []
          in
          register client (parser ~worker_safety:Types.Owner_only highlight);
          let on_highlight highlights context =
            ignore context;
            Atomic.set completion_domain (Some (Domain.self () :> int));
            Ok highlights
          in
          let code =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer)
                 ~content:"owner" ~filetype:"test"
                 ~tree_sitter_client:client ~background:submitter
                 ~on_highlight ())
          in
          (match Renderables.Code.highlight_state code with
          | Renderables.Code.Applied -> ()
          | Renderables.Code.Idle | Renderables.Code.Pending
          | Renderables.Code.Fallback _ ->
              fail "owner-only parser was submitted asynchronously");
          let owner = (Domain.self () :> int) in
          (match Atomic.get parser_domain with
          | Some domain -> equal int owner domain
          | None -> fail "owner-only parser did not run");
          (match Atomic.get completion_domain with
          | Some domain -> equal int owner domain
          | None -> fail "owner-only completion did not run");
          Renderables.Code.destroy code;
          Client.destroy client;
          Renderer.destroy renderer);
      test "worker parser errors remain Code fallback errors" (fun () ->
          require_multiple_domains ();
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let renderer = make_renderer () in
          let background = make_background env sw in
          let submitter = expect_background (Background.bind background ~sw) in
          let client = Client.create () in
          let highlight content =
            ignore content;
            Error (Types.Failed "expected parser failure")
          in
          register client (parser ~worker_safety:Types.Worker_safe highlight);
          let code =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer)
                 ~content:"broken" ~filetype:"test"
                 ~tree_sitter_client:client ~background:submitter ())
          in
          wait_until (fun () ->
              match Renderables.Code.highlight_state code with
              | Renderables.Code.Fallback (Types.Failed message) ->
                  String.equal message "expected parser failure"
              | Renderables.Code.Idle | Renderables.Code.Pending
              | Renderables.Code.Applied
              | Renderables.Code.Fallback (Types.No_parser _) -> false);
          Renderables.Code.destroy code;
          Client.destroy client;
          Renderer.destroy renderer);
      test "Markdown and Diff propagate the owner background capability" (fun () ->
          require_multiple_domains ();
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let renderer = make_renderer () in
          let background = make_background env sw in
          let submitter = expect_background (Background.bind background ~sw) in
          let client = Client.create () in
          let calls = Atomic.make 0 in
          let highlight content =
            ignore content;
            ignore (Atomic.fetch_and_add calls 1);
            Ok []
          in
          register client (parser ~worker_safety:Types.Worker_safe highlight);
          let markdown =
            expect_ok
              (Renderables.Markdown.create (Renderer.context renderer)
                 ~content:"```test\nmarkdown\n```"
                 ~tree_sitter_client:client ~background:submitter ())
          in
          wait_until (fun () -> Int.compare (Atomic.get calls) 1 >= 0);
          let diff_text = "--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+new" in
          let diff =
            expect_ok
              (Renderables.Diff.create (Renderer.context renderer)
                 ~content:diff_text ~filetype:"test"
                 ~tree_sitter_client:client ~background:submitter ())
          in
          let code =
            match Renderables.Diff.left_code diff with
            | Some code -> code
            | None -> fail "Diff did not create its Code child"
          in
          await_applied code;
          Renderables.Diff.destroy diff;
          Renderables.Markdown.destroy markdown;
          Client.destroy client;
          Renderer.destroy renderer);
    ]
