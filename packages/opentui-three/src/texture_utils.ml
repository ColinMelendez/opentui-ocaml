(** Procedural texture generators, port of the reference TextureUtils
    generators. The file loader arrives with the image-decode bridge; these
    cover checkerboard, gradient, and octave-noise generation. *)

let checkerboard ~(size : int) ~(squares : int) ?(a = '\255') ?(b = '\000') () :
    Texture.t =
  let cell = max 1 (size / squares) in
  let pixels = Bytes.make (size * size * 4) a in
  for y = 0 to size - 1 do
    for x = 0 to size - 1 do
      if Int.equal (((x / cell) + (y / cell)) land 1) 1 then begin
        let base = ((y * size) + x) * 4 in
        Bytes.set pixels base b;
        Bytes.set pixels (base + 1) b;
        Bytes.set pixels (base + 2) b;
        Bytes.set pixels (base + 3) '\255'
      end
    done
  done;
  match
    Texture.create ~pixels ~width:size ~height:size ()
  with
  | Ok texture -> texture
  | Error message -> invalid_arg message

let gradient ~(kind : [ `Horizontal | `Vertical | `Radial ]) ~(size : int)
    ~(from : int * int * int) ~(to_ : int * int * int) () : Texture.t =
  let fr, fg, fb = from in
  let tr, tg, tb = to_ in
  let f = Float.of_int in
  let lerp from_c to_c t =
    Int.of_float ((f from_c +. ((f to_c -. f from_c) *. t)) +. 0.5)
  in
  let pixels = Bytes.create (size * size * 4) in
  for y = 0 to size - 1 do
    for x = 0 to size - 1 do
      let nx = (f x +. 0.5) /. f size in
      let ny = (f y +. 0.5) /. f size in
      let t =
        match kind with
        | `Horizontal -> nx
        | `Vertical -> ny
        | `Radial ->
            let dx = nx -. 0.5 and dy = ny -. 0.5 in
            Float.sqrt ((dx *. dx) +. (dy *. dy)) *. 2.0
      in
      let base = ((y * size) + x) * 4 in
      Bytes.set pixels base (Char.chr (lerp fr tr t));
      Bytes.set pixels (base + 1) (Char.chr (lerp fg tg t));
      Bytes.set pixels (base + 2) (Char.chr (lerp fb tb t));
      Bytes.set pixels (base + 3) '\255'
    done
  done;
  match Texture.create ~pixels ~width:size ~height:size () with
  | Ok texture -> texture
  | Error message -> invalid_arg message

let octave_noise ~(seed : int) ~(octaves : int) ~(size : int) : Texture.t =
  (* Integer-hash value noise: deterministic across runs and machines. *)
  let hash x y ~frequency =
    let sample =
      ((x * 374761393) + (y * 668265263) + (seed * 1274126177)) land 0x7fffffff
    in
    let mixed = sample lxor ((frequency * 2654435761) land 0x7fffffff) in
    Float.of_int (mixed mod 65521) /. 65520.0
  in
  let smooth t = t *. t *. (3.0 -. (2.0 *. t)) in
  let value_noise x y ~frequency =
    let fx = Float.of_int x *. Float.of_int frequency in
    let fy = Float.of_int y *. Float.of_int frequency in
    let ix = int_of_float fx and iy = int_of_float fy in
    let tx = smooth (fx -. Float.of_int ix) in
    let ty = smooth (fy -. Float.of_int iy) in
    let v00 = hash ix iy ~frequency in
    let v10 = hash (ix + 1) iy ~frequency in
    let v01 = hash ix (iy + 1) ~frequency in
    let v11 = hash (ix + 1) (iy + 1) ~frequency in
    let top = v00 +. ((v10 -. v00) *. tx) in
    let bottom = v01 +. ((v11 -. v01) *. tx) in
    top +. ((bottom -. top) *. ty)
  in
  let pixels = Bytes.create (size * size * 4) in
  for y = 0 to size - 1 do
    for x = 0 to size - 1 do
      let amplitude = ref (1.0 /. Float.of_int octaves) in
      let frequency = ref 1 in
      let total = ref 0.0 in
      for _ = 0 to octaves - 1 do
        total := !total +. ((value_noise x y ~frequency:!frequency) *. !amplitude);
        amplitude := !amplitude /. 2.0;
        frequency := !frequency * 2
      done;
      let byte = Int.of_float ((!total *. 255.0) +. 0.5) in
      let clamped = max 0 (min 255 byte) in
      let base = ((y * size) + x) * 4 in
      Bytes.set pixels base (Char.chr clamped);
      Bytes.set pixels (base + 1) (Char.chr clamped);
      Bytes.set pixels (base + 2) (Char.chr clamped);
      Bytes.set pixels (base + 3) '\255'
    done
  done;
  match Texture.create ~pixels ~width:size ~height:size () with
  | Ok texture -> texture
  | Error message -> invalid_arg message
