type viewport = { x : float; y : float; width : float; height : float }
type direction = Row | Column

type 'a object_ = {
  value : 'a;
  screen_x : float;
  screen_y : float;
  width : float;
  height : float;
  z_index : int;
}

let overlaps (viewport : viewport) (object_ : 'a object_) =
  Float.compare (object_.screen_x +. object_.width) viewport.x > 0
  && Float.compare object_.screen_x (viewport.x +. viewport.width) < 0
  && Float.compare (object_.screen_y +. object_.height) viewport.y > 0
  && Float.compare object_.screen_y (viewport.y +. viewport.height) < 0

let get ?(direction = Column) ?(padding = 10.0) ?(min_trigger_size = 16)
    (viewport : viewport) objects =
  if Float.compare viewport.width 0.0 <= 0 || Float.compare viewport.height 0.0 <= 0 then []
  else
    let expanded : viewport =
      {
        x = viewport.x -. padding;
        y = viewport.y -. padding;
        width = viewport.width +. (2.0 *. padding);
        height = viewport.height +. (2.0 *. padding);
      }
    in
    let candidates =
      if List.length objects < min_trigger_size then objects
      else
        let primary_start object_ =
          match direction with Row -> object_.screen_x | Column -> object_.screen_y
        in
        let primary_end object_ =
          match direction with
          | Row -> object_.screen_x +. object_.width
          | Column -> object_.screen_y +. object_.height
        in
        let viewport_start =
          match direction with Row -> expanded.x | Column -> expanded.y
        in
        let viewport_end =
          match direction with
          | Row -> expanded.x +. expanded.width
          | Column -> expanded.y +. expanded.height
        in
        let low = ref 0 in
        let high = ref (List.length objects - 1) in
        let array = Array.of_list objects in
        let candidate = ref (-1) in
        while !low <= !high && !candidate < 0 do
          let middle = (!low + !high) / 2 in
          let object_ = array.(middle) in
          if Float.compare (primary_end object_) viewport_start <= 0 then
            low := middle + 1
          else if Float.compare (primary_start object_) viewport_end >= 0 then
            high := middle - 1
          else candidate := middle
        done;
        let start = if !candidate < 0 then max 0 (!low - 1) else !candidate in
        let left = ref start in
        let gap_count = ref 0 in
        while !left > 0 do
          let previous = array.(!left - 1) in
          if Float.compare (primary_end previous) viewport_start <= 0 then begin
            incr gap_count;
            if !gap_count >= 50 then left := 0 else decr left
          end else begin
            gap_count := 0;
            decr left
          end
        done;
        let right = ref (start + 1) in
        while !right < Array.length array
              && Float.compare (primary_start array.(!right)) viewport_end < 0 do
          incr right
        done;
        let result = ref [] in
        for index = !left to !right - 1 do
          let object_ = array.(index) in
          if overlaps expanded object_ then result := object_ :: !result
        done;
        List.rev !result
    in
    List.sort
      (fun left right -> Int.compare left.z_index right.z_index)
      (List.filter (overlaps expanded) candidates)
