# Animaciones de PES 2021

Cómo se sacan las animaciones de PES 2021 (vía *SP Football Life 2027*), cómo se
convierten al personaje del juego y cómo las usa el juego: remates, atajadas,
festejos, cinemáticas, escenas de equipo y la ceremonia final.

> **Nada de lo extraído va a git.** Todo queda en `animaciones_pes/` (ignorada en
> `.gitignore`) y es solo para uso local. Si esa carpeta no existe, el pateador y el
> arquero usan sus animaciones de siempre (`PesAnimaciones.disponible()`).

---

## 1. Qué hace falta

- El juego instalado: `SP Football Life 2027/Data/*.cpk`.
- La carpeta de trabajo `test/` del disco externo, con:
  - `PES21/`: lo ya extraído de `dt13_all.cpk` (los `.mtar`, `clip_index.json`, `fbx/`…)
    y `PES21/tools/cpk.py` (lee los `.cpk`).
  - `tools/pes-gani-master/`: el decodificador de animaciones (`pesmtar.py`).
  - `pes21_retarget.py`: pasa una animación decodificada al esqueleto Mixamo y la
    exporta como FBX (Blender).
  - `Soccer Game Pack/Ch36_nonPBR.fbx`: el personaje de destino.
- Blender y Godot 4.7 en el PATH.

`pes21_retarget.py` tiene la ruta de `pes-gani` escrita como `D:\...`. En Linux se usa
una copia con esa línea cambiada:

```bash
sed "s#^TOOL = .*#TOOL = '$TEST/tools/pes-gani-master'#" "$TEST/pes21_retarget.py" > /tmp/retarget_linux.py
```

En los comandos de abajo, `$TEST` es la carpeta `test/` y `$JUEGO` la del juego.

---

## 2. Dónde está cada cosa en PES

| Qué | Dónde | Formato |
|---|---|---|
| Animaciones de juego (remates, atajadas, festejos `dm_*`) | `dt13_all.cpk` → `common/anime/FoxAnim/Body/body_anime_file0..9.mtar` | contenedor `.mtar` con clips `gani` |
| Escenas (copa, penales, entrada, festejos `dml_*`) | `dt12_g4.cpk` → `common/demo/anime/FoxAnim/FixDemo/Animations/*.gani` | un `.gani` suelto por clip y por actor |
| Dónde va cada actor en una escena | `dt12_g4.cpk` → `common/demo/fixdemo/<tipo>/cut_data/*.fdc` | ver §2.2 |
| Cámaras de las escenas | referenciadas desde los `.fdc` (`*.canm`) | **sin leer todavía** |
| Público y banderas | `dt19_x64.cpk` → `common/mob/` | sin usar |

### 2.1 Nombres de los clips

En los `.mtar` cada clip se guarda solo con el hash de su nombre. Los nombres se
recuperaron probando (`clip_index.json`, 4105 de 4389). **Los 284 sin nombre no son
basura**, pero se revisaron y no hay ceremonias entre ellos. Las ceremonias y escenas
están en `dt12_g4.cpk`, que tiene más de 5700 `.gani` con nombre.

Los `*_eyes_target.gani` solo mueven hacia dónde miran los ojos: se ignoran.

### 2.2 Las escenas (`.fdc`)

Cada `.fdc` es un corte de una escena. Empieza con una tabla
`u32 cantidad` + `cantidad × (u32 offset, u32 tamaño, u32 nombre)`; la primera sección
es la del corte, con un registro por actor. Dentro de esa sección:

- el nombre del clip del actor (`cpk_dat/.../Animations/<clip>.gani`);
- **justo antes del nombre**: 4 `float32` = `x, y, z, giro` (metros y grados);
- 0x6C bytes antes del nombre: un `float32` con **el momento en que arranca el clip,
  en sesentavos de segundo** (548 → 9,1 s). Un valor enorme significa "no aplica".

Coordenadas de PES: la mitad de la cancha es `(0, 0, 0)`, `x` va a lo largo (los arcos
en ±52,5; el arco de los penales es −x) y `z` va a lo ancho.

**Los clips no traen su lugar en la escena**: la pista `root` de todos arranca en
`(0, 0, 0)`. La formación solo está en el `.fdc`.

---

## 3. Extraer, paso a paso

Desde la raíz del proyecto:

```bash
# 1. Los FBX ya convertidos de la extracción de dt13 (atajadas, pateador, festejos dm_*)
python3 tools/pes_copiar.py "$TEST/PES21"

# 2. Remates (kick_*) y vaselinas (*_lob), que la extracción original no incluyó
python3 tools/pes_extraer_remates.py "$TEST"

# 3. Las escenas: lugar y giro de cada actor en cada corte -> animaciones_pes/escenas.json
python3 -I tools/pes_extraer_escenas.py "$TEST" "$JUEGO"

# 4. Clips de dt12 (copa, penales, festejos de un jugador y los de las escenas que usa
#    el juego, ESCENAS_USADAS) -> animaciones_pes/json_ceremonia/
python3 -I tools/pes_extraer_ceremonias.py "$TEST" "$JUEGO"

# 5. Pasar los JSON al personaje (una vez por carpeta)
for d in json_remates json_ceremonia; do
  blender --background --python /tmp/retarget_linux.py -- \
    --json "$PWD/animaciones_pes/$d" --out "$PWD/animaciones_pes/fbx" \
    --target "$TEST/Soccer Game Pack/Ch36_nonPBR.fbx" \
    --skeleton "$TEST/PES21/dt13/common/anime/FoxAnim/Body/CharacterAssets/body_anim_skel.ask"
done

# 6. Importar y armar las librerías
godot --headless --path . --import
godot --headless --path . -s res://tools/pes_construir.gd
```

El retarget escribe `fbx/remates/` y `fbx/ceremonia/` según la categoría de cada JSON.

Hay otros dos pasos que no dependen de PES, pero el juego los necesita:

```bash
# Estadio sin la red fija del arco (la reemplaza la red con física)
godot --headless --path . -s res://tools/optimizar_estadio.gd

# Variantes de piel y pelo de los compañeros (los PNG ya están en git)
python3 tools/generar_companeros.py
```

---

## 4. La build: `tools/pes_construir.gd`

Genera `animaciones_pes/arquero.res`, `pateador.res` y `datos.json`. Tarda alrededor de
un minuto.

1. **Conversión.** El rig de los FBX es el mismo que el del personaje: las rotaciones se
   copian tal cual. La cadera pasa al espacio del esqueleto de cada personaje. Los clips
   del arquero se guardan también espejados (`__M`).
2. **Remates.** Cada carrera (`pk_runup_*`) se une con los golpes (`kick_*`) que mejor la
   continúan. El golpe es el cuadro de mayor velocidad del pie; **en las vaselinas es el
   cuadro en que el pie está más bajo**, porque el pico de velocidad llega después de
   tocar la pelota. Se descartan los remates que quedarían muy girados, con poca carrera
   o que siguen corriendo más de 3 m después del golpe.
3. **Piso.** `tools/pes_cuerpo.gd` calcula la pose a mano y busca el punto más bajo de la
   **malla**, no de los huesos. Si atraviesa el piso, sube la cadera en esos cuadros,
   con un suavizado.
4. **Empalmes.** Para cada atajada o remate se busca cómo seguir: qué clip y desde qué
   cuadro. Se comparan la pose, la altura y la velocidad de la cadera. Se descartan las
   reacciones en las que el arquero se vuelve a tirar al piso, y el lamento después de
   un gol se elige según si quedó de pie o arrodillado.
5. **Festejos de gol.** De los `dml_goal_celebrate_*` de un solo jugador quedan los que
   recorren 3–18 m, duran 3–9 s y no se tiran al piso.
6. **Compresión.** Se comprime cada clip y solo se acepta si no cambia: `compress()` a
   veces mete saltos de metros.

`datos.json` guarda los remates (dónde está el dedo al golpear, cómo sigue la reacción),
las atajadas (dónde toca la mano), los festejos de gol, las esperas y los puntos de la
malla para el control del piso.

**Antes de medir, la build deja al pateador sin girar.** Si ya existe una versión
anterior de las librerías, el juego coloca al pateador girado hacia su carrera, y todo lo
medido quedaba girado con él. Ese era el origen de "patea desde cualquier lado".

---

## 5. En el juego

### `scripts/pes_animaciones.gd` (`PesAnimaciones`)

| Función | Para qué |
|---|---|
| `colocar(raiz, ap, sk, anim, punto, direccion, en_el_final)` | arranca un clip girado para que se desplace hacia `direccion`, empezando o terminando en `punto` (después de un corte de cámara) |
| `colocar_mirando(raiz, ap, sk, anim, punto, mirar, t)` | igual, pero el cuerpo mira hacia `mirar` en el segundo `t` del clip |
| `colocar_actor(raiz, ap, actor, origen)` | pone a un actor de una escena de PES (ver abajo) |
| `transicion(...)` / `empalmar(...)` | pasa a otro clip sin que el cuerpo salte: congela la pose, mueve la raíz y funde |
| `cuidar_piso(personaje, sk)` | agrega `scripts/pes_piso.gd`, que sube el cuerpo si un fundido hunde un pie |

**Conversión de las escenas de PES** (`colocar_actor`). Se eligió midiendo, no a ojo:

```
lugar = origen + (z_pes, y_pes, x_pes) × 0.91      # 0.91: nuestros jugadores son más chicos
giro  = -giro_pes - 90°                             # un giro_pes de exactamente 0 vale 180
desde = (extra / 60) mod largo_del_clip
```

- Con esta conversión, en la ronda de 11 todos miran al centro (0,98), las filas miran
  al arco (0,99) y en el abrazo final todos terminan a menos de 1,5 m.
- **El giro 0** aparece en 5053 actores y significa "sin giro": tomado literal, en el
  abrazo corren en paralelo y quedan a 8,5 m.
- **Un actor en `(0, 0, 0)` con giro 0 es el jugador del momento** (el que pateó): PES
  lo pone donde esté. En el abrazo se lo hace terminar donde se juntan los demás.

**Hacia dónde mira un jugador:** se mide con la dirección de los pies
(`ToeBase - Foot`), que coincide con `_frente()` y con el juego (el pateador mira a −z).
La línea entre las caderas, cruzada con el eje vertical, **da al revés**. Por usarla se
puso a los equipos de espaldas en una primera versión.

### Pateador y arquero

- `player_kicker.gd`: elige el remate según adónde va el tiro y la potencia, al azar
  entre los parecidos. Con Shift elige entre las vaselinas, sin repetir la última. Lo
  ubica para que el pie llegue a la pelota y frena la carrera hasta el golpe.
- `player_goalkeeper.gd`: elige la atajada por zona y altura. Después encadena la
  reacción que calculó la build y la espera.

### Cinemáticas: `scripts/cinematicas.gd`

| Momento | Qué pasa | De dónde sale |
|---|---|---|
| Antes del 1.er tiro | ronda de 11 abrazados → dos filas abrazadas → el pateador sale de la fila → apoya la pelota → el arquero camina por la línea | escenas `pk_00_intro_circle00`, `pk_00_intro_teamMate00_5`; clips `dml_pk_ready0*` |
| Gol | festejo en el córner del lado de la pelota, y llegan 3 compañeros | `dml_goal_celebrate_*`, `dm_goal_*`, `dm_tu_*` |
| Atajada o afuera | primer plano del arquero y del pateador lamentándose, y reacción de las filas | `dml_pk_miss_shoot_*`, escena `pk_03_afterKick_teamMate_H_fault_5_00` |
| Fin del partido | el ganador se abraza con su equipo, el perdedor queda abatido y el ganador levanta la copa | escenas `end_pk_win_02`, `end_pk_lose_02`; clip `dml_end_raise01_trophy08_*` |

- Espacio salta cada cinemática. La cámara vuelve a su lugar con la pantalla en negro
  (`limpiar()`).
- **La copa** es la única formación hecha a mano: `raise01` (el salto con la copa) no
  aparece en ninguna escena de PES. La ceremonia de PES (`end_trophy_01`) necesita un
  podio de dos escalones.
- **Los compañeros** son copias del modelo del pateador con otro kit
  (`Player/kits/material_<equipo>_<variante>.tres`), y se reutilizan entre escenas.
- La copa (`scripts/copa.gd`) es genérica, armada por código: no se usan los trofeos con
  licencia del juego.

---

## 6. Herramientas para revisar

| Herramienta | Qué mide |
|---|---|
| `godot --headless --path . -s res://tools/pes_auditar.gd` | cada clip por separado: altura mínima de la malla, dedo-pelota en el golpe, pie de apoyo, saltos en los empalmes |
| `godot --headless --path . res://tools/pes_trazar.tscn` | tiros jugados de verdad, cuadro a cuadro (`TIROS=n`, `PICADA=1`, `DETALLE=1` → `animaciones_pes/traza.csv`) |
| F3 / F4 en el juego | panel con el clip de cada personaje y por qué se eligió; F4 copia el historial del partido |

---

## 7. Trampas conocidas

- **GDScript copia las variables locales dentro de una lambda.** Un `angulo -= ...`
  dentro de `_plano` no se acumula entre cuadros. Por eso cada plano de cámara recibe el
  tiempo transcurrido (`func(delta, t)`).
- **Sacar de una librería el clip que el `AnimationPlayer` está reproduciendo cuelga
  Godot**: hay que llamar a `ap.stop()` antes.
- **La rotación en `compress()`** se acepta con una tolerancia de 0,999 (unos 5°); con
  0,995 la cadera podía girar 11°.
- **Las capturas desde el juego traban unos 0,1 s** por imagen guardada. Para revisar un
  gesto exacto (por ejemplo el toque de la vaselina) conviene congelar el clip y posarlo
  en el cuadro justo.
- **Correr la build con librerías viejas**: si la estructura de `datos.json` cambió, el
  primer cuadro puede tirar errores de script al cargar el JSON viejo. Se corrigen solos
  al terminar la build.

## 8. Pendiente

- Leer las cámaras de las escenas (`.canm`).
- Usar los 169 festejos grupales (`dml_goal_celebrate_*_sub*`) con las posiciones de
  `escenas.json`.
- El árbitro (`_referee` en las escenas, `dml_pk_ready03_judge`).
