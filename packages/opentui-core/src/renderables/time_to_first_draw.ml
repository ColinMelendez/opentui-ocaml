type t = {
  renderable : Renderable.t;
  mutable text_color : Color.t;
  mutable label : string;
  mutable precision : int;
  mutable runtime_ns : int64 option;
  mutable destroyed : bool;
}

let normalize_precision value =
  if value < 0 then 0 else value

let string_repeat character count =
  if count <= 0 then ""
  else String.make count character

let fixed_ms_text nanoseconds precision =
  let precision = normalize_precision precision in
  let milliseconds = Int64.div nanoseconds 1_000_000L in
  let fractional_nanoseconds = Int64.rem nanoseconds 1_000_000L in
  if Int.equal precision 0 then Int64.to_string milliseconds
  else if precision <= 6 then begin
    let scale =
      let value = ref 1L in
      for _index = 1 to 6 - precision do value := Int64.mul !value 10L done;
      !value
    in
    let rounded_units =
      Int64.div (Int64.add fractional_nanoseconds (Int64.div scale 2L)) scale
    in
    let unit_limit =
      let value = ref 1L in
      for _index = 1 to precision do value := Int64.mul !value 10L done;
      !value
    in
    if Int64.compare rounded_units unit_limit >= 0 then
      Int64.to_string (Int64.add milliseconds 1L) ^ "."
      ^ string_repeat '0' precision
    else
      let digits = Int64.to_string rounded_units in
      Int64.to_string milliseconds ^ "."
      ^ string_repeat '0' (precision - String.length digits) ^ digits
  end else begin
    let nanosecond_digits =
      let digits = Int64.to_string (Int64.mul fractional_nanoseconds 1_000L) in
      string_repeat '0' (9 - String.length digits) ^ digits
    in
    let fractional_digits =
      if precision <= 9 then String.sub nanosecond_digits 0 precision
      else nanosecond_digits ^ string_repeat '0' (precision - 9)
    in
    Int64.to_string milliseconds ^ "." ^ fractional_digits
  end

let runtime_ms value =
  Option.map
    (fun nanoseconds -> Int64.to_float nanoseconds /. 1_000_000.0)
    value.runtime_ns

let ensure_alive value =
  if value.destroyed || Renderable.is_destroyed value.renderable then
    Error Error.Destroyed
  else Ok ()

let render_self value renderable buffer _delta_time =
  let nanoseconds =
    match value.runtime_ns with
    | Some value -> value
    | None ->
        let timestamp = Mtime_clock.elapsed_ns () in
        value.runtime_ns <- Some timestamp;
        timestamp
  in
  let content =
    value.label ^ ": " ^ fixed_ms_text nanoseconds value.precision ^ "ms"
  in
  let width = max 1 (int_of_float (Float.floor (Renderable.width renderable))) in
  let visible_content =
    if String.length content <= width then content
    else String.sub content 0 width
  in
  let x =
    int_of_float (Float.floor (Renderable.screen_x renderable))
    + max 0 ((width - String.length visible_content) / 2)
  in
  Buffer.draw_text buffer ~text:visible_content
    ~x:(Int32.of_int x)
    ~y:(Int32.of_float (Float.floor (Renderable.screen_y renderable)))
    ~foreground:value.text_color ~background:Color.transparent ~attributes:0l

let create context ?id
    ?(fg =
      match Color.rgba ~red:170 ~green:170 ~blue:170 ~alpha:255 with
      | Ok color -> color
      | Error _ -> Color.white)
    ?(label = "Time to first draw")
    ?(precision = 2) () =
  Result.bind (Renderable.Private.create context ?id ()) (fun renderable ->
      let value =
        {
          renderable;
          text_color = fg;
          label;
          precision = normalize_precision precision;
          runtime_ns = None;
          destroyed = false;
        }
      in
      let behavior =
        Renderable.Private.make_behavior ~render_self:(render_self value)
          ~destroy_self:(fun _ -> value.destroyed <- true) ()
      in
      Renderable.Private.set_behavior renderable behavior;
      let result =
        Result.bind
          (Renderable.set_width renderable (Yoga.Percent 100.0))
          (fun () ->
            Result.bind
              (Renderable.set_height renderable (Yoga.Point 1.0))
              (fun () ->
                Result.bind
                  (Renderable.set_flex_shrink renderable (Some 0.0))
                  (fun () ->
                    Renderable.set_align_self renderable Yoga.Align_center)))
      in
      match result with
      | Ok () -> Ok value
      | Error error ->
          Renderable.destroy renderable;
          Error error)

let as_renderable value = value.renderable
let fg value = value.text_color

let set_fg value color =
  Result.bind (ensure_alive value) (fun () ->
      value.text_color <- color;
      Renderable.request_render value.renderable)

let set_color = set_fg
let label value = value.label

let set_label value label =
  Result.bind (ensure_alive value) (fun () ->
      if String.equal value.label label then Ok ()
      else begin
        value.label <- label;
        Renderable.request_render value.renderable
      end)

let precision value = value.precision

let set_precision value precision =
  Result.bind (ensure_alive value) (fun () ->
      let precision = normalize_precision precision in
      if Int.equal value.precision precision then Ok ()
      else begin
        value.precision <- precision;
        Renderable.request_render value.renderable
      end)

let reset value =
  Result.bind (ensure_alive value) (fun () ->
      value.runtime_ns <- None;
      Renderable.request_render value.renderable)

let destroy value = Renderable.destroy value.renderable
