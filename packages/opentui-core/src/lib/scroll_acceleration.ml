type policy =
  | Linear
  | Macos of {
      a : float;
      tau : float;
      max_multiplier : float;
      mutable last_tick_ms : float option;
      mutable intervals : float list;
    }

type t = { policy : policy }

let linear () = { policy = Linear }

let macos ?(a = 0.8) ?(tau = 3.0) ?(max_multiplier = 6.0) () =
  {
    policy =
      Macos
        {
          a;
          tau;
          max_multiplier;
          last_tick_ms = None;
          intervals = [];
        };
  }

let now_ms () = Unix.gettimeofday () *. 1000.0

let tick acceleration ?now_ms:provided () =
  match acceleration.policy with
  | Linear -> 1.0
  | Macos state ->
      let now = Option.value provided ~default:(now_ms ()) in
      let interval =
        match state.last_tick_ms with
        | None -> None
        | Some previous -> Some (now -. previous)
      in
      (match interval with
      | None ->
          state.last_tick_ms <- Some now;
          state.intervals <- [];
          1.0
      | Some value when value > 150.0 ->
          state.last_tick_ms <- Some now;
          state.intervals <- [];
          1.0
      | Some value when value < 6.0 -> 1.0
      | Some value ->
          state.last_tick_ms <- Some now;
          state.intervals <- value :: state.intervals;
          if List.length state.intervals > 3 then
            state.intervals <- List.rev (List.tl (List.rev state.intervals));
          let total = List.fold_left ( +. ) 0.0 state.intervals in
          let average = total /. float_of_int (List.length state.intervals) in
          let velocity = 100.0 /. average in
          let x = velocity /. state.tau in
          let multiplier = 1.0 +. state.a *. (Float.exp x -. 1.0) in
          min state.max_multiplier multiplier)

let reset acceleration =
  match acceleration.policy with
  | Linear -> ()
  | Macos state ->
      state.last_tick_ms <- None;
      state.intervals <- []
