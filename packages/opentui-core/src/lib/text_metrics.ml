type width_method = Wcwidth | Unicode

type codepoint = {
  byte_start : int;
  byte_end : int;
  code : int;
  width : int;
}

let code value = value.code

let continuation byte = Int.equal (byte land 0xc0) 0x80

let decode source start =
  let length = String.length source in
  let first = Char.code (String.get source start) in
  let one value = value, start + 1 in
  if first < 0x80 then one first
  else if Int.equal (first land 0xe0) 0xc0 && start + 1 < length then
    let second = Char.code (String.get source (start + 1)) in
    if continuation second then
      ( (first land 0x1f) lsl 6 lor (second land 0x3f),
        start + 2 )
    else one 0xfffd
  else if Int.equal (first land 0xf0) 0xe0 && start + 2 < length then
    let second = Char.code (String.get source (start + 1)) in
    let third = Char.code (String.get source (start + 2)) in
    if continuation second && continuation third then
      ( (first land 0x0f) lsl 12 lor (second land 0x3f) lsl 6
        lor (third land 0x3f),
        start + 3 )
    else one 0xfffd
  else if Int.equal (first land 0xf8) 0xf0 && start + 3 < length then
    let second = Char.code (String.get source (start + 1)) in
    let third = Char.code (String.get source (start + 2)) in
    let fourth = Char.code (String.get source (start + 3)) in
    if continuation second && continuation third && continuation fourth then
      ( (first land 0x07) lsl 18 lor (second land 0x3f) lsl 12
        lor (third land 0x3f) lsl 6 lor (fourth land 0x3f),
        start + 4 )
    else one 0xfffd
  else one 0xfffd

let is_wide code =
  (code >= 0x1100 && code <= 0x115f)
  || (code >= 0x2329 && code <= 0x232a)
  || (code >= 0x2e80 && code <= 0xa4cf)
  || (code >= 0xac00 && code <= 0xd7a3)
  || (code >= 0xf900 && code <= 0xfaff)
  || (code >= 0xfe10 && code <= 0xfe19)
  || (code >= 0xfe30 && code <= 0xfe6f)
  || (code >= 0xff01 && code <= 0xff60)
  || (code >= 0xffe0 && code <= 0xffe6)
  || (code >= 0x1f300 && code <= 0x1faff)

(* This is the stable, width-relevant subset of Unicode combining and format
   characters. The native implementation uses Unicode grapheme tables; these
   ranges keep the portable editor from splitting the common combining,
   variation-selector, and ZWJ cases without claiming a second Unicode table. *)
let is_zero_width code =
  (code >= 0x0300 && code <= 0x036f)
  || (code >= 0x0483 && code <= 0x0489)
  || (code >= 0x0591 && code <= 0x05bd)
  || Int.equal code 0x05bf
  || (code >= 0x05c1 && code <= 0x05c2)
  || (code >= 0x05c4 && code <= 0x05c5)
  || Int.equal code 0x05c7
  || (code >= 0x0610 && code <= 0x061a)
  || (code >= 0x064b && code <= 0x065f)
  || Int.equal code 0x0670
  || (code >= 0x06d6 && code <= 0x06dc)
  || (code >= 0x06df && code <= 0x06e4)
  || (code >= 0x06e7 && code <= 0x06e8)
  || (code >= 0x06ea && code <= 0x06ed)
  || Int.equal code 0x0711
  || (code >= 0x0730 && code <= 0x074a)
  || (code >= 0x07a6 && code <= 0x07b0)
  || (code >= 0x0816 && code <= 0x0819)
  || (code >= 0x081b && code <= 0x0823)
  || (code >= 0x0825 && code <= 0x0827)
  || (code >= 0x0829 && code <= 0x082d)
  || (code >= 0x0859 && code <= 0x085f)
  || (code >= 0x08d3 && code <= 0x08e1)
  || (code >= 0x08e3 && code <= 0x08ff)
  || (code >= 0x0900 && code <= 0x0903)
  || (code >= 0x093a && code <= 0x093c)
  || (code >= 0x093e && code <= 0x094d)
  || (code >= 0x0951 && code <= 0x0957)
  || (code >= 0x0962 && code <= 0x0963)
  || (code >= 0x0981 && code <= 0x0983)
  || Int.equal code 0x09bc
  || (code >= 0x09be && code <= 0x09cd)
  || Int.equal code 0x09d7
  || (code >= 0x09e2 && code <= 0x09e3)
  || (code >= 0x0a01 && code <= 0x0a03)
  || Int.equal code 0x0a3c
  || (code >= 0x0a3e && code <= 0x0a4d)
  || (code >= 0x0a51 && code <= 0x0a51)
  || (code >= 0x0a70 && code <= 0x0a71)
  || Int.equal code 0x0a75
  || (code >= 0x0abc && code <= 0x0acd)
  || (code >= 0x0b01 && code <= 0x0b03)
  || Int.equal code 0x0b3c
  || (code >= 0x0b3e && code <= 0x0b4d)
  || (code >= 0x0b56 && code <= 0x0b57)
  || (code >= 0x0b62 && code <= 0x0b63)
  || (code >= 0x0c00 && code <= 0x0c04)
  || (code >= 0x0c3e && code <= 0x0c56)
  || (code >= 0x0c62 && code <= 0x0c63)
  || (code >= 0x0d00 && code <= 0x0d03)
  || (code >= 0x0d3b && code <= 0x0d4d)
  || Int.equal code 0x0d57
  || (code >= 0x0d62 && code <= 0x0d63)
  || Int.equal code 0x0e31
  || (code >= 0x0e34 && code <= 0x0e3a)
  || (code >= 0x0e47 && code <= 0x0e4e)
  || Int.equal code 0x0eb1
  || (code >= 0x0eb4 && code <= 0x0ebc)
  || (code >= 0x0ec8 && code <= 0x0ecd)
  || (code >= 0x0f18 && code <= 0x0f19)
  || (code >= 0x0f35 && code <= 0x0f39)
  || (code >= 0x0f71 && code <= 0x0f84)
  || (code >= 0x0f86 && code <= 0x0f87)
  || (code >= 0x0f8d && code <= 0x0f97)
  || (code >= 0x0f99 && code <= 0x0fbc)
  || Int.equal code 0x0fc6
  || (code >= 0x102d && code <= 0x103e)
  || (code >= 0x1056 && code <= 0x1059)
  || (code >= 0x105e && code <= 0x1060)
  || (code >= 0x1071 && code <= 0x1074)
  || (code >= 0x1082 && code <= 0x1086)
  || Int.equal code 0x108d
  || Int.equal code 0x108f
  || (code >= 0x109a && code <= 0x109d)
  || (code >= 0x135d && code <= 0x135f)
  || (code >= 0x1712 && code <= 0x1714)
  || (code >= 0x1732 && code <= 0x1734)
  || (code >= 0x1752 && code <= 0x1753)
  || (code >= 0x1772 && code <= 0x1773)
  || (code >= 0x17b4 && code <= 0x17d3)
  || Int.equal code 0x17dd
  || (code >= 0x180b && code <= 0x180f)
  || Int.equal code 0x18a9
  || (code >= 0x1ab0 && code <= 0x1aff)
  || (code >= 0x1dc0 && code <= 0x1dff)
  || (code >= 0x200b && code <= 0x200f)
  || (code >= 0x202a && code <= 0x202e)
  || (code >= 0x2060 && code <= 0x2064)
  || (code >= 0x2066 && code <= 0x206f)
  || (code >= 0x20d0 && code <= 0x20ff)
  || (code >= 0x2de0 && code <= 0x2dff)
  || (code >= 0x302a && code <= 0x302f)
  || (code >= 0x3099 && code <= 0x309a)
  || (code >= 0xa66f && code <= 0xa67f)
  || (code >= 0xa69e && code <= 0xa69f)
  || (code >= 0xa6f0 && code <= 0xa6f1)
  || (code >= 0xfb1e && code <= 0xfb1e)
  || (code >= 0xfe00 && code <= 0xfe0f)
  || (code >= 0xfe20 && code <= 0xfe2f)
  || (code >= 0xfff9 && code <= 0xfffb)
  || (code >= 0x101fd && code <= 0x101fd)
  || (code >= 0x102e0 && code <= 0x102e0)
  || (code >= 0x10376 && code <= 0x1037a)
  || (code >= 0x1d167 && code <= 0x1d169)
  || (code >= 0x1d17b && code <= 0x1d182)
  || (code >= 0x1d185 && code <= 0x1d18b)
  || (code >= 0x1d1aa && code <= 0x1d1ad)
  || (code >= 0x1d242 && code <= 0x1d244)
  || (code >= 0x1da00 && code <= 0x1da36)
  || (code >= 0x1e000 && code <= 0x1e02a)
  || (code >= 0x1e130 && code <= 0x1e136)
  || (code >= 0x1e8d0 && code <= 0x1e8d6)
  || (code >= 0x1e944 && code <= 0x1e94a)
  || (code >= 0xe0000 && code <= 0xe0fff)
  || (code >= 0xe0100 && code <= 0xe01ef)

let is_regional_indicator code = code >= 0x1f1e6 && code <= 0x1f1ff

let width ?(tab_width = 2) _width_method code =
  if is_zero_width code then 0
  else if Int.equal code 0 then 0
  else if Int.equal code 0x09 then max 1 tab_width
  else if Int.equal code 0x0a || Int.equal code 0x0d then 1
  else if code < 0x20 || (code >= 0x7f && code < 0xa0) then 0
  else if is_wide code then 2
  else 1

let scan ?(tab_width = 2) width_method source =
  let result = ref [] in
  let cursor = ref 0 in
  while !cursor < String.length source do
    let byte_start = !cursor in
    let code, byte_end = decode source byte_start in
    result :=
      { byte_start; byte_end; code; width = width ~tab_width width_method code }
      :: !result;
    cursor := byte_end
  done;
  let codepoints = Array.of_list (List.rev !result) in
  match width_method with
  | Wcwidth -> codepoints
  | Unicode ->
      if Array.length codepoints = 0 then codepoints
      else begin
        let assign_cluster start finish =
          let cluster_width = ref 0 in
          let has_vs16 = ref false in
          for index = start to finish do
            let codepoint = codepoints.(index) in
            if Int.equal codepoint.code 0xfe0f then has_vs16 := true;
            if codepoint.width > !cluster_width then
              cluster_width := codepoint.width
          done;
          if !has_vs16 && Int.equal !cluster_width 1 then cluster_width := 2;
          for index = start to finish do
            let codepoint = codepoints.(index) in
            codepoints.(index) <-
              { codepoint with width = if Int.equal index start then !cluster_width else 0 }
          done
        in
        let cluster_start = ref 0 in
        let regional_count = ref
          (if is_regional_indicator codepoints.(0).code then 1 else 0)
        in
        let index = ref 1 in
        while !index < Array.length codepoints do
          let previous = codepoints.(!index - 1) in
          let current = codepoints.(!index) in
          let current_is_regional = is_regional_indicator current.code in
          let continues =
            is_zero_width current.code
            || Int.equal previous.code 0x200d
            || (current_is_regional
                && is_regional_indicator previous.code
                && Int.equal !regional_count 1)
          in
          if continues then begin
            if current_is_regional then incr regional_count;
            incr index
          end else begin
            assign_cluster !cluster_start (!index - 1);
            cluster_start := !index;
            regional_count := if current_is_regional then 1 else 0;
            incr index
          end
        done;
        assign_cluster !cluster_start (Array.length codepoints - 1);
        codepoints
      end

let display_width ?(tab_width = 2) width_method source =
  Array.fold_left (fun total codepoint -> total + codepoint.width) 0
    (scan ~tab_width width_method source)

let byte_offset_at_display ?(tab_width = 2) width_method source requested =
  let target = max 0 requested in
  let result = ref 0 in
  let display = ref 0 in
  let codepoints = scan ~tab_width width_method source in
  let index = ref 0 in
  while !index < Array.length codepoints do
    let codepoint = codepoints.(!index) in
    if !display < target then begin
      if !display + codepoint.width <= target then begin
        display := !display + codepoint.width;
        result := codepoint.byte_end;
        incr index
      end else index := Array.length codepoints
    end else if Int.equal !display target && Int.equal codepoint.width 0 then begin
      result := codepoint.byte_end;
      incr index
    end else index := Array.length codepoints
  done;
  !result

let display_offset_of_byte ?(tab_width = 2) width_method source requested =
  let target = max 0 (min requested (String.length source)) in
  let result = ref 0 in
  let codepoints = scan ~tab_width width_method source in
  let index = ref 0 in
  while !index < Array.length codepoints
        && codepoints.(!index).byte_start < target do
    result := !result + codepoints.(!index).width;
    incr index
  done;
  !result
