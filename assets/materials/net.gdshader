shader_type spatial;
render_mode cull_disabled, shadows_disabled;

// Red del arco: cuadricula calculada en coordenadas de mundo, asi que todos
// los paneles (fondo, laterales y techo) comparten el mismo tamano de malla
// sin importar como este rotado o escalado cada uno.
//
// Se usa ALPHA_SCISSOR en vez de transparencia comun para evitar problemas
// de orden de dibujado: cada pixel del hilo se dibuja o se descarta.

uniform vec3 net_color : source_color = vec3(0.93, 0.94, 0.95);
uniform float cell = 0.13;       // lado del cuadrado de la red, en metros
uniform float thickness = 0.011; // grosor del hilo, en metros

// --- Deformacion al recibir la pelota ---
// El script red_arco.gd le pasa donde pego la pelota, en que direccion iba
// y cuanto tiempo paso desde el impacto. La red se hincha en esa direccion
// con una campana alrededor del punto de impacto, oscila un poco y se apaga.
uniform vec3 impacto = vec3(0.0, -999.0, 0.0);
uniform vec3 dir_impacto = vec3(0.0, 0.0, -1.0);
uniform float dt_impacto = -1.0; // segundos desde el impacto; negativo = quieta
uniform float fuerza = 0.0;      // cuanto se hunde, en metros
uniform float radio = 1.3;       // que tan ancha es la deformacion

varying vec3 world_pos;

void vertex() {
	vec3 v = VERTEX;

	if (dt_impacto >= 0.0) {
		vec3 pos_mundo = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
		float d = distance(pos_mundo, impacto);
		float campana = exp(-(d * d) / (radio * radio)); // mas hundido cerca del impacto
		float apagado = exp(-dt_impacto * 4.0);          // se va frenando
		float vibracion = cos(dt_impacto * 20.0);        // rebota un par de veces
		float desplazamiento = fuerza * campana * apagado * vibracion;

		// La red se hunde en el sentido en que iba la pelota, pero solo puede
		// moverse perpendicular a si misma. Por eso se proyecta la direccion
		// del tiro sobre la normal del panel: asi el mismo material sirve para
		// el fondo, los laterales y el techo sin saber cual es cual.
		vec3 normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float proyeccion = dot(normal_mundo, dir_impacto);
		v += NORMAL * desplazamiento * proyeccion;
	}

	VERTEX = v;
	world_pos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
}

void fragment() {
	// Se proyecta segun la normal dominante: asi el panel del fondo usa (x,y),
	// los laterales (z,y) y el techo (x,z).
	vec3 n = abs(mat3(INV_VIEW_MATRIX) * NORMAL);
	vec2 uv;
	if (n.z >= n.x && n.z >= n.y) {
		uv = world_pos.xy;
	} else if (n.x >= n.y) {
		uv = world_pos.zy;
	} else {
		uv = world_pos.xz;
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
