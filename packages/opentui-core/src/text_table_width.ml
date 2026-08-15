type active_column = { index : int; capacity : int; weight : float }

let compare_priority left_growth left_capacity right_growth right_capacity =
  let left =
    Int64.mul (Int64.of_int left_growth) (Int64.of_int left_growth)
    |> fun value -> Int64.mul value (Int64.of_int right_capacity)
  in
  let right =
    Int64.mul (Int64.of_int right_growth) (Int64.of_int right_growth)
    |> fun value -> Int64.mul value (Int64.of_int left_capacity)
  in
  Int64.compare left right

let all_equal values =
  match values with
  | [] -> true
  | first :: rest -> List.for_all (Int.equal first) rest

let allocate_proportional_column_widths ~widths ~target_width ~min_width =
  let min_width = max 0 min_width in
  let base_widths = List.map (fun width -> max min_width width) widths in
  let count = List.length base_widths in
  let total_base_width = List.fold_left ( + ) 0 base_widths in
  let capacities = Array.of_list (List.map (fun width -> width - min_width) base_widths) in
  let growth = Array.make count 0 in
  let available =
    min
      (max 0 (target_width - (min_width * count)))
      (total_base_width - (min_width * count))
  in
  if Int.equal available 0 then Array.to_list (Array.map (fun _ -> min_width) growth)
  else if Int.equal available (Array.fold_left ( + ) 0 capacities) then base_widths
  else
    let active =
      let result = ref [] in
      for index = 0 to count - 1 do
        let capacity = capacities.(index) in
        if capacity > 0 then
          result :=
            { index; capacity; weight = sqrt (float_of_int capacity) }
            :: !result
      done;
      List.sort
        (fun left right -> Float.compare left.weight right.weight)
        (List.rev !result)
    in
    if Int.equal (List.length active) count && all_equal (Array.to_list capacities) then begin
      let shared_growth = available / count in
      let remainder = available mod count in
      for index = 0 to count - 1 do
        growth.(index) <- shared_growth + if index < remainder then 1 else 0
      done;
      Array.to_list (Array.map (fun width -> width + min_width) growth)
    end else begin
      let remaining = ref available in
      let total_weight = ref (List.fold_left (fun total column -> total +. column.weight) 0.0 active) in
      List.iter
        (fun column ->
          if !total_weight > 0.0
             && float_of_int !remaining /. !total_weight > column.weight
          then begin
            growth.(column.index) <- column.capacity;
            remaining := !remaining - column.capacity;
            total_weight := !total_weight -. column.weight
          end)
        active;
      if !total_weight > 0.0 then begin
        let level = float_of_int !remaining /. !total_weight in
        List.iter
          (fun column ->
            if not (Int.equal growth.(column.index) column.capacity) then
              growth.(column.index) <-
                min column.capacity (int_of_float (Float.floor (level *. column.weight))))
          active
      end;
      let allocated_growth = ref (Array.fold_left ( + ) 0 growth) in
      while !allocated_growth > available do
        let worst_index = ref (-1) in
        for index = 0 to count - 1 do
          if not (Int.equal growth.(index) 0) then
            let replace =
              if Int.equal !worst_index (-1) then true
              else
                let comparison =
                  compare_priority growth.(index) capacities.(index)
                    growth.(!worst_index) capacities.(!worst_index)
                in
                comparison > 0
                || (Int.equal comparison 0 && index > !worst_index)
            in
            if replace then worst_index := index
        done;
        if Int.equal !worst_index (-1) then allocated_growth := available
        else begin
          growth.(!worst_index) <- growth.(!worst_index) - 1;
          decr allocated_growth
        end
      done;
      while !allocated_growth < available do
        let best_index = ref (-1) in
        for index = 0 to count - 1 do
          if growth.(index) < capacities.(index) then
            let replace =
              if Int.equal !best_index (-1) then true
              else
                let comparison =
                  compare_priority (growth.(index) + 1) capacities.(index)
                    (growth.(!best_index) + 1) capacities.(!best_index)
                in
                comparison < 0
            in
            if replace then best_index := index
        done;
        if Int.equal !best_index (-1) then allocated_growth := available
        else begin
          growth.(!best_index) <- growth.(!best_index) + 1;
          incr allocated_growth
        end
      done;
      Array.to_list
        (Array.map (fun value -> min_width + value) growth)
    end
