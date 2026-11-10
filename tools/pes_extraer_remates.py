#!/usr/bin/env python3
"""Decodifica de PES 2021 los remates (kick_*), que la exportacion original no incluyo.

Deja un JSON por clip en animaciones_pes/json_remates/. Despues se retargetean con
pes21_retarget.py en Blender, igual que el resto.

    python3 tools/pes_extraer_remates.py "/run/media/.../test"
"""
import json
import re
import sys
from pathlib import Path

RAIZ = Path(sys.argv[1])
PES = RAIZ / "PES21"
sys.path.insert(0, str(RAIZ / "tools" / "pes-gani-master" / "pes_gani"))
import pesmtar

SALIDA = Path(__file__).resolve().parent.parent / "animaciones_pes" / "json_remates"
# Los _lob son vaselinas: de ahi sale la picada.
PATRON = re.compile(r"^kick_(long|mid)_(0_0|2_0|3_0)_(instep|inside|infront)_y[0-6]_(000|045|f045)(_topspin|_curve)?$"
                    r"|^kick_(mid|short)_(0_0|3_0)_(outside|infront)_y0_\w+_lob$")

BODY = PES / "dt13" / "common" / "anime" / "FoxAnim" / "Body"
ASSETS = BODY / "CharacterAssets"
indice = json.loads((PES / "clip_index.json").read_text())
elegidos = {}
for x in indice:
    if x.get("name") and PATRON.match(x["name"]):
        elegidos.setdefault(x["name"], x)
print("clips:", len(elegidos))

SALIDA.mkdir(parents=True, exist_ok=True)
esqueleto = pesmtar.read_ask((ASSETS / "body_anim_skel.ask").read_bytes())
rig = pesmtar.read_frig((ASSETS / "body_skel.frig").read_bytes())
huesos = [b["name"] for b in esqueleto]

por_mtar = {}
for x in elegidos.values():
    por_mtar.setdefault(x["mtar"], []).append(x)
for mtar, clips in por_mtar.items():
    datos = (BODY / mtar).read_bytes()
    m = pesmtar.read_mtar(datos)
    entradas = {e["hash"]: e for e in m["entries"]}
    primero = next(iter(entradas.values()))
    canales = pesmtar.channel_map(rig, pesmtar.read_gani(datos[primero["addr"]:primero["addr"] + primero["size"]])["channels"])
    for x in clips:
        e = entradas.get(x["hash"])
        if e is None:
            continue
        clip = pesmtar.clip_to_json(datos[e["addr"]:e["addr"] + e["size"]], canales, huesos)
        clip.update(name=x["name"], hash=x["hash"], id=x["id"], source=mtar, category="remates")
        (SALIDA / f"{x['name']}.json").write_text(json.dumps(clip, separators=(",", ":")))
print("escritos:", len(list(SALIDA.glob("*.json"))))
