#!/usr/bin/env python3
"""Extrae de dt44_all.cpk los sonidos de partido de PES 2021: la tribuna y el arbitro.

Estan en common/sound/match/, en bancos de CRIWARE: cada .acb trae el audio adentro (o en
el .awb del mismo nombre) como streams HCA sin cifrar. Cada stream empieza con una
cabecera "HCA" (con los bytes enmascarados con 0x80 o no) seguida de 0x02 (version), asi
que se corta de una cabecera a la siguiente y ffmpeg lo decodifica (estereo, 48 kHz).
En la tribuna y el arbitro el nombre del banco ya dice que es; en SE_Movement (los golpes
de la pelota) se leen las tablas de cues del .acb para saber que es cada sonido.

Deja animaciones_pes/sonidos/<banco>/<n>.ogg y animaciones_pes/sonidos/sonidos.json con la
duracion y el volumen medio de cada uno y, en los silbatos, cuantos pitazos tiene y cuanto
suena (para elegir el corto, el largo o el del final sin depender del orden del banco).

Lo que hay, medido por la envolvente de volumen (no se puede escuchar desde aca):
- Goal, Goal_YEAH y Goal_OHH comparten arranques de 2-3 s y rugidos de 30 s que se van
  apagando: PES los suena en capas. Lo propio de cada uno es el "yeah" de 10 s y la ola
  de "ohh" de 8 s, pareja.
- Surprise: un "uuh" fuerte que cae. Anger: abucheos. CZ_Base y CM_Base: el ambiente.
- Referee_A..F: un arbitro cada uno, con silbatos cortos, largos y de varios pitazos.

    python3 -I tools/pes_extraer_sonidos.py "/run/media/.../test" "/run/media/.../SP Football Life 2027"
"""
import json
import mmap
import numpy as np
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

RAIZ = Path(sys.argv[1])
JUEGO = Path(sys.argv[2])
sys.path.insert(0, str(RAIZ / "PES21" / "tools"))
import cpk

SALIDA = Path(__file__).resolve().parent.parent / "animaciones_pes" / "sonidos"
CARPETA = "common/sound/match/"
## Los bancos que usa el juego: reacciones de la tribuna y silbatos.
BANCOS = re.compile(r"^SE_Cheers_\w+$|^SE_Referee_\w+$")
## Los golpes de la pelota (patada, red, palo, travesano, arquero, pique). Aca si se leen
## los cues, porque el banco mezcla 126 sonidos y cada uno tiene su nombre.
GOLPES = "SE_Movement"
CUES_GOLPES = re.compile(r"^SE_PL_(BALLHIT_(INSTEP|SHOOT|GOALNET|GOALPOST|GOALBAR|BOUND)|GK_CATCH|GK_PUNCH)_\d+$")


def streams_hca(datos: bytes) -> list[bytes]:
    inicios = [m.start() for m in re.finditer(rb"[\x48\xC8][\x43\xC3][\x41\xC1][\x00\x80]\x02", datos)]
    return [datos[a:b] for a, b in zip(inicios, inicios[1:] + [len(datos)])]


def leer_acb(acb: bytes) -> tuple[dict, dict]:
    """Los cues de un .acb ({nombre: [ids del awb]}) y los streams de su AFS2 embebido.

    Las tablas son @UTF, como las del cpk, pero con la version en los 16 bits altos del
    campo que cpk.py lee como offset de las filas: se pone en 0 antes de leerlas. Un cue
    apunta a una secuencia; sus pistas tienen eventos cuyo comando 0x07D0 (nota) apunta a
    un synth, y el synth a sus formas de onda (MemoryAwbId = id dentro del AFS2).
    """
    b = bytearray(acb)

    def tabla(off: int) -> dict:
        b[off + 8:off + 10] = b"\0\0"
        return cpk.parse_utf(b, off)

    raiz = tabla(0)
    fila = raiz["rows"][0]

    def sub(nombre: str) -> tuple[list, int]:
        _, off, tam = fila[nombre]
        if not tam:
            return [], 0
        t = tabla(raiz["data_off"] + off)
        return t["rows"], t["data_off"]

    def blob(base: int, valor) -> bytes:
        _, off, tam = valor
        return bytes(b[base + off:base + off + tam])

    nombres, _ = sub("CueNameTable")
    cues, _ = sub("CueTable")
    synths, base_synth = sub("SynthTable")
    secuencias, base_seq = sub("SequenceTable")
    pistas, _ = sub("TrackTable")
    eventos, base_ev = sub("TrackEventTable")
    ondas, _ = sub("WaveformTable")

    def ref(tipo: int, i: int, prof: int) -> list:
        if prof > 8:
            return []
        if tipo == 1:
            return [ondas[i]["MemoryAwbId"]]
        if tipo == 2:
            items = blob(base_synth, synths[i]["ReferenceItems"])
            return [x for k in range(0, len(items) - 3, 4) for x in ref(*struct.unpack(">HH", items[k:k + 4]), prof + 1)]
        if tipo == 3:
            salida = []
            indices = blob(base_seq, secuencias[i]["TrackIndex"])
            for k in range(0, len(indices) - 1, 2):
                pista = pistas[struct.unpack(">H", indices[k:k + 2])[0]]
                if pista["EventIndex"] == 0xFFFF:
                    continue
                cmd = blob(base_ev, eventos[pista["EventIndex"]]["Command"])
                p = 0
                while p + 3 <= len(cmd):
                    codigo, tam = struct.unpack(">HB", cmd[p:p + 3])
                    if codigo == 0x07D0 and tam >= 4:
                        salida += ref(*struct.unpack(">HH", cmd[p + 3:p + 7]), prof + 1)
                    p += 3 + tam
            return salida
        return []

    mapa = {n["CueName"]: sorted(set(ref(cues[n["CueIndex"]]["ReferenceType"], cues[n["CueIndex"]]["ReferenceIndex"], 0))) for n in nombres}
    _, off, tam = fila["AwbFile"]
    awb = bytes(b[raiz["data_off"] + off:raiz["data_off"] + off + tam])
    streams = {}
    if awb[:4] == b"AFS2":
        tam_off, tam_id = awb[5], awb[6]
        cuantos = struct.unpack("<I", awb[8:12])[0]
        alineado = struct.unpack("<H", awb[12:14])[0]
        ids = [int.from_bytes(awb[16 + k * tam_id:16 + (k + 1) * tam_id], "little") for k in range(cuantos)]
        p = 16 + cuantos * tam_id
        offs = [int.from_bytes(awb[p + k * tam_off:p + (k + 1) * tam_off], "little") for k in range(cuantos + 1)]
        for k in range(cuantos):
            inicio = (offs[k] + alineado - 1) // alineado * alineado
            streams[ids[k]] = awb[inicio:offs[k + 1]]
    return mapa, streams


def a_ogg(hca: bytes, ogg: Path, tmp: str) -> dict:
    """Decodifica un stream HCA a .ogg y lo mide; si sale vacio, lo borra."""
    archivo = Path(tmp) / "s.hca"
    archivo.write_bytes(hca)
    # El ultimo bloque de cada corte trae bytes de mas: ffmpeg avisa y sigue.
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-i", str(archivo), "-c:a", "libvorbis", "-q:a", "5", str(ogg)], check=False)
    datos = medir(ogg) if ogg.exists() else {"duracion": 0.0}
    if datos["duracion"] < 0.05:
        ogg.unlink(missing_ok=True)
    return datos


def medir(ogg: Path) -> dict:
    salida = subprocess.run(["ffmpeg", "-v", "info", "-i", str(ogg), "-af", "volumedetect", "-f", "null", "-"],
                            capture_output=True, text=True).stderr
    duracion = re.search(r"Duration: (\d+):(\d+):([\d.]+)", salida)
    medio = re.search(r"mean_volume: ([-\d.]+) dB", salida)
    return {
        "duracion": round(int(duracion[1]) * 3600 + int(duracion[2]) * 60 + float(duracion[3]), 3) if duracion else 0.0,
        "volumen_db": float(medio[1]) if medio else -99.0,
    }


def pitazos(ogg: Path) -> dict:
    """Cuantas veces suena el silbato (envolvente cada 50 ms, a menos de 12 dB del pico)."""
    crudo = subprocess.run(["ffmpeg", "-v", "quiet", "-i", str(ogg), "-ac", "1", "-ar", "8000", "-f", "s16le", "-"],
                           capture_output=True).stdout
    a = np.frombuffer(crudo, np.int16).astype(float) / 32768.0
    n = 400
    k = len(a) // n
    env = 20.0 * np.log10(np.sqrt((a[:k * n].reshape(k, n) ** 2).mean(1)) + 1e-6)
    suena = env > env.max() - 12.0
    return {"pitazos": int(suena[0] + np.sum(suena[1:] & ~suena[:-1])), "sonando": round(float(suena.sum()) * 0.05, 2)}


def main() -> None:
    with open(JUEGO / "Data" / "dt44_all.cpk", "rb") as f:
        datos = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        meta = cpk.parse_utf(datos, 0x10)["rows"][0]
        toc = cpk.parse_utf(datos, meta["TocOffset"] + 0x10)["rows"]
        archivos = {}
        for fila in toc:
            ruta = (fila["DirName"] or "") + "/" + (fila["FileName"] or "")
            if CARPETA in ruta and (BANCOS.match(Path(fila["FileName"] or "").stem) or (fila["FileName"] or "") == GOLPES + ".acb"):
                inicio = meta["ContentOffset"] + fila["FileOffset"]
                archivos.setdefault(Path(fila["FileName"]).stem, []).append(datos[inicio:inicio + fila["FileSize"]])
    indice = {}
    with tempfile.TemporaryDirectory() as tmp:
        if GOLPES in archivos:
            mapa, streams = leer_acb(archivos.pop(GOLPES)[0])
            carpeta = SALIDA / GOLPES
            carpeta.mkdir(parents=True, exist_ok=True)
            indice[GOLPES] = []
            for cue, ids in sorted(mapa.items()):
                if not CUES_GOLPES.match(cue):
                    continue
                for i in ids:
                    ogg = carpeta / f"{cue}_{i:03d}.ogg"
                    datos_ogg = a_ogg(streams[i], ogg, tmp)
                    if ogg.exists():
                        indice[GOLPES].append({"archivo": f"{GOLPES}/{ogg.name}", "cue": cue} | datos_ogg)
            print(f"{GOLPES}: {len(indice[GOLPES])}")
        for banco, partes in sorted(archivos.items()):
            streams = [s for p in partes for s in streams_hca(p)]
            if not streams:
                continue
            carpeta = SALIDA / banco
            carpeta.mkdir(parents=True, exist_ok=True)
            indice[banco] = []
            for i, s in enumerate(streams):
                ogg = carpeta / f"{i:02d}.ogg"
                datos_ogg = a_ogg(s, ogg, tmp)
                # El ultimo stream de algunos bancos sale vacio.
                if not ogg.exists():
                    continue
                if banco.startswith("SE_Referee"):
                    datos_ogg |= pitazos(ogg)
                indice[banco].append({"archivo": f"{banco}/{ogg.name}"} | datos_ogg)
            print(f"{banco}: {len(indice[banco])}")
    (SALIDA / "sonidos.json").write_text(json.dumps(indice, indent=1))


if __name__ == "__main__":
    main()
