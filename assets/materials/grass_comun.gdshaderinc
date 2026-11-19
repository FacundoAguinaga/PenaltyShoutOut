// Codigo comun del cesped de la cancha.
//
// Lo usan dos shaders que tienen que verse IGUAL donde se tocan:
//   - grass_volumetric.gdshader: el piso de la cancha (POM, toda la cancha).
//   - grass_shells.gdshader: las capas de hojas cerca de la camara.
//
// Todo esta en METROS y en COORDENADAS DE MUNDO (p = world_pos.xz).
// Los valores de estos uniforms se configuran en grass_volumetric_material.tres;
// cesped_volumetrico.gd los copia al material de las capas al arrancar, asi
// que hay un solo lugar donde tunear el color.

uniform vec3 grass_base : source_color = vec3(0.25, 0.42, 0.14);
uniform vec3 grass_dark : source_color = vec3(0.11, 0.25, 0.06);
uniform vec3 grass_tip : source_color = vec3(0.41, 0.55, 0.22);
uniform vec3 wear_color : source_color = vec3(0.47, 0.44, 0.27);

// Franjas de corte. En una cancha real las franjas NO son dos verdes: el pasto
// esta peinado hacia un lado en una franja y hacia el otro en la siguiente. La
// franja peinada "alejandose" de la camara se ve clara y la otra oscura, y al
// girar 180 grados se invierten. Eso es lo que imita stripe_view.
uniform float stripe_width = 5.5;       // ancho de cada franja, en metros
uniform float stripe_view = 0.24;       // contraste que depende de la camara
uniform float stripe_fixed = 0.07;      // contraste fijo (se ve tambien desde arriba)
uniform float stripe_softness = 0.18;   // ancho del borde entre franjas
uniform float goal_line_z = -11.0;      // las franjas arrancan en la linea de meta
uniform float pitch_length = 105.0;     // distancia entre lineas de meta

// Variacion de color: manchas grandes y grano fino.
uniform float macro_strength = 0.10;
uniform float detail_strength = 0.12;

// Desgaste: punto de penal y boca del arco, en los dos arcos.
uniform float wear_strength = 0.55;

uniform float wind_strength = 0.5;      // 0 = pasto quieto
uniform float wind_speed = 1.4;

float grass_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Ruido de valor (sin textura).
float grass_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = grass_hash(i);
	float b = grass_hash(i + vec2(1.0, 0.0));
	float c = grass_hash(i + vec2(0.0, 1.0));
	float d = grass_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Peso de una octava de ruido segun el tamano del pixel en el piso: si el
// periodo del ruido es menor a ~3 pixeles se apaga, asi no hay moire.
float grass_octave(float period, float footprint) {
	return 1.0 - smoothstep(period * 0.18, period * 0.40, footprint);
}

// -1 / +1 segun hacia donde esta peinada la franja, con borde suave.
float grass_mow_sign(vec2 p) {
	// El corte de la cortadora no es una regla: el borde ondula un poco.
	float z = p.y - goal_line_z + (grass_noise(vec2(p.x * 0.35, p.y * 0.2)) - 0.5) * 0.10;
	float x = z / stripe_width;
	float f = fract(x);
	float s = mod(floor(x), 2.0) * 2.0 - 1.0;
	float edge = min(f, 1.0 - f) * stripe_width;
	return s * smoothstep(0.0, stripe_softness, edge);
}

// Direccion (x,z) hacia la que esta peinado el pasto en p.
vec2 grass_lean(vec2 p) {
	return vec2(0.0, grass_mow_sign(p));
}

// Multiplicador de brillo de la franja. to_cam es el vector normalizado del
// punto hacia la camara.
float grass_stripe(vec2 p, vec3 to_cam) {
	float s = grass_mow_sign(p);
	// Pasto peinado alejandose de la camara (lean opuesto a to_cam) = claro.
	float view = -s * to_cam.z;
	return 1.0 + stripe_view * view + stripe_fixed * s;
}

// Desgaste 0..1 (0 = pasto sano).
float grass_wear(vec2 p) {
	// Coordenadas relativas a la linea de meta mas cercana: sirve para los
	// dos arcos sin repetir codigo.
	vec2 r = vec2(p.x, min(p.y - goal_line_z, goal_line_z + pitch_length - p.y));
	float n = grass_noise(p * 1.6) * 0.65 + grass_noise(p * 5.3) * 0.35;

	// Punto de penal (11 m) y donde se para el pateador.
	float spot = length((r - vec2(0.0, 11.0)) * vec2(1.0, 0.8));
	float w_spot = 1.0 - smoothstep(0.25, 1.6, spot + (n - 0.5) * 0.9);
	float run = length((r - vec2(0.0, 13.5)) * vec2(1.3, 0.55));
	float w_run = (1.0 - smoothstep(0.3, 2.2, run + (n - 0.5) * 1.2)) * 0.45;

	// Boca del arco: el arquero vive ahi.
	vec2 gm = vec2(max(abs(r.x) - 2.6, 0.0) / 1.6, max(r.y - 1.2, 0.0) / 2.0);
	float w_goal = (1.0 - smoothstep(0.2, 1.0, length(gm) + (n - 0.5) * 0.7));
	w_goal *= step(-0.6, r.y);

	float w = max(max(w_spot, w_run), w_goal * 0.85);
	// Manchas: el desgaste nunca es parejo.
	w *= smoothstep(0.15, 0.65, n + w * 0.35);
	return clamp(w * wear_strength, 0.0, 1.0);
}

// Campos de color que no dependen del pixel, empaquetados en 0..1:
//   x = manchas grandes, y = tono amarillento, z = grano medio, w = desgaste.
// cesped_volumetrico.gd los hornea en una textura (grass_horneado.gdshader)
// para que las hojas no tengan que calcular todo este ruido en cada capa.
vec4 grass_fields(vec2 p) {
	// Manchas grandes (varios metros): riego, sombra de tribuna, resiembra.
	float macro = grass_noise(p * 0.045) * 0.6 + grass_noise(p * 0.17 + 7.1) * 0.4;
	float hue = grass_noise(p * 0.09 + 31.0);
	float g = (grass_noise(p * 0.9) - 0.5) * 0.35 + (grass_noise(p * 3.7 + 3.3) - 0.5) * 0.35;
	return vec4(macro, hue, g / 0.7 + 0.5, grass_wear(p));
}

// Color final a partir de los campos. g = grano total (ya con octavas).
vec3 grass_shade(vec2 p, float macro, float hue, float g, float wear) {
	vec3 col = grass_base;
	col *= 1.0 + (macro - 0.5) * 2.0 * macro_strength;
	col = mix(col, col * vec3(1.07, 1.02, 0.80), smoothstep(0.55, 0.9, hue) * 0.5);
	col *= 1.0 + g * 2.0 * detail_strength;
	if (wear > 0.001) {
		float tierra = grass_noise(p * 9.0) * 0.5 + 0.5;
		col = mix(col, wear_color * tierra, wear * 0.75);
	}
	return col;
}

// Grano fino (periodo ~7 cm): siempre en tiempo real, se apaga a lo lejos.
float grass_fine_grain(vec2 p, float footprint) {
	return (grass_noise(p * 14.0 + 9.1) - 0.5) * 0.30 * grass_octave(0.07, footprint);
}

// Color del pasto en p (sin luz), todo procedural. footprint = tamano del
// pixel en metros: las octavas que no se pueden ver se apagan.
vec3 grass_color(vec2 p, float footprint) {
	float macro = grass_noise(p * 0.045) * 0.6 + grass_noise(p * 0.17 + 7.1) * 0.4;
	float hue = grass_noise(p * 0.09 + 31.0);
	float g = 0.0;
	g += (grass_noise(p * 0.9) - 0.5) * 0.35 * grass_octave(1.1, footprint);
	g += (grass_noise(p * 3.7 + 3.3) - 0.5) * 0.35 * grass_octave(0.27, footprint);
	g += grass_fine_grain(p, footprint);
	return grass_shade(p, macro, hue, g, grass_wear(p));
}

// Viento: desplazamiento horizontal (en metros) de la punta de una hoja.
vec2 grass_wind(vec2 p, float t) {
	float phase = t * wind_speed + dot(p, vec2(0.31, 0.17)) * 2.3;
	float gust = grass_noise(p * 0.12 + vec2(t * 0.35, 0.0));
	return vec2(0.89, 0.44) * sin(phase) * (0.4 + gust) * wind_strength * 0.004;
}
