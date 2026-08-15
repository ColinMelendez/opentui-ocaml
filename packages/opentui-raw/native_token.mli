(** Opaque generation-checked tokens used by the raw native bridge.

    These types have no public constructors or operations. A token is only
    valid while its owning raw resource remains open. *)

module Renderer : sig
  type t
(** A renderer token. *)
end

module Buffer : sig
  type t
(** A renderer-owned buffer token. *)
end

module Optimized_buffer : sig
  type t
(** An explicitly owned standalone optimized-buffer token. *)
end

module Event_sink : sig
  type t
(** An event-sink token. *)
end

module Yoga_node : sig
  type t
(** A Yoga-node token. *)
end

module Span_feed : sig
  type t
(** A span-feed token. *)
end

module Span : sig
  type t
(** A drained-span token. *)
end

module Reservation : sig
  type t
(** A span-feed reservation token. *)
end

module Text_buffer : sig
  type t
(** A native text-buffer token. *)
end

module Text_buffer_view : sig
  type t
(** A view token owned by a native text buffer. *)
end

module Syntax_style : sig
  type t
(** A native syntax-style token. *)
end

module Native_renderable : sig
  type t
(** A native measure-callback owner. *)
end

module Image : sig
  type t
(** A reference-counted native image handle. *)
end
