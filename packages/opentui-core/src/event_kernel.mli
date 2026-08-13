type 'a t

val create : unit -> 'a t
val on : 'a t -> ('a -> unit) -> Event_subscription.t
val once : 'a t -> ('a -> unit) -> Event_subscription.t
val prepend : 'a t -> ('a -> unit) -> Event_subscription.t
val emit : 'a t -> 'a -> bool
val listener_count : 'a t -> int
val clear : 'a t -> unit
