type named_key =
  | Return
  | Linefeed
  | Tab
  | Backspace
  | Escape
  | Space
  | Up
  | Down
  | Right
  | Left
  | Clear
  | Home
  | End
  | Insert
  | Delete
  | Page_up
  | Page_down
  | F1
  | F2
  | F3
  | F4
  | F5
  | F6
  | F7
  | F8
  | F9
  | F10
  | F11
  | F12
  | Menu

type modifiers = {
  shift : bool;
  meta : bool;
  ctrl : bool;
}

type key = Character of bytes | Named of named_key

type event =
  | Key of { key : key; modifiers : modifiers }
  | Sequence of { protocol : Stdin_parser.protocol; bytes : bytes }
  | Paste of bytes

val named_key_name : named_key -> string
val decode : Stdin_parser.event -> event
