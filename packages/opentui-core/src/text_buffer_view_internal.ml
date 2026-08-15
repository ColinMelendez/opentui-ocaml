type t = {
  raw : Opentui_raw.Text_buffer_view.t;
  buffer : Text_buffer_internal.t;
  mutable wrap_width : int32 option;
  mutable wrap_mode : wrap_mode;
  mutable first_line_offset : int32;
  mutable viewport_x : int32;
  mutable viewport_y : int32;
  mutable viewport_width : int32;
  mutable viewport_height : int32;
  mutable selection : selection option;
  mutable local_selection : local_selection option;
  mutable tab_indicator : string;
  mutable tab_indicator_color : Color.t option;
  mutable truncate : bool;
  mutable closed : bool;
}

and wrap_mode = No_wrap | Char | Word

and selection = {
  start : int;
  end_ : int;
  bg_color : Color.t option;
  fg_color : Color.t option;
}

and local_selection = {
  anchor_x : int;
  anchor_y : int;
  focus_x : int;
  focus_y : int;
  bg_color : Color.t option;
  fg_color : Color.t option;
}

let of_raw raw buffer =
  {
    raw;
    buffer;
    wrap_width = None;
    wrap_mode = No_wrap;
    first_line_offset = 0l;
    viewport_x = 0l;
    viewport_y = 0l;
    viewport_width = 0l;
    viewport_height = 0l;
    selection = None;
    local_selection = None;
    tab_indicator = "";
    tab_indicator_color = None;
    truncate = false;
    closed = false;
  }

let raw view = view.raw
let buffer view = view.buffer
let is_open view = not view.closed && Text_buffer_internal.is_open view.buffer
let mark_closed view = view.closed <- true
let wrap_width view = view.wrap_width
let set_wrap_width view value = view.wrap_width <- value
let wrap_mode view = view.wrap_mode
let set_wrap_mode view value = view.wrap_mode <- value
let first_line_offset view = view.first_line_offset
let set_first_line_offset view value = view.first_line_offset <- value

let viewport view =
  view.viewport_x, view.viewport_y, view.viewport_width, view.viewport_height

let set_viewport view ~x ~y ~width ~height =
  view.viewport_x <- x;
  view.viewport_y <- y;
  view.viewport_width <- width;
  view.viewport_height <- height

let selection view = view.selection
let set_selection view value = view.selection <- value
let local_selection view = view.local_selection
let set_local_selection view value = view.local_selection <- value
let tab_indicator view = view.tab_indicator
let set_tab_indicator view value = view.tab_indicator <- value
let tab_indicator_color view = view.tab_indicator_color
let set_tab_indicator_color view value = view.tab_indicator_color <- value
let truncate view = view.truncate
let set_truncate view value = view.truncate <- value
