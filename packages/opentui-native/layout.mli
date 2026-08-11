(** Owner-scoped Yoga layout trees for imperative rendering.

    Node values belong to the layout that created them. Closing a layout
    invalidates all of its nodes; removing a child invalidates the detached
    native subtree. *)

type direction = Inherit | Ltr | Rtl
(** The direction used by {!calculate}. *)

type layout = {
  left : float;
  top : float;
  right : float;
  bottom : float;
  width : float;
  height : float;
}
(** A copied computed layout in parent-relative coordinates. *)

type t
(** A Yoga layout-tree owner. *)

module Node : sig
  (** A node owned by one layout tree. *)
  type t

  (** [set_dimensions node ...] sets validated fixed width and height. *)
  val set_dimensions : t -> width:float -> height:float -> (unit, Error.t) result

  (** [layout node] returns the most recently calculated layout for [node]. *)
  val layout : t -> (layout, Error.t) result
end

(** [create ()] creates a layout tree with a root node. *)
val create : unit -> (t, Error.t) result

(** [close layout] releases the tree and invalidates its nodes. It is
    idempotent. *)
val close : t -> unit

(** [root layout] returns the tree's root node. *)
val root : t -> (Node.t, Error.t) result

(** [add_child ~parent] creates and attaches a child to [parent]. *)
val add_child : parent:Node.t -> (Node.t, Error.t) result

(** [remove_child ~parent ~child] detaches and destroys [child] and its
    descendants. *)
val remove_child : parent:Node.t -> child:Node.t -> (unit, Error.t) result

(** [calculate layout ...] computes layouts for the entire tree. *)
val calculate :
  t ->
  width:float ->
  height:float ->
  direction:direction ->
  (unit, Error.t) result
