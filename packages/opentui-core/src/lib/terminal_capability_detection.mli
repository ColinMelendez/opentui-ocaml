(** Recognition of terminal capability responses carried by parser events. *)

type pixel_resolution = {
  width : int32;
  height : int32;
}
(** A terminal pixel resolution bounded to the dimensions accepted by Core. *)

(** [is_capability_response sequence] recognizes the capability response
    families used by the upstream renderer. It may inspect a larger response
    chunk containing unrelated bytes. *)
val is_capability_response : string -> bool

(** [is_pixel_resolution_response sequence] recognizes a DECRQPSR response. *)
val is_pixel_resolution_response : string -> bool

(** [parse_pixel_resolution sequence] returns the first syntactically valid
    pixel response whose dimensions fit in Core's signed 32-bit geometry. *)
val parse_pixel_resolution : string -> pixel_resolution option

(** The terminal query that requests a [CSI 4;height;width t] response. *)
val pixel_resolution_query : unit -> string
