shader_type spatial;
render_mode cull_disabled, shadows_disabled;

// Red del arco: la malla la genera y la deforma red_arco.gd (simulacion de
// tela). Aca solo se dibujan los hilos. La UV de cada vertice esta en metros
// sobre la red en reposo, asi que la cuadricula viaja pegada a la tela cuando
// se estira o se embolsa, en vez de quedar fija en el mundo.
//
// Se usa ALPHA_SCISSOR en vez de transparencia comun para evitar problemas
// de orden de dibujado: cada pixel del hilo se dibuja o se descarta.

uniform vec3 net_color : source_color = vec3(0.93, 0.94, 0.95);
uniform float cell = 0.13;       // lado del cuadrado de la red, en metros
uniform float thickness = 0.011; // grosor del hilo, en metros
uniform bool diamond = false;    // malla en rombo en vez de cuadrada

void fragment() {
	vec2 uv = UV;
	if (diamond) {
		uv = vec2(uv.x + uv.y, uv.x - uv.y) * 0.70710678;
	}

	// Distancia al hilo mas cercano, en metros.
	vec2 f = fract(uv / cell);
	vec2 d = min(f, 1.0 - f) * cell;
	float thread = 1.0 - smoothstep(thickness, thickness + 0.003, min(d.x, d.y));

	ALBEDO = net_color;
	ROUGHNESS = 0.8;
	ALPHA = thread;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
