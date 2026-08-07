type t = { mutable open_ : bool }

let create () = { open_ = true }
let is_open owner = owner.open_
let close owner = owner.open_ <- false

module Private = struct
  let create = create
  let close = close
end
