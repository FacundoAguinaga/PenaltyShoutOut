# Animaciones del arquero

Cómo están hechas las animaciones del arquero, cómo las usa el juego y cómo
agregar nuevas.

## 1. Las que usa el juego: Cascadeur v2

34 animaciones hechas en Cascadeur, en `Player/Animations/cascadeur_v2/`:

- `*.fbx`: los originales exportados de Cascadeur (esqueleto Manny).
- `*.res`: las mismas pasadas al esqueleto del arquero. **Son las que usa el
  juego**, en la librería `arquero_cascadeur_v2.tres` (`cascadeur/...` en el
  AnimationPlayer).

Las de Blender (`Player/Animations/blender/`, librería `blender/...`) siguen en
el proyecto pero no se usan; sus recursos están en
`resources/animresources/blender/`. Ver el anexo al final.

- **Save_\***: el arquero la agarra.
- **Dive_\***: el arquero se tira. Según la jugada le rebota en las manos o es gol.
- **medio**: zona central. **derecha / izquierda**: el lado, desde la vista del
  pateador (+X = derecha; se verificó: "derecha" se tira hacia +X en el juego).
  Las "izquierda" son espejos exactos de las "derecha".

## 2. Las 9 zonas del arco

El código clasifica cada remate en una grilla de 3×3
(`scripts/dive_anim_data.gd`, enum `Zone`):

| | Izquierda | Centro | Derecha |
|---|---|---|---|
| **Arriba** (> 1,63 m) | 0 TOP_LEFT | 1 TOP_CENTER | 2 TOP_RIGHT |
| **Media** | 3 MID_LEFT | 4 MID_CENTER | 5 MID_RIGHT |
| **Abajo** (< 0,81 m) | 6 BOTTOM_LEFT | 7 BOTTOM_CENTER | 8 BOTTOM_RIGHT |

Centro = a menos de 1,22 m del medio del arco.

## 3. Cómo se decide la jugada

Se decide **antes** de arrancar la animación (en `on_ball_kicked`), así la
animación nunca contradice el resultado (`scripts/result_module.gd`):

1. El arquero elige una zona con lo que cree (con el error según dificultad).
2. **Se tiró a otra zona** que la del tiro → animación DIVE de la zona que
   eligió → **GOL**. Si hace falta se lo corre para que la pelota pase a 0,6 m
   de su cuerpo y su mano.
3. **Acertó la zona y el tiro no es muy fuerte** → animación SAVE → **la
   agarra**: al contacto la pelota queda pegada entre los nudillos de las dos
   manos (o en la mano del contacto si están separadas) y las sigue.
4. **Acertó la zona pero el tiro es fuerte** → animación DIVE de esa zona → al
   contacto **la pelota rebota** (`_rebotar()`): sale hacia la cancha y para
   el costado.

"Muy fuerte" depende de la dificultad: `velocidad_max_atajar` en
`resources/goalkeeper_stats_*.tres`. Fácil 20 m/s, medio 24 m/s, difícil
28 m/s. Los tiros van de 15 a 40 m/s.

Dentro de una zona puede haber varias animaciones del mismo tipo: se elige la
que toca **más cerca** de por donde el arquero cree que pasa la pelota
(`AnimSelector.elegir()`). Si la zona no tiene ninguna de ese tipo, se usa la
más cercana de cualquier zona y se avisa por consola
(`[AnimSelector] Zona ... sin ...`).

### Que la mano llegue a tiempo (y se vea natural)

El arquero **arranca cuando el pateador suelta el tiro**, no cuando sale la
pelota: el tiro ya está definido en ese momento (fuerza y dirección), así que
lo "lee" como un arquero de verdad (`anticipar()`, llamado desde
`GameManager._on_kick_connecting`). De soltar a patear pasan ~1,1 s (pausa de
0,4 s + la carrera de la animación de patada hasta el golpe, 0,715 s;
`PlayerKicker.seconds_until_contact()`).

El plan hace que el arquero **despegue con la patada y no antes**: cada
animación tiene su `despegue` (el cuadro en que la cadera arranca de costado o
hacia arriba, lo mide el bakeo). Hasta la patada hace la preparación a
velocidad normal; cuando se patea de verdad (`on_ball_kicked`) se acelera la
estirada (hasta 1,8x) para que la mano llegue justo con la pelota. Si la
estirada es demasiado larga para eso, despega un poco antes.

Si la pelota se patea sin pasar por el pateador (por ejemplo en las pruebas),
el arquero reacciona recién ahí y `TimingModule.planificar()` arranca la
animación más adelantada y la acelera hasta 1,8x.

Para que la mano llegue a la pelota el arquero se corre de costado, pero solo
durante la estirada (los últimos 0,45 s antes del contacto) y con arranque y
frenada suaves. El contacto se detecta cuando la pelota cruza el plano de las
manos (o choca con los colisionadores del cuerpo).

### El arquero no atraviesa los palos

Algunas palomitas siguen de largo después del contacto. `_esquivar_palos()`
predice cada cuadro dónde va a estar cada parte del cuerpo un instante
después y, si se va a meter en un palo, corre al arquero hacia la cancha lo
justo para que pase por delante: conserva la inercia de la palomita y cae
delante del palo. Medido con la 17 y la 18: el cuerpo pasa a 0,23–0,40 m del
palo (antes lo atravesaba 11 cm). Los palos se configuran en el arquero
(`palos`, `radio_palo`).

### Tiros al palo y goles

- El arquero calcula por dónde pasa la pelota en la **línea de gol** (z = -11,
  donde están los palos). Antes lo hacía en z = -12 y un tiro cruzado que
  entraba pegado al palo daba "afuera": el arquero no se movía y era gol.
- Se tira también a las pelotas que van **al palo** (pueden rebotar para
  adentro).
- `GoalZone` empieza 22 cm detrás de la línea: es gol cuando la pelota la
  cruzó **entera**. Antes una pelota que pegaba en el palo y quedaba rozando la
  línea por delante contaba como gol.

### Para probar: `siempre_adivina`

En el arquero (`Goalkeeper` en `scenes/game.tscn`, grupo System Config).
Prendido, siempre elige la zona correcta y reacciona sin demora: nunca es gol
por tirarse al otro lado, solo ATAJA o REBOTE. **Está prendido: apagarlo para
jugar de verdad.**

## 4. Las 34 animaciones

Zona asignada **por dónde toca la mano** (nudillos, medido en el modelo del
juego). Contacto = cuadro de Cascadeur (30 fps, desde 0): el primero en que
los nudillos llegan a su punto (en las que después se deslizan con la mano
quieta, el contacto es cuando llega, no cuando termina de deslizarse).

| Animación | Tipo | Zona | Contacto | Mano en el contacto (x, y) m |
|---|---|---|---|---|
| Save_medio_arriba | SAVE | TOP_CENTER | 31 (1,03 s) | (0,07, 2,47) |
| Save_medio_derecha_9 | SAVE | TOP_CENTER | 32 (1,07 s) | (0,31, 2,02) |
| Save_medio_izquierda_9 | SAVE | TOP_CENTER | 32 (1,07 s) | (-0,32, 2,02) |
| Save_medio_derecha_1 | SAVE | MID_CENTER | 35 (1,17 s) | (0,52, 1,57) |
| Save_medio_izquierda_1 | SAVE | MID_CENTER | 35 (1,17 s) | (-0,53, 1,57) |
| Save_medio_4 | SAVE | BOTTOM_CENTER | 30 (1,00 s) | (-0,14, 0,21) |
| Save_derecha_11 | SAVE | BOTTOM_RIGHT | 44 (1,47 s) | (2,48, 0,21) |
| Save_derecha_12 | SAVE | BOTTOM_RIGHT | 41 (1,37 s) | (2,49, 0,23) |
| Save_derecha_13 | SAVE | BOTTOM_RIGHT | 34 (1,13 s) | (2,15, 0,25) |
| Save_izquierda_11/12/13 | SAVE | BOTTOM_LEFT | 45 / 42 / 34 | espejo |
| Dive_medio_arriba | DIVE | TOP_CENTER | 32 (1,07 s) | (-0,07, 2,53) |
| Dive_medio_derecha_9 | DIVE | TOP_CENTER | 31 (1,03 s) | (0,28, 2,01) |
| Dive_medio_izquierda_9 | DIVE | TOP_CENTER | 31 (1,03 s) | (-0,29, 2,02) |
| Dive_medio | DIVE | MID_CENTER | 21 (0,70 s) | (0,09, 1,20) |
| Dive_medio_derecha_1 / _2 | DIVE | MID_CENTER | 44 / 33 | (0,51, 1,59) / (0,54, 1,03) |
| Dive_medio_izquierda_1 / _2 | DIVE | MID_CENTER | 44 / 33 | espejo |
| Dive_derecha_11 | DIVE | MID_RIGHT | 38 (1,27 s) | (2,38, 0,84) |
| Dive_izquierda_11 | DIVE | MID_LEFT | 38 (1,27 s) | (-2,39, 0,84) |
| Dive_medio_derecha_3 | DIVE | BOTTOM_CENTER | 31 (1,03 s) | (0,69, 0,57) |
| Dive_medio_izquierda_3 | DIVE | BOTTOM_CENTER | 31 (1,03 s) | (-0,69, 0,57) |
| Dive_derecha_13 | DIVE | BOTTOM_RIGHT | 40 (1,33 s) | (2,28, 0,17) |
| Dive_medio_derecha_12 | DIVE | BOTTOM_RIGHT | 42 (1,40 s) | (2,49, 0,14) |
| Dive_izquierda_13 / Dive_medio_izquierda_12 | DIVE | BOTTOM_LEFT | 46 / 44 | espejo |
| Dive_derecha_17 | DIVE | TOP_RIGHT | 32 (1,07 s) | (3,46, 2,03) |
| Dive_derecha_18 | DIVE | MID_RIGHT | 32 (1,07 s) | (3,37, 1,22) |
| Dive_derecha_19 | DIVE | BOTTOM_RIGHT | 32 (1,07 s) | (3,42, 0,45) |
| Dive_izquierda_17 / 18 / 19 | DIVE | TOP_LEFT / MID_LEFT / BOTTOM_LEFT | 32 | espejo |

Las 17, 18 y 19 son dives al palo y no tienen punto de referencia de
Cascadeur: el contacto es el primer cuadro en que los nudillos llegan a
x ≥ 3,30 m (la pelota pegada al palo). Las tres llegan en el cuadro 32.

Después del contacto la 17 y la 18 siguen de largo (la mano termina en x = 5,2
y 4,3 m) y el cuerpo atravesaría el palo. En el juego no pasa: ver "El arquero
no atraviesa los palos" más arriba.

### Zonas que no tienen animación propia

| Zona | Falta | Se usa (la más cercana) |
|---|---|---|
| TOP_LEFT / TOP_RIGHT | SAVE | Save_izquierda/derecha_12 |
| MID_LEFT / MID_RIGHT | SAVE | Save_izquierda/derecha_12 |

Todas las zonas tienen DIVE. En esas cuatro, al **agarrar** la mano queda lejos
de la pelota (en la prueba: 1,45 m arriba y 0,75 m a media altura) y la pelota
"salta" a las manos. Para que se vean bien hacen falta atajadas arriba y a
media altura a los costados (contacto cerca de (±2,5, 2,0) y (±2,5, 1,2), o
pegadas al palo como las 17/18).

## 5. Cómo se pasan de Cascadeur al juego

Los FBX de Cascadeur usan el esqueleto de Unreal **Manny** (`root`, `pelvis`,
`spine_01..05`, `upperarm_l`...) y el arquero usa **Mixamo** (`mixamorig1Hips`...).
No se usa el BoneMap del importador de Godot porque renombraría los huesos del
arquero y rompería las animaciones Mixamo que ya tiene la escena (idle, etc.).

`tools/retarget_manny.gd` las convierte, hueso por hueso, en espacio de mundo:

- Copia **cuánto giró** cada hueso de Manny respecto de su pose de reposo, y lo
  aplica al hueso equivalente del arquero corrigiendo la diferencia de reposos
  (Manny está en A-pose y Mixamo en T-pose): la dirección de cada hueso en el
  juego es la misma que en Cascadeur.
- La pose de referencia del arquero es la del **skin** de la malla (T-pose). El
  "rest" del Skeleton3D de la escena es una pose cualquiera y no sirve.
- Los huesos twist e ik_* de Manny se ignoran; los dedos se pasan.
- **Root motion**: el desplazamiento del `root` se suma a la cadera (como en
  las animaciones Mixamo) y se resta la posición del cuadro 0, así arranca
  donde está el arquero y no salta. El arquero no se mueve por root motion: el
  código lo corre lo justo para que la mano llegue a la pelota.
- Escala por altura de cadera: 1,04.

Para volver a convertir (después de cambiar o agregar FBX en la carpeta):

```
godot --headless --path . res://tools/retarget_manny.tscn
```

Medido: la mano en el juego queda a 1–16 cm del punto medido en Cascadeur, y
los pies nunca bajan del piso (mínimo 0,8 cm).

## 6. Agregar una animación nueva

1. Exportar el FBX desde Cascadeur (30 fps, esqueleto Manny) a
   `Player/Animations/cascadeur_v2/` y correr `retarget_manny.tscn`.
2. Crear su `DiveAnimData` en `resources/animresources/` (y sumarlo a
   `libreria_animaciones` del arquero en `scenes/game.tscn`):

| Campo | Qué es |
|---|---|
| `anim_name` | `cascadeur/<nombre del fbx>` |
| `zone` | El número de la tabla de zonas (0 a 8), por dónde toca la mano. |
| `tipo` | `0` = SAVE (la agarra), `1` = DIVE (rebote o gol). |
| `contact_time` | Segundo en que la mano llega a la pelota (cuadro / 30). |
| `hand_bone` | `mixamorig1LeftHandMiddle1` o `mixamorig1RightHandMiddle1` (nudillos de la mano que llega). |
| `canonical_target` | **No se escribe a mano.** Lo calcula el bakeo. |

3. Correr el bakeo: `godot --headless --path . res://tools/bakear.tscn`.

**No crees recursos vacíos "para después"**: un recurso con `anim_name` en
blanco se elige igual y el arquero no anima nada.

## 7. Herramientas

| Herramienta | Para qué |
|---|---|
| `tools/retarget_manny.tscn` | Pasa los FBX de Cascadeur al esqueleto del arquero. |
| `tools/medir_cascadeur.tscn` | Busca el cuadro de contacto de cada una comparando con el punto medido en Cascadeur, y el pie más bajo. |
| `tools/bakear.tscn` | Calcula el `canonical_target` de cada `DiveAnimData`. |
| `tools/contacto.tscn` | Ventana de contacto de cada una (cuadros en que la mano está a menos de 15 cm del punto de contacto). |
| `tools/test_tiros.tscn` | Patea a las 9 zonas y muestra animación, resultado, distancia mano-pelota y dónde termina la pelota. `VEL=18` suave, `VEL=32` fuerte, `FORZAR=fallo` fuerza gol, `TIRO=3` un solo tiro con la trayectoria, `PATEADOR=1 POT=80` patea con el pateador (carrera incluida, como en el juego), `POSTE=1` patea pegado a los palos, `FULL=1` apunta afuera de los palos (con `PATEADOR=1` el tiro cruzado entra pegado al palo). También muestra cuánto le sobra al cuerpo hasta el palo. |

En el juego, cada jugada imprime el resultado y la animación
(`[Goalkeeper] ATAJA | zona elegida ...`) y el contacto
(`[Goalkeeper] Contacto (agarra): ... en 1.41 s de la animacion`).

## Anexo A. Animaciones de Blender (v1, ya no se usan)

Eran 18 (una SAVE y una DIVE por zona, contacto en 1,10 s) y no agarraban la
pelota. Siguen en `Player/Animations/blender/`.

Se generan con `tools/blender/generar_arquero.py`, sin abrir Blender:

```
blender -b Player/Animations/blender/arquero.blend --python tools/blender/generar_arquero.py
```

**Laterales** (izquierda y derecha): parten de `goalkeeper diving save`
(palomita a la derecha de mocap) y se transforman con:

| Operación | Qué hace |
|---|---|
| **Salto** | Suma (o resta) altura a la cadera con una campana alrededor del contacto. Las de abajo bajan la cadera ~0,5 m: la palomita va rasante. |
| **Alcance** | Escala el desplazamiento lateral de la cadera. En los DIVE el arquero se tira para el lado correcto pero recorre ~60%. |
| **Apuntar** | Rota el brazo desde el hombro para que la mano vaya a un punto objetivo, con peso suave en el tiempo. |
| **Piso** | Si al bajar la cadera el cuerpo atraviesa el piso, lo sube. |
| **Espejo** | Refleja todo en X para sacar la versión izquierda. |

**Centro**: parten de la postura de espera y se arman con IK de dos huesos:
las piernas mantienen los pies apoyados (las rodillas se doblan solas al
agacharse) y los brazos van a su objetivo con el codo doblado.

| | SAVE | DIVE |
|---|---|---|
| Arriba | salta con los dos brazos arriba | salta tarde y corto, le pasa por arriba |
| Media | bloquea con las manos al pecho | lo engañan: se corre al costado |
| Abajo | se agacha y la tapa con las manos abajo | se agacha tarde, le pasa por abajo |

El archivo `Player/Animations/blender/arquero.blend` tiene las 18 acciones.
Para verlas: pestaña Animation → Dope Sheet → modo Action Editor → elegir la
acción en el desplegable.

### Resultado medido en el juego (mano en el contacto)

| | Izquierda / derecha | Centro |
|---|---|---|
| Save Up | (±2,22, 2,04) | (-0,20, 2,23) |
| Save Mid | (±2,27, 1,22) | (-0,14, 1,17) |
| Save Down | (±2,27, 0,37) | (-0,16, 0,28) |
| Dive Up | (±1,49, 1,75) | (-0,30, 1,68) |
| Dive Mid | (±1,53, 1,15) | (-0,75, 0,97) |
| Dive Down | (±1,51, 0,36) | (-0,27, 0,77) |

## Anexo B. Pasar una animación de Blender al juego

No alcanza con exportar el FBX: **Blender reorienta los ejes de cada hueso** al
importar y exporta en metros (el juego está en centímetros). Si se mete el FBX
directo, la mano termina en otro lado (se midió: 3,24 m de error).

`tools/retarget.gd` lo resuelve con una **calibración**: comparando la misma
animación en el juego y exportada desde Blender, calcula para cada hueso la
conversión fija entre los dos sistemas de ejes. Esa conversión no depende de
la pose: en la calibración dio el mismo valor en los 103 cuadros (desvío
máximo 0,07°), y la ida y vuelta da **0,000 m** de diferencia.

Para agregar una animación nueva hecha en Blender:

```
MODO=convertir FBX=res://Player/Animations/blender/nueva.fbx OUT=res://Player/Animations/blender/nueva.res godot --headless --script res://tools/retarget.gd
```

Después agregarla a `arquero_blender.tres`, crear su `DiveAnimData`, y correr
`tools/bakear.tscn` para calcular el `canonical_target`.

La calibración (`tools/calibracion_blender.json`) vale para cualquier
animación exportada desde el mismo rig. Si se cambia de personaje hay que
recalibrar con `MODO=calibrar`.
