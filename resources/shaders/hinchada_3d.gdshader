shader_type spatial;
render_mode cull_back;

// Espectador 3D (niveles de detalle cerca, media y baja). El cuerpo se mueve
// leyendo la posicion de cada vertice de una textura (VAT): UV2.x dice que
// columna le toca al vertice y UV2.y que parte del cuerpo es.

uniform sampler2D vat : filter_nearest, repeat_disable;
uniform sampler2D vat_normales : filter_nearest, repeat_disable;
uniform sampler2D albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 lum_media = vec4(0.3);

#include "res://resources/shaders/hinchada_comun.gdshaderinc"

varying vec4 v_pesos;
varying vec2 v_rest;
varying vec3 v_primario;
varying flat vec4 v_dato;

void vertex() {
	Persona p = leer_persona(INSTANCE_CUSTOM);
	Mezcla m = calcular_mezcla(p);
	int columna = int(UV2.x + 0.5);

	float cuadro_b = cuadro_anim(m.anim_b, p.semilla);
	vec3 pos = muestra_vat(vat, columna, m.anim_b, cuadro_b);
	vec3 nor = muestra_normal(vat_normales, columna, m.anim_b, cuadro_b);
	if (m.peso < 0.999 && m.anim_a != m.anim_b) {
		float cuadro_a = cuadro_anim(m.anim_a, p.semilla);
		pos = mix(muestra_vat(vat, columna, m.anim_a, cuadro_a), pos, m.peso);
		nor = mix(muestra_normal(vat_normales, columna, m.anim_a, cuadro_a), nor, m.peso);
	}
	NORMAL = normalize(nor);
	pos.y += m.salto * salto_y(p.semilla);

	v_rest = VERTEX.xy;
	v_pesos = pesos_de_parte(UV2.y);
	v_primario = COLOR.rgb;
	v_dato = vec4(float(p.kit), float(p.piel), float(p.pelo), 0.0);
	VERTEX = pos;
}

void fragment() {
	vec4 tx = texture(albedo, UV);
	vec3 base = tx.rgb;
	// El pelo viene pintado en el alfa de la textura (0 = pelo).
	float pelo = (1.0 - tx.a) * v_pesos.z;
	vec4 pesos = vec4(v_pesos.xy, v_pesos.z - pelo, v_pesos.w + pelo);
	Persona p;
	p.kit = int(v_dato.x + 0.5);
	p.piel = int(v_dato.y + 0.5);
	p.pelo = int(v_dato.z + 0.5);
	vec3 sombras = vec3(sombra_parte(base, lum_media.x), sombra_parte(base, lum_media.y),
			sombra_parte(base, lum_media.w));
	ALBEDO = vestir(base, pesos, sombras, v_rest, p, v_primario);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
