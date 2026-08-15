let create_text_attributes ?(bold = false) ?(italic = false)
    ?(underline = false) ?(dim = false) ?(blink = false) ?(inverse = false)
    ?(hidden = false) ?(strikethrough = false) () =
  Text_attributes.of_flags ~bold ~italic ~underline ~dim ~blink ~inverse ~hidden
    ~strikethrough ()

let pack_link ~link_id ~attributes =
  let link_id = max 0 (min 0xffffff link_id) in
  (attributes land 0xff) lor (link_id lsl 8)

let unpack_link attributes =
  attributes land 0xff, (attributes lsr 8) land 0xffffff

let visualize_tree ~root ~children ~label =
  let lines = ref [] in
  let stack = ref [ root, "" ] in
  let running = ref true in
  while !running do
    match !stack with
    | [] -> running := false
    | (node, prefix) :: rest ->
        stack := rest;
        lines := (prefix ^ label node) :: !lines;
        let descendants = children node in
        let child_prefix = prefix ^ "  " in
        let reversed = List.rev_map (fun child -> child, child_prefix) descendants in
        stack := reversed @ !stack
  done;
  String.concat "\n" (List.rev !lines)
