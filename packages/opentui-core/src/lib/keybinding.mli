(** Typed keybinding composition for interactive renderables. *)

type 'a binding = {
  name : string;
  ctrl : bool;
  shift : bool;
  meta : bool;
  super : bool;
  action : 'a;
}

type aliases

type 'a t

val default_aliases : unit -> aliases
val merge_aliases : aliases -> (string * string) list -> aliases

val binding :
  ?ctrl:bool ->
  ?shift:bool ->
  ?meta:bool ->
  ?super:bool ->
  name:string ->
  action:'a ->
  unit ->
  'a binding

val create : ?aliases:aliases -> 'a binding list -> 'a t
val set_bindings : 'a t -> 'a binding list -> unit
val set_aliases : 'a t -> aliases -> unit
val action : 'a t -> Key_handler.key_event -> 'a option
val name : Key_handler.key_event -> string
