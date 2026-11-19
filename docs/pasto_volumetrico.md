# Cesped de la cancha

El pasto de cancha es corto (3-4 cm) y muy denso, asi que NO se llena la
cancha de mallas de hojas. Igual que en los juegos de futbol comerciales, el
grueso del realismo esta en el shader del piso, y las hojas con volumen se
agregan solo cerca de la camara.

Son tres capas:

1. **Piso con POM** (`grass_volumetric.gdshader`), en toda la cancha. Color
   procedural, franjas de corte, desgaste y un paralaje de 3-4 cm que se
   apaga cuando el pixel es mas grande que una mata.
2. **Hojas con shells** (`grass_shells.gdshader`), solo en un parche de
   ~20 m alrededor de la camara: 16 planos apilados que recortan hojas con
   discard. Dan silueta real (la pelota y los botines quedan metidos
   en el pasto). Se apagan solas cuando la camara esta lejos.
3. **Lineas de cal** (`grass_lineas.gdshader`): las lineas del modelo,
   levantadas 4 mm (antes tenian z-fighting a lo lejos) y con el grano y las
   franjas del pasto.

## Archivos

| Archivo | Para que sirve |
| --- | --- |
| `assets/materials/grass_comun.gdshaderinc` | Codigo compartido: color, franjas, desgaste, viento. |
| `assets/materials/grass_volumetric.gdshader` | Piso (POM). |
| `assets/materials/grass_volumetric_material.tres` | Plantilla del material del piso (los valores reales vienen del nodo `Stadium`). |
| `assets/materials/grass_shells.gdshader` | Hojas cerca de camara. |
| `assets/materials/grass_shells_material.tres` | Densidad, ancho y vuelco de las hojas. |
| `assets/materials/grass_lineas.gdshader` | Lineas de cal. |
| `assets/materials/grass_horneado.gdshader` | Hornea manchas, tono, grano medio y desgaste en una textura para las hojas. |
| `scripts/cesped_volumetrico.gd` | Asigna los materiales, hornea la mascara de lineas y mueve el parche de hojas. Va en el nodo raiz de `scenes/stadium.tscn`. |

## Por que no se edita el modelo

`assets/models/stadium_optimizado.scn` se regenera con
`tools/optimizar_estadio.gd`, que junta los triangulos por material. Cualquier
cambio manual en ese `.scn` se pierde. Por eso `cesped_volumetrico.gd`
recorre las mallas al iniciar y reemplaza por nombre de material:

- `auto_1`: la cancha → material de piso.
- `auto_30`: las lineas → material de lineas. Ademas, con sus triangulos se
  hornea una mascara (4 cm por pixel, ~150 ms al cargar) para que las hojas
  que caen sobre la cal salgan blancas.
- `Trawa_03_1`: cesped perimetral, no se toca.

Si el modelo cambia de nombres de material, se ajustan `target_materials` y
`line_materials` en el inspector del nodo `Stadium`.

## Franjas de corte

En una cancha real las franjas no son dos verdes: el pasto esta peinado hacia
un lado en una franja y hacia el otro en la siguiente. Por eso:

- `stripe_view`: contraste que depende de la camara. La franja peinada
  alejandose de la camara se ve clara; si la camara gira 180 grados, se
  invierten.
- `stripe_fixed`: contraste fijo, para que se vean tambien desde arriba.
- Las normales del piso se inclinan con el peinado (`lean_normal`), asi que
  los focos tambien pintan distinto cada franja.
- El borde ondula un poco y es suave (`stripe_softness`).

## Editor y parametros

`cesped_volumetrico.gd` es `@tool`: al abrir `stadium.tscn` o `game.tscn` en
el editor se ve el pasto completo en el viewport, con las hojas siguiendo a la
camara del editor.

**Todo se tunea desde el inspector del nodo `Stadium`**, agrupado en:

| Grupo | Que tiene |
| --- | --- |
| Color del pasto | `grass_base`, `grass_dark`, `grass_tip`, manchas, grano, color de cal. |
| Desgaste | Fuerza y color del pasto gastado (punto de penal, boca del arco). |
| Franjas de corte | Ancho, contraste segun camara, contraste fijo, borde, linea de meta. |
| Viento | Fuerza y velocidad. |
| Piso (paralaje) | `grass_height` (alto del pasto, piso y hojas), densidad del relieve, normales, AO, `fade_start`/`fade_end`. |
| Hojas | Prender/apagar, densidad, grosor, vuelco, variacion de tono. |
| Hojas: capas y LOD | `shell_layers`, `shell_radius`, `shell_fade_dist`, `layer_px`, `min_layers`, `shell_tile_size`. |
| Debug | Vista de debug del piso; hojas en rojo. |
| Avanzado | Nombres de materiales del modelo, resoluciones de las mascaras. |

Los cambios se ven en vivo. Los `.tres` de `assets/materials` quedan como
plantilla: el script los duplica y les pasa los valores del nodo, asi que no
se modifican.

Al guardar la escena en el editor, el script saca los materiales que puso
(`NOTIFICATION_EDITOR_PRE_SAVE`) y los vuelve a poner despues: en el `.tscn`
solo quedan los valores exportados.

### LOD de las hojas

- `shell_layers`: capas maximas, las que se usan de cerca.
- `layer_px`: cada cuantos pixeles de alto de hoja hace falta una capa. Lejos
  la hoja mide pocos pixeles y quedan pocas capas. Subirlo = mas barato.
- `min_layers`: piso de capas aunque este lejos.
- `shell_fade_dist`: distancia donde las hojas desaparecen (se funden con el
  piso desde el 60% de esa distancia).
- `shell_radius`: tamano del parche que sigue a la camara.
- `shell_tile_size`: tamano de las baldosas en las que se decide el LOD.

## Rendimiento

Medido en una GTX 1650 a 1920x1080, vista de juego (camara fija del penal):

| Configuracion | FPS |
| --- | --- |
| Sin hojas | 50 |
| Hojas, sin AA | 38 |
| Hojas + MSAA 2x / SMAA / TAA | 34 |

Lo que aprendimos midiendo:

- El costo de las hojas es casi todo rasterizar capas. Ni la luz ni el ruido
  pesan (hornear el color en una textura no cambio los FPS).
- **LOD por baldosa**: cada capa esta partida en baldosas de 2.5 m y el vertex
  shader deja solo las capas necesarias para la distancia (una cada
  `layer_px` pixeles de alto de hoja, minimo `min_layers`). Las demas se
  colapsan a triangulos de area cero. A la distancia de la pelota quedan ~5
  de 16 capas. Paso de 21 a 38 FPS.
- **Pase transparente**: las hojas escriben `ALPHA = 1` y profundidad en vez de
  usar alpha scissor; asi no pasan por el depth prepass (que corria el shader
  dos veces). Las capas se dibujan de arriba hacia abajo para que el early-z
  descarte lo tapado.
- **Tamano de pixel isotropico**: la visibilidad de las hojas usa cuanto mide
  un pixel a esa distancia, no `fwidth` sobre el piso. A ras del piso el
  pixel proyectado se estira mucho en profundidad y las hojas se apagaban en
  la vista de juego aunque se ven perfectamente (son verticales).

### Antialiasing

El proyecto usa **SMAA** (`rendering/anti_aliasing/quality/screen_space_aa`).

- **MSAA no sirve para las hojas**: se recortan con `discard`, que mata todas
  las muestras del pixel. Se ve igual que sin AA y cuesta lo mismo que TAA.
- **SMAA**: suaviza un poco, conserva el detalle de las hojas.
- **TAA**: lineas limpias y sin titileo en movimiento, pero funde las hojas en
  una superficie mas lisa. Puede dejar estela en la pelota.
- Comparacion: `docs/capturas_pasto/comparacion_aa.png` (sin AA, MSAA 2x /
  SMAA, TAA).

## Debug

Grupo "Debug" del nodo `Stadium`:

- `debug_mode`: vista del piso (Altura, Normales, Detalle = cuanto paralaje se
  aplica, Desgaste).
- `debug_shells`: pinta las hojas de rojo, para ver hasta donde llegan.

## Limitaciones

- El piso con POM no tiene silueta; la silueta solo existe en el parche de
  hojas.
- Las hojas no proyectan sombra propia (la oclusion es aproximada con color
  de raiz y AO).
- Las hojas no se aplastan cuando pasa un jugador.
