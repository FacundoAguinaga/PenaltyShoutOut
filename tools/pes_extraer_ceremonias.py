#!/usr/bin/env python3
"""Decodifica de dt12_g4.cpk las escenas de PES 2021: copa, penales y festejos con objetos.

Estan en common/demo/anime/FoxAnim/FixDemo/Animations, como .gani sueltos, y no en los
.mtar de dt13_all.cpk de donde sale todo lo demas. Los clips de una misma escena
(dml_x, dml_x_sub1, dml_x_sub2...) estan sincronizados, pero no todos traen su lugar en
la formacion: en raise01 arrancan los 16 en el mismo punto y hay que ubicarlos.
Deja un JSON por clip en animaciones_pes/json_ceremonia/.

    python3 tools/pes_extraer_ceremonias.py "/run/media/.../test" "/run/media/.../SP Football Life 2027"

Despues se retargetean con pes21_retarget.py en Blender, como el resto.
"""
import json
import mmap
import re
import sys
from pathlib import Path

RAIZ = Path(sys.argv[1])
JUEGO = Path(sys.argv[2])
sys.path.insert(0, str(RAIZ / "PES21" / "tools"))
sys.path.insert(0, str(RAIZ / "tools" / "pes-gani-master" / "pes_gani"))
import cpk
import pesmtar

SALIDA = Path(__file__).resolve().parent.parent / "animaciones_pes" / "json_ceremonia"
## Escenas de animaciones_pes/escenas.json (tools/pes_extraer_escenas.py) que usa el juego:
## se extraen todos sus clips.
ESCENAS_USADAS = ["pk_00_intro_teamMate00_5", "pk_00_intro_circle00", "pk_03_afterKick_teamMate_H_success_5_00",
                  "pk_03_afterKick_teamMate_H_fault_5_00", "end_pk_win_02", "end_pk_lose_02", "end_trophy_01_pl",
                  "end_trophy_01_cupeur"]
CARPETA = "common/demo/anime/FoxAnim/FixDemo/"
ELEGIDOS = re.compile(
    r"^dml_end_raise01_trophy08_(cup_lg_chl|sub\d+)$"
    r"|^dml_end_trophy01_(clap|hug|joy)\w*$"
    r"|^dml_pk_(goal|lose|miss|win)_\w+$"
    r"|^dml_pk_ready03_(kicker|keeper)_in$"
    r"|^dml_pk_wait_miss_set01_\d+$"
)
# Festejos de gol de un solo jugador, sin companeros ni objetos: se pueden usar sueltos.
FESTEJO = re.compile(r"^dml_goal_celebrate_(\d+)(\w*)$")


def main() -> None:
    with open(JUEGO / "Data" / "dt12_g4.cpk", "rb") as f:
        datos = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        meta = cpk.parse_utf(datos, 0x10)["rows"][0]
        toc = cpk.parse_utf(datos, meta["TocOffset"] + 0x10)["rows"]

        def leer(fila: dict) -> bytes:
            inicio = meta["ContentOffset"] + fila["FileOffset"]
            return datos[inicio:inicio + fila["FileSize"]]

        def archivo(nombre: str) -> bytes:
            return leer(next(r for r in toc if r["FileName"] == nombre and (r["DirName"] or "").endswith("CharacterAssets") and CARPETA in (r["DirName"] or "") + "/"))

        esqueleto = pesmtar.read_ask(archivo("body_anim_skel.ask"))
        rig = pesmtar.read_frig(archivo("body_skel.frig"))
        huesos = [b["name"] for b in esqueleto]
        SALIDA.mkdir(parents=True, exist_ok=True)
        escenas = json.loads((SALIDA.parent / "escenas.json").read_text())
        de_escenas = {a["clip"] for e in ESCENAS_USADAS for a in escenas[e] if a["clip"].startswith("dml_") and not a["clip"].endswith("_hi")}
        hechos = 0
        grupales = set()
        for fila in toc:
            m = FESTEJO.match((fila["FileName"] or "").removesuffix(".gani"))
            if m and m.group(2) and not m.group(2).endswith("_eyes_target"):
                grupales.add(m.group(1))
        for fila in toc:
            nombre = (fila["FileName"] or "").removesuffix(".gani")
            # Los _eyes_target solo mueven hacia donde miran los ojos.
            m = FESTEJO.match(nombre)
            solo = m is not None and not m.group(2) and m.group(1) not in grupales
            if not (fila["DirName"] or "").endswith("FixDemo/Animations") or not (solo or ELEGIDOS.match(nombre) or nombre in de_escenas) or nombre.endswith("_eyes_target"):
                continue
            bruto = leer(fila)
            canales = pesmtar.channel_map(rig, pesmtar.read_gani(bruto)["channels"])
            clip = pesmtar.clip_to_json(bruto, canales, huesos)
            clip.update(name=nombre, source="dt12_g4.cpk", category="ceremonia")
            (SALIDA / f"{nombre}.json").write_text(json.dumps(clip, separators=(",", ":")))
            hechos += 1
        print("escritos:", hechos)


if __name__ == "__main__":
    main()
