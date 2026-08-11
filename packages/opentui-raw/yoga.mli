(** Owner-scoped bindings for the audited Yoga subset. Closing a tree
    invalidates its root and every node. Removing a child recursively destroys
    the detached subtree. *)

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
(** A Yoga tree owner. *)

module Node : sig
  (** A node owned by one Yoga tree. *)
  type t

  (** [set_width node width] sets a validated point-valued width. *)
  val set_width : t -> float -> (unit, Error.t) result

  (** [set_height node height] sets a validated point-valued height. *)
  val set_height : t -> float -> (unit, Error.t) result

  (** [layout node] returns copied computed layout fields. *)
  val layout : t -> (layout, Error.t) result
end

(** [create ()] creates a tree and its root. *)
val create : unit -> (t, Error.t) result

(** [close tree] destroys the tree and invalidates all node values. *)
val close : t -> unit

(** [root tree] returns the tree root. *)
val root : t -> (Node.t, Error.t) result

(** [add_child tree ~parent] creates and attaches a child in [tree]. *)
val add_child :
  t -> parent:Node.t -> (Node.t, Error.t) result

(** [remove_child tree ~parent ~child] requires a direct parent/child
    relationship in [tree] and destroys the detached subtree. *)
val remove_child :
  t -> parent:Node.t -> child:Node.t -> (unit, Error.t) result

(** [move_child tree ~parent ~child ~index] moves an attached direct child to
    zero-based [index] within [parent]. The child and its descendants keep
    their native identities. An invalid index or parent/child relationship is
    rejected without changing the tree. *)
val move_child :
  t -> parent:Node.t -> child:Node.t -> index:int32 -> (unit, Error.t) result

(** [calculate tree ...] computes layout for the tree. *)
val calculate :
  t ->
  width:float ->
  height:float ->
  direction:direction ->
  (unit, Error.t) result
