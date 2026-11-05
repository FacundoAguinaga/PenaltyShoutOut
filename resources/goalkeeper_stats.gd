class_name GoalkeeperStats
extends Resource

@export_range(0, 100) var reflexes: float = 50.0
@export_range(0.05, 0.5) var reaction_time: float = 0.25
@export_range(0, 100) var reach: float = 50.0
@export_range(0, 100) var dive_speed: float = 50.0
## Hasta que velocidad (m/s) el arquero agarra la pelota. Mas fuerte que esto,
## si llega, la tapa y rebota. Los tiros van de 15 a 40 m/s.
@export_range(10, 45) var velocidad_max_atajar: float = 24.0
## Error de percepcion (0 = lee el tiro perfecto, 1 = se equivoca mucho de
## zona). Es lo que de verdad separa las dificultades: ErrorModule lo usa como
## radio del error con el que el arquero estima por donde va la pelota.
@export_range(0, 1) var error_percepcion: float = 0.4
