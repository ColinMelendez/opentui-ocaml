(** Stateful composition of key and mouse decoding over framed parser events.
    Input payloads in the returned events are owned copies. *)

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
(** Decoder state, including pressed mouse-button tracking. *)

(** [create ()] creates a fresh decoder. *)
val create : unit -> t

(** [reset decoder] clears mouse state. *)
val reset : t -> unit

(** [decode decoder input] maps one parser event to one semantic event. *)
val decode : t -> Stdin_parser.event -> event
