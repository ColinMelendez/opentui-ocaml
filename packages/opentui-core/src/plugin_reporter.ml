type t = {
  callback : Plugin_failure.t -> unit;
  mutable failures : Plugin_failure.t list;
}

let create callback = { callback; failures = [] }

let ignore = create (fun _failure -> ())

let report reporter failure =
  try reporter.callback failure with
  | exception_value ->
      reporter.failures <-
        Plugin_failure.make ~phase:Plugin_failure.Reporter
          ~origin:Plugin_failure.Reporter
          ~cause:
            (Plugin_failure.Reporter_exception
               {
                 exception_value;
                 backtrace = Printexc.get_raw_backtrace ();
               })
          ()
        :: reporter.failures

let compose first second =
  create (fun failure ->
      report first failure;
      report second failure)

let failures reporter = List.rev reporter.failures
