"""
Genera las animaciones de arquero en Blender a partir de una palomita de mocap.

Se corre sin abrir Blender:
    blender -b Player/Animations/blender/arquero.blend --python tools/blender/generar_arquero.py

Hay dos familias:

LATERALES (save/dive _left/_right _up/_mid/_down). Parten de la palomita
(`goalkeeper diving save`, a la derecha) y se modifican con:
  - salto:   se le suma (o resta) altura a la cadera con una campana alrededor
             del contacto. El cuerpo entero sigue a la cadera.
  - alcance: se escala el desplazamiento lateral de la cadera (los fallos se
             tiran para el lado correcto pero no llegan).
  - apuntar: se rota el brazo desde el hombro para que la mano vaya hacia un
             punto (IK de un hueso), con peso suave en el tiempo.
  - piso:    si al bajar la cadera el cuerpo atraviesa el piso, se lo sube.
  - espejo:  se refleja todo en X para obtener la version izquierda.

CENTRO (save/dive _center _up/_mid/_down). Parten de la postura de espera del
primer cuadro y se arman con:
  - la cadera sube (salto), baja (agacharse) o se corre de costado;
  - las piernas tienen IK de dos huesos para que los pies queden apoyados
    (las rodillas se doblan solas al agacharse);
  - los brazos tienen IK de dos huesos hacia un objetivo (codo doblado);
  - el torso se inclina hacia adelante para las de abajo.

Ninguna atajada agarra la pelota: los brazos quedan estirados despues del
contacto (la pelota rebota en las manos, eso lo resuelve el juego).

Todo se calcula sobre matrices de mundo y se vuelve a pasar a la base local
de cada hueso, asi que los hijos siguen a sus padres solos. En Blender el
arquero mira hacia -Y, X es el costado y Z la altura.
"""
import math
import os

import bpy
from mathutils import Matrix, Quaternion, Vector

SALIDA = "E:/descargas javi/PenaltyShoutOut/Player/Animations/blender/"
F0, F1 = 1, 103
HIPS = "mixamorig1:Hips"
SPINE = "mixamorig1:Spine"
M = "mixamorig1:"

sc = bpy.context.scene
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
bones = arm.data.bones
pose = arm.pose.bones
MW = arm.matrix_world.copy()

# la accion original queda guardada como base de todas las variantes
if "BASE_divingsave" not in bpy.data.actions:
    arm.animation_data.action.name = "BASE_divingsave"
BASE = bpy.data.actions["BASE_divingsave"]
BASE.use_fake_user = True
arm.animation_data.action = BASE
for pb in pose:
    pb.rotation_mode = 'QUATERNION'

# orden padres-antes-que-hijos y reposo relativo al padre
orden = []


def _rec(b):
    orden.append(b.name)
    for c in b.children:
        _rec(c)


for b in bones:
    if b.parent is None:
        _rec(b)

rest_rel = {
    b.name: (b.parent.matrix_local.inverted() @ b.matrix_local) if b.parent else b.matrix_local.copy()
    for b in bones
}


def leer_base():
    """Base local de cada hueso en cada cuadro de la animacion original."""
    arm.animation_data.action = BASE
    datos = {}
    for f in range(F0, F1 + 1):
        sc.frame_set(f)
        datos[f] = {pb.name: pb.matrix_basis.copy() for pb in pose}
    return datos


def fk(base):
    """Matrices de mundo a partir de las bases locales."""
    W = {}
    for n in orden:
        b = bones[n]
        W[n] = (W[b.parent.name] if b.parent else MW) @ rest_rel[n] @ base[n]
    return W


def base_desde_mundo(n, Wn, W):
    padre = bones[n].parent
    Wp = W[padre.name] if padre else MW
    return rest_rel[n].inverted() @ Wp.inverted() @ Wn


def suave(x):
    return 0.5 - 0.5 * math.cos(math.pi * min(max(x, 0.0), 1.0))


def ventana(f, a, c, b):
    """0 en a, 1 en c, 0 en b, con transiciones suaves."""
    if f <= a or f >= b:
        return 0.0
    return suave((f - a) / (c - a) if f <= c else (b - f) / (b - c))


def meseta(f, a, c, d, b):
    """0 en a, sube hasta 1 en c, se queda en 1 hasta d y baja a 0 en b."""
    if f <= a or f >= b:
        return 0.0
    if f < c:
        return suave((f - a) / (c - a))
    if f <= d:
        return 1.0
    return suave((b - f) / (b - d))


def rotar(B, W, n, q, centro):
    """Rota el hueso n (y sus hijos) con el cuaternion q alrededor de un punto."""
    D = Matrix.Translation(centro) @ q.to_matrix().to_4x4() @ Matrix.Translation(-centro)
    B[n] = base_desde_mundo(n, D @ W[n], W)
    return fk(B)


def mover_cadera(B, W, delta):
    Wh = W[HIPS].copy()
    Wh.translation = Wh.translation + delta
    B[HIPS] = base_desde_mundo(HIPS, Wh, W)
    return fk(B)


def ik2(B, W, sup, inf, fin, objetivo, polo):
    """IK de dos huesos (hombro-codo-mano o cadera-rodilla-pie): lleva el
    extremo al objetivo doblando la articulacion del medio hacia el polo."""
    s = W[sup].translation.copy()
    e = W[inf].translation
    h = W[fin].translation
    l1, l2 = (e - s).length, (h - e).length
    d = min(max((objetivo - s).length, abs(l1 - l2) + 1e-3), l1 + l2 - 1e-3)
    eje = (objetivo - s).normalized()
    cos_a = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    a = math.acos(min(max(cos_a, -1.0), 1.0))
    pp = polo - s
    perp = (pp - eje * pp.dot(eje)).normalized()
    codo = s + eje * (math.cos(a) * l1) + perp * (math.sin(a) * l1)
    W = rotar(B, W, sup, (e - s).normalized().rotation_difference((codo - s).normalized()), s)
    e2, h2 = W[inf].translation.copy(), W[fin].translation
    final = s + eje * d
    return rotar(B, W, inf, (h2 - e2).normalized().rotation_difference((final - e2).normalized()), e2)


def min_z(W):
    return min(W[n].translation.z for n in orden)


def generar(base, salto=0.0, alcance=1.0, apuntes=(), vent_salto=(20, 34, 48), vent_brazo=(22, 34, 46)):
    h0 = fk(base[F0])[HIPS].translation.copy()
    out = {}
    for f in range(F0, F1 + 1):
        B = dict(base[f])
        W = fk(B)
        piso = min(min_z(W), 0.0)
        # salto y alcance: se mueve la cadera y el resto del cuerpo la sigue
        h = W[HIPS].translation
        nueva = Vector((h0.x + (h.x - h0.x) * alcance, h.y, h.z + salto * ventana(f, *vent_salto)))
        W = mover_cadera(B, W, nueva - h)
        # apuntar brazos: rotacion desde el hombro hacia el objetivo
        peso = ventana(f, *vent_brazo)
        if peso > 0.0:
            for brazo, mano, (gx, gz) in apuntes:
                s = W[brazo].translation
                m = W[mano].translation
                objetivo = Vector((gx, m.y, gz))
                q = (m - s).normalized().rotation_difference((objetivo - s).normalized())
                W = rotar(B, W, brazo, Quaternion().slerp(q, peso), s.copy())
        # piso: al bajar la cadera el cuerpo no puede quedar mas hundido que
        # en la animacion original
        hundido = piso - min_z(W)
        if hundido > 0.0:
            W = mover_cadera(B, W, Vector((0.0, 0.0, hundido)))
        out[f] = B
    return out


PIERNAS = (("RightUpLeg", "RightLeg", "RightFoot"), ("LeftUpLeg", "LeftLeg", "LeftFoot"))
BRAZOS = (("RightArm", "RightForeArm", "RightHand"), ("LeftArm", "LeftForeArm", "LeftHand"))


def generar_centro(base, altura=0.0, perfil=(20, 34, 36, 52), lateral=0.0, agache=0.06,
                   inclinar=0.0, brazos=None, vent_brazo=(20, 32, 46, 66)):
    """Animacion de centro sobre la postura de espera.
    altura > 0 salta (los pies se despegan), < 0 se agacha (pies apoyados).
    brazos = ((x, y, z) mano derecha, (x, y, z) mano izquierda) en mundo."""
    quieto = base[F0]
    W0 = fk(quieto)
    pies0 = {p[2]: W0[M + p[2]].copy() for p in PIERNAS}
    out = {}
    for f in range(F0, F1 + 1):
        B = dict(quieto)
        W = fk(B)
        # preparacion: flexiona un poco las piernas antes de reaccionar
        prep = -agache * ventana(f, 4, perfil[0], perfil[1])
        dz = altura * meseta(f, *perfil) + prep
        dx = lateral * meseta(f, *perfil)
        W = mover_cadera(B, W, Vector((dx, 0.0, dz)))
        if inclinar:
            s = W[M + "Spine"].translation.copy()
            ang = math.radians(inclinar) * meseta(f, *perfil)
            W = rotar(B, W, M + "Spine", Quaternion(Vector((1, 0, 0)), ang), s)
        # piernas: los pies siguen a la cadera solo hacia arriba y de costado
        for sup, inf, fin in PIERNAS:
            P0 = pies0[fin]
            obj = P0.translation + Vector((dx, 0.0, max(0.0, dz)))
            rodilla = W[M + inf].translation + Vector((0.0, -1.0, 0.0))
            W = ik2(B, W, M + sup, M + inf, M + fin, obj, rodilla)
            Wp = P0.copy()
            Wp.translation = W[M + fin].translation
            B[M + fin] = base_desde_mundo(M + fin, Wp, W)
            W = fk(B)
        # brazos: IK hacia el objetivo, con peso suave en el tiempo
        peso = meseta(f, *vent_brazo)
        if brazos and peso > 0.0:
            for (sup, inf, fin), obj in zip(BRAZOS, brazos):
                actual = W[M + fin].translation
                destino = actual.lerp(Vector(obj), peso)
                lado = 1.0 if "Left" in sup else -1.0
                codo = W[M + inf].translation + Vector((lado * 0.6, 0.3, -0.4))
                W = ik2(B, W, M + sup, M + inf, M + fin, destino, codo)
        out[f] = B
    return out


def espejo_nombre(n):
    if "Left" in n:
        return n.replace("Left", "Right")
    if "Right" in n:
        return n.replace("Right", "Left")
    return n


S = Matrix.Scale(-1.0, 4, Vector((1.0, 0.0, 0.0)))
WREST = {b.name: MW @ b.matrix_local for b in bones}
CORR = {n: (S @ WREST[espejo_nombre(n)] @ S).inverted() @ WREST[n] for n in WREST}


def espejar(anim):
    out = {}
    for f, B in anim.items():
        W = fk(B)
        Wm = {n: S @ W[espejo_nombre(n)] @ S @ CORR[n] for n in orden}
        out[f] = {n: base_desde_mundo(n, Wm[n], Wm) for n in orden}
    return out


def escribir_y_exportar(nombre, anim):
    act = bpy.data.actions.get(nombre)
    if act:
        bpy.data.actions.remove(act)
    act = bpy.data.actions.new(nombre)
    act.use_fake_user = True
    arm.animation_data.action = act
    for f in range(F0, F1 + 1):
        for n in orden:
            pb = pose[n]
            pb.matrix_basis = anim[f][n]
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
    sc.frame_start, sc.frame_end = F0, F1
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    ruta = SALIDA + nombre + ".fbx"
    bpy.ops.export_scene.fbx(
        filepath=ruta, use_selection=True, object_types={'ARMATURE'},
        add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False,
        bake_anim_use_nla_strips=False, bake_anim_simplify_factor=0.0,
        bake_anim_force_startend_keying=True, use_armature_deform_only=False)
    arm.animation_data.action = BASE
    print("  %-20s %d KB" % (nombre + ".fbx", os.path.getsize(ruta) // 1024))


os.makedirs(SALIDA, exist_ok=True)
base = leer_base()


def apuntes(der, izq):
    return ((M + "RightArm", M + "RightHand", der), (M + "LeftArm", M + "LeftHand", izq))


# Los saves llevan los brazos estirados hasta el cuadro 52 (tapan, no abrazan
# la pelota). Los dives llegan con las manos cortas: la pelota pasa de largo.
LATERALES = {
    "save_right_up": generar(base, salto=0.75, apuntes=apuntes((2.70, 2.35), (2.45, 2.15)), vent_brazo=(22, 34, 52)),
    "save_right_mid": generar(base, salto=0.10, apuntes=apuntes((2.60, 1.25), (2.35, 1.10)), vent_brazo=(22, 34, 52)),
    "save_right_down": generar(base, salto=-0.50, vent_salto=(18, 34, 56),
                               apuntes=apuntes((2.65, 0.20), (2.45, 0.15)), vent_brazo=(20, 34, 52)),
    "dive_right_up": generar(base, salto=0.35, alcance=0.60, apuntes=apuntes((1.75, 2.15), (1.55, 2.00))),
    "dive_right_mid": generar(base, alcance=0.55, apuntes=apuntes((1.60, 1.15), (1.45, 1.00))),
    "dive_right_down": generar(base, salto=-0.45, alcance=0.60, vent_salto=(18, 34, 56),
                               apuntes=apuntes((1.55, 0.30), (1.40, 0.25))),
}
# Centro: la mano derecha esta en -X. Objetivos (x, y, z): y negativo es
# hacia adelante (hacia el pateador).
CENTRO = {
    # salta con los dos brazos arriba y la manda por encima del travesano
    "save_center_up": generar_centro(base, altura=0.42, perfil=(22, 34, 37, 54),
                                     brazos=((-0.22, -0.35, 2.65), (0.22, -0.35, 2.65)),
                                     vent_brazo=(18, 31, 44, 64)),
    # bloquea con las manos adelante, a la altura del pecho
    "save_center_mid": generar_centro(base, altura=-0.10, perfil=(18, 32, 50, 72), inclinar=12,
                                      brazos=((-0.14, -0.65, 1.15), (0.14, -0.65, 1.15))),
    # se agacha y la tapa con las manos abajo
    "save_center_down": generar_centro(base, altura=-0.42, perfil=(16, 32, 54, 80), inclinar=35,
                                       brazos=((-0.16, -0.55, 0.20), (0.16, -0.55, 0.20))),
    # salta tarde y corto: la pelota le pasa por arriba de las manos
    "dive_center_up": generar_centro(base, altura=0.15, perfil=(28, 40, 42, 56),
                                     brazos=((-0.30, -0.30, 2.05), (0.30, -0.30, 2.05)),
                                     vent_brazo=(26, 40, 48, 66)),
    # lo enganan: se corre para un costado y la pelota entra por el medio
    "dive_center_mid": generar_centro(base, altura=-0.12, lateral=-0.55, perfil=(14, 30, 60, 85), inclinar=10,
                                      brazos=((-0.75, -0.40, 0.95), (0.05, -0.45, 0.90))),
    # se agacha tarde: la pelota le pasa por abajo de las manos
    "dive_center_down": generar_centro(base, altura=-0.14, perfil=(26, 42, 56, 78), inclinar=20,
                                       brazos=((-0.25, -0.45, 0.75), (0.25, -0.45, 0.75)),
                                       vent_brazo=(26, 42, 52, 72)),
}
print("exportando:")
for nombre, anim in LATERALES.items():
    escribir_y_exportar(nombre, anim)
    escribir_y_exportar(nombre.replace("right", "left"), espejar(anim))
for nombre, anim in CENTRO.items():
    escribir_y_exportar(nombre, anim)
arm.animation_data.action = bpy.data.actions["save_center_up"]
sc.frame_set(34)
if bpy.app.background:
    bpy.ops.wm.save_mainfile()
print("listo")
