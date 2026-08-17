type t =
  | Linear
  | In_quad
  | Out_quad
  | In_out_quad
  | In_expo
  | Out_expo
  | In_out_sine
  | Out_bounce
  | Out_elastic
  | In_bounce
  | In_circ
  | Out_circ
  | In_out_circ
  | In_back
  | Out_back
  | In_out_back

let linear = Linear
let in_quad = In_quad
let out_quad = Out_quad
let in_out_quad = In_out_quad
let in_expo = In_expo
let out_expo = Out_expo
let in_out_sine = In_out_sine
let out_bounce = Out_bounce
let out_elastic = Out_elastic
let in_bounce = In_bounce
let in_circ = In_circ
let out_circ = Out_circ
let in_out_circ = In_out_circ
let in_back = In_back
let out_back = Out_back
let in_out_back = In_out_back

let clamp progress =
  if Float.compare progress 0.0 < 0 then 0.0
  else if Float.compare progress 1.0 > 0 then 1.0
  else progress

let out_bounce_function progress =
  let n1 = 7.5625 in
  let d1 = 2.75 in
  if Float.compare progress (1.0 /. d1) < 0 then
    n1 *. progress *. progress
  else if Float.compare progress (2.0 /. d1) < 0 then
    let shifted = progress -. (1.5 /. d1) in
    n1 *. shifted *. shifted +. 0.75
  else if Float.compare progress (2.5 /. d1) < 0 then
    let shifted = progress -. (2.25 /. d1) in
    n1 *. shifted *. shifted +. 0.9375
  else
    let shifted = progress -. (2.625 /. d1) in
    n1 *. shifted *. shifted +. 0.984375

let apply easing progress =
  let progress = clamp progress in
  match easing with
  | Linear -> progress
  | In_quad -> progress *. progress
  | Out_quad -> progress *. (2.0 -. progress)
  | In_out_quad ->
      if Float.compare progress 0.5 < 0 then
        2.0 *. progress *. progress
      else
        -1.0 +. (4.0 -. (2.0 *. progress)) *. progress
  | In_expo ->
      if Float.equal progress 0.0 then 0.0
      else 2.0 ** (10.0 *. (progress -. 1.0))
  | Out_expo ->
      if Float.equal progress 1.0 then 1.0
      else 1.0 -. (2.0 ** (-10.0 *. progress))
  | In_out_sine ->
      -. (Float.cos (Float.pi *. progress) -. 1.0) /. 2.0
  | Out_bounce -> out_bounce_function progress
  | Out_elastic ->
      let c4 = (2.0 *. Float.pi) /. 3.0 in
      if Float.equal progress 0.0 then 0.0
      else if Float.equal progress 1.0 then 1.0
      else
        (2.0 ** (-10.0 *. progress))
        *. Float.sin ((progress *. 10.0 -. 0.75) *. c4)
        +. 1.0
  | In_bounce -> 1.0 -. out_bounce_function (1.0 -. progress)
  | In_circ -> 1.0 -. Float.sqrt (1.0 -. (progress *. progress))
  | Out_circ -> Float.sqrt (1.0 -. ((progress -. 1.0) *. (progress -. 1.0)))
  | In_out_circ ->
      let doubled = progress *. 2.0 in
      if Float.compare doubled 1.0 < 0 then
        -. (Float.sqrt (1.0 -. (doubled *. doubled)) -. 1.0) /. 2.0
      else
        let shifted = doubled -. 2.0 in
        (Float.sqrt (1.0 -. (shifted *. shifted)) +. 1.0) /. 2.0
  | In_back ->
      let s = 1.70158 in
      progress *. progress *. ((s +. 1.0) *. progress -. s)
  | Out_back ->
      let s = 1.70158 in
      let shifted = progress -. 1.0 in
      shifted *. shifted *. ((s +. 1.0) *. shifted +. s) +. 1.0
  | In_out_back ->
      let s = 1.70158 *. 1.525 in
      let doubled = progress *. 2.0 in
      if Float.compare doubled 1.0 < 0 then
        0.5 *. doubled *. doubled *. ((s +. 1.0) *. doubled -. s)
      else
        let shifted = doubled -. 2.0 in
        0.5 *. (shifted *. shifted *. ((s +. 1.0) *. shifted +. s) +. 2.0)

let eval = apply
