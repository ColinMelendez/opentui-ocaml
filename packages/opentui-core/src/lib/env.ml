type value_type = String | Boolean | Number

type value = Text of string | Bool of bool | Number of float

type definition = {
  name : string;
  description : string;
  default : value option;
  required : bool;
  value_type : value_type;
}

type error =
  | Invalid_name
  | Duplicate_definition of string
  | Unregistered of string
  | Missing_required of string
  | Invalid_number of string

type t = {
  get : string -> string option;
  mutable entries : definition list;
  mutable cache : (string * (value option, error) result) list;
}

let create ~get () = { get; entries = []; cache = [] }

let valid_name name =
  String.length name > 0
  &&
  let valid = ref true in
  for index = 0 to String.length name - 1 do
    let character = String.get name index in
    if not (Char.equal character '_' || Char.equal character '-'
            || Char.equal character '.'
            || (Char.code character >= Char.code 'A'
                && Char.code character <= Char.code 'Z')
            || (Char.code character >= Char.code 'a'
                && Char.code character <= Char.code 'z')
            || (Char.code character >= Char.code '0'
                && Char.code character <= Char.code '9'))
    then valid := false
  done;
  !valid

let same_value left right =
  match left, right with
  | None, None -> true
  | Some (Text left), Some (Text right) -> String.equal left right
  | Some (Bool left), Some (Bool right) -> Bool.equal left right
  | Some (Number left), Some (Number right) -> Float.equal left right
  | None, Some _ | Some _, None
  | Some (Text _), Some (Bool _)
  | Some (Text _), Some (Number _)
  | Some (Bool _), Some (Text _)
  | Some (Bool _), Some (Number _)
  | Some (Number _), Some (Text _)
  | Some (Number _), Some (Bool _) -> false

let same_definition left right =
  String.equal left.name right.name
  && String.equal left.description right.description
  && same_value left.default right.default
  && Bool.equal left.required right.required
  &&
  match left.value_type, right.value_type with
  | String, String | Boolean, Boolean | Number, Number -> true
  | String, Boolean | String, Number | Boolean, String | Boolean, Number
  | Number, String | Number, Boolean -> false

let register owner definition =
  if not (valid_name definition.name) then Error Invalid_name
  else
    match List.find_opt (fun entry -> String.equal entry.name definition.name) owner.entries with
    | Some current when same_definition current definition -> Ok ()
    | Some _ -> Error (Duplicate_definition definition.name)
    | None ->
        owner.entries <- owner.entries @ [ definition ];
        owner.cache <- [];
        Ok ()

let definition owner name =
  List.find_opt (fun entry -> String.equal entry.name name) owner.entries

let has owner name = Option.is_some (definition owner name)

let parse_boolean value =
  match String.lowercase_ascii value with
  | "true" | "1" | "on" | "yes" -> Ok (Bool true)
  | "false" | "0" | "off" | "no" -> Ok (Bool false)
  | _ -> Ok (Bool false)

let parse definition raw =
  match definition.value_type with
  | String -> Ok (Text raw)
  | Boolean -> parse_boolean raw
  | Number ->
      (match float_of_string_opt raw with
      | Some value when Float.is_finite value -> Ok (Number value)
      | Some _ | None -> Error (Invalid_number definition.name))

let value owner name =
  match List.find_opt (fun (entry, _) -> String.equal entry name) owner.cache with
  | Some (_, result) -> result
  | None ->
      let result =
        match definition owner name with
        | None -> Error (Unregistered name)
        | Some definition ->
            (match owner.get name, definition.default with
            | None, Some default -> Ok (Some default)
            | None, None when not definition.required -> Ok None
            | None, None -> Error (Missing_required name)
            | Some raw, _ -> Result.map (fun parsed -> Some parsed) (parse definition raw))
      in
      owner.cache <- (name, result) :: owner.cache;
      result

let clear_cache owner = owner.cache <- []
let definitions owner = owner.entries

let message = function
  | Invalid_name -> "environment variable name is invalid"
  | Duplicate_definition name -> "environment variable already registered: " ^ name
  | Unregistered name -> "environment variable is not registered: " ^ name
  | Missing_required name -> "required environment variable is missing: " ^ name
  | Invalid_number name -> "environment variable is not a finite number: " ^ name

let type_name = function String -> "string" | Boolean -> "boolean" | Number -> "number"

let markdown owner =
  if List.is_empty owner.entries then
    "# Environment Variables\n\nNo environment variables registered.\n"
  else
    let default_text = function
      | Some (Text value) -> "\"" ^ value ^ "\""
      | Some (Bool value) -> string_of_bool value
      | Some (Number value) -> string_of_float value
      | None -> "*Required*"
    in
    let render entry =
      let default_line =
        match entry.default, entry.required with
        | Some value, _ -> "**Default:** `" ^ default_text (Some value) ^ "`\n"
        | None, false -> "**Default:** *unset*\n"
        | None, true -> "**Default:** *Required*\n"
      in
      "## " ^ entry.name ^ "\n\n"
      ^ entry.description ^ "\n\n"
      ^ "**Type:** `" ^ type_name entry.value_type ^ "`  \n"
      ^ default_line ^ "\n"
    in
    "# Environment Variables\n\n"
    ^ String.concat "" (List.map render owner.entries)

let colored owner =
  if List.is_empty owner.entries then
    "\027[1;36mEnvironment Variables\027[0m\n\nNo environment variables registered.\n"
  else
    let default_text = function
      | Some (Text value) -> "\"" ^ value ^ "\""
      | Some (Bool value) -> string_of_bool value
      | Some (Number value) -> string_of_float value
      | None -> ""
    in
    let render entry =
      let default_value, default_color =
        match entry.default, entry.required with
        | Some value, _ -> default_text (Some value), "35"
        | None, false -> "unset", "35"
        | None, true -> "Required", "31"
      in
      "\027[1;33m" ^ entry.name ^ "\027[0m\n"
      ^ entry.description ^ "\n"
      ^ "\027[32mType:\027[0m \027[36m" ^ type_name entry.value_type
      ^ "\027[0m\n"
      ^ "\027[32mDefault:\027[0m \027[" ^ default_color ^ "m"
      ^ default_value ^ "\027[0m\n\n"
    in
    "\027[1;36mEnvironment Variables\027[0m\n\n"
    ^ String.concat "" (List.map render owner.entries)
