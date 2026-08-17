open Windtrap

module Background = Opentui_core.Platform.Eio_runtime.Background

exception Submission_cancelled
exception Worker_failure
exception Completion_failure

let domain_id () = (Domain.self () :> int)

let require_multiple_domains () =
  if Int.compare (Domain.recommended_domain_count ()) 2 < 0 then
    skip ~reason:"requires at least one executor domain in addition to the owner" ()

let expect_background result =
  match result with
  | Ok value -> value
  | Error error -> fail (Background.message error)

let expect_result expected actual =
  match expected, actual with
  | Ok expected, Ok actual -> equal int expected actual
  | Error expected, Error actual -> equal string expected actual
  | Ok unexpected, Error actual ->
      ignore unexpected;
      ignore actual;
      fail "typed worker result changed from Ok to Error"
  | Error unexpected, Ok actual ->
      ignore unexpected;
      ignore actual;
      fail "typed worker result changed from Error to Ok"

let make_background env sw =
  expect_background
    (Background.create ~sw
       ~domain_mgr:(Eio.Stdenv.domain_mgr env)
       ~worker_count:1)

let await_submission submitter ~work =
  let result, resolver = Eio.Promise.create () in
  ignore
    (expect_background
       (Background.submit submitter ~work ~on_complete:(fun value ->
            Eio.Promise.resolve resolver value)));
  Eio.Promise.await result

let wait_until predicate =
  let attempts = ref 0 in
  while not (predicate ()) && Int.compare !attempts 1000 < 0 do
    incr attempts;
    Eio.Fiber.yield ()
  done;
  if not (predicate ()) then fail "background operation did not reach its state"

let test_domains_and_results () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let background = make_background env sw in
  let submitter = expect_background (Background.bind background ~sw) in
  let owner = domain_id () in
  let worker = Atomic.make None in
  let completion = Atomic.make None in
  let result, resolver = Eio.Promise.create () in
  ignore
    (expect_background
       (Background.submit submitter
          ~work:(fun () ->
            Atomic.set worker (Some (domain_id ())); Ok 41)
          ~on_complete:(fun value ->
            Atomic.set completion (Some (domain_id ()));
            Eio.Promise.resolve resolver value)));
  expect_result (Ok 41) (Eio.Promise.await result);
  (match Atomic.get worker with
  | Some worker -> equal bool true (not (Int.equal worker owner))
  | None -> fail "worker domain was not recorded");
  (match Atomic.get completion with
  | Some completion -> equal int owner completion
  | None -> fail "completion domain was not recorded")

let test_result_shapes_and_worker_reuse () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let background = make_background env sw in
  let submitter = expect_background (Background.bind background ~sw) in
  let first_worker = Atomic.make None in
  let second_worker = Atomic.make None in
  let first =
    await_submission submitter ~work:(fun () ->
        Atomic.set first_worker (Some (domain_id ())); Ok 7)
  in
  let second =
    await_submission submitter ~work:(fun () ->
        Atomic.set second_worker (Some (domain_id ())); Error "typed failure")
  in
  expect_result (Ok 7) first;
  expect_result (Error "typed failure") second;
  (match Atomic.get first_worker, Atomic.get second_worker with
  | Some first_worker, Some second_worker -> equal int first_worker second_worker
  | None, _ -> fail "first worker domain was not recorded"
  | _, None -> fail "second worker domain was not recorded")

let test_cancel_after_start () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let background = make_background env sw in
  let submitter = expect_background (Background.bind background ~sw) in
  let started = Atomic.make false in
  let release = Atomic.make false in
  let calls = ref 0 in
  let submitted =
    expect_background
      (Background.submit submitter
         ~work:(fun () ->
           Atomic.set started true;
           while not (Atomic.get release) do Domain.cpu_relax () done;
           Ok ())
         ~on_complete:(fun value ->
           ignore value;
           incr calls))
  in
  wait_until (fun () -> Atomic.get started);
  Background.cancel submitted;
  Atomic.set release true;
  Eio.Time.Mono.sleep (Eio.Stdenv.mono_clock env) 0.01;
  equal int 0 !calls

let test_submission_switch_cancellation () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun application_sw ->
  let background = make_background env application_sw in
  let cancellation_finished, cancellation_resolver = Eio.Promise.create () in
  let started = Atomic.make false in
  let release = Atomic.make false in
  let callback_calls = Atomic.make 0 in
  Eio.Fiber.fork ~sw:application_sw (fun () ->
      (try
         Eio.Switch.run @@ fun submission_sw ->
         let submitter =
           expect_background (Background.bind background ~sw:submission_sw)
         in
         ignore
           (expect_background
              (Background.submit submitter
                 ~work:(fun () ->
                   Atomic.set started true;
                   while not (Atomic.get release) do Domain.cpu_relax () done;
                   Ok ())
                 ~on_complete:(fun value ->
                   ignore value;
                   ignore (Atomic.fetch_and_add callback_calls 1))));
         Eio.Fiber.fork ~sw:submission_sw (fun () ->
             wait_until (fun () -> Atomic.get started);
             Eio.Switch.fail submission_sw Submission_cancelled);
         Eio.Time.Mono.sleep (Eio.Stdenv.mono_clock env) 0.02
       with
       | Submission_cancelled -> ());
      Eio.Promise.resolve cancellation_resolver ());
  Eio.Promise.await cancellation_finished;
  Atomic.set release true;
  Eio.Time.Mono.sleep (Eio.Stdenv.mono_clock env) 0.02;
  equal int 0 (Atomic.get callback_calls)

let test_invalid_and_closed_lifecycle () =
  require_multiple_domains ();
  Eio_main.run @@ fun env ->
  let invalid_result =
    Eio.Switch.run @@ fun sw ->
    Background.create ~sw ~domain_mgr:(Eio.Stdenv.domain_mgr env)
      ~worker_count:0
  in
  (match invalid_result with
  | Error (Background.Invalid_worker_count 0) -> ()
  | Error error -> fail (Background.message error)
  | Ok value ->
      ignore value;
      fail "zero worker count was accepted");
  let too_many = Domain.recommended_domain_count () in
  (match
     Eio.Switch.run @@ fun sw ->
     Background.create ~sw ~domain_mgr:(Eio.Stdenv.domain_mgr env)
       ~worker_count:too_many
   with
  | Error (Background.Invalid_worker_count count) -> equal int too_many count
  | Error error -> fail (Background.message error)
  | Ok value ->
      ignore value;
      fail "a worker count exceeding the domain budget was accepted");
  let closed_pool, closed_switch, closed_submitter =
    Eio.Switch.run @@ fun sw ->
    let pool = make_background env sw in
    let submitter = expect_background (Background.bind pool ~sw) in
    pool, sw, submitter
  in
  (match Background.bind closed_pool ~sw:closed_switch with
  | Error Background.Closed -> ()
  | Error error -> fail (Background.message error)
  | Ok value ->
      ignore value;
      fail "a closed application owner accepted a binding");
  (match
     Background.submit closed_submitter ~work:(fun () -> Ok ())
       ~on_complete:(fun value -> ignore value)
   with
  | Error Background.Closed -> ()
  | Error error -> fail (Background.message error)
  | Ok value ->
      ignore value;
      fail "a submitter escaped its closed application owner");
  Eio.Switch.run @@ fun application_sw ->
  let background = make_background env application_sw in
  let escaped_submitter =
    Eio.Switch.run @@ fun submission_sw ->
    expect_background (Background.bind background ~sw:submission_sw)
  in
  (match
     Background.submit escaped_submitter ~work:(fun () -> Ok ())
       ~on_complete:(fun value -> ignore value)
   with
  | Error Background.Closed -> ()
  | Error error -> fail (Background.message error)
  | Ok _ -> fail "a normally released submission switch accepted a job")

let expect_worker_failure thunk =
  try
    thunk ();
    fail "expected an Eio switch failure"
  with
  | Worker_failure -> ()

let expect_completion_failure thunk =
  try
    thunk ();
    fail "expected an Eio switch failure"
  with
  | Completion_failure -> ()

let test_unexpected_worker_failure () =
  require_multiple_domains ();
  expect_worker_failure (fun () ->
      Eio_main.run @@ fun env ->
      Eio.Switch.run @@ fun sw ->
      let background = make_background env sw in
      let submitter = expect_background (Background.bind background ~sw) in
      ignore
        (expect_background
           (Background.submit submitter
              ~work:(fun () -> raise Worker_failure)
              ~on_complete:(fun value ->
                ignore value)));
      Eio.Time.Mono.sleep (Eio.Stdenv.mono_clock env) 0.02)

let test_unexpected_completion_failure () =
  require_multiple_domains ();
  expect_completion_failure (fun () ->
      Eio_main.run @@ fun env ->
      Eio.Switch.run @@ fun sw ->
      let background = make_background env sw in
      let submitter = expect_background (Background.bind background ~sw) in
      ignore
        (expect_background
           (Background.submit submitter
              ~work:(fun () -> Ok ())
              ~on_complete:(fun value ->
                ignore value;
                raise Completion_failure)));
      Eio.Time.Mono.sleep (Eio.Stdenv.mono_clock env) 0.02)

let () =
  run "opentui-core-background"
    [ test "worker and completion domains are distinct and typed results survive"
        test_domains_and_results;
      test "executor workers are reused across typed jobs"
        test_result_shapes_and_worker_reuse;
      test "cancelling after worker start suppresses completion" test_cancel_after_start;
      test "submission cancellation suppresses completion"
        test_submission_switch_cancellation;
      test "invalid counts and closed owners are rejected"
        test_invalid_and_closed_lifecycle;
      test "unexpected worker exceptions fail the owner switch"
        test_unexpected_worker_failure;
      test "unexpected completion exceptions fail the owner switch"
        test_unexpected_completion_failure ]
