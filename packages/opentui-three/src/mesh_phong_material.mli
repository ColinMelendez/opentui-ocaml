(** Specular highlights plus emissive output, port of three.js
    MeshPhongMaterial for the non-textured surface (maps arrive with the
    textured-material slice).

    Defaults match the reference: dark 0x111111 specular, shininess 30,
    black emissive at intensity one. *)

val create :
  ?color:Color.t ->
  ?specular:Color.t ->
  ?shininess:float ->
  ?emissive:Color.t ->
  ?emissive_intensity:float ->
    unit -> Material.t

(** Emissive output is added to the lit result unconditionally:
    [emissive.rgb * emissive_intensity] survives even with no lights in
    the scene, matching the reference. *)
