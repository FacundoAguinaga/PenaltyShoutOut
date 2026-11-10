#!/usr/bin/env python3
"""Lee las escenas de PES 2021 (common/demo/fixdemo/*/cut_data/*.fdc de dt12_g4.cpk).

Cada .fdc es un corte de una escena: nombra el clip de cada actor y, justo antes de
cada nombre, guarda donde esta parado y hacia donde mira: x, y, z (metros; x a lo
largo de la cancha, con la mitad en 0 y los arcos en +-52.5; z a lo ancho) y el giro
en grados. Los clips de una escena estan grabados cada uno respecto de su actor, asi
que la formacion solo esta aca.

Deja animaciones_pes/escenas.json: {corte: [{clip, pos: [x, y, z], giro, extra}]}.

    python3 tools/pes_extraer_escenas.py "/run/media/.../test" "/run/media/.../SP Football Life 2027"
"""
import json
import mmap
import re
import struct
import sys
from pathlib import Path

RAIZ = Path(sys.argv[1])
JUEGO = Path(sys.argv[2])
sys.path.insert(0, str(RAIZ / "PES21" / "tools"))
import cpk

SALIDA = Path(__file__).resolve().parent.parent / "animaciones_pes" / "escenas.json"
CLIP = re.compile(rb"cpk_dat/common/demo/anime/FoxAnim/FixDemo/Animations/(\w+)\.gani\0")


def leer_corte(datos: bytes) -> list:
    # La tabla del principio: cantidad de secciones y por cada una (offset, tamano, nombre).
    # La primera es la del corte, con un registro por actor.
    inicio, tamano, _ = struct.unpack_from("<III", datos, 4)
    bloque = datos[inicio:inicio + tamano]
    actores = []
    for m in CLIP.finditer(bloque):
        if m.group(1).endswith(b"_eyes_target"):
            continue
        s = m.start()
        x, y, z, giro = struct.unpack_from("<4f", bloque, s - 16)
        # Un dato por actor que todavia no se sabe que es (548 en los que arrancan despues).
        extra = struct.unpack_from("<f", bloque, s - 0x6c)[0]
        actores.append({"clip": m.group(1).decode(), "pos": [round(x, 4), round(y, 4), round(z, 4)], "giro": round(giro, 3), "extra": round(extra, 3)})
    return actores


def main() -> None:
    with open(JUEGO / "Data" / "dt12_g4.cpk", "rb") as f:
        b = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        meta = cpk.parse_utf(b, 0x10)["rows"][0]
        toc = cpk.parse_utf(b, meta["TocOffset"] + 0x10)["rows"]
        escenas = {}
        for fila in toc:
            nombre = fila["FileName"] or ""
            if not nombre.endswith(".fdc") or "cut_data" not in (fila["DirName"] or ""):
                continue
            inicio = meta["ContentOffset"] + fila["FileOffset"]
            actores = leer_corte(b[inicio:inicio + fila["FileSize"]])
            if actores:
                escenas[nombre.removesuffix(".fdc")] = actores
    SALIDA.write_text(json.dumps(escenas, indent=1))
    print("cortes con actores:", len(escenas))


if __name__ == "__main__":
    main()
