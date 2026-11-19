shader_type spatial;
render_mode unshaded, cull_back;

// Solo lo usa tools/hinchada_hornear.gd para sacar las "fotos" de los
// impostores. Cada instancia muestra un cuadro fijo de una animacion:
//   INSTANCE_CUSTOM.x = animacion, INSTANCE_CUSTOM.y = cuadro
// modo 0: color (las partes que despues se tiñen quedan en gris)
// modo 1: mascara (R remera, G pantalon, B piel)
// modo 2: coordenadas del cuerpo en T (R x, G y) + pelo (B)

uniform sampler2D vat : filter_nearest, repeat_disable;
uniform sampler2D albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 lum_media = vec4(0.3);
uniform int modo = 0;

#include "res://resources/shaders/hinchada_comun.gdshaderinc"

varying vec4 v_pesos;
varying vec2 v_rest;

void vertex() {
	int anim = int(INSTANCE_CUSTOM.x + 0.5);
	v_rest = VERTEX.xy;
	v_pesos = pesos_de_parte(UV2.y);
	VERTEX = muestra_vat(vat, int(UV2.x + 0.5), anim, INSTANCE_CUSTOM.y);
}

void fragment() {
	vec4 tx = texture(albedo, UV);
	vec3 base = tx.rgb;
	float pelo = (1.0 - tx.a) * v_pesos.z;
	vec4 pesos = vec4(v_pesos.xy, v_pesos.z - pelo, v_pesos.w + pelo);
	if (modo == 0) {
		// Un poco de volumen: luz fija desde arriba y adelante.
		vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		float luz = 0.72 + 0.28 * clamp(dot(n, normalize(vec3(0.15, 0.65, 0.75))), 0.0, 1.0);
		float tenible = pesos.x + pesos.y + pesos.w;
		float sombra = sombra_parte(base, lum_media.x) * pesos.x
				+ sombra_parte(base, lum_media.y) * pesos.y
				+ sombra_parte(base, lum_media.w) * pesos.w;
		// Se guarda a la mitad para que entre el rango 0 a 2.
		ALBEDO = (base * (1.0 - tenible) + vec3(sombra * 0.5)) * luz;
	} else if (modo == 1) {
		ALBEDO = pesos.xyz;
	} else {
		ALBEDO = vec3(clamp(v_rest.x * 0.5 + 0.5, 0.0, 1.0), clamp(v_rest.y * 0.5, 0.0, 1.0), pesos.w);
	}
}
