type value_type = String | Boolean | Number

type value = Text of string | Bool of bool | Number of float

type definition = {
  name : string;
  description : string;
  default : value option;
  required : bool;
  value_type : value_type;
}

type error =
  | Invalid_name
  | Duplicate_definition of string
  | Unregistered of string
  | Missing_required of string
  | Invalid_number of string

type t

val create : get:(string -> string option) -> unit -> t
val register : t -> definition -> (unit, error) result
val definition : t -> string -> definition option
val value : t -> string -> (value option, error) result
val has : t -> string -> bool
val clear_cache : t -> unit
val definitions : t -> definition list
val message : error -> string
val markdown : t -> string
val colored : t -> string
