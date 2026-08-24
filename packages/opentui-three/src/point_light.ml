let create ?(color = Color.create ()) ?(intensity = 1.0) ?(distance = 0.0) () =
  Object3d.make
    ~kind:(Object3d.Point_light { color; intensity; distance })
    ()

let state node =
  match Object3d.kind node with
  | Object3d.Point_light state -> state
  | _ -> raise (Invalid_argument "Point_light.state: node is not a point light")

let color node = (state node).color

let intensity node = (state node).intensity

let set_intensity node intensity = (state node).intensity <- intensity

let distance node = (state node).distance

let set_distance node distance = (state node).distance <- distance
