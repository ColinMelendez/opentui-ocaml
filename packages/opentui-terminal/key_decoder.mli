(** Stateless decoding of terminal key and opaque protocol events. *)

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
(** Modifier flags attached to a decoded key. *)

type key = Character of bytes | Named of named_key
(** A copied character payload or a named key. *)

type event =
  | Key of { key : key; modifiers : modifiers }
  | Sequence of { protocol : Stdin_parser.protocol; bytes : bytes }
  | Paste of bytes
(** A decoded key, opaque protocol sequence, or copied paste payload. *)

(** [named_key_name key] returns a stable lowercase diagnostic name. *)
val named_key_name : named_key -> string

(** [decode input] decodes common control, UTF-8, meta, CSI, SS3, and
    modifyOtherKeys forms. Unsupported or malformed sequences remain opaque. *)
val decode : Stdin_parser.event -> event
