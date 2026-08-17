(** Native images owned by OCaml and backed by the vendored Zig decoder. *)

type protocol = Auto | Kitty | Sixel | Blocks

type format = Unknown | Png | Raw_rgba | Jpeg | Webp | Gif
type color_status = Assumed_srgb | Explicit_srgb

type info = {
  width : int;
  height : int;
  source_width : int;
  source_height : int;
  format : format;
  color_status : color_status;
  orientation : int;
  has_alpha : bool;
}

type read_operation = Stat | Open | Read

type read_error =
  | Io of { operation : read_operation; detail : string }
  | Too_large of { limit : int }

type decode_error =
  | Invalid_argument
  | Native of Opentui_raw.Image.error

type error =
  | Closed
  | Invalid_argument
  | Native of Opentui_raw.Image.error

type load_error =
  | Read of read_error
  | Decode of decode_error
  | Native of error
  | Core of Error.t

type source =
  | Encoded of bytes
  | Rgba of { pixels : bytes; width : int; height : int; stride : int }
  | Path of Eio.Fs.dir_ty Eio.Path.t

type raw = {
  data : bytes;
  width : int;
  height : int;
  stride : int;
  bgra : bool;
}

type t

val max_path_bytes : int
val message : error -> string
val pp : Format.formatter -> error -> unit
val read_message : read_error -> string
val read_pp : Format.formatter -> read_error -> unit
val decode_message : decode_error -> string
val decode_pp : Format.formatter -> decode_error -> unit
val load_message : load_error -> string
val load_pp : Format.formatter -> load_error -> unit

val read_path : Eio.Fs.dir_ty Eio.Path.t -> (bytes, read_error) result
val decode : bytes -> (t, decode_error) result
val info : bytes -> (info, decode_error) result
val from_rgba :
  pixels:bytes -> width:int -> height:int -> stride:int -> (t, decode_error) result
val load : source -> (t, load_error) result
val close : t -> unit
val get_info : t -> (info, error) result
val width : t -> (int, error) result
val height : t -> (int, error) result
val source_width : t -> (int, error) result
val source_height : t -> (int, error) result
val retain : t -> (t, error) result
val clone : t -> (t, error) result
val materialize : t -> (unit, error) result
val ensure_encoded_png : t -> (unit, error) result
val copy_to :
  t -> destination:bytes -> stride:int -> ?bgra:bool -> unit -> (unit, error) result
val copy : t -> ?bgra:bool -> unit -> ((bytes * int), error) result
val resize :
  t -> ?width:int -> ?height:int -> ?filter:[ `Default | `Area | `Triangle
  | `Cubic_bspline | `Catmull_rom | `Mitchell | `Nearest ] -> unit -> (t, error) result
val take_raw : t -> ?bgra:bool -> unit -> (raw, error) result
val extract :
  t -> left:int -> top:int -> width:int -> height:int -> (t, error) result
val extend :
  t -> ?top:int -> ?right:int -> ?bottom:int -> ?left:int -> ?background:bytes ->
  unit -> (t, error) result
val transform :
  t -> [ `Rotate_90 | `Rotate_180 | `Rotate_270 | `Flip | `Flop ] ->
  (t, error) result
val composite :
  t -> overlay:t -> ?left:int -> ?top:int ->
  ?blend:[ `Source_over | `Source | `Destination_over ] -> ?opacity:int ->
  unit -> (t, error) result

module Private : sig
  val with_open :
    t -> (Opentui_raw.Native_token.Image.t -> ('a, Opentui_raw.Image.error) result) ->
    ('a, Opentui_raw.Image.error) result
  val raw : t -> Opentui_raw.Image.t
end
