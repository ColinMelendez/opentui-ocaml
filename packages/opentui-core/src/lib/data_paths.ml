type paths = {
  global_config_path : string;
  global_config_file : string;
  local_config_file : string;
  global_data_path : string;
}

type listener = { id : int; callback : paths -> unit; subscription : Event_subscription.t }

type t = {
  home : string;
  cwd : string;
  getenv : string -> string option;
  mutable name : string;
  mutable cached : paths option;
  mutable next_id : int;
  mutable listeners : listener list;
}

let create ?(app_name = "opentui") ~home ~cwd ~getenv () =
  match Validate_dir_name.validate app_name with
  | Error error -> Error error
  | Ok () -> Ok { home; cwd; getenv; name = app_name; cached = None; next_id = 1; listeners = [] }

let app_name owner = owner.name

let base getenv key fallback =
  match getenv key with
  | Some value when String.length value > 0 -> value
  | Some _ | None -> fallback

let compute owner =
  let config_base = base owner.getenv "XDG_CONFIG_HOME" (Filename.concat owner.home ".config") in
  let data_base = base owner.getenv "XDG_DATA_HOME" (Filename.concat owner.home ".local/share") in
  let global_config_path = Filename.concat config_base owner.name in
  {
    global_config_path;
    global_config_file = Filename.concat global_config_path "init.ts";
    local_config_file = Filename.concat owner.cwd ("." ^ owner.name ^ ".ts");
    global_data_path = Filename.concat data_base owner.name;
  }

let paths owner =
  match owner.cached with
  | Some value -> value
  | None ->
      let value = compute owner in
      owner.cached <- Some value;
      value

let set_app_name owner name =
  match Validate_dir_name.validate name with
  | Error error -> Error error
  | Ok () ->
      if not (String.equal name owner.name) then begin
        owner.name <- name;
        owner.cached <- None;
        let current = paths owner in
        List.iter (fun listener -> listener.callback current) owner.listeners
      end;
      Ok ()

let on_paths_changed owner callback =
  let id = owner.next_id in
  owner.next_id <- id + 1;
  let subscription_ref = ref None in
  let subscription =
    Event_subscription.Private.create (fun () ->
        match !subscription_ref with
        | None -> ()
        | Some _ -> owner.listeners <- List.filter (fun listener -> not (Int.equal listener.id id)) owner.listeners)
  in
  subscription_ref := Some subscription;
  owner.listeners <- { id; callback; subscription } :: owner.listeners;
  subscription
