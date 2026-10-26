class_name GoalkeeperStats
extends Resource

@export_range(0, 100) var reflexes: float = 50.0
@export_range(0.05, 0.5) var reaction_time: float = 0.25
@export_range(0, 100) var reach: float = 50.0
@export_range(0, 100) var dive_speed: float = 50.0
## Hasta que velocidad (m/s) el arquero agarra la pelota. Mas fuerte que esto,
## si llega, la tapa y rebota. Los tiros van de 15 a 40 m/s.
@export_range(10, 45) var velocidad_max_atajar: float = 24.0
