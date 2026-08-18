open Windtrap

module Objects = Opentui_core.Lib.Objects_in_viewport

let make_object value position z_index : string Objects.object_ =
  { value; screen_x = position; screen_y = position; width = 10.0; height = 10.0; z_index }

let values objects = List.map (fun object_ -> object_.Objects.value) objects

let expect_values expected actual = equal (list string) expected (values actual)

let column_viewport = { Objects.x = 0.0; y = 0.0; width = 10.0; height = 10.0 }

let row_viewport = { Objects.x = 0.0; y = 0.0; width = 10.0; height = 10.0 }

let optimized_objects () =
  List.init 20 (fun index -> make_object (Printf.sprintf "item-%d" index)
    (float_of_int (index * 10)) index)

let test_unsorted_column_input_is_culled_correctly () =
  let objects = List.rev (optimized_objects ()) in
  let visible =
    Objects.get ~direction:Objects.Column ~padding:0.0 ~min_trigger_size:16
      column_viewport objects
  in
  expect_values [ "item-0" ] visible

let test_unsorted_row_input_is_culled_correctly () =
  let objects = List.rev (optimized_objects ()) in
  let visible =
    Objects.get ~direction:Objects.Row ~padding:0.0 ~min_trigger_size:16
      row_viewport objects
  in
  expect_values [ "item-0" ] visible

let test_z_ties_keep_primary_order_after_stable_sort () =
  let filler =
    List.init 17 (fun index ->
        make_object (Printf.sprintf "filler-%d" index)
          (float_of_int ((index + 1) * 20)) 100)
  in
  let objects =
    make_object "back" 0.0 4
    :: make_object "middle" 0.0 4
    :: make_object "front" 0.0 1
    :: filler
  in
  let visible =
    Objects.get ~direction:Objects.Column ~padding:0.0 ~min_trigger_size:16
      column_viewport objects
  in
  expect_values [ "front"; "back"; "middle" ] visible

let () =
  run "opentui-core-objects-in-viewport"
    [
      test "unsorted column input is culled correctly"
        test_unsorted_column_input_is_culled_correctly;
      test "unsorted row input is culled correctly"
        test_unsorted_row_input_is_culled_correctly;
      test "z ties keep primary order after stable sorting"
        test_z_ties_keep_primary_order_after_stable_sort;
    ]
