type kind = Text | Binary | Unknown

type metadata = {
  mime_type : string option;
  kind : kind option;
}

let decode bytes = Bytes.to_string bytes

let is_csi_final code = code >= 0x40 && code <= 0x7e

let strip_ansi text =
  let length = String.length text in
  let output = Stdlib.Buffer.create length in
  let index = ref 0 in
  while !index < length do
    let code = Char.code (String.get text !index) in
    if code <> 0x1b then begin
      Stdlib.Buffer.add_char output (String.get text !index);
      incr index
    end else if !index + 1 >= length then
      incr index
    else begin
      let next = Char.code (String.get text (!index + 1)) in
      if next = Char.code '[' then begin
        index := !index + 2;
        while !index < length && not (is_csi_final (Char.code (String.get text !index))) do
          incr index
        done;
        if !index < length then incr index
      end else if next = Char.code ']' then begin
        index := !index + 2;
        let finished = ref false in
        while !index < length && not !finished do
          let current = Char.code (String.get text !index) in
          if current = 7 then begin
            incr index;
            finished := true
          end else if current = 0x1b && !index + 1 < length
                    && Char.code (String.get text (!index + 1)) = Char.code '\\' then begin
            index := !index + 2;
            finished := true
          end else incr index
        done
      end else
        index := !index + 2
    end
  done;
  Stdlib.Buffer.contents output
