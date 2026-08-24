type kind =
  | Basic
  | Lambert
  | Phong

type t = {
  kind : kind;
  color : Color.t;
  mutable specular : Color.t;
  mutable shininess : float;
  mutable emissive : Color.t;
  mutable emissive_intensity : float;
}

let color m = m.color

let kind m = m.kind

let specular m = m.specular

let shininess m = m.shininess

let emissive m = m.emissive

let emissive_intensity m = m.emissive_intensity
