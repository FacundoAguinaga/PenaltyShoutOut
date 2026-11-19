// Logica compartida por los shaders de la hinchada (3D, impostor y horneado):
// que animacion hace cada espectador en cada momento y de que color se viste.
//
// Datos por espectador (los escribe CrowdManager en el MultiMesh):
//   INSTANCE_CUSTOM.x  numero al azar propio (0 a 1)
//   INSTANCE_CUSTOM.y  personalidad + 8 * sentado + 16 * equipo
//   INSTANCE_CUSTOM.z  equipacion (indice en las tablas kit_*)
//   INSTANCE_CUSTOM.w  tono de piel + 8 * pelo + 64 * tipo de NPC
//   COLOR.rgb          color principal de la remera

const float PI_H = 3.14159265;

// Reloj propio (lo avanza CrowdManager): asi la hinchada se puede pausar.
uniform float tiempo = 0.0;
// Lo que esta pasando: 0 nada, 1 tension, 2 gol, 3 fallo/atajada.
uniform int evento = 0;
uniform int evento_previo = 0;
// Equipo que pateo (0 local, 1 visitante).
uniform int equipo_evento = 0;
uniform int equipo_evento_previo = 0;
uniform float evento_inicio = -1000.0;
// Cada espectador tarda entre 0 y esto (segundos) en reaccionar.
uniform float retardo_reaccion = 1.1;

uniform float fps_anim = 15.0;
uniform int anim_inicio[16];
uniform int anim_cuadros[16];
// Ver scripts/hinchada_conductas.gd
uniform int tabla[384];
uniform float salto_altura = 0.13;
uniform float salto_frecuencia = 2.3;

// Equipaciones (colores en lineal).
uniform vec3 kit_secundario[32];
uniform vec3 kit_pantalon[32];
uniform int kit_patron[32];
uniform vec3 tonos_piel[8];
uniform vec3 tonos_pelo[8];

struct Persona {
	float semilla;
	int personalidad;
	int sentado;
	int equipo;
	int kit;
	int piel;
	int pelo;
	int npc;
};

struct Mezcla {
	int anim_a;
	int anim_b;
	float peso; // 0 = todo anim_a, 1 = todo anim_b
	float salto;
};

float azar1(float n) {
	return fract(sin(n) * 43758.5453);
}

Persona leer_persona(vec4 c) {
	Persona p;
	int a = int(c.y + 0.5);
	int b = int(c.w + 0.5);
	p.semilla = c.x;
	p.personalidad = a & 7;
	p.sentado = (a >> 3) & 1;
	p.equipo = (a >> 4) & 3;
	p.kit = clamp(int(c.z + 0.5), 0, 31);
	p.piel = b & 7;
	p.pelo = (b >> 3) & 7;
	p.npc = b >> 6;
	return p;
}

int estado_de(int ev, int eq_ev, int equipo) {
	if (ev <= 1) {
		return ev;
	}
	if (equipo >= 2) {
		return 5;
	}
	bool propio = equipo == eq_ev;
	if (ev == 2) {
		return propio ? 2 : 4;
	}
	return propio ? 4 : 3;
}

int entrada_tabla(Persona p, int estado, float azar) {
	int op = clamp(int(azar * 4.0), 0, 3);
	return tabla[((p.personalidad * 6 + estado) * 2 + p.sentado) * 4 + op];
}

Mezcla calcular_mezcla(Persona p) {
	float s = p.semilla;
	// Cuanto hace que este espectador "se entero" de lo que paso.
	float dt = tiempo - evento_inicio - azar1(s * 37.17) * retardo_reaccion;
	int est_ahora = estado_de(evento, equipo_evento, p.equipo);
	int est_antes = estado_de(evento_previo, equipo_evento_previo, p.equipo);
	int est = dt >= 0.0 ? est_ahora : est_antes;

	// Cada tanto (distinto para cada uno) elige otra de sus 4 opciones.
	float periodo = 3.0 + 5.0 * azar1(s * 91.73);
	float ts = (tiempo + s * 173.0) / periodo;
	float tramo = floor(ts);
	float en_tramo = fract(ts) * periodo;
	float azar_tramo = azar1(tramo * 12.9898 + s * 78.233);

	int eb = entrada_tabla(p, est, azar_tramo);
	int ea = eb;
	float w = 1.0;
	const float FUNDIDO = 0.45;
	if (dt >= 0.0 && dt < FUNDIDO && est_ahora != est_antes) {
		ea = entrada_tabla(p, est_antes, azar_tramo);
		w = dt / FUNDIDO;
	} else if (en_tramo < FUNDIDO) {
		ea = entrada_tabla(p, est, azar1((tramo - 1.0) * 12.9898 + s * 78.233));
		w = en_tramo / FUNDIDO;
	}
	Mezcla m;
	m.anim_a = ea & 63;
	m.anim_b = eb & 63;
	m.peso = smoothstep(0.0, 1.0, w);
	m.salto = mix(float(ea >> 6), float(eb >> 6), m.peso);
	return m;
}

// Cuadro (con decimales) en el que va la animacion de este espectador.
float cuadro_anim(int anim, float semilla) {
	float vel = 0.88 + 0.24 * azar1(semilla * 5.31);
	return mod(tiempo * fps_anim * vel + semilla * 613.0, float(anim_cuadros[anim]));
}

vec3 muestra_vat(sampler2D tex, int columna, int anim, float cuadro) {
	int n = anim_cuadros[anim];
	int i0 = int(floor(cuadro)) % n;
	int i1 = (i0 + 1) % n;
	int base = anim_inicio[anim];
	vec3 a = texelFetch(tex, ivec2(columna, base + i0), 0).xyz;
	vec3 b = texelFetch(tex, ivec2(columna, base + i1), 0).xyz;
	return mix(a, b, fract(cuadro));
}

vec3 muestra_normal(sampler2D tex, int columna, int anim, float cuadro) {
	int fila = anim_inicio[anim] + int(cuadro + 0.5) % anim_cuadros[anim];
	return texelFetch(tex, ivec2(columna, fila), 0).xyz * 2.0 - 1.0;
}

// Saltitos en el lugar: toda la tribuna salta casi a la vez, como una popular.
float salto_y(float semilla) {
	float c = fract(tiempo * salto_frecuencia + semilla * 0.09);
	return c < 0.7 ? sin(c / 0.7 * PI_H) * salto_altura : 0.0;
}

// Cuanto del secundario lleva la remera en este punto. `rest` es la posicion
// del punto con el cuerpo en T, en metros (x al costado, y altura).
float patron_remera(int patron, vec2 rest) {
	if (patron == 1) {
		return step(0.5, fract(rest.x / 0.12 + 0.25));
	} else if (patron == 2) {
		return step(0.5, fract(rest.y / 0.15));
	} else if (patron == 3) {
		return 1.0 - step(0.065, abs((rest.y - 1.28) + rest.x * 0.9));
	} else if (patron == 4) {
		return step(0.0, rest.x);
	} else if (patron == 5) {
		return 1.0 - step(0.06, abs(rest.y - 1.33));
	} else if (patron == 6) {
		return step(0.205, abs(rest.x));
	}
	return 0.0;
}

// Sombreado propio de la textura, normalizado: 1 = brillo promedio de la parte.
float sombra_parte(vec3 base, float lum_ref) {
	return clamp(dot(base, vec3(0.299, 0.587, 0.114)) / max(lum_ref, 0.01), 0.25, 1.7);
}

// pesos = cuanto de este punto es remera (x), pantalon (y), piel (z), pelo (w).
// sombras = sombreado normalizado para remera (x), pantalon (y) y pelo (z).
vec3 vestir(vec3 base, vec4 pesos, vec3 sombras, vec2 rest, Persona p, vec3 primario) {
	float m = patron_remera(kit_patron[p.kit], rest);
	vec3 c_remera = mix(primario, kit_secundario[p.kit], m) * sombras.x;
	vec3 c_pantalon = kit_pantalon[p.kit] * sombras.y;
	vec3 c_piel = base * tonos_piel[p.piel];
	vec3 c_pelo = tonos_pelo[p.pelo] * sombras.z;
	if (p.pelo == 7) {
		c_pelo = c_piel; // pelado
	} else if (p.pelo == 6) {
		c_pelo = primario * sombras.z; // gorra del color de la remera
	}
	float resto = clamp(1.0 - (pesos.x + pesos.y + pesos.z + pesos.w), 0.0, 1.0);
	return c_remera * pesos.x + c_pantalon * pesos.y + c_piel * pesos.z + c_pelo * pesos.w + base * resto;
}

vec4 pesos_de_parte(float parte) {
	// 0 otro (calzado), 1 remera, 2 pantalon, 3 piel, 4 pelo
	int i = int(parte + 0.5);
	return vec4(float(i == 1), float(i == 2), float(i == 3), float(i == 4));
}
