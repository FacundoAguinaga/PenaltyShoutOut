# Hinchada (tribunas)

La hinchada son ~24.000 espectadores repartidos en los nodos `CrowdSection`
de `scenes/stadium.tscn` (hijos del nodo `Crowd`, script `crowd_manager.gd`).

## Cómo funciona

- **Niveles de detalle por distancia.** Cada sección tiene tres versiones y
  Godot muestra una sola según la distancia a la cámara (y el zoom):
  - *cerca*: personaje 3D de ~2600 triángulos.
  - *media*: personaje 3D de ~1500 triángulos.
  - *lejos*: un cartel (impostor) con una foto del personaje, 2 triángulos.
  Los umbrales están en `Crowd > Rendimiento` (`px_cerca`, `px_media`: altura
  en pantalla de una persona, en píxeles a 1080p).
- **Animación por textura (VAT).** No hay esqueletos en juego: la posición de
  cada vértice en cada cuadro está horneada en una textura.
- **Variedad.** Cada espectador tiene tipo de NPC, camiseta o ropa común,
  pantalón, tono de piel, pelo (o gorra, o pelado), altura, contextura y
  personalidad.

## Agregar un NPC

1. Bajar un personaje de Mixamo en FBX **con skin** (pose en T).
2. Copiarlo a `assets/models/people/npc/`.
3. Abrir Godot una vez (o `godot --path . --import`) para que lo importe.
4. Hornear:

```bash
godot --path . res://tools/hinchada_hornear.tscn
```

El horneado detecta remera / pantalón / piel / calzado por el nombre de cada
malla (o por los huesos si el personaje es una sola malla). Si se equivoca,
crear `<personaje>.json` al lado del FBX:

```json
{"partes": {"NombreDeLaMalla": "remera"}}
```

Valores: `remera`, `pantalon`, `piel`, `otro`, `omitir`.

Qué tan seguido aparece cada NPC: `peso` de cada uno en
`resources/hinchada/banco.tres`.

## Equipaciones

En el nodo `Crowd`, grupo **Equipaciones**: `equipaciones_local` y
`equipaciones_visitante` son listas de `HinchadaEquipacion` (color primario,
secundario, patrón, pantalón y peso). Hasta 8 por equipo. Si están vacías se
inventan tres a partir de `home_team_color` / `away_team_color`.
`proporcion_camiseta` es cuántos hinchas van con camiseta; el resto usa ropa
común (`ROPA_COMUN` en `crowd_manager.gd`).

Patrones: liso, rayas verticales, aros, banda, mitades, franja en el pecho,
mangas.

## Comportamientos

`scripts/hinchada_conductas.gd` tiene una tabla: para cada **personalidad**
(tranquilo, hincha, fanático, charlatán, sufridor, aplaudidor, amargo,
eufórico) y cada **estado** (normal, tensión, festejo, festejo leve, lamento,
neutral), 4 animaciones posibles de pie y 4 sentado. Cada espectador cambia
de opción cada pocos segundos y reacciona con un retardo propio.

Cada `CrowdSection` tiene `estilo` (AUTO, PLATEA, GENERAL, POPULAR) que define
la mezcla de personalidades. En AUTO el manager arma zonas solo (grupos que
saltan, zonas tranquilas).

Para agregar una animación: sumarla a `ANIMS` en `tools/hinchada_hornear.gd`
(FBX de Mixamo en `assets/models/people/3d/`), hornear y usar su nombre en la
tabla de conductas. Máximo 16.

## Esquinas (secciones curvas)

`CrowdSection > Curva > curva_grados` dobla la sección en arco: 0 es recta,
90 es un cuarto de vuelta abrazando la cancha, negativo curva hacia afuera.
El nodo sigue marcando el medio de la primera fila; el radio sale solo del
ancho (`seats_per_row × seat_spacing`) y las filas de atrás llevan más gente.

Las cuatro esquinas del estadio ya están cargadas en `Crowd/Esquinas`
(tres bandejas curvas más las franjas rectas que las unen con las tribunas),
medidas sobre las butacas del modelo. Para vaciar una, desactivá `enabled`
en sus secciones o borrá el nodo `Esquina_XX`.

## Depurar

- `Crowd > Rendimiento > forzar_nivel`: obliga a toda la hinchada a un nivel.
- `Crowd > Rendimiento > depurar_animacion`: todos hacen esa animación.
- Fotos desde varias cámaras, con el costo de la hinchada en ms:

```bash
godot --path . res://tools/captura_tribuna.tscn -- /tmp/capturas gol
```
