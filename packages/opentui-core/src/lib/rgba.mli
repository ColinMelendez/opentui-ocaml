(** RGBA values that retain the intent with which a terminal color was chosen. *)

type rgb_triplet = int * int * int

type color_intent = Rgb | Indexed | Default

type t

val from_ints : ?alpha:int -> int -> int -> int -> t
val from_values : ?alpha:float -> float -> float -> float -> t
val from_index : ?snapshot:t -> int -> (t, string) result
val default_foreground : ?snapshot:t -> unit -> t
val default_background : ?snapshot:t -> unit -> t
val of_hex : string -> (t, string) result
val parse : string -> (t, string) result
val clone : t -> t
val to_color : t -> (Color.t, Native.Error.t) result

val channels : t -> int * int * int * int
val to_ints : t -> int * int * int * int
val map : t -> (float -> 'a) -> 'a * 'a * 'a * 'a
val red : t -> int
val green : t -> int
val blue : t -> int
val alpha : t -> int
val intent : t -> color_intent
val slot : t -> int option
val to_hex : t -> string
val rgb_to_hex : t -> string
val hsv_to_rgb : float -> float -> float -> t

val normalize_index : int -> (int, string) result
val ansi256_index_to_rgb : int -> (rgb_triplet, string) result

val equal : t -> t -> bool
