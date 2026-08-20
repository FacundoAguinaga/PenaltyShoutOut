# Penalty ShoutOut — PLAN de trabajo

**Integrantes:** Javier Montoro — Facundo Aguinaga
**Materia / Cátedra:** _(completar)_
**Fecha de entrega / Feria:** _(completar)_
**Repositorio:** _(completar URL)_

> Este documento cumple con el requisito de la cátedra: al desarrollarse el proyecto con asistencia de agentes de IA, se deja constancia escrita del plan de trabajo, el alcance, la división de tareas y el criterio de uso y validación de la IA.

---

## 1. Descripción del proyecto

**Penalty ShoutOut** es un juego de penales 1 vs 1 para dos jugadores en la misma computadora (multijugador local). Cada partida es una tanda de penales donde los jugadores alternan roles de pateador y arquero, pudiendo elegir entre distintas canchas y equipos.

El objetivo de diseño es una experiencia **corta, tensa y de revancha inmediata**: partidas de 2 a 4 minutos, ideales para el formato de feria, donde cualquier visitante puede sentarse, entender las reglas en 10 segundos y jugar.

---

## 2. Reglas: victoria, derrota y finalización

| Condición | Definición |
|---|---|
| **Victoria** | Gana quien convierta más penales al finalizar la tanda (5 tiros por jugador). |
| **Empate** | Se pasa a muerte súbita: se sigue de a un tiro por jugador hasta que uno anote y el otro falle en la misma ronda. |
| **Derrota** | Perder la tanda según el criterio anterior. |
| **Finalización** | La partida termina cuando queda definido un ganador. Se muestra pantalla de resultado con estadísticas y opción de revancha o volver al menú. |

**Regla de cierre anticipado (opcional, a evaluar en testing):** si la diferencia de goles es mayor a los tiros restantes, la tanda se cierra antes (regla real del fútbol). Se implementa como *flag* configurable para poder desactivarla si perjudica el ritmo en la feria.

---

## 3. Loop general del juego

```
MENÚ PRINCIPAL
    │
    ├─► Selección de cancha
    ├─► Selección de equipo (Jugador 1 / Jugador 2)
    │
    ▼
TANDA DE PENALES  ── 5 rondas ──►  ronda = [P1 patea / P2 ataja] + [P2 patea / P1 ataja]
    │
    ├─► ¿Empate? ──► MUERTE SÚBITA (repite hasta desempate)
    │
    ▼
PANTALLA DE RESULTADO (ganador + estadísticas)
    │
    ├─► REVANCHA (mismo setup, marcador en cero)
    └─► VOLVER AL MENÚ
```

---

## 4. Mecánica principal

### 4.1 Pateador
Tres decisiones encadenadas antes del disparo:

1. **Dirección** (horizontal): izquierda / centro / derecha, con posiciones intermedias sobre un eje continuo.
2. **Altura** (vertical): raso / media altura / alto.
3. **Potencia**: barra que sube y baja; se confirma con un botón. Más potencia = disparo más rápido pero mayor dispersión respecto al punto apuntado.

La mira se controla con el stick y se confirma con un botón. El tiro sale fuera si la combinación dirección+altura+potencia excede el marco del arco.

### 4.2 Arquero
- Elige un lado y una altura para lanzarse.
- El **timing** importa: existe una ventana de reacción corta; lanzarse demasiado temprano permite al pateador leer el movimiento, demasiado tarde reduce el alcance.
- La atajada se resuelve por superposición entre el área de cobertura del arquero y la trayectoria de la pelota.

### 4.3 Ocultamiento de información
Para que el 1v1 sea justo en pantalla compartida, la mira del pateador **no se muestra al arquero**: se usa un indicador visible solo para el jugador que patea (HUD parcial + tiempo de decisión limitado). Este es el principal desafío de diseño y se valida en la Etapa 3.

---

## 5. Progresión y "upgrade"

**No existen mejoras que otorguen ventaja competitiva.** El juego se mantiene deliberadamente equilibrado: los dos jugadores tienen exactamente las mismas capacidades durante toda la partida.

Lo que sí se desbloquea o varía es **cosmético**: canchas, equipos, camisetas y pelotas. La variedad cumple una función de rejugabilidad, no de poder.

*(Opcional, si sobra tiempo: desbloqueo de canchas o equipos por cantidad de partidas jugadas, sin impacto en la jugabilidad.)*

---

## 6. Alcance del proyecto

### MVP — obligatorio para la feria
- [ ] Tanda de penales completa de 5 tiros + muerte súbita.
- [ ] Mecánica de patear (dirección, altura, potencia).
- [ ] Mecánica de atajar (lado, altura, timing).
- [ ] Soporte para 2 joysticks en multijugador local.
- [ ] Al menos 2 canchas y 4 equipos.
- [ ] Menú principal, selección de cancha/equipo, pantalla de resultado, revancha.
- [ ] Marcador visible durante toda la tanda.
- [ ] Audio básico: patada, atajada, gol, público.
- [ ] Build ejecutable que arranque sin consola ni pasos técnicos.

### Deseable — si el tiempo lo permite
- [ ] Cámara con repetición del gol/atajada.
- [ ] 4 canchas y 8 equipos.
- [ ] Efectos de partículas (red que se mueve, pasto, confeti).
- [ ] Comentarios/locución básica.
- [ ] Modo 1 jugador vs CPU (para cuando en la feria haya un solo visitante).

### Fuera de alcance — no se hace
- Multijugador en red.
- Ranking global o persistencia online.
- Sistema de progresión con ventajas competitivas.
- Vinculación con proyectos de electrónica.

---

## 7. Stack técnico y arquitectura

| Ítem | Definición |
|---|---|
| Motor | **Godot 4.x** |
| Lenguaje | GDScript |
| Input | Input Map de Godot con acciones duplicadas por jugador (`p1_*` / `p2_*`), asignadas a `device 0` y `device 1`. Fallback a teclado. |
| Físicas | `RigidBody3D` para la pelota, `Area3D` para arco / afuera / manos del arquero |
| Estado global | Singleton por *autoload* (`GameManager`) para pasar datos entre escenas |
| Control de versiones | Git + GitHub, con `.gitignore` de Godot (ignorar `.godot/`, `export_presets.cfg` si lleva rutas locales) |
| Plataforma destino | PC / Windows (export template standalone) |

### Escenas principales (`.tscn`)
1. `main_menu.tscn` — jugar, controles, salir.
2. `setup.tscn` — selección de cancha y equipos.
3. `match.tscn` — la tanda de penales (escena principal).
4. `result.tscn` — ganador, estadísticas, revancha / menú.

Escenas reutilizables: `ball.tscn`, `goalkeeper.tscn`, `shooter.tscn`, `pitch_*.tscn` (una por cancha), `hud.tscn`.

### Scripts principales (`.gd`)
| Script | Responsabilidad |
|---|---|
| `game_manager.gd` (autoload) | Estado global que persiste entre escenas: cancha, equipos, marcador, configuración. |
| `match_manager.gd` | Máquina de estados de la tanda: turnos, rondas, muerte súbita, condición de fin. |
| `shooter.gd` | Input y lógica del pateador (dirección, altura, potencia). |
| `goalkeeper.gd` | Input y lógica del arquero (lado, altura, timing). |
| `ball.gd` | Trayectoria, curva, colisiones, señales de gol / atajada / afuera. |
| `hud.gd` | Marcador, indicadores de turno y estadísticas en pantalla. |
| `ui_manager.gd` | Navegación de menús y transiciones de escena. |
| `audio_manager.gd` (autoload) | Reproducción de SFX y ambiente. |

**Comunicación entre nodos:** por `signal` (por ejemplo `ball.goal_scored` → `match_manager`), evitando referencias directas cruzadas. Los parámetros de balance se exponen con `@export` para ajustarlos desde el Inspector sin tocar código.

### Estructura del repositorio
```
/
├── documento.md              ← este archivo
├── README.md
├── .gitignore
├── project.godot
├── /scenes
│   ├── /ui
│   ├── /match
│   └── /pitches
├── /scripts
├── /assets
│   ├── /models
│   ├── /textures
│   ├── /audio
│   └── /fonts
├── /docs
│   ├── controles.md
│   └── prompts-ia.md         ← registro de uso de agentes de IA
└── /builds
```

---

## 8. Plan de trabajo por etapas

Cada etapa cierra con un **commit etiquetado** y un entregable jugable o verificable.

| # | Etapa | Tareas | Entregable |
|---|---|---|---|
| **0** | Setup | Crear repo, `.gitignore` de Unity, proyecto base, subir este documento. | Repo inicializado |
| **1** | Prototipo de tiro | Arco, pelota, física básica. Apuntar + potencia. Detección de gol / afuera. | Se puede patear al arco |
| **2** | Arquero | Control del arquero, lanzamiento por lado y altura, ventana de timing, detección de atajada. | 1v1 crudo funcionando |
| **3** | Balance de la mecánica | Ajuste de velocidad de pelota, alcance del arquero, ventana de reacción, ocultamiento de la mira. Testing con personas reales. | Mecánica sentida como justa |
| **4** | Estructura de partida | `MatchManager`: turnos, 5 rondas, marcador, muerte súbita, condición de victoria. | Tanda completa de principio a fin |
| **5** | Multijugador local | Input Map con acciones por jugador, detección de `device 0` / `device 1`, fallback a teclado. | Dos personas jugando con joysticks |
| **6** | UI y flujo | Menú, selección de cancha/equipo, HUD, pantalla de resultado, revancha. | Loop cerrado sin tocar el editor |
| **7** | Contenido y arte | Canchas, equipos, camisetas, materiales, iluminación, cámaras. | Juego presentable |
| **8** | Audio y pulido | SFX, ambiente de estadio, feedback visual, partículas. | Juego con "juice" |
| **9** | Testing y build | Testeo con usuarios ajenos al proyecto, corrección de bugs, build final, prueba en la máquina de la feria. | Ejecutable estable |
| **10** | Feria | Montaje, prueba de proyector y joysticks, cartel de controles, plan B. | Stand funcionando |

**Criterio de priorización:** las Etapas 1 a 6 son innegociables. Si el tiempo se acorta, se recorta contenido de la Etapa 7 (menos canchas y equipos), nunca la jugabilidad ni el testing.

### Hitos de control
- **Hito A (fin Etapa 3):** la mecánica es divertida. Si acá no lo es, no se sigue agregando contenido — se rediseña.
- **Hito B (fin Etapa 6):** el juego se puede jugar entero sin abrir el editor de Godot.
- **Hito C (fin Etapa 9):** build probado en la máquina real de la feria, no solo en la de desarrollo.

### División de tareas entre integrantes

| Área | Responsable principal | Apoya |
|---|---|---|
| Mecánica de tiro y física de la pelota | Javier Montoro | Facundo Aguinaga |
| Mecánica del arquero y timing | Facundo Aguinaga | Javier Montoro |
| `match_manager` (turnos, rondas, muerte súbita) | Javier Montoro | Facundo Aguinaga |
| Input Map y multijugador local | Facundo Aguinaga | Javier Montoro |
| UI, menús y HUD | Facundo Aguinaga | Javier Montoro |
| Canchas, equipos y arte | Javier Montoro | Facundo Aguinaga |
| Audio | Facundo Aguinaga | — |
| Build, testing y documentación | Ambos | — |

**Modo de trabajo:** rama `main` estable + una rama por funcionalidad (`feat/arquero`, `feat/ui-menu`, etc.), merge solo cuando la funcionalidad corre sin errores. Ninguno de los dos toca la misma escena `.tscn` al mismo tiempo: los archivos de escena de Godot generan conflictos difíciles de resolver a mano, así que se avisa antes de editar una escena compartida.

**Sincronización:** una puesta en común por semana para revisar avances contra el plan y reasignar si alguna tarea se traba.

---

## 9. Uso de agentes de IA

Este proyecto se desarrolla con asistencia de agentes de IA (Claude / asistentes de código). Se declara explícitamente el criterio de uso:

### 9.1 Qué se delega a la IA
- Generación de scripts base y *boilerplate* (managers, controladores, estructuras de datos).
- Explicación de APIs de Unity y del Input System.
- Debugging: análisis de errores de compilación y de comportamientos inesperados.
- Refactors, renombrado y organización de código.
- Redacción de documentación y comentarios.

### 9.2 Qué NO se delega
- Las **decisiones de diseño**: reglas, balance, qué hace divertido al juego, qué se recorta. Son del autor.
- La **validación**: ningún código entra al repositorio sin haber sido leído, entendido y probado en el editor.
- La **defensa oral del proyecto**: se debe poder explicar línea por línea qué hace cada script.

### 9.3 Flujo de trabajo con agentes
1. Definir la tarea de forma acotada (un script o una funcionalidad por vez).
2. Pedir la implementación al agente, indicando contexto: **Godot 4.x, GDScript**, scripts existentes, árbol de nodos y señales involucradas. Aclarar la versión evita que devuelva código de Godot 3, que es incompatible.
3. **Leer el código antes de pegarlo.** Si hay algo que no se entiende, se pregunta hasta entenderlo. Aplica a los dos integrantes por igual: nadie mergea código que no puede explicar.
4. Probar en el editor. Verificar el caso normal y al menos un caso borde.
5. Commit con mensaje descriptivo.

### 9.4 Trazabilidad
Se mantiene el archivo `/Docs/prompts-ia.md` con los prompts relevantes utilizados y una nota de qué se modificó manualmente sobre lo generado. Esto permite auditar el proceso y sostener la defensa del trabajo.

### 9.5 Convención de commits
```
feat: agrega mecánica de potencia del disparo
fix: corrige detección de gol cuando la pelota pega en el travesaño
refactor: separa lógica de turnos de MatchManager
docs: actualiza plan de trabajo
```
Se recomienda indicar en el cuerpo del commit cuando la implementación fue asistida por IA.

---

## 10. Criterios de aceptación y testing

| Área | Criterio |
|---|---|
| Física | La pelota nunca atraviesa el arco, la red ni al arquero. |
| Turnos | El orden de pateador/arquero se respeta las 5 rondas sin desincronizarse. |
| Marcador | El marcador coincide siempre con los goles efectivamente convertidos. |
| Muerte súbita | Se activa solo con empate y termina exactamente cuando uno anota y el otro falla. |
| Input | Los dos joysticks controlan a jugadores distintos y no se cruzan al reconectar. |
| Justicia | El arquero no puede ver hacia dónde apunta el pateador. |
| Robustez | El juego no crashea al desconectar un joystick ni al hacer spam de botones. |
| Onboarding | Una persona que nunca lo jugó entiende los controles en menos de 30 segundos. |

**Testing con usuarios:** mínimo 5 personas ajenas al desarrollo antes de la feria. Se observa sin explicar nada y se anota dónde se traban.

---

## 11. Riesgos y mitigación

| Riesgo | Impacto | Mitigación |
|---|---|---|
| La mecánica no resulta divertida | Alto | Hito A temprano: prototipar y testear la mecánica antes de invertir en arte. |
| Balance roto (siempre gana el pateador o siempre el arquero) | Alto | Parámetros expuestos en el Inspector para ajustar sin recompilar; testing iterativo en Etapa 3. |
| Problemas con los joysticks en la feria | Alto | Fallback a teclado siempre disponible + probar los joysticks exactos en la máquina real. |
| Alcance demasiado ambicioso | Medio | Lista de "fuera de alcance" cerrada; recortar contenido antes que jugabilidad. |
| Código generado por IA que no se entiende | Medio | Regla de no commitear sin leer y entender; registro en `prompts-ia.md`. |
| Pérdida de trabajo | Medio | Commits frecuentes y push diario a GitHub. |

---

## 12. Requerimientos físicos para la feria

| Recurso | Cantidad / Detalle |
|---|---|
| Computadora o notebook | 1 (ejecuta el juego) |
| Joysticks | 2 (multijugador local) |
| Monitor o proyector con pantalla | 1 |
| Tomas de corriente | 2 (PC + monitor/proyector) |
| Mesa | 1, para apoyar el equipo |
| Espacio | Aprox. 2 × 2 m, para los dos jugadores y la circulación de visitantes |
| Vinculación con electrónica | No aplica |

**Extras recomendados:** zapatilla/alargue, cartel impreso con los controles, y el ejecutable copiado en un pendrive como respaldo.

---

## 13. Checklist previo a la entrega

- [ ] Repositorio público y accesible, con este documento en la raíz.
- [ ] `README.md` con descripción, controles e instrucciones de ejecución.
- [ ] Build funcionando en una máquina distinta a la de desarrollo.
- [ ] `/Docs/prompts-ia.md` actualizado.
- [ ] Historial de commits que refleje el proceso, no un único commit final.
- [ ] Testeo hecho con al menos 5 personas externas.
- [ ] Recursos físicos confirmados con la organización de la feria.

---

## Anexo A — Mapeo con los puntos de la consigna

| Punto pedido | Respuesta | Sección |
|---|---|---|
| Nombre del proyecto | Penalty ShoutOut | Encabezado |
| De qué trata el juego | Juego de penales 1v1 local, tanda en distintas canchas y equipos | 1 |
| Condiciones de victoria / derrota / finalización | Más goles en 5 tiros; empate → muerte súbita; termina al definirse ganador | 2 |
| Loop general | Menú → selección → tanda → resultado → revancha o menú | 3 |
| "Upgrade" al finalizar | Sin mejoras competitivas; solo cosméticos (canchas, equipos, camisetas) | 5 |
| Mecánica principal | Alternar patear y atajar: dirección, altura y potencia vs. lado, altura y timing | 4 |
| Recursos físicos para la feria | 1 PC, 2 joysticks, monitor/proyector, 2 tomas, mesa, 2 × 2 m | 12 |
| ¿Multiplayer? | Sí, local en la misma máquina | 1, 7 |
| ¿Competitivo (ranking)? | No | 6 |
| Qué lo hace divertido | Tensión del 1v1, partidas cortas, revancha inmediata, variedad de canchas y equipos | 1, 5 |
| ¿Se vincula con electrónica? | No | 12 |
| Plan de trabajo por usar agentes de IA | Etapas, hitos, división de tareas y criterio de uso/validación de IA | 8, 9 |
