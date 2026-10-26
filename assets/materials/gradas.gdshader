shader_type spatial;

// Gradas: dibuja filas escalonadas, butacas y publico sobre las superficies
// planas del modelo del estadio, que es low-poly y no trae esa geometria.
//
// El modelo NO tiene UV-maps, asi que todo se calcula en COORDENADAS DE MUNDO:
//   - Las filas se separan por altura (Y), como las gradas reales.
//   - Las butacas se separan por el angulo alrededor del centro del estadio,
//     que es como estan dispuestas en un estadio real (en cunas radiales).

uniform vec3 color_butaca_a : source_color = vec3(0.42, 0.07, 0.14);
uniform vec3 color_butaca_b : source_color = vec3(0.58, 0.13, 0.20);
uniform vec3 color_hueco : source_color = vec3(0.13, 0.13, 0.15);

uniform float alto_fila = 0.48;    // alto de cada fila, en metros
uniform float ancho_butaca = 0.36; // ancho angular de cada butaca
uniform float radio_ref = 45.0;    // radio de referencia para las cunas
uniform float ocupacion = 0.62;    // proporcion de butacas con gente
uniform vec3 centro = vec3(0.0, 0.0, 41.5);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 d = vec2(wp.x - centro.x, wp.z - centro.z);
	float a_lo_largo = atan(d.x, d.y) * radio_ref;

	float fila = wp.y / alto_fila;
	float columna = a_lo_largo / ancho_butaca;

	float ff = fract(fila);
	float fc = fract(columna);

	// escalon horizontal entre filas y separacion vertical entre butacas
	float escalon = smoothstep(0.0, 0.14, ff) * (1.0 - smoothstep(0.84, 1.0, ff));
	float separacion = smoothstep(0.0, 0.12, fc) * (1.0 - smoothstep(0.86, 1.0, fc));

	vec2 celda = vec2(floor(columna), floor(fila));
	vec3 color = mix(color_butaca_a, color_butaca_b, hash(celda + 7.3));

	// Publico: de lejos la gente se lee mayormente neutra y oscura, con algun
	// color suelto. Por eso la ropa se desatura fuerte antes de mezclarla.
	if (hash(celda) < ocupacion) {
		vec3 ropa = vec3(hash(celda + 1.7), hash(celda + 3.1), hash(celda + 5.9));
		float lum = dot(ropa, vec3(0.333));
		ropa = mix(vec3(lum * 0.26 + 0.04), ropa, 0.3);
		color = mix(color, ropa, 0.55);
	}

	ALBEDO = mix(color_hueco, color, escalon * separacion);
	ROUGHNESS = 0.9;
	SPECULAR = 0.05;
}
