extends Node3D
class_name RedArco

## Deforma la red cuando la pelota la golpea.
##
## El calculo de la deformacion vive en net.gdshader (se hace en el vertex
## shader). Este script solo detecta el impacto y le pasa al shader tres cosas:
## donde pego la pelota, en que direccion iba, y cuanto tiempo paso desde
## entonces. Se usa un contador propio en vez del TIME del shader para no
## depender de cuanto hace que arranco el juego.

@export var pelota: RigidBody3D
## Cuanto se hunde la red como maximo, en metros.
@export var fuerza_maxima: float = 0.75
## Ancho de la zona que se deforma alrededor del impacto, en metros.
@export var radio: float = 1.3
## Por debajo de esta velocidad el impacto no se nota.
@export var velocidad_minima: float = 3.0
## Cuanto dura la deformacion antes de volver a quedar quieta.
@export var duracion: float = 1.5

var _material: ShaderMaterial
var _cuerpo: StaticBody3D
var _tiempo: float = -1.0

func _ready() -> void:
	# Los cuatro paneles comparten el mismo material, asi que alcanza con
	# tomarlo de uno: el shader calcula la distancia al impacto por vertice,
	# y solo se deforma el panel que quedo cerca.
	var fondo := get_node_or_null("Fondo") as MeshInstance3D
	if fondo:
		_material = fondo.get_surface_override_material(0) as ShaderMaterial
	_cuerpo = get_node_or_null("Cuerpo") as StaticBody3D

	if _material:
		_material.set_shader_parameter("radio", radio)
		_material.set_shader_parameter("dt_impacto", -1.0)

	if pelota:
		pelota.contact_monitor = true
		pelota.max_contacts_reported = 4
		pelota.body_entered.connect(_al_chocar)

func _al_chocar(cuerpo: Node) -> void:
	if _material == null or cuerpo != _cuerpo:
		return
	var v: Vector3 = pelota.linear_velocity
	if v.length() < velocidad_minima:
		return
	_material.set_shader_parameter("impacto", pelota.global_position)
	_material.set_shader_parameter("dir_impacto", v.normalized())
	_material.set_shader_parameter("fuerza", fuerza_maxima * clampf(v.length() / 25.0, 0.25, 1.0))
	_tiempo = 0.0

func _process(delta: float) -> void:
	if _tiempo < 0.0 or _material == null:
		return
	_tiempo += delta
	if _tiempo > duracion:
		_tiempo = -1.0
		_material.set_shader_parameter("dt_impacto", -1.0)
		return
	_material.set_shader_parameter("dt_impacto", _tiempo)
