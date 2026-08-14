type t = { node : Text_node.t }

type child = Text_node.input =
  | String of string
  | Node of Text_node.t
  | Styled of Lib.Styled_text.t

let add ?index children child = Text_node.add ?index children.node child
let remove children child = Text_node.remove children.node child

let insert_before children child ~anchor =
  Text_node.insert_before children.node child ~anchor

let children children = Text_node.get_children children.node
let child_count children = Text_node.child_count children.node
let clear children = Text_node.clear children.node

module Private = struct
  let of_node node = { node }
end
