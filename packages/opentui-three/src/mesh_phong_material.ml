let create ?(color = Color.create ()) ?(specular = Color.from_hex_int 0x111111)
    ?(shininess = 30.0) ?(emissive = Color.create ~r:0.0 ~g:0.0 ~b:0.0 ())
    ?(emissive_intensity = 1.0) () =
  { Material.kind = Phong;
    color;
    specular;
    shininess;
    emissive;
    emissive_intensity }
