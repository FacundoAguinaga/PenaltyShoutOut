shader_type spatial;

// Lineas de cal de la cancha.
//
// En el modelo del estadio las lineas ("auto_30") estan en el mismo plano que
// el cesped, asi que a lo lejos peleaban por el depth buffer (z-fighting: la
// linea se veia cortada). Aca se levantan unos milimetros y se les da el
// mismo grano y las mismas franjas que al pasto: la cal esta pintada sobre
// las hojas, no es una cinta blanca perfecta.

render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/materials/grass_comun.gdshaderinc"

uniform vec3 line_color : source_color = vec3(0.86, 0.88, 0.86);
uniform float lift = 0.004;              // metros sobre el cesped

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += lift;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - world_pos);
	float footprint = max(fwidth(p.x), fwidth(p.y));

	// Grano de la cal: deja ver un poco de verde entre las hojas pintadas.
	float g = (grass_noise(p * 40.0) - 0.5) * grass_octave(0.025, footprint);
	g += (grass_noise(p * 9.0 + 4.0) - 0.5) * 0.5 * grass_octave(0.11, footprint);
	vec3 col = line_color * (0.94 + g * 0.18);
	col = mix(col, grass_base, 0.06 + max(g, 0.0) * 0.12 * grass_octave(0.025, footprint));
	// Las franjas de corte se notan tambien sobre la cal, pero menos.
	col *= mix(1.0, grass_stripe(p, to_cam), 0.5);

	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
