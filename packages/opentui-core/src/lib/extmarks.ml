type extmark = Extmarks_history.extmark = {
  id : int;
  start : int;
  end_ : int;
  virtual_ : bool;
  style_id : int option;
  priority : int option;
  data : string option;
  type_id : int;
}

type options = {
  start : int;
  end_ : int;
  virtual_ : bool;
  style_id : int option;
  priority : int option;
  data : string option;
  type_id : int option;
  metadata : string option;
}

type t = {
  marks : (int, extmark) Hashtbl.t;
  metadata : (int, string) Hashtbl.t;
  types_by_name : (string, int) Hashtbl.t;
  names_by_type : (int, string) Hashtbl.t;
  mutable next_id : int;
  mutable next_type_id : int;
  history : Extmarks_history.t;
  mutable destroyed : bool;
}

let ensure_open controller = if controller.destroyed then Error Error.Destroyed else Ok ()

let current_marks controller =
  Hashtbl.to_seq_values controller.marks |> List.of_seq

let adjust_position ~offset ~length position =
  if position <= offset then position
  else if position >= offset + length then position - length
  else offset

let adjust_after_insertion controller ~offset ~length =
  Result.bind (ensure_open controller) (fun () ->
      if offset < 0 || length < 0 then Error Error.Invalid_argument
      else begin
        Hashtbl.iter
          (fun id (mark : extmark) ->
            let start = if mark.start >= offset then mark.start + length else mark.start in
            let finish = if mark.end_ >= offset then mark.end_ + length else mark.end_ in
            let updated : extmark = { mark with start; end_ = finish } in
            Hashtbl.replace controller.marks id updated)
          controller.marks;
        Ok ()
      end)

let adjust_after_deletion controller ~offset ~length =
  Result.bind (ensure_open controller) (fun () ->
      if offset < 0 || length < 0 then Error Error.Invalid_argument
      else begin
        Hashtbl.iter
          (fun id (mark : extmark) ->
            let start = adjust_position ~offset ~length mark.start in
            let finish = adjust_position ~offset ~length mark.end_ in
            let updated : extmark = { mark with start; end_ = max start finish } in
            Hashtbl.replace controller.marks id updated)
          controller.marks;
        Ok ()
      end)

let create () =
  let controller =
    {
      marks = Hashtbl.create 16;
      metadata = Hashtbl.create 16;
      types_by_name = Hashtbl.create 8;
      names_by_type = Hashtbl.create 8;
      next_id = 1;
      next_type_id = 1;
      history = Extmarks_history.create ();
      destroyed = false;
    }
  in
  controller

let create_mark controller options =
  Result.bind (ensure_open controller) (fun () ->
      if options.start < 0 || options.end_ < options.start then Error Error.Invalid_argument
      else
        let type_id = Option.value options.type_id ~default:0 in
        let id = controller.next_id in
        controller.next_id <- id + 1;
        let mark =
          { id; start = options.start; end_ = options.end_; virtual_ = options.virtual_; style_id = options.style_id; priority = options.priority; data = options.data; type_id }
        in
        Hashtbl.add controller.marks id mark;
        Option.iter (fun metadata -> Hashtbl.replace controller.metadata id metadata) options.metadata;
        Ok id)

let delete controller id =
  Result.bind (ensure_open controller) (fun () ->
      if not (Hashtbl.mem controller.marks id) then Ok false
      else begin
        Hashtbl.remove controller.marks id;
        Hashtbl.remove controller.metadata id;
        Ok true
      end)

let get controller id = Result.bind (ensure_open controller) (fun () -> Ok (Hashtbl.find_opt controller.marks id))
let all controller = Result.bind (ensure_open controller) (fun () -> Ok (current_marks controller))
let virtual_marks controller = Result.bind (all controller) (fun marks -> Ok (List.filter (fun (mark : extmark) -> mark.virtual_) marks))
let at_offset controller offset = Result.bind (all controller) (fun marks -> Ok (List.filter (fun (mark : extmark) -> offset >= mark.start && offset < mark.end_) marks))
let all_for_type_id controller type_id = Result.bind (all controller) (fun marks -> Ok (List.filter (fun (mark : extmark) -> Int.equal mark.type_id type_id) marks))
let clear controller = Result.bind (ensure_open controller) (fun () -> Hashtbl.clear controller.marks; Hashtbl.clear controller.metadata; Ok ())

let register_type controller name =
  Result.bind (ensure_open controller) (fun () ->
      match Hashtbl.find_opt controller.types_by_name name with
      | Some id -> Ok id
      | None ->
          let id = controller.next_type_id in
          controller.next_type_id <- id + 1;
          Hashtbl.add controller.types_by_name name id;
          Hashtbl.add controller.names_by_type id name;
          Ok id)

let type_id controller name = Result.bind (ensure_open controller) (fun () -> Ok (Hashtbl.find_opt controller.types_by_name name))
let type_name controller id = Result.bind (ensure_open controller) (fun () -> Ok (Hashtbl.find_opt controller.names_by_type id))
let metadata controller id = Result.bind (ensure_open controller) (fun () -> Ok (Hashtbl.find_opt controller.metadata id))

let restore controller marks next_id =
  Hashtbl.clear controller.marks;
  List.iter (fun (mark : extmark) -> Hashtbl.replace controller.marks mark.id mark) marks;
  controller.next_id <- next_id
let save_snapshot controller =
  Result.bind (ensure_open controller) (fun () -> Extmarks_history.save_snapshot controller.history (current_marks controller) ~next_id:controller.next_id; Ok ())

let undo controller =
  Result.bind (ensure_open controller) (fun () ->
      match Extmarks_history.undo controller.history with
      | None -> Ok false
      | Some snapshot ->
          Extmarks_history.push_redo controller.history { Extmarks_history.extmarks = current_marks controller; next_id = controller.next_id };
          restore controller snapshot.extmarks snapshot.next_id;
          Ok true)

let redo controller =
  Result.bind (ensure_open controller) (fun () ->
      match Extmarks_history.redo controller.history with
      | None -> Ok false
      | Some snapshot ->
          Extmarks_history.push_undo controller.history { Extmarks_history.extmarks = current_marks controller; next_id = controller.next_id };
          restore controller snapshot.extmarks snapshot.next_id;
          Ok true)

let can_undo controller = Result.bind (ensure_open controller) (fun () -> Ok (Extmarks_history.can_undo controller.history))
let can_redo controller = Result.bind (ensure_open controller) (fun () -> Ok (Extmarks_history.can_redo controller.history))

let destroy controller =
  if not controller.destroyed then begin
    controller.destroyed <- true;
    Hashtbl.clear controller.marks;
    Hashtbl.clear controller.metadata;
    Extmarks_history.clear controller.history
  end
