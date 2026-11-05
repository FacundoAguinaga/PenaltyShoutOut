shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D vat_texture : filter_nearest, hint_default_black;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;

uniform int vat_width = 2315;
uniform int total_frames = 474;

// Colores de equipo para teñir ropa
uniform vec4 home_team_color : source_color = vec4(0.85, 0.15, 0.15, 1.0); // Rojo
uniform vec4 away_team_color : source_color = vec4(0.15, 0.35, 0.90, 1.0); // Azul
uniform vec4 neutral_color : source_color = vec4(0.85, 0.85, 0.85, 1.0);   // Blanco/Gris

// Reaccion de toda la hinchada (la pone CrowdManager): 0 normal, 1 gol,
// 2 lamento (fallo el que patea), 3 tension antes del penal. Cada espectador
// elige su animacion aca segun su equipo y un numero al azar propio, asi
// cambiar de reaccion es cambiar un uniform y no reescribir 25.000 instancias.
uniform int reaccion = 0;
// Equipo que festeja el gol (reaccion 1) o del que patea y fallo (reaccion 2):
// 0 local, 1 visitante.
uniform int equipo_reaccion = 0;

struct AnimData {
	int start_frame;
	int frame_count;
};

AnimData get_anim_data(int anim_id) {
	AnimData a;
	if (anim_id == 0) { a.start_frame = 0; a.frame_count = 60; }        // idle parado
	else if (anim_id == 1) { a.start_frame = 60; a.frame_count = 88; }   // cheer (festejo de pie)
	else if (anim_id == 2) { a.start_frame = 148; a.frame_count = 90; }  // victory (celebración)
	else if (anim_id == 3) { a.start_frame = 238; a.frame_count = 90; }  // angry (lamento/enojo)
	else if (anim_id == 4) { a.start_frame = 328; a.frame_count = 36; }  // clap (aplauso parado)
	else if (anim_id == 5) { a.start_frame = 364; a.frame_count = 60; }  // sitting (sentado idle)
	else if (anim_id == 6) { a.start_frame = 424; a.frame_count = 50; }  // sitting_clap (sentado aplaudiendo)
	else { a.start_frame = 0; a.frame_count = 60; }
	return a;
}

varying vec4 instance_tint;

void vertex() {
	// INSTANCE_CUSTOM components:
	// x: time offset / phase (0.0 to 10.0)
	// y: animation id (0 to 6)
	// z: playback speed factor (e.g. 0.9 to 1.1)
	// w: team tint id (0 = home, 1 = away, 2 = neutral, 3 = per-instance COLOR)
	
	float time_offset = INSTANCE_CUSTOM.x;
	int anim_id = int(round(INSTANCE_CUSTOM.y));
	float speed = INSTANCE_CUSTOM.z > 0.01 ? INSTANCE_CUSTOM.z : 1.0;
	int tint_id = int(round(INSTANCE_CUSTOM.w));

	// Numero al azar fijo por espectador (time_offset ya es al azar 0-10).
	float azar = fract(sin(time_offset * 91.3458) * 47453.5453);
	bool propio = tint_id == equipo_reaccion;
	bool rival = tint_id == 1 - equipo_reaccion;
	if (reaccion == 1) {
		// Gol: los del equipo festejan, los rivales se enojan, el resto aplaude.
		if (propio) { anim_id = azar < 0.6 ? 1 : 2; }
		else if (rival) { anim_id = 3; }
		else { anim_id = azar < 0.7 ? 4 : 2; }
	} else if (reaccion == 2) {
		// Fallo el que patea: su hinchada se lamenta y la rival festeja.
		if (propio) { anim_id = 3; }
		else if (rival) { anim_id = azar < 0.6 ? 2 : 4; }
		else { anim_id = azar < 0.5 ? 4 : 0; }
	} else if (reaccion == 3) {
		anim_id = azar < 0.75 ? 0 : 4;
	}

	if (tint_id == 0) {
		instance_tint = home_team_color;
	} else if (tint_id == 1) {
		instance_tint = away_team_color;
	} else if (tint_id == 2) {
		instance_tint = neutral_color;
	} else {
		instance_tint = vec4(1.0);
	}
	// Variacion de brillo por instancia (CrowdManager setea
	// set_instance_color(shade 0.75-1.0)). Sin esto toda la tribuna
	// queda plana y se pierde el moteado organico.
	instance_tint.rgb *= COLOR.rgb;
	
	AnimData anim = get_anim_data(anim_id);
	
	// Calcular fotograma con interpolación suave
	float anim_time = (TIME + time_offset) * 30.0 * speed;
	float local_frame = mod(anim_time, float(anim.frame_count));
	if (local_frame < 0.0) {
		local_frame += float(anim.frame_count);
	}
	
	int frame_a = anim.start_frame + int(floor(local_frame));
	int frame_b = anim.start_frame + int(mod(floor(local_frame) + 1.0, float(anim.frame_count)));
	float blend = fract(local_frame);
	// Seguridad: si el JSON y el shader divergen, no leer fuera de la textura
	frame_a = clamp(frame_a, 0, total_frames - 1);
	frame_b = clamp(frame_b, 0, total_frames - 1);

	// Decodificar el ID de vértice original desde UV2.x.
	// UV2.x = (v_idx + 0.5) / vat_width (ver prepare_crowd_asset.py).
	// En vertex() UV2 es por-vertice (no interpolado), asi que el floor
	// recupera el v_idx original aunque Godot haya spliteado vertices
	// por costuras de UV/normales.
	// REQUIERE: GLB importado sin LODs, sin shadow mesh y sin compresion
	// de vertices, o los UV2 interpolados rompen el v_id (ver .import).
	int v_id = int(floor(UV2.x * float(vat_width)));
	v_id = clamp(v_id, 0, vat_width - 1);

	// Leer posiciones horneadas en la textura flotante.
	// REQUIERE: crowd_vat.exr importado lossless, sin mipmaps, sin
	// fix_alpha_border y sin compresion VRAM (ver .import). Cualquier
	// filtro/cuantizacion aca estira los vertices a metros de error.
	vec3 pos_a = texelFetch(vat_texture, ivec2(v_id, frame_a), 0).xyz;
	vec3 pos_b = texelFetch(vat_texture, ivec2(v_id, frame_b), 0).xyz;

	VERTEX = mix(pos_a, pos_b, blend);
	// NORMAL se deja del bind-pose: correcto para crowd a distancia,
	// evita necesitar una segunda VAT de normales.
}

void fragment() {
	vec4 col = texture(albedo_texture, UV);
	
	// Teñir camiseta y pantalón (zona del torso en UV: U en [0, 0.45], V en [0.2, 0.75])
	if (UV.x < 0.45 && UV.y > 0.22 && UV.y < 0.72) {
		col.rgb = mix(col.rgb, col.rgb * instance_tint.rgb * 1.4, 0.75);
	}
	
	ALBEDO = col.rgb;
	ROUGHNESS = 0.7;
	METALLIC = 0.05;
}
