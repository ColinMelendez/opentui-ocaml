type 'a binding = {
  name : string;
  ctrl : bool;
  shift : bool;
  meta : bool;
  super : bool;
  action : 'a;
}

type aliases = (string, string) Hashtbl.t
type 'a t = { mutable aliases : aliases; mutable bindings : 'a binding list }

let default_aliases () =
  let aliases = Hashtbl.create 32 in
  List.iter
    (fun (from, to_) -> Hashtbl.replace aliases from to_)
    [
      "enter", "return";
      "esc", "escape";
      "kp0", "0";
      "kp1", "1";
      "kp2", "2";
      "kp3", "3";
      "kp4", "4";
      "kp5", "5";
      "kp6", "6";
      "kp7", "7";
      "kp8", "8";
      "kp9", "9";
      "kpdecimal", ".";
      "kpdivide", "/";
      "kpmultiply", "*";
      "kpminus", "-";
      "kpplus", "+";
      "kpenter", "enter";
      "kpequal", "=";
      "kpseparator", ",";
      "kpleft", "left";
      "kpright", "right";
      "kpup", "up";
      "kpdown", "down";
      "kppageup", "pageup";
      "kppagedown", "pagedown";
      "kphome", "home";
      "kpend", "end";
      "kpinsert", "insert";
      "kpdelete", "delete";
    ];
  aliases

let merge_aliases aliases entries =
  let result = Hashtbl.copy aliases in
  List.iter (fun (from, to_) -> Hashtbl.replace result from to_) entries;
  result

let binding ?(ctrl = false) ?(shift = false) ?(meta = false) ?(super = false)
    ~name ~action () =
  { name; ctrl; shift; meta; super; action }

let create ?(aliases = default_aliases ()) bindings =
  { aliases = Hashtbl.copy aliases; bindings }

let set_bindings keybindings bindings = keybindings.bindings <- bindings
let set_aliases keybindings aliases = keybindings.aliases <- Hashtbl.copy aliases

let named_name = function
  | Key_decoder.Named named -> Key_decoder.named_key_name named
  | Key_decoder.Character bytes ->
      let value = Bytes.to_string bytes in
      if String.length value = 1 then String.lowercase_ascii value else value

let name event = named_name (Key_handler.key event)

let modifier_key ~name ~ctrl ~shift ~meta ~super =
  String.concat ":"
    [ name; if ctrl then "1" else "0"; if shift then "1" else "0";
      if meta then "1" else "0"; if super then "1" else "0" ]

let rec resolve_alias aliases value depth =
  if depth = 0 then value
  else
    match Hashtbl.find_opt aliases value with
    | None -> value
    | Some next when String.equal next value -> value
    | Some next -> resolve_alias aliases next (depth - 1)

let binding_keys keybindings binding =
  let direct =
    modifier_key ~name:binding.name ~ctrl:binding.ctrl ~shift:binding.shift
      ~meta:binding.meta ~super:binding.super
  in
  let normalized = resolve_alias keybindings.aliases binding.name 8 in
  let aliased =
    modifier_key ~name:normalized ~ctrl:binding.ctrl ~shift:binding.shift
      ~meta:binding.meta ~super:binding.super
  in
  if String.equal direct aliased then [ direct ] else [ direct; aliased ]

let set_binding table key value = Hashtbl.replace table key value

let action keybindings event =
  let modifiers = Key_handler.key_modifiers event in
  let key_name = name event in
  let key =
    modifier_key ~name:key_name ~ctrl:modifiers.ctrl ~shift:modifiers.shift
      ~meta:modifiers.meta ~super:false
  in
  let rec find = function
    | [] -> None
    | binding :: rest ->
        let keys = binding_keys keybindings binding in
        if List.exists (String.equal key) keys then Some binding.action
        else find rest
  in
  find keybindings.bindings
