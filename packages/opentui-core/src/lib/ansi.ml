let alternate_screen = "\x1b[?1049h"
let main_screen = "\x1b[?1049l"
let reset = "\x1b[0m"
let reset_scroll_region = "\x1b[r"
let cursor_home = "\x1b[H"
let clear_screen = "\x1b[2J"
let clear_saved_lines = "\x1b[3J"
let bracketed_paste_start = "\x1b[200~"
let bracketed_paste_end = "\x1b[201~"
let modify_other_keys_set = "\x1b[>4;1m"
let modify_other_keys_reset = "\x1b[>4;0m"
let reset_background = "\x1b[49m"

let positive value = Int.compare value 0 > 0

let scroll_region ~top ~bottom =
  if not (positive top && positive bottom) || Int.compare top bottom > 0 then
    Error "scroll region coordinates must be positive and ordered"
  else Ok (Printf.sprintf "\x1b[%d;%dr" top bottom)

let cursor_position ~row ~column =
  if not (positive row && positive column) then
    Error "cursor coordinates must be positive"
  else Ok (Printf.sprintf "\x1b[%d;%dH" row column)

let cursor_move ~row ~column =
  if Int.compare row 0 < 0 || Int.compare column 0 < 0 then
    Error "cursor movement must be non-negative"
  else
    let vertical = if Int.equal row 0 then "" else Printf.sprintf "\x1b[%dB" row in
    let horizontal = if Int.equal column 0 then "" else Printf.sprintf "\x1b[%dC" column in
    Ok (vertical ^ horizontal)

let scroll_sequence ~lines ~direction =
  if not (positive lines) then Error "scroll line count must be positive"
  else
    let final = match direction with `Up -> 'S' | `Down -> 'T' in
    Ok (Printf.sprintf "\x1b[%d%c" lines final)

let scroll_up ~lines = scroll_sequence ~lines ~direction:`Up
let scroll_down ~lines = scroll_sequence ~lines ~direction:`Down

let move_cursor ~row ~column =
  if not (positive row && positive column) then
    Error "cursor coordinates must be positive"
  else Ok (Printf.sprintf "\x1b[%d;%dH" row column)

let move_cursor_and_clear ~row ~column =
  Result.map (fun position -> position ^ "\x1b[J") (move_cursor ~row ~column)

let byte value = Int.compare value 0 >= 0 && Int.compare value 255 <= 0

let rgb_background ~red ~green ~blue =
  if byte red && byte green && byte blue then
    Ok (Printf.sprintf "\x1b[48;2;%d;%d;%dm" red green blue)
  else Error "RGB channel must be in the range 0..255"
