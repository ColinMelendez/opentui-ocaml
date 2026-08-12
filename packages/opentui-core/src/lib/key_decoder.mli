(** Low-level decoding of complete terminal key frames.

    {!Opentui_core.Lib.Stdin_parser} owns byte framing and emits the typed
    events used by the rest of the terminal stack. This module recognizes the
    key portion of one already-framed byte sequence. *)

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

type decoded = {
  key : key;
  modifiers : modifiers;
}
(** A key and its decoded modifier flags. *)

(** [named_key_name key] returns a stable lowercase diagnostic name. *)
val named_key_name : named_key -> string

(** [decode bytes] decodes common control, UTF-8, meta, CSI, SS3, and
    modifyOtherKeys forms. [None] leaves mouse, response, and malformed
    sequences for the owning parser to classify. *)
val decode : bytes -> decoded option
