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
- 0x6C bytes antes del nombre: un `float32` (`extra` en `escenas.json`) que **no es el
  momento de arranque**: en la escena de derrota vale 17 s en un clip de 5 s. No se usa.

**Los clips de una escena están sincronizados en su propio tiempo**: se reproducen todos
desde el mismo segundo. En la ronda de 11, todos se separan entre los 9 y los 11 s de su
clip; arrancando cada uno en un segundo distinto (como se hizo primero, leyendo `extra`
como arranque) unos ya se iban de la ronda mientras otros seguían abrazados.

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

# 5b. Sonidos de partido (tribuna y árbitro) -> animaciones_pes/sonidos/ (opcional)
python3 -I tools/pes_extraer_sonidos.py "$TEST" "$JUEGO"

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
| `colocar_actor(raiz, ap, actor, origen, escala, desde)` | pone a un actor de una escena de PES en el segundo `desde` de su clip (ver abajo) |
| `transicion(...)` / `empalmar(...)` | pasa a otro clip sin que el cuerpo salte: congela la pose, mueve la raíz y funde |
| `cuidar_piso(personaje, sk)` | agrega `scripts/pes_piso.gd`, que sube el cuerpo si un fundido hunde un pie |

**Conversión de las escenas de PES** (`colocar_actor`, `lugar_pes`). Se eligió midiendo,
no a ojo:

```
lugar = origen + (-z_pes, y_pes, x_pes) × escala
giro  = giro_pes + 90°                              # el 0 es 0
```

Cómo se midió: solo con los datos de PES (`json_ceremonia/`, pista `root` de cada clip,
y el lugar y el giro del `.fdc`), girando el camino de cada clip y poniéndolo en su lugar,
para todas las lecturas posibles del giro (sentido, desfase de 0/90/180/270° y qué hacer
con el 0). En los 131 festejos grupales, la buena hace que el 88 % de los jugadores toque
a alguien en algún momento (mediana 0,25 m); ninguna otra pasa del 67 %. Después se
pasa a Godot: el clip, puesto en el personaje, recorre su camino de PES dado vuelta
(x y z con el signo cambiado), y de ahí sale el `+ 90°`.

**Tiene que ser una rotación, no un espejo.** La primera versión intercambiaba x y z
(`(z, y, x)` con giro `-giro - 90°`). Eso es un espejo: los lugares y los giros quedaban
reflejados, pero los cuerpos y sus recorridos no. La ronda y las filas, que son simétricas,
casi no lo mostraban; en los festejos el que abrazaba quedaba delante o al costado del
otro, abrazando al aire. Con el espejo, además, parecía que "un giro 0 vale 180 cuando
todos están en 0" (en el abrazo final): era un efecto del espejo. Con la rotación, el 0
es 0 siempre.

**La escala depende de si corren.** El retarget achica la altura de la cadera al 91 %
(nuestros jugadores son más chicos) pero **no lo que se desplazan**: un clip que en PES
corre 23,71 m acá corre 23,72 m. Entonces:

- Escenas quietas (ronda, filas, abatidos, copa): `ESCALA_ESCENAS` = 0,91, para que las
  manos lleguen a los hombros de cuerpos más chicos.
- Escenas en que corren (festejos grupales, abrazo final): `ESCALA_CON_CARRERA` = 1.
  Con 0,91, dos que arrancan a 15 m se encontraban 1,4 m corridos: se abrazaban a
  metros de distancia. (En el abrazo final no cambia nada medible: los cinco arrancan a
  la misma distancia y se corren todos igual.)
- Por lo mismo, los compañeros son todos del mismo alto: con otra escala de modelo
  también corren otra distancia.

Todos los actores de una escena van desde el mismo segundo (`_poner_escena(..., desde)`):
la ronda desde 3,8 s (a los 9 s se desarman), las filas desde 8 s (ya enganchados).

**Las puntas de las filas.** Cada fila de PES es `sub3, sub1, wait, sub2`, y los cuatro
abrazan a los dos lados: PES arma filas más largas repitiendo esos cuatro (el corte
`teamMateFull00` también) y su cámara no muestra las puntas. Este corte agrega además en
una punta otro `wait`, el clip del medio. Visto en el juego, desde el segundo 7 del clip
las dos puntas de cada fila estiran el brazo de afuera hacia un compañero que no está.
Por eso:

- `_puntas_sobrantes()` saca la punta que repite el clip del medio de su fila.
- `_soltar_puntas()` deja colgando el brazo de afuera de cada punta con la pose de
  `pk_idle` (`scripts/brazo_suelto.gd`, un `SkeletonModifier3D` que corre después de la
  animación). El resto del cuerpo, con el otro brazo sobre el hombro del vecino, sigue
  el clip de PES.

- Con esta conversión, en la ronda de 11 todos miran al centro, las filas miran al arco
  y en las filas ninguna mano levantada queda lejos de un compañero (con el espejo, 5).
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
- **Preparaciones y amagues del arquero** (`gkprejump_*`): no son en el lugar. `front`
  termina con la cadera 1,85 m al costado, `frontFeint` amaga 0,4 m a un lado y termina
  1,2 m al otro, en el aire; solo `front_min` es casi quieta (0,2 m). Antes se elegían al
  azar: si la estirada iba para el otro lado, cambiaba de lado en el aire, y aunque fuera
  para el mismo lado volvía para atrás, porque la estirada lleva al arquero hasta la
  pelota desde el centro. Ahora se elige (o su espejo `__M`) solo si va hacia el lado de
  la estirada, y la estirada sigue desde el cuadro de su clip en que el cuerpo ya se
  corrió lo mismo, más despacio para tocar la pelota cuando estaba planeado. Al terminar
  el amague sale directo a la estirada, sin volver a la espera.

### Cinemáticas: `scripts/cinematicas.gd`

| Momento | Qué pasa | De dónde sale |
|---|---|---|
| Antes del 1.er tiro | ronda de 11 abrazados → dos filas abrazadas → el pateador sale de la fila → apoya la pelota → el arquero camina por la línea | escenas `pk_00_intro_circle00`, `pk_00_intro_teamMate00_5`; clips `dml_pk_ready0*` |
| Gol | festejo grupal en el córner del lado de la pelota (3 de cada 4), o el autor festejando solo | festejos grupales `dml_goal_celebrate_N` + `_subK`; `dm_goal_*` |
| Atajada o afuera | primer plano del arquero y del pateador lamentándose, y reacción de las filas | `dml_pk_miss_shoot_*`, escena `pk_03_afterKick_teamMate_H_fault_5_00` |
| Fin del partido | el ganador se abraza con su equipo, el perdedor queda abatido y el ganador levanta la copa | escenas `end_pk_win_02`, `end_pk_lose_02`; clip `dml_end_raise01_trophy08_*` |

- Espacio salta cada cinemática. La cámara vuelve a su lugar con la pantalla en negro
  (`limpiar()`).
- **Festejos grupales.** En PES el festejo del autor (`dml_goal_celebrate_N`) viene con
  los de sus compañeros (`_sub1`, `_sub2`…): el que choca los cinco tiene a otro que se
  los choca. `pes_extraer_ceremonias.py` busca, por cada `N`, el corte de `escenas.json`
  que lo trae completo (sin carteles ni cámaras) y deja `festejos_grupales.json`. La
  build mide el camino de la cadera de cada actor y descarta los que duran menos de 4 s o
  más de 14, los que se tiran al piso, aquellos en que el autor no se cruza con nadie y
  aquellos en que alguno no llega a tocar a nadie (cadera a menos de 0,6 m de otro en algún
  momento) o termina a más de 2 m del más cercano: en PES hay festejos en que alguno le
  hace el gesto de abrazar a otro que está a 2 m, y en el juego se ve como abrazar al aire.
  Quedan 30 de 131. Medido en el juego andando, cada jugador queda a 0,1–0,25 m de donde
  lo pone PES; los datos de PES solos (sin ninguna conversión nuestra) dan lo mismo.
- **El festejo de uno solo** ya no trae compañeros: antes llegaban tres con clips sueltos
  (`dm_tu_*`) en lugares puestos a mano, que no estaban coordinados con el del autor. En una
  tanda de verdad el equipo queda en la mitad de la cancha. La cámara del festejo sigue el
  centro del grupo mientras se mueve.
  El juego mueve y gira **al grupo entero, sin separarlo**: el autor termina a 3 m del
  banderín, los demás del lado de la cancha y nadie se va más de 1,5 m de las líneas.
  Esos clips nunca se usan sueltos.
- **La copa** es la única formación hecha a mano: `raise01` (el salto con la copa) no
  aparece en ninguna escena de PES. La ceremonia de PES (`end_trophy_01`) necesita un
  podio de dos escalones.
- **Los compañeros** son copias del modelo del pateador con otro kit
  (`Player/kits/material_<equipo>_<variante>.tres`), y se reutilizan entre escenas.
- La copa (`scripts/copa.gd`) es genérica, armada por código: no se usan los trofeos con
  licencia del juego.

---

### Editor de festejos: `tools/editor_festejos.tscn`

Al pasar las escenas al juego algunos lugares quedan corridos y en los festejos en grupo
alguno abraza al aire o se mete adentro de otro. Se corrigen a mano con el editor
(F6 sobre la escena en Godot, o `godot --path . res://tools/editor_festejos.tscn`):

- Lista los 30 festejos grupales, las escenas de equipo (ronda, filas, filas tras un
  fallo, abrazo del ganador, abatidos, copa) y los festejos de un solo jugador.
- Reproduce la escena como la pone el juego, con el recorrido de la cadera de cada uno
  dibujado en el piso y la distancia al compañero más cercano.
- Por jugador: mover (arrastrando o con las flechas), girar (Q / E), adelantar o atrasar
  su clip (Z / X; negativo = espera quieto en el primer cuadro) y ocultarlo (H). Por
  escena: adelantarla entera y sacarla del juego ("Usar en el juego").
- Ctrl+Z deshace, Ctrl+S guarda en `resources/festejos_ajustes.json`.
- Al final de los grupales están los **descartados**: los festejos grupales que la build
  no acepta (duran menos de 4 s o más de 14, alguno se tira al piso, alguno no llega a
  tocar a nadie o termina lejos). El nombre dice por qué. No salen en el juego hasta que
  se los arregla y se marca "Usar en el juego" (`"activado": true` en los ajustes).
  La build guarda sus caminos en `datos.json` (`festejos_grupales_descartados`) y sus
  clips aparte, en `animaciones_pes/grupales_extra.res`. El juego carga ese archivo
  solo si hay alguno activado.

El juego aplica esos ajustes encima de lo extraído (`scripts/festejos_ajustes.gd`), al
cargar `escenas.json` y `datos.json`: no hace falta volver a extraer ni a correr la build.
En los grupales también se corren los caminos de la cadera, que son los que usa
`_lugar_del_grupo()` para llevar el grupo al córner. Los lugares están en el espacio de la
escena: después el juego gira y mueve el grupo entero.

En el abrazo del ganador, el juego vuelve a poner al protagonista (el primero) donde
terminan los demás, así que moverlo a él no cambia nada: hay que mover a los otros.

## 6. Herramientas para revisar

| Herramienta | Qué mide |
|---|---|
| `godot --headless --path . -s res://tools/pes_auditar.gd` | cada clip por separado: altura mínima de la malla, dedo-pelota en el golpe, pie de apoyo, saltos en los empalmes |
| `godot --headless --path . res://tools/pes_trazar.tscn` | tiros jugados de verdad, cuadro a cuadro (`TIROS=n`, `PICADA=1`, `DETALLE=1` → `animaciones_pes/traza.csv`) |
| `godot --headless --path . -s res://tools/test_red.gd` | tiros contra la red: cuánto se embolsa, cuántos nudos se mueven, si la pelota sale rebotando o la atraviesa (`RED="holgura,elasticidad,estiramiento"` para probar otros valores) |
| `godot --headless --path . -s res://tools/test_picada.gd` | la picada con aire contra la parábola que predice el arquero |
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

## 8. Sonidos de la tribuna y del árbitro

`tools/pes_extraer_sonidos.py` saca de `dt44_all.cpk` (`common/sound/match/`) los bancos
`SE_Cheers_*` y `SE_Referee_*` (183 sonidos, 23 MB). Son bancos de CRIWARE (`.acb`, con
el audio adentro o en el `.awb` del mismo nombre) con streams **HCA sin cifrar**: se corta
cada uno desde su cabecera `HCA` y ffmpeg lo pasa a `.ogg`. Las tablas de cues del `.acb`
no hacen falta: el nombre del banco dice qué es. El extractor deja `sonidos.json` con la
duración y el volumen de cada uno y, en los silbatos, los pitazos y cuánto suena.

Sin poder escucharlos, se clasificaron por la envolvente de volumen:

| Grupo | De dónde | Cuándo |
|---|---|---|
| ambiente | el `CZ_Base` parejo de 58 s | todo el partido, con el crossfade de siempre |
| gol | un arranque de 2–3 s + un rugido de 20–30 s que se apaga (`Goal`) o el "yeah" de 10 s (`Goal_YEAH`), en dos capas como en PES | gol |
| uh | la ola de "ohh" de 8 s (`Goal_OHH`) | afuera / palo |
| atajada | los "uuh" fuertes de `Surprise` | atajada |
| abucheo | `Anger` | 4 de cada 10 tiros afuera |
| expectativa | el murmullo que crece antes de un córner (`Special_CK`, 14 s) y los de `Special_Pass` | antes de cada penal; se apaga cuando llega el desenlace |
| silbatos | un árbitro (A–F) al azar por partido: corto (un pitazo < 0,35 s), del penal (uno de 0,7–1,6 s), final (el de más pitazos) | como antes |
| patada | `SE_PL_BALLHIT_INSTEP_03..05`, según la velocidad del tiro | al patear |
| red, palo, travesaño, pique | `GOALNET`, `GOALPOST`, `GOALBAR`, `BOUND`, con la fuerza del golpe (`_01` a `_05`) | `SoccerBall.impacto` |
| arquero | `GK_CATCH` si la agarra, `GK_PUNCH` si la rechaza | atajada / rebote |

**Los golpes de la pelota** salen de `SE_Movement.acb`, que mezcla 126 sonidos con nombre
(`SE_PL_BALLHIT_GOALNET_04`...). Ahí sí se leen las tablas de cues: son `@UTF` como las del
cpk, pero en ACB el campo que `cpk.py` lee como offset de las filas trae la versión en los
16 bits altos, y se pone en 0 antes de leer. Un cue apunta a una secuencia, sus pistas a
eventos cuyo comando `0x07D0` apunta a un synth, y el synth a sus formas de onda
(`MemoryAwbId`, el id dentro del AFS2 embebido).

**Los palos y el travesaño no tenían colisión**: la pelota los atravesaba y la frenaba
recién la red de costado. `SoccerBall._chocar_con_el_arco()` los trata como cilindros
(los del arco: centro en x = ±3,79 y en y = 2,57, radio 0,125, sobre z = −10,995), mira el
tramo que la pelota va a recorrer en el cuadro y la hace rebotar. Corre **antes que la red**
(`process_physics_priority = -10`), porque `red_arco.gd` también se adelanta a la pelota y
la frenaba contra el borde de la tela atado al palo antes de que llegara a rebotar.

Hay **un solo** `SoundManager`, el autoload: `game.tscn` traía otro nodo con el mismo
script, y en el partido sonaban dos ambientes de tribuna encimados. `SoundManager` los carga con `AudioStreamOggVorbis.load_from_file` (no hace falta
importarlos) y, si no están, usa los de `audio/`. Los volúmenes se igualaron midiendo el
volumen medio de los dos juegos con ffmpeg.

## 9. Pendiente


- Leer las cámaras de las escenas (`.canm`).
- El árbitro (`_referee` en las escenas, `dml_pk_ready03_judge`).

## 10. La picada y la red

**La picada** (`SoccerBall.kick(..., picada = true)`) ya no es una parábola sin aire. Sale
con un poco de efecto hacia atrás (2 a 3 vueltas por segundo) y vuela con roce cuadrático
y efecto Magnus, con las medidas de una pelota de verdad. Sube rápido, se frena (de 11,5
a 9 m/s), el punto más alto queda pasada la mitad del recorrido y cae más parada. Al picar,
el efecto la frena. Con más efecto el Magnus la sostiene tanto que vuelve a flotar.
El pateador sigue calculando la parábola de siempre (la que lee el arquero), y la pelota
busca la velocidad de salida que, con aire, cruza la línea **en el mismo punto y en el
mismo momento** (`salida_picada`, error menor a 1 cm). Así no cambió nada de la dificultad
del arquero.

**La red** tenía en `game.tscn` una elasticidad de 1,165 (el valor pensado es del orden de
0,0001). Con eso los hilos no hacían nada: cada nudo se movía solo, la red se hundía
como una carpa en punta (unos 60 nudos) y una pelota que caía sobre el techo lo atravesaba.
Ahora: holgura 0,15, elasticidad 0,0002, estiramiento 0,12; se mueven 150 a 250 nudos y la
bolsa llega a 0,9 m. Además, la bolsa se angosta contra el pasto (`_limitar_a_la_bolsa`):
un tiro fuerte y bajo al palo aplastaba la primera fila de tela contra el piso y la pelota
se iba por debajo.

