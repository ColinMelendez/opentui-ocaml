type style_definition = {
  fg : Lib.Rgba.t option;
  bg : Lib.Rgba.t option;
  bold : bool option;
  italic : bool option;
  underline : bool option;
  dim : bool option;
}

type style_definition_input = {
  fg : Lib.Rgba.t option;
  bg : Lib.Rgba.t option;
  bold : bool option;
  italic : bool option;
  underline : bool option;
  dim : bool option;
}
type merged_style = { fg : Lib.Rgba.t option; bg : Lib.Rgba.t option; attributes : int }

type theme_token = {
  foreground : Lib.Rgba.t option;
  background : Lib.Rgba.t option;
  bold : bool option;
  italic : bool option;
  underline : bool option;
  dim : bool option;
}

type theme_token_style = {
  scope : string list;
  style : theme_token;
}

type t = {
  mutable next_id : int;
  definitions : (string, style_definition) Hashtbl.t;
  ids : (string, int) Hashtbl.t;
  mutable merged_cache : (string * merged_style) list;
  mutable destroyed : bool;
  native : Opentui_raw.Syntax_style.t option;
}

let create () =
  {
    next_id = 0;
    definitions = Hashtbl.create 16;
    ids = Hashtbl.create 16;
    merged_cache = [];
    destroyed = false;
    native = Result.to_option (Opentui_raw.Syntax_style.create ());
  }

let ensure_open style = not style.destroyed

let raw_color color =
  match Lib.Rgba.to_color color with
  | Error _ -> None
  | Ok value ->
      Some
        (Opentui_raw.Color.Private.to_native (Color.Private.to_raw value))

let native_register style name (definition : style_definition) =
  let fg = Option.bind definition.fg raw_color in
  let bg = Option.bind definition.bg raw_color in
  match style.native with
  | Some native ->
      ignore
        (Opentui_raw.Syntax_style.register_style native ~name ~fg ~bg
           ~attributes:(Int32.of_int
                          (Lib.Text_attributes.of_flags
                             ~bold:(Option.value definition.bold ~default:false)
                             ~italic:(Option.value definition.italic ~default:false)
                             ~underline:(Option.value definition.underline ~default:false)
                             ~dim:(Option.value definition.dim ~default:false)
                             ())));
  | None -> ()

let convert_theme_to_styles (theme : theme_token_style list) : (string * style_definition) list =
  List.concat_map
    (fun token ->
      let definition : style_definition =
        {
          fg = token.style.foreground;
          bg = token.style.background;
          bold = token.style.bold;
          italic = token.style.italic;
          underline = token.style.underline;
          dim = token.style.dim;
        }
      in
      List.map (fun scope -> scope, definition) token.scope)
    theme

let register_style style name (definition : style_definition_input) =
  if not (ensure_open style) then invalid_arg "register_style on destroyed syntax style";
  let definition : style_definition =
    {
      fg = definition.fg;
      bg = definition.bg;
      bold = definition.bold;
      italic = definition.italic;
      underline = definition.underline;
      dim = definition.dim;
    }
  in
  let id =
    match Hashtbl.find_opt style.ids name with
    | Some id -> id
    | None ->
        let id = style.next_id in
        style.next_id <- id + 1;
        Hashtbl.add style.ids name id;
        id
  in
  Hashtbl.replace style.definitions name definition;
  native_register style name definition;
  style.merged_cache <- [];
  id

let from_styles definitions =
  let style = create () in
  List.iter (fun (name, definition) -> ignore (register_style style name definition)) definitions;
  style

let from_theme theme =
  let definitions = convert_theme_to_styles theme in
  let inputs =
    List.map
      (fun (name, (definition : style_definition)) ->
        ( name,
          {
            fg = definition.fg;
            bg = definition.bg;
            bold = definition.bold;
            italic = definition.italic;
            underline = definition.underline;
            dim = definition.dim;
          } ))
      definitions
  in
  from_styles inputs

let resolve_style_id style name =
  if not (ensure_open style) then None else Hashtbl.find_opt style.ids name

let get_style_id style name =
  match resolve_style_id style name with
  | Some id -> Some id
  | None ->
      (match String.index_opt name '.' with
      | None -> None
      | Some separator -> resolve_style_id style (String.sub name 0 separator))

let style_count style = if ensure_open style then Hashtbl.length style.ids else 0

let get_style style name =
  if not (ensure_open style) then None
  else
    match Hashtbl.find_opt style.definitions name with
    | Some definition -> Some definition
    | None ->
        (match String.index_opt name '.' with
        | None -> None
        | Some separator -> Hashtbl.find_opt style.definitions (String.sub name 0 separator))

let attribute_value value = Option.value value ~default:false

let merge_styles style names =
  if not (ensure_open style) then { fg = None; bg = None; attributes = 0 }
  else
    let key = String.concat ":" names in
    match List.assoc_opt key style.merged_cache with
    | Some merged -> merged
    | None ->
        let fg = ref None in
        let bg = ref None in
        let bold = ref None in
        let italic = ref None in
        let underline = ref None in
        let dim = ref None in
        List.iter
          (fun name ->
            match get_style style name with
            | None -> ()
            | Some definition ->
                (match definition.fg with Some value -> fg := Some value | None -> ());
                (match definition.bg with Some value -> bg := Some value | None -> ());
                (match definition.bold with Some value -> bold := Some value | None -> ());
                (match definition.italic with Some value -> italic := Some value | None -> ());
                (match definition.underline with Some value -> underline := Some value | None -> ());
                (match definition.dim with Some value -> dim := Some value | None -> ()))
          names;
        let merged =
          {
            fg = !fg;
            bg = !bg;
            attributes =
              Lib.Text_attributes.of_flags ~bold:(attribute_value !bold)
                ~italic:(attribute_value !italic) ~underline:(attribute_value !underline)
                ~dim:(attribute_value !dim) ();
          }
        in
        style.merged_cache <- (key, merged) :: style.merged_cache;
        merged

let clear_cache style = style.merged_cache <- []
let cache_size style = List.length style.merged_cache

let all_styles style =
  if not (ensure_open style) then [] else Hashtbl.to_seq style.definitions |> List.of_seq

let registered_names style =
  if not (ensure_open style) then [] else Hashtbl.to_seq_keys style.ids |> List.of_seq

let destroy style =
  if not style.destroyed then begin
    style.destroyed <- true;
    Hashtbl.clear style.definitions;
    Hashtbl.clear style.ids;
    style.merged_cache <- [];
    Option.iter (fun native -> ignore (Opentui_raw.Syntax_style.close native)) style.native
  end

let is_destroyed style = style.destroyed

module Private = struct
  let native style = style.native
end
