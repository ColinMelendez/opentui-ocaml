(** Minimal PNG writer for renderer screenshots: 8-bit RGBA, no filtering,
    stored (uncompressed) deflate blocks. The audited Zig ABI exposes PNG
    encoding only inside native Image state with no byte extraction, so
    the three package owns emission; correctness is pinned by decoding
    through Opentui_core.Image and comparing pixels. *)

let crc_table = lazy (Array.init 256 (fun n ->
    let c = ref n in
    for _ = 0 to 7 do
      if Int.equal (!c land 1) 1 then c := 0xedb88320 lxor (!c lsr 1)
      else c := !c lsr 1
    done;
    !c))

let crc32 data start length =
  let table = Lazy.force crc_table in
  let c = ref 0xffffffff in
  for i = start to start + length - 1 do
    let index = (!c lxor Char.code data.[i]) land 0xff in
    c := table.(index) lxor (!c lsr 8)
  done;
  Int32.lognot (Int32.of_int !c)

let chunk kind payload =
  let length = String.length payload in
  let out = Bytes.create (12 + length) in
  Bytes.set_int32_be out 0 (Int32.of_int length);
  Bytes.blit_string kind 0 out 4 4;
  Bytes.blit_string payload 0 out 8 length;
  let crc_source = Bytes.create (4 + length) in
  Bytes.blit_string kind 0 crc_source 0 4;
  Bytes.blit_string payload 0 crc_source 4 length;
  Bytes.set_int32_be out (8 + length)
    (crc32 (Bytes.to_string crc_source) 0 (4 + length));
  Bytes.to_string out

let adler32 data start length =
  let modul = 65521 in
  let a = ref 1 and b = ref 0 in
  for i = start to start + length - 1 do
    a := (!a + Char.code data.[i]) mod modul;
    b := (!b + !a) mod modul
  done;
  let combined = (!b lsl 16) lor !a in
  let out = Bytes.create 4 in
  for i = 0 to 3 do
    Bytes.set out i (Char.chr ((combined lsr ((3 - i) * 8)) land 0xff))
  done;
  Bytes.to_string out

(* zlib stream over stored deflate blocks: two header bytes, then each
   block as [final|type=00][len lo hi][nlen lo hi][raw], then Adler-32. *)
let zlib_stored raw =
  let total = String.length raw in
  let block_max = 65535 in
  let block_count = max 1 ((total + block_max - 1) / block_max) in
  let out = Buffer.create (total + (block_count * 5) + 6) in
  if Int.equal total 0 then begin
    (* An empty payload still needs one empty final stored block. *)
    Buffer.add_char out '\x78';
    Buffer.add_char out '\x01';
    Buffer.add_char out '\x01';
    Buffer.add_char out '\x00';
    Buffer.add_char out '\x00';
    Buffer.add_char out '\xff';
    Buffer.add_char out '\xff';
    Buffer.add_string out (adler32 raw 0 total);
    Buffer.contents out
  end
  else begin
  Buffer.add_char out '\x78';
  Buffer.add_char out '\x01';
  let rec emit offset =
    if offset < total then begin
      let remaining = total - offset in
      let len = min remaining block_max in
      let is_final = if Int.equal (offset + len) total then 1 else 0 in
      Buffer.add_char out (Char.chr is_final);
      Buffer.add_char out (Char.chr (len land 0xff));
      Buffer.add_char out (Char.chr (len lsr 8));
      Buffer.add_char out (Char.chr ((lnot len) land 0xff));
      Buffer.add_char out (Char.chr (((lnot len) lsr 8) land 0xff));
      Buffer.add_substring out raw offset len;
      emit (offset + len)
    end
  in
  emit 0;
  Buffer.add_string out (adler32 raw 0 total);
  Buffer.contents out
  end

(* Raw RGBA rows must be prefixed with one filter byte each (type 0). *)
let filter_rows data ~width ~height =
  let stride = width * 4 in
  let out = Bytes.create ((stride + 1) * height) in
  for y = 0 to height - 1 do
    Bytes.set out (y * (stride + 1)) '\000';
    Bytes.blit_string data (y * stride) out ((y * (stride + 1)) + 1) stride
  done;
  Bytes.to_string out

let encode_rgba data ~width ~height =
  (* IHDR: width, height, bit depth 8, color type 6 (RGBA),
     compression 0, filter 0, interlace 0. *)
  let ihdr = Bytes.create 13 in
  Bytes.set_int32_be ihdr 0 (Int32.of_int width);
  Bytes.set_int32_be ihdr 4 (Int32.of_int height);
  Bytes.set ihdr 8 '\008';
  Bytes.set ihdr 9 '\006';
  Bytes.set ihdr 10 '\000';
  Bytes.set ihdr 11 '\000';
  Bytes.set ihdr 12 '\000';
  let filtered = filter_rows data ~width ~height in
  let idat = zlib_stored filtered in
  "\x89PNG\r\n\x1a\n"
  ^ chunk "IHDR" (Bytes.to_string ihdr)
  ^ chunk "IDAT" idat
  ^ chunk "IEND" ""
