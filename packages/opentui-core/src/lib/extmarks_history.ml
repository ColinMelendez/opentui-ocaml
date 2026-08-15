type extmark = {
  id : int;
  start : int;
  end_ : int;
  virtual_ : bool;
  style_id : int option;
  priority : int option;
  data : string option;
  type_id : int;
}

type snapshot = { extmarks : extmark list; next_id : int }
type t = { mutable undo_stack : snapshot list; mutable redo_stack : snapshot list }

let create () = { undo_stack = []; redo_stack = [] }

let copy_mark mark = { mark with data = mark.data }
let copy_snapshot snapshot = { snapshot with extmarks = List.map copy_mark snapshot.extmarks }

let save_snapshot history extmarks ~next_id =
  history.undo_stack <- { extmarks = List.map copy_mark extmarks; next_id } :: history.undo_stack;
  history.redo_stack <- []

let undo history =
  match history.undo_stack with
  | [] -> None
  | snapshot :: rest ->
      history.undo_stack <- rest;
      Some (copy_snapshot snapshot)

let redo history =
  match history.redo_stack with
  | [] -> None
  | snapshot :: rest ->
      history.redo_stack <- rest;
      Some (copy_snapshot snapshot)

let push_undo history snapshot = history.undo_stack <- copy_snapshot snapshot :: history.undo_stack
let push_redo history snapshot = history.redo_stack <- copy_snapshot snapshot :: history.redo_stack
let clear history = history.undo_stack <- []; history.redo_stack <- []
let can_undo history = not (List.is_empty history.undo_stack)
let can_redo history = not (List.is_empty history.redo_stack)
