let allocation_metrics = [ Thumper.Metric.alloc_words ]
let allocation_budget = [ Thumper.Budget.no_more_alloc_than 0.0 ]

module Warmed = Opentui_bench_workload.Warmed_workload
module Retained = Opentui_bench_workload.Retained_workload

let () =
  Thumper.run "warmed"
    ~budgets:allocation_budget
    [
      Thumper.group "steady-state" ~metrics:allocation_metrics
        [
          Thumper.bench_with_setup
            ~setup:Retained.Frame.create ~teardown:Retained.Frame.close
            "retained-frame"
            Retained.Frame.run;
          Thumper.bench_with_setup
            ~setup:Warmed.Input_burst.create
            "input-burst"
            Warmed.Input_burst.run;
          Thumper.bench_with_setup
            ~setup:Warmed.Output_write.create
            "output-write"
            Warmed.Output_write.run;
        ];
      Thumper.group "retained-core" ~metrics:allocation_metrics
        [
          Thumper.bench_with_setup ~setup:Retained.Text.create
            ~teardown:Retained.Text.close "text" Retained.Text.run;
          Thumper.bench_with_setup ~setup:Retained.Layout.create
            ~teardown:Retained.Layout.close "layout" Retained.Layout.run;
          Thumper.bench_with_setup ~setup:Retained.Reorder.create
            ~teardown:Retained.Reorder.close "reorder" Retained.Reorder.run;
          Thumper.bench_with_setup ~setup:Retained.Pointer.create
            ~teardown:Retained.Pointer.close "pointer" Retained.Pointer.run;
          Thumper.bench_with_setup ~setup:Retained.Teardown.create
            ~teardown:Retained.Teardown.close "teardown" Retained.Teardown.run;
        ];
    ]
