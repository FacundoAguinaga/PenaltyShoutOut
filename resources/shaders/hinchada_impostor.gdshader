shader_type spatial;
render_mode skip_vertex_transform, cull_disabled;

// Espectador lejano: un cartel que siempre mira a la camara y muestra una
// "foto" del NPC haciendo su animacion. Dos triangulos por persona en vez de
// cientos. Las fotos las saca tools/hinchada_hornear.gd.

uniform sampler2D atlas_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_mascara : filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_coords : filter_linear_mipmap, repeat_disable;
uniform vec2 celda_mundo = vec2(1.40625, 2.38);
uniform int cuadros_por_anim = 12;
uniform int total_anims = 11;
// La textura es una grilla de bloques, uno por NPC.
uniform int npcs_por_fila = 4;
uniform ivec2 bloques = ivec2(1, 1);
// Ajustes para que el cartel reciba la misma luz que los personajes 3D.
uniform float inclinacion_luz = 0.3;
uniform float brillo = 0.95;

#include "res://resources/shaders/hinchada_comun.gdshaderinc"

varying vec3 v_primario;
varying flat vec4 v_dato;
// Las dos fotos entre las que esta la animacion y cuanto de la segunda.
varying vec2 v_uv_a;
varying vec2 v_uv_b;
varying float v_mezcla;

vec2 uv_celda(int npc, int anim, int k, vec2 uv) {
	ivec2 bloque = ivec2(npc % npcs_por_fila, npc / npcs_por_fila);
	return vec2((float(bloque.x * cuadros_por_anim + k) + uv.x) / float(bloques.x * cuadros_por_anim),
			(float(bloque.y * total_anims + anim) + uv.y) / float(bloques.y * total_anims));
}

void vertex() {
	Persona p = leer_persona(INSTANCE_CUSTOM);
	Mezcla m = calcular_mezcla(p);
	int anim = m.peso > 0.5 ? m.anim_b : m.anim_a;
	float fase = cuadro_anim(anim, p.semilla) / float(anim_cuadros[anim]) * float(cuadros_por_anim);
	int k = int(fase) % cuadros_por_anim;
	v_uv_a = uv_celda(p.npc, anim, k, UV);
	v_uv_b = uv_celda(p.npc, anim, (k + 1) % cuadros_por_anim, UV);
	v_mezcla = fract(fase);

	vec3 pie = MODEL_MATRIX[3].xyz;
	float ancho = length(MODEL_MATRIX[0].xyz);
	float alto = length(MODEL_MATRIX[1].xyz);
	vec3 a_camara = CAMERA_POSITION_WORLD - pie;
	a_camara.y = 0.0;
	a_camara = normalize(a_camara);
	vec3 derecha = vec3(a_camara.z, 0.0, -a_camara.x);
	vec3 mundo = pie + derecha * VERTEX.x * celda_mundo.x * ancho
			+ vec3(0.0, VERTEX.y * celda_mundo.y * alto + m.salto * salto_y(p.semilla), 0.0);
	VERTEX = (VIEW_MATRIX * vec4(mundo, 1.0)).xyz;

	// Se ilumina como si mirara a donde mira el espectador (no a la camara),
	// para que reciba la misma luz que los 3D que tiene al lado.
	vec3 frente = normalize(MODEL_MATRIX[2].xyz);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(frente + vec3(0.0, inclinacion_luz, 0.0)), 0.0)).xyz);

	v_primario = COLOR.rgb;
	v_dato = vec4(float(p.kit), float(p.piel), float(p.pelo), 0.0);
}

vec4 foto_vestida(vec2 uv, Persona p) {
	vec4 foto = texture(atlas_albedo, uv);
	vec3 mascara = texture(atlas_mascara, uv).rgb;
	vec3 coords = texture(atlas_coords, uv).rgb;
	vec4 pesos = vec4(mascara, coords.b);
	vec2 rest = vec2(coords.r * 2.0 - 1.0, coords.g * 2.0);
	// En las partes teñibles la foto guarda el sombreado a la mitad.
	float sombra = dot(foto.rgb, vec3(0.3333)) * 2.0;
	return vec4(vestir(foto.rgb, pesos, vec3(sombra), rest, p, v_primario), foto.a);
}

void fragment() {
	Persona p;
	p.kit = int(v_dato.x + 0.5);
	p.piel = int(v_dato.y + 0.5);
	p.pelo = int(v_dato.z + 0.5);
	// Se funden dos fotos seguidas para que el movimiento no vaya a saltos.
	vec4 c = mix(foto_vestida(v_uv_a, p), foto_vestida(v_uv_b, p), v_mezcla);
	ALBEDO = c.rgb * brillo;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
