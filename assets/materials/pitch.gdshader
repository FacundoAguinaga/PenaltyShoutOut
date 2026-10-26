shader_type spatial;

// Cancha de futbol: cesped con franjas de corte + lineas reglamentarias.
//
// Todas las medidas estan en METROS y se calculan en COORDENADAS DE MUNDO.
// Por eso el material no se deforma aunque el nodo que lo usa tenga una
// escala rara (el Ground de game.tscn esta escalado 6x en X y 14x en Z).
//
// La geometria coincide con la escena real:
//   - Los postes del arco estan en z = -11 (ahi va la linea de meta).
//   - La pelota arranca en z = -2, asi que el punto de penal se dibuja ahi
//     para que la pelota quede parada justo sobre el punto.

uniform vec3 grass_light : source_color = vec3(0.29, 0.56, 0.19);
uniform vec3 grass_dark : source_color = vec3(0.23, 0.47, 0.15);
uniform vec3 line_color : source_color = vec3(0.90, 0.93, 0.90);

uniform float stripe_width = 4.0;  // ancho de cada franja de corte
uniform float line_width = 0.12;   // ancho de las lineas pintadas

uniform float goal_line_z = -11.0;
uniform float penalty_spot_z = -2.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Distancia a un segmento: devuelve 1 dentro de la linea, 0 fuera.
float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	float d = length(pa - ba * h);
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.03, d);
}

// Contorno de circunferencia.
float ring(vec2 p, vec2 c, float r, float w) {
	float d = abs(length(p - c) - r);
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.03, d);
}

// Circulo relleno (punto de penal).
float disc(vec2 p, vec2 c, float r) {
	return 1.0 - smoothstep(r, r + 0.03, length(p - c));
}

void fragment() {
	vec2 p = vec2(world_pos.x, world_pos.z);

	// Franjas de corte, paralelas a la linea de meta.
	float band = mod(floor((p.y - goal_line_z) / stripe_width), 2.0);
	vec3 col = mix(grass_dark, grass_light, band);

	float m = 0.0;

	// Linea de meta.
	m = max(m, seg(p, vec2(-34.0, goal_line_z), vec2(34.0, goal_line_z), line_width));

	// Area grande: 16.5 m desde cada poste y 16.5 m hacia adentro.
	float pa_x = 20.16;
	float pa_z = goal_line_z + 16.5;
	m = max(m, seg(p, vec2(-pa_x, goal_line_z), vec2(-pa_x, pa_z), line_width));
	m = max(m, seg(p, vec2(pa_x, goal_line_z), vec2(pa_x, pa_z), line_width));
	m = max(m, seg(p, vec2(-pa_x, pa_z), vec2(pa_x, pa_z), line_width));

	// Area chica: 5.5 m desde cada poste y 5.5 m hacia adentro.
	float ga_x = 9.16;
	float ga_z = goal_line_z + 5.5;
	m = max(m, seg(p, vec2(-ga_x, goal_line_z), vec2(-ga_x, ga_z), line_width));
	m = max(m, seg(p, vec2(ga_x, goal_line_z), vec2(ga_x, ga_z), line_width));
	m = max(m, seg(p, vec2(-ga_x, ga_z), vec2(ga_x, ga_z), line_width));

	// Punto de penal.
	m = max(m, disc(p, vec2(0.0, penalty_spot_z), 0.11));

	// Semicirculo del area: radio 9.15 m desde el punto, solo la parte
	// que queda por fuera del area grande.
	if (p.y > pa_z) {
		m = max(m, ring(p, vec2(0.0, penalty_spot_z), 9.15, line_width));
	}

	ALBEDO = mix(col, line_color, m);
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
