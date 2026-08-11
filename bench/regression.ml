let allocation_metrics = [ Thumper.Metric.alloc_words ]
let allocation_budget = [ Thumper.Budget.no_more_alloc_than 0.0 ]

let () =
  Thumper.run "warmed"
    ~budgets:allocation_budget
    [
      Thumper.group "steady-state" ~metrics:allocation_metrics
        [
          Thumper.bench_with_setup
            ~setup:Opentui_bench_workload.Warmed_workload.Retained_frame.create
            ~teardown:Opentui_bench_workload.Warmed_workload.Retained_frame.close
            "retained-frame"
            Opentui_bench_workload.Warmed_workload.Retained_frame.run;
          Thumper.bench_with_setup
            ~setup:Opentui_bench_workload.Warmed_workload.Input_burst.create
            "input-burst"
            Opentui_bench_workload.Warmed_workload.Input_burst.run;
          Thumper.bench_with_setup
            ~setup:Opentui_bench_workload.Warmed_workload.Output_write.create
            "output-write"
            Opentui_bench_workload.Warmed_workload.Output_write.run;
        ];
    ]
