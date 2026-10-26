# Archivos de arranque para Cascadeur

Estos `.casc` **no son animaciones terminadas**. Cada uno trae el muñeco del
juego (`Ch36_nonPBR.fbx`) con una animación existente ya importada encima, para
no tener que empezar de cero ni configurar el rig.

| Archivo | Base que trae | Qué falta hacerle |
|---|---|---|
| `arranque_save_right_up.casc` | `goalkeeper diving save` — palomita ancha a la derecha, mano a x=+2.85 pero a solo 0.5 m de altura | Subirle el brazo para que llegue al ángulo |
| `arranque_save_left_up.casc` | `goalkeeper diving save (2)` — palomita ancha a la izquierda, mano a x=−3.53, misma altura baja | Lo mismo, del otro lado |

Son las **dos zonas que el juego no cubre bien**: los ángulos superiores. Las
otras siete están resueltas con animaciones que ya estaban en el proyecto (ver
`docs/animaciones.md`).

## Cómo seguir

1. Abrí el `.casc` en Cascadeur.
2. Ajustá la pose del contacto (el cuadro donde la mano toca la pelota) para que
   el brazo llegue arriba. Acá es donde sirve el AutoPosing.
3. Guardá.
4. Exportá a FBX. **Esto necesita licencia paga**: la versión `basic` solo
   guarda `.casc`.
5. Poné el FBX en `Player/Animations/` y avisá, que el resto ya está cableado.

## Por qué no están hechas

Las herramientas que crean animación en Cascadeur (AutoPosing, AutoPhysics,
Inbetweening) **no tienen API de Python** — son solo de interfaz gráfica. Se
verificó: devuelven objetos sin métodos. El Mirror sí tiene API pero no surte
efecto por script (necesita el estado de selección de la interfaz).

Por eso estos archivos llegan hasta acá y el último tramo es a mano.
