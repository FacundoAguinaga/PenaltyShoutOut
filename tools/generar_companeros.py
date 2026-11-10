#!/usr/bin/env python3
"""Genera las variantes de los kits para los companeros: otro tono de piel y de pelo.

El personaje tiene un solo atlas, asi que basta con recolorear la piel y el pelo.
Se reconoce la piel por el color (tierra, sin ser la camiseta) y el pelo por estar
oscuro en la zona de la cabeza, sin tocar la cara.

    python3 tools/generar_companeros.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

KITS = Path(__file__).resolve().parent.parent / "Player" / "kits"
# Zonas del atlas, en fracciones de su lado.
CABEZA = (0.46, 0.50, 0.82, 0.70)
CARA = (0.58, 0.51, 0.70, 0.60)
# nombre: (multiplica la piel en RGB, color del pelo)
VARIANTES = {
    "moreno": ((0.42, 0.36, 0.32), (18, 14, 12)),
    "canela": ((0.72, 0.62, 0.52), (52, 30, 16)),
    "rubio": ((1.04, 0.96, 0.90), (196, 150, 74)),
}
# El rojo es el equipo del pateador y el azul el del arquero.
EQUIPOS = ["rojo", "azul"]
MATERIAL = """[gd_resource type="StandardMaterial3D" load_steps=3 format=3]

[ext_resource type="Texture2D" path="res://Player/kits/kit_{equipo}_{nombre}.png" id="1_kit"]
[ext_resource type="Texture2D" path="res://Player/cac-1784590690052_1.png" id="2_normal"]

[resource]
resource_name = "Kit_{equipo}_{nombre}"
albedo_texture = ExtResource("1_kit")
metallic = 0.0
roughness = 0.75
normal_enabled = true
normal_texture = ExtResource("2_normal")
"""


def caja(lado: int, zona: tuple) -> tuple:
    x0, y0, x1, y1 = (int(v * lado) for v in zona)
    m = np.zeros((lado, lado), dtype=bool)
    m[y0:y1, x0:x1] = True
    return m


def main() -> None:
    for equipo in EQUIPOS:
        base = np.asarray(Image.open(KITS / f"kit_{equipo}.png").convert("RGB")).astype(np.float32)
        lado = base.shape[0]
        r, g, b = base[..., 0], base[..., 1], base[..., 2]
        piel = (r > 90) & (r > g) & (g > b) & (g / np.maximum(r, 1) > 0.55) & (r - b > 25)
        pelo = (r < 70) & (g < 70) & (b < 70) & caja(lado, CABEZA) & ~caja(lado, CARA)
        for nombre, (tono, color_pelo) in VARIANTES.items():
            salida = base.copy()
            salida[piel] = np.clip(base[piel] * np.array(tono), 0, 255)
            # Conserva las sombras del pelo: lo mas oscuro del atlas sigue siendo mas oscuro.
            brillo = (base[pelo].mean(axis=1, keepdims=True) / 40.0).clip(0.5, 1.3)
            salida[pelo] = np.clip(np.array(color_pelo) * brillo, 0, 255)
            Image.fromarray(salida.astype(np.uint8)).save(KITS / f"kit_{equipo}_{nombre}.png")
            (KITS / f"material_{equipo}_{nombre}.tres").write_text(MATERIAL.format(equipo=equipo, nombre=nombre))
            print(equipo, nombre, "listo")


if __name__ == "__main__":
    main()
