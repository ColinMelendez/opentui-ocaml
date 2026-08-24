type kind =
  | Basic
  | Lambert

type t = { kind : kind; color : Color.t }

let color m = m.color

let kind m = m.kind
