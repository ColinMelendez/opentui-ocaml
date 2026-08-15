(** Keyboard dispatch corresponding to [packages/core/src/lib/KeyHandler.ts].

    The handler keeps global and focused-renderable listeners separate. Global
    listeners run first, then focused-renderable listeners run unless a global
    listener prevents the default action or stops propagation. Dispatch is
    synchronous; callback exceptions are reported through the configured error
    callback and do not abort the remaining listeners. *)

type event_kind = Keypress | Keyrelease | Paste

type key_event
(** A mutable key event delivered to one keyboard callback chain. *)

type paste_event
(** A mutable paste event delivered to one keyboard callback chain. *)

type handler_scope = Global | Renderable

type handler_error = {
  kind : event_kind;
  scope : handler_scope;
  owner_num : int option;
  exception_value : exn;
}

type t

(** [create ~on_error ()] creates an owner-local keyboard dispatcher. *)
val create : ?on_error:(handler_error -> unit) -> unit -> t

val key_raw : key_event -> bytes
val key : key_event -> Key_decoder.key
val key_modifiers : key_event -> Key_decoder.modifiers
val key_metadata : key_event -> Key_decoder.metadata
val key_event_kind : key_event -> event_kind

val paste_raw : paste_event -> bytes

(** Control flags are mutable during one callback chain. *)
val default_prevented : key_event -> bool
val stop_propagation : key_event -> unit
val prevent_default : key_event -> unit
val propagation_stopped : key_event -> bool

val paste_default_prevented : paste_event -> bool
val paste_stop_propagation : paste_event -> unit
val paste_prevent_default : paste_event -> unit
val paste_propagation_stopped : paste_event -> bool

(** Global registrations run before focused-renderable registrations. *)
val on_keypress : t -> (key_event -> unit) -> Event_subscription.t
val once_keypress : t -> (key_event -> unit) -> Event_subscription.t
val prepend_keypress : t -> (key_event -> unit) -> Event_subscription.t
val on_keyrelease : t -> (key_event -> unit) -> Event_subscription.t
val once_keyrelease : t -> (key_event -> unit) -> Event_subscription.t
val prepend_keyrelease : t -> (key_event -> unit) -> Event_subscription.t
val on_paste : t -> (paste_event -> unit) -> Event_subscription.t
val once_paste : t -> (paste_event -> unit) -> Event_subscription.t
val prepend_paste : t -> (paste_event -> unit) -> Event_subscription.t

(** Internal registrations are owned by one focused renderable. *)
val on_internal_keypress :
  t -> owner_num:int -> (key_event -> unit) -> Event_subscription.t

val on_internal_keyrelease :
  t -> owner_num:int -> (key_event -> unit) -> Event_subscription.t

val on_internal_paste :
  t -> owner_num:int -> (paste_event -> unit) -> Event_subscription.t

val process_key :
  t -> raw:bytes -> key:Key_decoder.key -> modifiers:Key_decoder.modifiers ->
  ?metadata:Key_decoder.metadata -> unit -> bool

val process_keyrelease :
  t -> raw:bytes -> key:Key_decoder.key -> modifiers:Key_decoder.modifiers ->
  ?metadata:Key_decoder.metadata -> unit -> bool

val process_paste : t -> bytes -> bool

(** [clear] removes all later global and internal registrations. *)
val clear : t -> unit
