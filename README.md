Espacio físico del juego/app:
<img width="1024" height="571" alt="image" src="https://github.com/user-attachments/assets/a9c4f33b-ff53-43a7-9c04-4cf77d2274fb" />

## Créditos de assets de terceros

| Asset | Autor | Fuente | Licencia |
|---|---|---|---|
| `assets/stadium/estadios/*.FBX` (16 estadios) | torftorf1 | [European Stadium Pack (itch.io)](https://torftorf1.itch.io/european-stadium-pack) | No declarada — ver nota |

**Nota sobre la licencia:** el pack se publica como descarga gratuita en itch.io,
pero el autor no declara una licencia explícita ni incluye un archivo LICENSE.
Se usa acá dando crédito al autor. Si el proyecto se fuera a publicar
comercialmente habría que pedirle permiso expreso a torftorf1. Los modelos
representan estadios reales, así que también correspondería revisar el uso de
marcas en ese caso.

## Cómo cambiar de estadio

El pack trae 16 estadios (4 de España, 4 de Italia, 4 de Francia, 4 de
Inglaterra). Para cambiar el de la cancha actual se edita una sola línea de
`scenes/game.tscn`:

```
[ext_resource type="PackedScene" path="res://assets/stadium/estadios/Fst_Eng_001.FBX" id="20_stadium"]
```

Ojo: **cada estadio tiene su propia escala**, porque la cancha de cada modelo
mide distinto. La escala correcta se calcula como `105 / largo_de_la_cancha` (en
unidades del modelo) para que la cancha quede en los 105 m reglamentarios, y la
posición en Y como `-(altura_de_la_cancha * escala) - 0.85` para que la cancha
del modelo quede justo por debajo de la nuestra.

## Materiales propios (shaders)

El pack de estadios es low-poly y **no trae UV-maps**, así que las superficies
vienen como polígonos de color plano. El detalle visual se agrega con shaders
que calculan todo en **coordenadas de mundo** (no hacen falta UVs):

| Archivo | Qué hace |
|---|---|
| `assets/materials/pitch.gdshader` | Césped con franjas de corte y las líneas reglamentarias (área grande, área chica, punto de penal y semicírculo). Las medidas están en metros y atadas a la posición real del arco (z = -11). |
| `assets/materials/gradas.gdshader` | Dibuja las filas escalonadas, las butacas y el público sobre las gradas. Las filas se separan por altura y las butacas por el ángulo alrededor del centro del estadio, que es como se disponen en un estadio real. |
| `assets/materials/net.gdshader` | Red del arco, como cuadrícula con `ALPHA_SCISSOR`. |
| `assets/materials/hormigon_material.tres` | Gris de hormigón para la estructura, para que no compita con las gradas. |

Los shaders se aplican **por superficie** desde `scenes/game.tscn`, con
`surface_material_override/N` sobre la malla del estadio (la 4 son las gradas;
la 3, 5 y 7 la estructura).

## Equipos y camisetas

El modelo de los jugadores (Mixamo) viene con textura de **piel desnuda**, sin
ropa. Las camisetas se generan pintándolas sobre esa textura: se exportan los
vértices de la malla en pose de reposo junto con sus UVs, se rasteriza la malla
en espacio UV para saber a qué parte del cuerpo corresponde cada píxel, y con
eso se pintan las zonas.

Como el modelo está en **pose T**, cada zona se identifica por la altura
normalizada del vértice y su distancia al eje del cuerpo:

| Zona | Altura | Distancia al eje |
|---|---|---|
| Botines | < 0.065 | — |
| Medias | 0.065 – 0.29 | — |
| Short | 0.36 – 0.55 | < 27 |
| Camiseta (torso) | 0.55 – 0.845 | < 22 |
| Mangas | 0.70 – 0.875 | 10 – 40 |

La distancia al eje es lo que separa el torso de los brazos: hasta el 75% de la
altura el cuerpo no pasa de 19 unidades de ancho, y de ahí para arriba los
brazos extendidos llegan a 89.

Las camisetas pintadas conservan la **luminancia de la textura original**, así
que mantienen el sombreado y los pliegues en vez de quedar como un color plano.

Kits disponibles en `Player/kits/`: rojo, azul, verde, amarillo y arquero.
Se asignan por `surface_material_override/0` sobre la malla `Ch36` de cada
jugador en `scenes/game.tscn`.

### Cara y pelo

Se pintan con la misma técnica, pero usando la **posición 3D completa** del
vértice en vez de solo la altura, porque hacen falta dos datos más: hacia dónde
mira la cara y de qué lado está cada ojo.

La cara del modelo apunta hacia **+Z** (el punto de mayor Z es la nariz). La
cabeza va de y=151.4 (mentón) a y=176.9 (coronilla), o sea 25,5 cm, y los
rasgos se ubican por proporción anatómica sobre esa medida:

| Rasgo | Altura (cm) | Posición en X |
|---|---|---|
| Boca | 156.2 | centrada |
| Nariz (geometría, no pintada) | ~161 | centrada |
| Ojos | 164.6 | ±3.1 |
| Cejas | 167.0 | ±3.2 |
| Línea del pelo (frente) | 171.2 | — |

Los rasgos solo se pintan donde `z > 4`, o sea en la mitad delantera de la
cabeza: si no, aparecerían también en la nuca. El pelo, en cambio, cubre desde
la línea del pelo hacia arriba **más** toda la parte de atrás (`z < 3`).

Cada equipo tiene su color de pelo, así que el pateador y el arquero se
distinguen incluso de espaldas.

## Red que se deforma

Cuando la pelota entra, la red se hunde en el punto del impacto y vuelve
oscilando. Está repartido en dos archivos:

- **`scripts/red_arco.gd`** detecta el impacto (con `contact_monitor` sobre la
  pelota) y le pasa al shader tres datos: dónde pegó, en qué dirección iba y
  cuánto tiempo pasó desde entonces. Usa un contador propio en vez del `TIME`
  del shader para no depender de hace cuánto arrancó el juego.
- **`assets/materials/net.gdshader`** hace la deformación en el vertex shader:
  una campana alrededor del punto de impacto (`exp(-d²/radio²)`), que se apaga
  con el tiempo (`exp(-t*4)`) y oscila (`cos(t*20)`).

Los paneles de la red están subdivididos (el fondo tiene 420 vértices) porque
sin vértices intermedios no habría nada que mover.

La red solo puede moverse perpendicular a sí misma, así que la dirección del
tiro se **proyecta sobre la normal del panel**. Eso permite que el mismo
material sirva para el fondo, los laterales y el techo sin que el shader sepa
cuál es cuál.

Parámetros ajustables desde el Inspector en el nodo `RedArco`: `fuerza_maxima`
(cuánto se hunde, 0.75 m), `radio` (ancho de la deformación, 1.3 m),
`velocidad_minima` y `duracion`.

## Colisiones agregadas

| Nodo | Qué resuelve |
|---|---|
| `RedArco/Cuerpo` | La pelota no atraviesa la red (criterio de aceptación del plan). |
| `World/PisoCuerpo` | **El césped no tenía colisión**: la pelota se caía al vacío en cada tiro. Se extiende por detrás de la línea de meta, si no la pelota que entra al arco cae igual. |
