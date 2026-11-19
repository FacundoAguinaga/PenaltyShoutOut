extends SceneTree

## Compara la picada con aire contra la parabola que predice el arquero:
## godot --headless --path . -s res://tools/test_picada.gd
func _init() -> void:
	var desde := Vector3(0.0, 0.11, 0.0)
	for caso in [[Vector3(0.0, 1.3, -11.0), 1.5], [Vector3(-2.5, 1.8, -11.0), 1.3], [Vector3(2.0, 1.3, -11.0), 1.05]]:
		var objetivo: Vector3 = caso[0]
		var t: float = caso[1]
		var hacia := objetivo - desde
		var parabola := Vector3(hacia.x / t, (hacia.y + 0.5 * 9.8 * t * t) / t, hacia.z / t)
		var giro := SoccerBall.giro_de_picada(parabola, 0.0)
		var v0 := SoccerBall.salida_picada(desde, parabola, giro)
		var llega := SoccerBall._simular_hasta(desde, v0, giro, t)
		# Altura maxima de cada una
		var alto_p := desde.y + parabola.y * parabola.y / 19.6
		var p := desde; var v := v0; var w := giro; var alto_a := 0.0; var h := 1.0 / 60.0; var tt := 0.0
		var vel_final := Vector3.ZERO
		var x_alto := 0.0
		while tt < t:
			v += SoccerBall.aceleracion_aire(v, w) * h; w *= exp(-0.25 * h); v.y -= 9.8 * h; p += v * h; tt += h
			if p.y > alto_a: alto_a = p.y; x_alto = -p.z
			vel_final = v
		print("objetivo %s t=%.2f | parabola v=%s (%.1f m/s, alto %.2f) | aire v=%s (%.1f m/s, alto %.2f) llega %s, cae a %.1f m/s con angulo %.0f°, lo mas alto a los %.1f m de 11 (parabola: angulo %.0f°)" % [objetivo, t, parabola, parabola.length(), alto_p, v0, v0.length(), alto_a, llega, vel_final.length(), rad_to_deg(atan2(-vel_final.y, Vector2(vel_final.x, vel_final.z).length())), x_alto, rad_to_deg(atan2(-(parabola.y - 9.8 * t), Vector2(parabola.x, parabola.z).length()))])
	quit()
