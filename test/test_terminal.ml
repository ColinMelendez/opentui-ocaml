open Windtrap

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_terminal.Byte_queue.message error)

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual ->
      let same_error left right =
        match left, right with
        | Opentui_terminal.Byte_queue.Invalid_capacity,
          Opentui_terminal.Byte_queue.Invalid_capacity -> true
        | Opentui_terminal.Byte_queue.Invalid_range,
          Opentui_terminal.Byte_queue.Invalid_range -> true
        | Opentui_terminal.Byte_queue.Max_capacity,
          Opentui_terminal.Byte_queue.Max_capacity -> true
        | _ -> false
      in
      equal bool true (same_error expected actual)

let byte_array values =
  let result =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
      (List.length values)
  in
  List.iteri (fun index value -> Bigarray.Array1.set result index value) values;
  result

let queue_contents queue =
  let result = Bytes.create (Opentui_terminal.Byte_queue.length queue) in
  for index = 0 to Bytes.length result - 1 do
    match Opentui_terminal.Byte_queue.get queue index with
    | Some value -> Bytes.set_uint8 result index value
    | None -> fail "queue index disappeared"
  done;
  result

let () =
  run "opentui-terminal"
    [
      test "bigarray input, consume, and compaction preserve byte order" (fun () ->
          let module Queue = Opentui_terminal.Byte_queue in
          let queue =
            expect_ok (Queue.create ~initial_capacity:4 ~max_capacity:8 ())
          in
          ignore
            (expect_ok
               (Queue.append queue ~source:(byte_array [ 48; 49; 50; 51 ]) ~off:0
                  ~len:4));
          equal int 4 (Queue.length queue);
          equal int 4 (Queue.capacity queue);
          ignore (expect_ok (Queue.consume queue 2));
          ignore
            (expect_ok
               (Queue.append_bytes queue ~source:(Bytes.of_string "45") ~off:0
                  ~len:2));
          equal string "2345" (Bytes.to_string (queue_contents queue));
          equal int 4 (Queue.capacity queue);
          (match Queue.get queue (-1), Queue.get queue 4 with
          | None, None -> ()
          | _ -> fail "out-of-range reads were accepted"));
      test "growth is bounded and a rejected append is atomic" (fun () ->
          let module Queue = Opentui_terminal.Byte_queue in
          let queue =
            expect_ok (Queue.create ~initial_capacity:2 ~max_capacity:8 ())
          in
          ignore
            (expect_ok
               (Queue.append_bytes queue ~source:(Bytes.of_string "abcde")
                  ~off:0 ~len:5));
          equal int 8 (Queue.capacity queue);
          equal string "abcde" (Bytes.to_string (queue_contents queue));
          expect_error Queue.Max_capacity
            (Queue.append_bytes queue ~source:(Bytes.of_string "fghi") ~off:0
               ~len:4);
          equal string "abcde" (Bytes.to_string (queue_contents queue));
          equal int 5 (Queue.length queue));
      test "partial consumption compacts to reuse a leading hole" (fun () ->
          let module Queue = Opentui_terminal.Byte_queue in
          let queue =
            expect_ok (Queue.create ~initial_capacity:4 ~max_capacity:8 ())
          in
          ignore
            (expect_ok
               (Queue.append_bytes queue ~source:(Bytes.of_string "abcd")
                  ~off:0 ~len:4));
          ignore (expect_ok (Queue.consume queue 1));
          ignore
            (expect_ok
               (Queue.append_bytes queue ~source:(Bytes.of_string "e") ~off:0
                  ~len:1));
          equal string "bcde" (Bytes.to_string (queue_contents queue));
          equal int 4 (Queue.capacity queue));
      test "invalid capacities and ranges are structured errors" (fun () ->
          let module Queue = Opentui_terminal.Byte_queue in
          expect_error Queue.Invalid_capacity
            (Queue.create ~initial_capacity:0 ());
          expect_error Queue.Invalid_capacity
            (Queue.create ~initial_capacity:9 ~max_capacity:8 ());
          let queue = expect_ok (Queue.create ()) in
          let source = byte_array [ 1; 2; 3 ] in
          expect_error Queue.Invalid_range
            (Queue.append queue ~source ~off:(-1) ~len:1);
          expect_error Queue.Invalid_range
            (Queue.append queue ~source ~off:2 ~len:2);
          expect_error Queue.Invalid_range (Queue.consume queue 1);
          equal int 0 (Queue.length queue);
          ignore (expect_ok (Queue.append queue ~source ~off:0 ~len:0));
          equal int 0 (Queue.length queue))
    ]
