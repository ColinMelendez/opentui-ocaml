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
  | F13 | F14 | F15 | F16 | F17 | F18 | F19 | F20
  | F21 | F22 | F23 | F24 | F25 | F26 | F27 | F28 | F29 | F30
  | F31 | F32 | F33 | F34 | F35
  | Menu
  | Capslock | Scrolllock | Numlock | Printscreen | Pause
  | Kp0 | Kp1 | Kp2 | Kp3 | Kp4 | Kp5 | Kp6 | Kp7 | Kp8 | Kp9
  | Kpdecimal | Kpdivide | Kpmultiply | Kpminus | Kpplus | Kpenter
  | Kpequal | Kpseparator | Kpleft | Kpright | Kpup | Kpdown
  | Kppageup | Kppagedown | Kphome | Kpend | Kpinsert | Kpdelete
  | Mediaplay | Mediapause | Mediaplaypause | Mediareverse | Mediastop
  | Mediafastforward | Mediarewind | Medianext | Mediaprev | Mediarecord
  | Volumedown | Volumeup | Mute
  | Leftshift | Leftctrl | Leftalt | Leftsuper | Lefthyper | Leftmeta
  | Rightshift | Rightctrl | Rightalt | Rightsuper | Righthyper | Rightmeta
  | Iso_level3_shift | Iso_level5_shift

type event_type = Press | Repeat | Release
type source = Raw | Kitty

type metadata = {
  event_type : event_type;
  source : source;
  repeated : bool;
  option : bool;
  super : bool;
  hyper : bool;
  caps_lock : bool;
  num_lock : bool;
  number : bool;
  code : int option;
  base_code : int option;
  text : string option;
}

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
  metadata : metadata;
}
(** A key and its decoded modifier flags. *)

(** [named_key_name key] returns a stable lowercase diagnostic name. *)
val named_key_name : named_key -> string
val raw_metadata : metadata
val kitty_metadata :
  event_type:event_type ->
  ?repeated:bool ->
  ?option:bool ->
  ?super:bool ->
  ?hyper:bool ->
  ?caps_lock:bool ->
  ?num_lock:bool ->
  ?number:bool ->
  ?code:int ->
  ?base_code:int ->
  ?text:string ->
  unit -> metadata

(** [decode bytes] decodes common control, UTF-8, meta, CSI, SS3, and
    modifyOtherKeys forms. [None] leaves mouse, response, and malformed
    sequences for the owning parser to classify. *)
val decode : bytes -> decoded option
