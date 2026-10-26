shader_type spatial;

// Pelota de futbol clasica (icosaedro truncado: 20 hexagonos claros y 12
// pentagonos oscuros), generada de forma procedural sin necesidad de textura.
//
// Como funciona: los centros de los 12 pentagonos son los vertices de un
// icosaedro, y los centros de los 20 hexagonos son los vertices de un
// dodecaedro. Para cada punto de la esfera se busca cual de esos 32 centros
// queda mas cerca; si el ganador es uno de los 12, el punto va oscuro.
// Donde el primero y el segundo quedan casi empatados, cae la costura.

uniform vec3 color_claro : source_color = vec3(0.94, 0.94, 0.95);
uniform vec3 color_oscuro : source_color = vec3(0.08, 0.08, 0.10);
uniform vec3 color_costura : source_color = vec3(0.30, 0.30, 0.33);
uniform float ancho_costura = 0.013;

varying vec3 dir_local;

void vertex() {
	dir_local = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(dir_local);

	float PHI = 1.6180339887;
	float INV = 0.6180339887;

	vec3 pentagonos[12] = {
		vec3(0.0, 1.0, PHI), vec3(0.0, 1.0, -PHI), vec3(0.0, -1.0, PHI), vec3(0.0, -1.0, -PHI),
		vec3(1.0, PHI, 0.0), vec3(1.0, -PHI, 0.0), vec3(-1.0, PHI, 0.0), vec3(-1.0, -PHI, 0.0),
		vec3(PHI, 0.0, 1.0), vec3(-PHI, 0.0, 1.0), vec3(PHI, 0.0, -1.0), vec3(-PHI, 0.0, -1.0)
	};

	vec3 hexagonos[20] = {
		vec3(1.0, 1.0, 1.0), vec3(1.0, 1.0, -1.0), vec3(1.0, -1.0, 1.0), vec3(1.0, -1.0, -1.0),
		vec3(-1.0, 1.0, 1.0), vec3(-1.0, 1.0, -1.0), vec3(-1.0, -1.0, 1.0), vec3(-1.0, -1.0, -1.0),
		vec3(0.0, INV, PHI), vec3(0.0, INV, -PHI), vec3(0.0, -INV, PHI), vec3(0.0, -INV, -PHI),
		vec3(INV, PHI, 0.0), vec3(INV, -PHI, 0.0), vec3(-INV, PHI, 0.0), vec3(-INV, -PHI, 0.0),
		vec3(PHI, 0.0, INV), vec3(-PHI, 0.0, INV), vec3(PHI, 0.0, -INV), vec3(-PHI, 0.0, -INV)
	};

	// se busca el centro mas cercano y el segundo mas cercano
	float mejor = -2.0;
	float segundo = -2.0;
	bool gana_pentagono = false;

	for (int i = 0; i < 12; i++) {
		float p = dot(d, normalize(pentagonos[i]));
		if (p > mejor) {
			segundo = mejor;
			mejor = p;
			gana_pentagono = true;
		} else if (p > segundo) {
			segundo = p;
		}
	}
	for (int i = 0; i < 20; i++) {
		float p = dot(d, normalize(hexagonos[i]));
		if (p > mejor) {
			segundo = mejor;
			mejor = p;
			gana_pentagono = false;
		} else if (p > segundo) {
			segundo = p;
		}
	}

	vec3 color = gana_pentagono ? color_oscuro : color_claro;

	// costura: donde el primero y el segundo centro quedan casi empatados
	float costura = 1.0 - smoothstep(ancho_costura, ancho_costura + 0.008, mejor - segundo);
	color = mix(color, color_costura, costura);

	ALBEDO = color;
	ROUGHNESS = 0.45;
	SPECULAR = 0.4;
}
