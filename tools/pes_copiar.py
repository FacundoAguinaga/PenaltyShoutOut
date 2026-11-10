#!/usr/bin/env python3
"""Copia al proyecto los clips de PES 2021 que usa el juego.

Quedan en animaciones_pes/ (ignorada por git). Despues hay que importarlos y
armar las librerias:

    python3 tools/pes_copiar.py "/run/media/.../PES21"
    godot --headless --path . --import
    godot --headless --path . -s res://tools/pes_construir.gd
"""
import csv
import json
import re
import shutil
import sys
from pathlib import Path

DESTINO = Path(__file__).resolve().parent.parent / "animaciones_pes"

# Familias de atajada desde parado. Se dejan afuera las de salir corriendo
# (_3_0_), las que arrancan en el piso y las que se van hacia atras del arco.
FAMILIAS = {"gkcatch", "gkblockcover", "gkdeflect", "gkdeflectlate", "gkpunch",
            "gkdeflectExpect3", "gkdeflectFoot", "gkcollapsing"}
Z_MIN_CM, Z_MAX_CM = -10, 110


def atajadas(pes: Path) -> dict:
    contactos = json.loads((pes / "gk_contacts.json").read_text())
    with open(pes / "gk_contacts.csv", newline="") as f:
        huesos = {fila["name"]: fila["hit_bone_name"] for fila in csv.DictReader(f) if fila["hit_bone_name"]}
    elegidas = {}
    for nombre, clip in contactos.items():
        if clip.get("category") != "gk_saves" or not clip.get("contacts"):
            continue
        familia = re.match(r"[a-zA-Z0-9]+", nombre).group(0)
        desde_parado = "_0_0" in nombre or "_pk_" in nombre
        if familia not in FAMILIAS or not desde_parado:
            continue
        contacto = clip["contacts"][0]
        pelota = contacto.get("ball_pos_cm")
        if not pelota or pelota[0] is None or contacto["hit_frame"] < 3:
            continue
        if Z_MIN_CM <= pelota[2] <= Z_MAX_CM:
            elegidas[nombre] = {
                "hit_frame": contacto["hit_frame"],
                "contacto_m": [pelota[0] / 100.0, pelota[1] / 100.0, pelota[2] / 100.0],
                "hueso": huesos.get(nombre, ""),
            }
    return elegidas


def filtrar(carpeta: Path, patron: str) -> list:
    return sorted(f for f in carpeta.glob("*.fbx") if re.search(patron, f.stem))


def main() -> None:
    pes = Path(sys.argv[1])
    fbx = pes / "fbx"
    DESTINO.mkdir(exist_ok=True)

    saves = atajadas(pes)
    grupos = {
        "atajadas": [fbx / "gk_saves" / f"{n}.fbx" for n in saves],
        "arquero_extra": (
            sorted((fbx / "penalty_gk").glob("*.fbx"))
            + filtrar(fbx / "gk_saves", r"^(gkrise_(faceup|sideways|sideways_catch|facedown_catch)_0_0|gkseeoff|gksavingCancel)")
            + filtrar(fbx / "gk_reactions", r"^dm_(oop|layer)_gk_(pk|cheer)")
        ),
        "pateador": sorted((fbx / "penalty_player").glob("*.fbx")),
        "festejos": filtrar(fbx / "celebration", r"^dm_(goal|pfm|tu|oop)_"),
    }

    (DESTINO / "atajadas.json").write_text(json.dumps(saves, indent=1))
    for grupo, archivos in grupos.items():
        carpeta = DESTINO / "fbx" / grupo
        carpeta.mkdir(parents=True, exist_ok=True)
        copiados = 0
        for f in archivos:
            if f.exists():
                destino = carpeta / f.name
                if not destino.exists():
                    shutil.copy2(f, destino)
                copiados += 1
        print(f"{grupo}: {copiados}")


if __name__ == "__main__":
    main()
