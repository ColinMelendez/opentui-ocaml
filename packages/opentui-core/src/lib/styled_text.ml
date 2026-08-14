type chunk = {
  text : string;
  fg : Color.t option;
  bg : Color.t option;
  attributes : int;
  link : string option;
}

type t = chunk list

let chunk ?fg ?bg ?(attributes = 0) ?link text =
  { text; fg; bg; attributes; link }

let create chunks = chunks
let of_string text = [ chunk text ]
let chunks text = text

let plain_text text =
  String.concat "" (List.map (fun chunk -> chunk.text) text)
