let create ?(color = Color.create ()) () =
  { Material.kind = Basic;
    color;
    specular = Color.create ~r:0.0 ~g:0.0 ~b:0.0 ();
    shininess = 0.0;
    emissive = Color.create ~r:0.0 ~g:0.0 ~b:0.0 ();
    emissive_intensity = 1.0 }
