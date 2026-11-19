shader_type spatial;

// Hojas de pasto cerca de la camara ("shell texturing").
//
// La malla son N planos apilados (los arma cesped_volumetrico.gd), uno cada
// pocos milimetros entre el piso y la altura del pasto. Cada plano recorta
// con alpha scissor los puntos donde hay una hoja a esa altura, asi que el
// conjunto forma hojas con silueta real: tapan la base de la pelota y de los
// botines, y a ras del piso se ve el pasto "de costado".
//
// Las capas siguen a la camara y se apagan solas cuando el pixel es mas
// grande que una hoja (a esa distancia el piso con POM ya alcanza). El
// patron esta en coordenadas de mundo, por eso no "nada" al moverse.
//
// En los VERTICES, VERTEX.y trae la fraccion de altura de la capa (0..1).

render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled, depth_draw_always;

#include "res://assets/materials/grass_comun.gdshaderinc"

uniform float grass_height = 0.05;
uniform float shell_density = 70.0;      // hojas por metro
uniform float blade_width = 0.30;        // radio de la hoja en la raiz (en celdas)
uniform float lean_amount = 0.55;        // cuanto se vuelca la hoja (en celdas)
uniform float shell_radius = 20.0;       // radio del parche, lo pone el script
uniform float blade_tint = 0.22;         // variacion de tono entre hojas
// 1 = pinta las hojas de rojo (vis), para ver donde se dibujan.
uniform int debug_shells = 0;
uniform float shell_fade_dist = 35.0;    // distancia a camara donde desaparecen

// Mascara de lineas de cal horneada desde la malla de lineas del estadio.
// line_rect = (x_min, z_min, ancho, largo) en metros.
uniform sampler2D line_mask : filter_linear, repeat_disable;
uniform vec4 line_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float use_line_mask = 0.0;
uniform vec3 line_color : source_color = vec3(0.86, 0.88, 0.86);

// Campos de color horneados (ver grass_fields en grass_comun.gdshaderinc).
// field_rect = (x_min, z_min, ancho, largo). Sin textura se calcula todo.
uniform sampler2D grass_field : filter_linear, repeat_disable;
uniform vec4 field_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float use_field = 0.0;

// Rectangulo de la cancha (x_min, z_min, x_max, z_max): fuera no hay hojas.
uniform vec4 pitch_rect = vec4(-40.0, -15.0, 40.0, 98.0);

varying vec3 world_pos;
varying float layer;

uniform float layer_px = 1.6;            // pixeles de alto por capa (LOD)
uniform float min_layers = 3.0;
uniform float tile_half_diag = 1.77;     // lo pone el script

void vertex() {
	layer = VERTEX.y;
	VERTEX.y = layer * grass_height + 0.0015;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// LOD por baldosa: cuantas capas hacen falta para que el pasto, que a
	// esta distancia mide blade_px pixeles de alto, no muestre escalones.
	// Las que sobran se colapsan a un punto (triangulo de area cero: la GPU
	// lo descarta sin rasterizar nada). Es lo que hace barata la vista de
	// juego, donde el pasto esta a 15-25 m.
	vec3 tile = (MODEL_MATRIX * vec4(UV.x, 0.0, UV.y, 1.0)).xyz;
	float d = max(length(tile - CAMERA_POSITION_WORLD) - tile_half_diag, 0.05);
	float px = d * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float total = UV2.y;
	float needed = clamp(ceil(grass_height / px / layer_px), min_layers, total);
	float stride = floor(total / needed);
	// Siempre se conserva la capa de arriba; el resto, una cada "stride".
	bool keep = mod(total - 1.0 - UV2.x, stride) < 0.5;
	// Baldosas donde ninguna hoja se veria: afuera.
	float cell = 1.0 / shell_density;
	if (d > shell_fade_dist || px > cell * 1.1) {
		keep = false;
	}
	if (!keep) {
		VERTEX = vec3(0.0);
		world_pos = vec3(0.0);
	}
}

// Cobertura 0..1 de una grilla de hojas en p, a la altura relativa h.
float blade_layer(vec2 p, float density, float h, float vis, vec2 lean, vec2 wind, float seed, float footprint, out float tip, out float rnd) {
	vec2 sp = p * density;
	vec2 id = floor(sp);
	vec2 f = fract(sp) - 0.5;
	float r0 = grass_hash(id + seed);
	float r1 = grass_hash(id + seed + 17.3);
	float r2 = grass_hash(id + seed + 41.7);
	rnd = grass_hash(id + seed + 63.1);

	// Alto de esta hoja (0..1 del alto del pasto). Se achica con la distancia
	// para que el parche se funda con el piso en vez de cortarse.
	float hb = (0.55 + 0.45 * r0) * vis;
	tip = clamp(h / max(hb, 0.001), 0.0, 1.0);
	if (h >= hb) {
		return 0.0;
	}

	// Centro de la hoja: raiz al azar dentro de la celda, punta volcada hacia
	// el peinado de la franja, con algo de azar y viento.
	vec2 root = (vec2(r1, r2) - 0.5) * 0.45;
	vec2 rand_dir = vec2(cos(r0 * 6.2831), sin(r0 * 6.2831));
	vec2 bend = (lean * lean_amount + rand_dir * 0.25) * tip * tip;
	vec2 c = root + bend + wind * density * tip * tip;

	vec2 d = f - c;
	// Hoja fina: un poco elongada en la direccion del peinado.
	d.y *= 0.8;
	float radius = blade_width * pow(1.0 - tip, 0.55);
	// Ancho del borde suave = ~0.75 pixel (en unidades de celda).
	float aa = footprint * density * 0.75;
	return 1.0 - smoothstep(radius - aa, radius + aa, length(d));
}

void fragment() {
	vec2 p = world_pos.xz;
	if (p.x < pitch_rect.x || p.y < pitch_rect.y || p.x > pitch_rect.z || p.y > pitch_rect.w) {
		discard;
	}

	vec3 to_cam_v = CAMERA_POSITION_WORLD - world_pos;
	float dist = length(to_cam_v);
	vec3 to_cam = to_cam_v / max(dist, 0.0001);

	// Tamano del pixel a esta distancia (en metros). NO se usa fwidth(p):
	// a ras del piso el pixel proyectado sobre el suelo se estira mucho en
	// profundidad y las hojas se apagaban aunque, al ser verticales, se ven
	// perfectamente. Lo que importa es cuanto mide un pixel a esa distancia.
	float footprint = dist * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);

	// Visibilidad: se apaga lejos de la camara, en el borde del parche y
	// cuando la hoja mide menos de ~2 pixeles.
	float cell = 1.0 / shell_density;
	float vis = 1.0 - smoothstep(shell_fade_dist * 0.6, shell_fade_dist, dist);
	vis *= 1.0 - smoothstep(cell * 0.45, cell * 1.1, footprint);
	vec2 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
	vis *= 1.0 - smoothstep(shell_radius * 0.7, shell_radius, length(p - center));
	// Ninguna hoja es mas alta que vis: las capas de arriba se descartan sin
	// calcular nada. Es la mayor parte del costo ahorrado a distancia.
	if (layer >= vis) {
		discard;
	}
	vec4 fields = use_field > 0.5
		? texture(grass_field, (p - field_rect.xy) / field_rect.zw)
		: grass_fields(p);
	// Donde el pasto esta gastado hay menos hojas y mas bajas.
	vis *= 1.0 - fields.w * 0.55;
	if (layer >= vis) {
		discard;
	}

	vec2 lean = grass_lean(p);
	vec2 wind = grass_wind(p, TIME);

	// Dos grillas a distinta escala y desfasadas: rompe la sensacion de
	// grilla y da mas densidad sin achicar las celdas.
	float tip_a;
	float tip_b;
	float rnd_a;
	float rnd_b;
	float a = blade_layer(p, shell_density, layer, vis, lean, wind, 1.0, footprint, tip_a, rnd_a);
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	float b = blade_layer(rot * p + 0.37, shell_density * 1.31, layer, vis * 0.92, rot * lean, rot * wind, 9.0, footprint, tip_b, rnd_b);
	float cov = max(a, b);
	float tip = a >= b ? tip_a : tip_b;
	float rnd = a >= b ? rnd_a : rnd_b;
	// Sin hoja en este pixel: se corta antes de calcular el color.
	if (cov < 0.5) {
		discard;
	}
	// Escribir ALPHA manda el material al pase transparente, que no tiene
	// depth prepass: con alpha scissor Godot corria este shader dos veces por
	// fragmento. Con depth_draw_always y discard el resultado es opaco igual.
	ALPHA = 1.0;

	float g = (fields.z - 0.5) * 0.7 + grass_fine_grain(p, footprint);
	vec3 col = grass_shade(p, fields.x, fields.y, g, fields.w);
	col *= grass_stripe(p, to_cam);

	// Lineas de cal: las hojas que estan sobre la linea estan pintadas.
	if (use_line_mask > 0.5) {
		vec2 uv = (p - line_rect.xy) / line_rect.zw;
		float m = texture(line_mask, uv).r;
		col = mix(col, line_color, smoothstep(0.35, 0.65, m));
	}

	// Raiz oscura (ocluida por las otras hojas), punta clara.
	// Gradiente segun la altura de la capa y la de la propia hoja (las hojas
	// cortas tambien tienen punta clara).
	float h = mix(layer, tip, 0.6);
	vec3 root_col = col * mix(grass_dark / grass_base, vec3(1.0), 0.55);
	vec3 tip_col = col * mix(vec3(1.0), grass_tip / grass_base, 0.45);
	col = mix(root_col, tip_col, smoothstep(0.0, 1.0, h));
	// Cada hoja con su tono: algunas mas secas/amarillas, otras mas oscuras.
	// Es lo que hace que a distancia se lea "pasto" y no una alfombra lisa.
	col *= 1.0 + (rnd - 0.5) * 2.0 * blade_tint;
	col = mix(col, col * vec3(1.10, 1.04, 0.72), smoothstep(0.8, 1.0, rnd) * 0.6);

	ALBEDO = col;
	if (debug_shells == 1) {
		ALBEDO = vec3(1.0, 0.0, 0.0) * (0.3 + 0.7 * h);
	}
	AO = mix(0.6, 1.0, h);
	// Normal: hacia arriba, volcada con el peinado. Igual que en el piso,
	// para que la luz de los focos coincida en el borde del parche.
	vec3 n = normalize(vec3(lean.x, 0.0, lean.y) * 0.22 + vec3(0.0, 1.0, 0.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = mix(0.80, 0.55, h);
	SPECULAR = mix(0.25, 0.45, h);
	// Las hojas son finas: dejan pasar algo de luz a contraluz.
	BACKLIGHT = grass_tip * 0.25 * h;
}
