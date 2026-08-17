module Types = Tree_sitter_types

type t = {
  parsers : (string, Types.parser) Hashtbl.t;
  mutable destroyed : bool;
}

let create () =
  { parsers = Hashtbl.create 16; destroyed = false }

let valid_name value = String.length value > 0 && not (String.contains value ' ')

let register_parser client (parser : Types.parser) =
  if client.destroyed then Error (Types.Failed "tree-sitter client is destroyed")
  else if not (valid_name parser.Types.filetype)
          || List.exists (fun alias -> not (valid_name alias)) parser.Types.aliases
  then Error (Types.Failed "parser filetype and aliases must be non-empty names")
  else begin
    List.iter (fun name -> Hashtbl.replace client.parsers (String.lowercase_ascii name) parser)
      (parser.Types.filetype :: parser.Types.aliases);
    Ok ()
  end

let remove_parser client name =
  Hashtbl.remove client.parsers (String.lowercase_ascii name)

let resolve_parser client name =
  if client.destroyed then None
  else Hashtbl.find_opt client.parsers (String.lowercase_ascii name)

let parser_names client =
  if client.destroyed then []
  else Hashtbl.to_seq_keys client.parsers |> List.of_seq

let clear client = Hashtbl.clear client.parsers

let destroy client =
  if not client.destroyed then begin
    clear client;
    client.destroyed <- true
  end

let is_destroyed client = client.destroyed

let run_parser (parser : Types.parser) ~content = parser.Types.highlight content
