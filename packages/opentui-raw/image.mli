(** Typed ownership over the vendored native image subsystem. *)

type format = Unknown | Png | Raw_rgba | Jpeg | Webp | Gif
type color_status = Assumed_srgb | Explicit_srgb

type info = {
  width : int32;
  height : int32;
  source_width : int32;
  source_height : int32;
  format : format;
  color_status : color_status;
  orientation : int32;
  has_alpha : bool;
}

type resize_filter =
  | Default
  | Area
  | Triangle
  | Cubic_bspline
  | Catmull_rom
  | Mitchell
  | Nearest

type transform = Rotate_90 | Rotate_180 | Rotate_270 | Flip | Flop
type blend = Source_over | Source | Destination_over
type t

type error =
  | Invalid_handle
  | Unsupported_format
  | Unsupported_color_space
  | Malformed_input
  | Dimension_limit
  | Memory_limit
  | Invalid_argument
  | Out_of_memory
  | Output_too_small
  | Internal_error
  | Unsupported_feature

val message : error -> string
val pp : Format.formatter -> error -> unit

val info : bytes -> (info, error) result
val decode : bytes -> (t, error) result
val create_from_rgba :
  pixels:bytes -> width:int -> height:int -> stride:int -> (t, error) result
val get_info : t -> (info, error) result
val retain : t -> (t, error) result
val materialize : t -> (unit, error) result
val ensure_encoded_png : t -> (unit, error) result
val clone : t -> (t, error) result
val copy_pixels : t -> destination:bytes -> stride:int -> bgra:bool -> (unit, error) result
val resize : t -> width:int -> height:int -> filter:resize_filter -> (t, error) result
val extract :
  t -> left:int -> top:int -> width:int -> height:int -> (t, error) result
val extend :
  t -> top:int -> right:int -> bottom:int -> left:int -> background:bytes ->
  (t, error) result
val transform : t -> transform -> (t, error) result
val composite :
  t -> overlay:t -> left:int -> top:int -> blend:blend -> opacity:int ->
  (t, error) result
val close : t -> unit

module Private : sig
  val with_open : t -> (Native_token.Image.t -> ('a, error) result) -> ('a, error) result
  val handle : t -> Native_token.Image.t
end
