let none = 0
let bold = 1 lsl 0
let dim = 1 lsl 1
let italic = 1 lsl 2
let underline = 1 lsl 3
let blink = 1 lsl 4
let inverse = 1 lsl 5
let hidden = 1 lsl 6
let strikethrough = 1 lsl 7

let of_flags ?(bold = false) ?(dim = false) ?(italic = false)
    ?(underline = false) ?(blink = false) ?(inverse = false)
    ?(hidden = false) ?(strikethrough = false) () =
  let result = ref none in
  if bold then result := !result lor (1 lsl 0);
  if dim then result := !result lor (1 lsl 1);
  if italic then result := !result lor (1 lsl 2);
  if underline then result := !result lor (1 lsl 3);
  if blink then result := !result lor (1 lsl 4);
  if inverse then result := !result lor (1 lsl 5);
  if hidden then result := !result lor (1 lsl 6);
  if strikethrough then result := !result lor (1 lsl 7);
  !result

let base attributes = attributes land 0xff
