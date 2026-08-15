type line_kind = Context | Added | Removed | Meta
type line = { kind : line_kind; text : string; old_number : int option; new_number : int option }
type hunk = { old_start : int; old_count : int; new_start : int; new_count : int; heading : string; lines : line list }
type patch = { old_file : string option; new_file : string option; hunks : hunk list }
type parse_error = Empty | Malformed of { line : int; message : string }

let starts_with source prefix =
  String.length source >= String.length prefix
  && String.equal (String.sub source 0 (String.length prefix)) prefix

let parse_nat source start finish =
  if start >= finish then None
  else
    let value = ref 0 in
    let valid = ref true in
    for index = start to finish - 1 do
      let code = Char.code (String.get source index) in
      if code < Char.code '0' || code > Char.code '9' then valid := false
      else value := (!value * 10) + code - Char.code '0'
    done;
    if !valid then Some !value else None

let find_string source start needle =
  let result = ref None in
  let index = ref start in
  let last = String.length source - String.length needle in
  while !index <= last && Option.is_none !result do
    if String.equal (String.sub source !index (String.length needle)) needle then result := Some !index;
    incr index
  done;
  !result

let parse_range source start finish =
  let comma = String.index_from_opt source start ',' in
  let limit = Option.value comma ~default:finish in
  match parse_nat source start limit with
  | None -> None, None
  | Some first ->
      let count =
        match comma with
        | None -> 1
        | Some comma when comma < finish -> Option.value (parse_nat source (comma + 1) finish) ~default:1
        | Some _ -> 1
      in
      Some first, Some count

let parse_header line line_number =
  match find_string line 0 "@@" with
  | None -> Error (Malformed { line = line_number; message = "missing hunk marker" })
  | Some start_marker ->
      (match find_string line (start_marker + 2) "@@" with
      | None -> Error (Malformed { line = line_number; message = "unterminated hunk header" })
      | Some end_marker ->
          let header = String.sub line (start_marker + 2) (end_marker - start_marker - 2) |> String.trim in
          let words = String.split_on_char ' ' header |> List.filter (fun value -> String.length value > 0) in
          match words with
          | old_range :: new_range :: rest when String.length old_range > 1 && String.length new_range > 1 && String.get old_range 0 = '-' && String.get new_range 0 = '+' ->
              let old_start, old_count = parse_range old_range 1 (String.length old_range) in
              let new_start, new_count = parse_range new_range 1 (String.length new_range) in
              (match old_start, old_count, new_start, new_count with
              | Some old_start, Some old_count, Some new_start, Some new_count ->
                  Ok (old_start, old_count, new_start, new_count, String.concat " " rest)
              | _ -> Error (Malformed { line = line_number; message = "invalid hunk range" }))
          | _ -> Error (Malformed { line = line_number; message = "invalid hunk header" }))

let classify_line raw old_number new_number =
  if String.length raw = 0 then Error "diff body line has no prefix"
  else
    match String.get raw 0 with
    | '+' -> Ok { kind = Added; text = String.sub raw 1 (String.length raw - 1); old_number = None; new_number }
    | '-' -> Ok { kind = Removed; text = String.sub raw 1 (String.length raw - 1); old_number; new_number = None }
    | ' ' -> Ok { kind = Context; text = String.sub raw 1 (String.length raw - 1); old_number; new_number }
    | '\\' -> Ok { kind = Meta; text = raw; old_number = None; new_number = None }
    | _ -> Error "diff body line has an unknown prefix"

let parse content =
  if String.length content = 0 then Error Empty
  else
    let split_lines = String.split_on_char '\n' content in
    let split_lines =
      match List.rev split_lines with
      | "" :: rest -> List.rev rest
      | _ -> split_lines
    in
    let lines = Array.of_list split_lines in
    let old_file = ref None in
    let new_file = ref None in
    for index = 0 to Array.length lines - 1 do
      let line = lines.(index) in
      if starts_with line "--- " then old_file := Some (String.sub line 4 (String.length line - 4))
      else if starts_with line "+++ " then new_file := Some (String.sub line 4 (String.length line - 4))
    done;
    let hunks = ref [] in
    let index = ref 0 in
    let failure = ref None in
    while !index < Array.length lines && Option.is_none !failure do
      if starts_with lines.(!index) "@@" then begin
        match parse_header lines.(!index) (!index + 1) with
        | Error error -> failure := Some error
        | Ok (old_start, old_count, new_start, new_count, heading) ->
            let old_line = ref old_start in
            let new_line = ref new_start in
            let body = ref [] in
            incr index;
            while !index < Array.length lines
                  && not (starts_with lines.(!index) "@@")
                  && Option.is_none !failure do
              (match classify_line lines.(!index) (Some !old_line) (Some !new_line) with
              | Error message ->
                  failure := Some (Malformed { line = !index + 1; message })
              | Ok parsed ->
                  body := parsed :: !body;
                  (match parsed.kind with
                  | Context -> incr old_line; incr new_line
                  | Added -> incr new_line
                  | Removed -> incr old_line
                  | Meta -> ());
                  incr index)
            done;
            if Option.is_none !failure then begin
              let body = List.rev !body in
              let old_seen, new_seen =
                List.fold_left
                  (fun (old_seen, new_seen) line ->
                    match line.kind with
                    | Context -> old_seen + 1, new_seen + 1
                    | Added -> old_seen, new_seen + 1
                    | Removed -> old_seen + 1, new_seen
                    | Meta -> old_seen, new_seen)
                  (0, 0) body
              in
              if not (Int.equal old_seen old_count && Int.equal new_seen new_count) then
                failure :=
                  Some
                    (Malformed
                       {
                         line = !index;
                         message = "hunk line count does not match its header";
                       })
              else
                hunks := { old_start; old_count; new_start; new_count; heading; lines = body } :: !hunks
            end
      end else incr index
    done;
    match !failure, List.rev !hunks with
    | Some error, _ -> Error error
    | None, [] -> Error (Malformed { line = 1; message = "diff contains no hunks" })
    | None, hunks -> Ok { old_file = !old_file; new_file = !new_file; hunks }

let unified_lines patch = List.concat_map (fun hunk -> hunk.lines) patch.hunks
let line_text line = line.text
let is_context line = match line.kind with Context -> true | Added | Removed | Meta -> false
let is_added line = match line.kind with Added -> true | Context | Removed | Meta -> false
let is_removed line = match line.kind with Removed -> true | Context | Added | Meta -> false
