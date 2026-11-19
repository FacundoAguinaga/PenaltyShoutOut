shader_type canvas_item;
render_mode blend_disabled;

// Hornea los campos de color del cesped (grass_fields) en una textura.
// Lo usa cesped_volumetrico.gd una sola vez al cargar, en un SubViewport que
// cubre la cancha. Cada pixel = un punto del mundo dentro de field_rect.
// Se guardan datos (no colores), por eso no hay conversion sRGB.

#include "res://assets/materials/grass_comun.gdshaderinc"

uniform vec4 field_rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	vec2 p = field_rect.xy + UV * field_rect.zw;
	COLOR = grass_fields(p);
}
