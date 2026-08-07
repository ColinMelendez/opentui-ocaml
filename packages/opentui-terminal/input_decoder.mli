type event =
  | Key of {
      key : Key_decoder.key;
      modifiers : Key_decoder.modifiers;
    }
  | Mouse of Mouse_decoder.event
  | Sequence of {
      protocol : Stdin_parser.protocol;
      bytes : bytes;
    }
  | Paste of bytes

type t

val create : unit -> t
val reset : t -> unit
val decode : t -> Stdin_parser.event -> event
