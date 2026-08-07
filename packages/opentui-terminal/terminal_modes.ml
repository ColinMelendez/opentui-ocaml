type screen = Main | Alternate
type mouse_mode = Disabled | Buttons | Motion

type state = {
  screen : screen;
  cursor_visible : bool;
  mouse_mode : mouse_mode;
  mouse_was_enabled : bool;
  bracketed_paste : bool;
}

type t = state

type transition = {
  state : t;
  output : bytes;
}

let initial =
  {
    screen = Main;
    cursor_visible = true;
    mouse_mode = Disabled;
    mouse_was_enabled = false;
    bracketed_paste = false;
  }

let next transition = transition.state
let output transition = Bytes.copy transition.output

let screen state = state.screen
let cursor_visible state = state.cursor_visible
let mouse_mode state = state.mouse_mode
let bracketed_paste state = state.bracketed_paste

let output_of_strings strings =
  let length =
    List.fold_left
      (fun total string -> total + String.length string)
      0 strings
  in
  let result = Bytes.create length in
  let offset = ref 0 in
  List.iter
    (fun string ->
      let length = String.length string in
      Bytes.blit_string string 0 result !offset length;
      offset := !offset + length)
    strings;
  result

let transition state strings = { state; output = output_of_strings strings }

let set_screen state screen =
  match state.screen, screen with
  | Main, Main | Alternate, Alternate -> transition state []
  | Main, Alternate ->
      transition { state with screen = Alternate } [ "\x1b[?1049h" ]
  | Alternate, Main ->
      transition { state with screen = Main } [ "\x1b[?1049l" ]

let set_cursor_visible state visible =
  if Bool.equal state.cursor_visible visible then transition state []
  else
    let sequence = if visible then "\x1b[?25h" else "\x1b[?25l" in
    transition { state with cursor_visible = visible } [ sequence ]

let disable_any_event_tracking = "\x1b[?1003l"
let disable_button_event_tracking = "\x1b[?1002l"
let disable_mouse_tracking = "\x1b[?1000l"
let disable_sgr_mouse_mode = "\x1b[?1006l"

let mouse_disable_sequences =
  [
    disable_any_event_tracking;
    disable_button_event_tracking;
    disable_mouse_tracking;
    disable_sgr_mouse_mode;
  ]

let set_mouse state ~movement =
  let requested = if movement then Motion else Buttons in
  match state.mouse_mode, requested with
  | Disabled, Disabled | Buttons, Disabled | Motion, Disabled ->
      transition state []
  | Buttons, Buttons | Motion, Motion -> transition state []
  | Disabled, Buttons ->
      transition
        {
          state with
          mouse_mode = Buttons;
          mouse_was_enabled = true;
        }
        [
          disable_any_event_tracking;
          "\x1b[?1000h";
          "\x1b[?1002h";
          "\x1b[?1006h";
        ]
  | Disabled, Motion | Buttons, Motion | Motion, Buttons ->
      let prefix = if movement then [] else [ disable_any_event_tracking ] in
      transition
        {
          state with
          mouse_mode = requested;
          mouse_was_enabled = true;
        }
        (prefix
        @ [ "\x1b[?1000h"; "\x1b[?1002h" ]
        @ (if movement then [ "\x1b[?1003h" ] else [])
        @ [ "\x1b[?1006h" ])

let disable_mouse state =
  match state.mouse_mode with
  | Disabled -> transition state []
  | Buttons | Motion ->
      transition { state with mouse_mode = Disabled } mouse_disable_sequences

let set_bracketed_paste state enabled =
  if Bool.equal state.bracketed_paste enabled then transition state []
  else
    let sequence = if enabled then "\x1b[?2004h" else "\x1b[?2004l" in
    transition { state with bracketed_paste = enabled } [ sequence ]

let reset state =
  let cursor = if state.cursor_visible then [] else [ "\x1b[?25h" ] in
  let mouse = if state.mouse_was_enabled then mouse_disable_sequences else [] in
  let paste = if state.bracketed_paste then [ "\x1b[?2004l" ] else [] in
  let screen =
    match state.screen with
    | Main -> []
    | Alternate -> [ "\x1b[?1049l" ]
  in
  transition initial (cursor @ [ "\x1b[0m" ] @ mouse @ paste @ screen)
