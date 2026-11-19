shader_type spatial;

// Piso de la cancha.
//
// La cancha NO se llena de geometria: el material del cesped del estadio se
// reemplaza por este shader. El volumen corto (3-4 cm) se resuelve por pixel
// con "parallax occlusion mapping" sobre un campo de altura procedural: se
// marcha el rayo de camara a traves del pasto, se busca donde cruza la altura
// del cesped y se sombrea ese punto.
//
// Cerca de la camara, ademas, cesped_volumetrico.gd pone las capas de
// grass_shells.gdshader, que dan hojas con silueta. Color, franjas y desgaste
// salen de grass_comun.gdshaderinc para que los dos coincidan.
//
// Todo en METROS y COORDENADAS DE MUNDO: no depende de los UV del modelo.

render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/materials/grass_comun.gdshaderinc"

uniform float grass_height = 0.05;       // alto del pasto, en metros
uniform float blade_density = 50.0;      // matas por metro (1 / separacion)
uniform float clump_scale = 5.0;         // matas grandes
uniform float height_strength = 0.8;     // cuanto pesa la altura en el color
uniform float normal_strength = 1.0;     // inclinacion de las normales
uniform float ao_strength = 0.30;        // oscurecimiento entre hojas
uniform float lean_normal = 0.22;        // cuanto inclina la franja a la normal

uniform float fade_start = 25.0;         // distancia donde empieza a simplificar
uniform float fade_end = 60.0;           // distancia donde ya no hay paralaje

// 0 = normal. 1 = altura, 2 = normales, 3 = mascara de detalle, 4 = desgaste.
uniform int debug_mode = 0;

varying vec3 world_pos;

// 14 pasos alcanzan para 3-4 cm de pasto.
const int POM_STEPS = 14;

// Una mata por celda, orientada al azar y algo volcada hacia donde esta
// peinada la franja.
float blade_field(vec2 p, float density, vec2 lean) {
	vec2 sp = p * density;
	vec2 id = floor(sp);
	vec2 off = (vec2(grass_hash(id + 11.3), grass_hash(id + 17.9)) - 0.5) * 0.40;
	vec2 f = fract(sp) - 0.5 - off;
	float ang = grass_hash(id + 3.17) * 6.28318530718;
	// Las hojas se alinean un poco con el peinado.
	ang = mix(ang, 1.5708, abs(lean.y) * 0.35);
	float cs = cos(ang);
	float sn = sin(ang);
	vec2 q = vec2(cs * f.x + sn * f.y, -sn * f.x + cs * f.y);
	q.x += q.y * q.y * (grass_hash(id + 7.31) - 0.5) * 1.6;
	float w = 0.06 + 0.08 * grass_hash(id + 1.93);
	float l = 0.18 + 0.08 * grass_hash(id + 5.17);
	float d = length(vec2(q.x / w, q.y / l));
	return smoothstep(1.0, 0.0, d);
}

// Altura normalizada 0..1 del techo del cesped.
float turf_height(vec2 p, vec2 lean, float wear) {
	p += grass_wind(p, TIME) * 0.5;
	float clump = grass_noise(p * clump_scale);
	float fine = grass_noise(p * 35.0);
	float blade = blade_field(p, blade_density, lean);
	float h = 0.30 + 0.26 * clump + 0.12 * fine + 0.38 * blade;
	// Donde esta gastado el pasto es mas bajo y ralo.
	h *= 1.0 - wear * 0.6;
	return clamp(h, 0.0, 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 base_p = world_pos.xz;
	vec3 to_fragment = world_pos - CAMERA_POSITION_WORLD;
	float dist = length(to_fragment);
	vec3 ray = to_fragment / max(dist, 0.0001);

	// Tamano del pixel en el piso. Las matas miden ~2 cm: si el pixel es
	// mas grande que unos milimetros, el paralaje solo genera ruido (los
	// puntitos que se veian a media distancia), asi que se apaga.
	float footprint = max(fwidth(base_p.x), fwidth(base_p.y));
	float cell = 1.0 / blade_density;
	float detail = 1.0 - smoothstep(fade_start, fade_end, dist);
	detail *= 1.0 - smoothstep(cell * 0.25, cell * 0.7, footprint);

	vec2 lean = grass_lean(base_p);
	float wear = grass_wear(base_p);

	vec2 p = base_p;
	float h_norm = 0.55;

	if (ray.y < -0.001 && detail > 0.001) {
		h_norm = turf_height(p, lean, wear);
		float max_t = min(grass_height * detail / max(-ray.y, 0.02), 0.6);
		float step_t = max_t / float(POM_STEPS);
		for (int i = 1; i <= POM_STEPS; i++) {
			float t = step_t * float(i);
			vec2 sp = base_p - ray.xz * t;
			float sample_h = turf_height(sp, lean, wear);
			float y = -ray.y * t;
			if (y >= sample_h * grass_height * detail) {
				p = sp;
				h_norm = sample_h;
				break;
			}
		}
	}

	float shade_h = mix(0.55, h_norm, detail * height_strength);
	float tip = smoothstep(0.05, 0.95, shade_h);

	// Normal: campo de altura cerca, e inclinacion de la franja siempre (eso
	// hace que los focos pinten las franjas distinto segun de donde vienen).
	vec3 n_world = vec3(0.0, 1.0, 0.0);
	if (detail > 0.001) {
		// El paso de la derivada nunca es menor que el pixel: si no, en el
		// borde de cada mata la pendiente da casi vertical, la normal queda
		// de espaldas a la luz y aparecen puntitos negros a media distancia.
		float e = max(0.0035, footprint);
		float h0 = turf_height(p, lean, wear);
		float hx = turf_height(p + vec2(e, 0.0), lean, wear);
		float hz = turf_height(p + vec2(0.0, e), lean, wear);
		float k = normal_strength * grass_height * detail / e;
		vec2 slope = vec2(hx - h0, hz - h0) * k;
		// Limitar la inclinacion a ~40 grados.
		slope *= min(1.0, 0.85 / max(length(slope), 0.0001));
		n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	}
	n_world = normalize(n_world + vec3(lean.x, 0.0, lean.y) * lean_normal);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	vec3 to_cam = -ray;
	vec3 col = grass_color(p, footprint);
	col *= grass_stripe(p, to_cam);

	float clump = grass_noise(p * clump_scale);
	float ao = mix(1.0 - ao_strength, 1.0, tip) * mix(0.90, 1.0, clump);

	// Raiz oscura y punta clara (solo donde hay paralaje).
	col = mix(col * mix(grass_dark / grass_base, vec3(1.0), 0.55), col, mix(1.0, tip, detail));
	col = mix(col, col * grass_tip / grass_base, tip * tip * 0.25 * detail);
	col *= mix(1.0, ao, 0.35);

	ALBEDO = col;
	AO = ao;
	// El pasto peinado hacia la luz brilla mas: rugosidad media y algo de
	// especular en las puntas.
	ROUGHNESS = mix(0.80, 0.55, tip) + wear * 0.15;
	SPECULAR = mix(0.25, 0.45, tip) * (1.0 - wear * 0.5);
	BACKLIGHT = grass_tip * 0.12;
	METALLIC = 0.0;

	if (debug_mode != 0) {
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		AO = 1.0;
		BACKLIGHT = vec3(0.0);
		if (debug_mode == 1) {
			EMISSION = vec3(h_norm);
		} else if (debug_mode == 2) {
			EMISSION = n_world * 0.5 + 0.5;
		} else if (debug_mode == 3) {
			EMISSION = vec3(detail);
		} else {
			EMISSION = vec3(wear);
		}
	}
}
