let create ?name geometry material =
  Object3d.make ?name ~kind:(Object3d.Mesh (geometry, material)) ()

let geometry node =
  match Object3d.kind node with
  | Object3d.Mesh (geometry, _) -> geometry
  | _ -> raise (Invalid_argument "Mesh.geometry: node is not a mesh")

let material node =
  match Object3d.kind node with
  | Object3d.Mesh (_, material) -> material
  | _ -> raise (Invalid_argument "Mesh.material: node is not a mesh")

let set_geometry node geometry =
  match Object3d.kind node with
  | Object3d.Mesh (_, material) -> node.kind <- Object3d.Mesh (geometry, material)
  | _ -> raise (Invalid_argument "Mesh.set_geometry: node is not a mesh")

let set_material node material =
  match Object3d.kind node with
  | Object3d.Mesh (geometry, _) -> node.kind <- Object3d.Mesh (geometry, material)
  | _ -> raise (Invalid_argument "Mesh.set_material: node is not a mesh")
