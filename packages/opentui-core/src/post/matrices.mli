(** The 4x4 RGBA matrices shipped by the reference post-processing module.

    Matrices use row-major output rows.  The alpha row is kept as identity so
    the renderer's native blending metadata is not accidentally discarded. *)

val sepia_matrix : floatarray
val protanopia_sim_matrix : floatarray
val deuteranopia_sim_matrix : floatarray
val tritanopia_sim_matrix : floatarray
val achromatopsia_matrix : floatarray
val protanopia_comp_matrix : floatarray
val deuteranopia_comp_matrix : floatarray
val tritanopia_comp_matrix : floatarray
val technicolor_matrix : floatarray
val solarization_matrix : floatarray
val synthwave_matrix : floatarray
val greenscale_matrix : floatarray
val grayscale_matrix : floatarray
val invert_matrix : floatarray
