type event =
  | Key of {
      key : Key_decoder.key;
      modifiers : Key_decoder.modifiers;
    }
  | Mouse of Mouse_decoder.event
  | Sequence of {
      protocol : Stdin_parser.protocol;
      bytes : bytes;
    }
  | Paste of bytes

type t = { mouse : Mouse_decoder.t }

let create () = { mouse = Mouse_decoder.create () }
let reset decoder = Mouse_decoder.reset decoder.mouse

let decode decoder input =
  match Mouse_decoder.decode decoder.mouse input with
  | Some event -> Mouse event
  | None ->
      (match Key_decoder.decode input with
      | Key_decoder.Key { key; modifiers } -> Key { key; modifiers }
      | Key_decoder.Sequence { protocol; bytes } -> Sequence { protocol; bytes }
      | Key_decoder.Paste bytes -> Paste bytes)
