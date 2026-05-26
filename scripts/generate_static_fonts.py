#!/usr/bin/env python3
# Gera os 9 arquivos estáticos por peso a partir de uma variable font.
# Use quando precisar substituir Outfit-VariableFont.ttf / Inter-VariableFont.ttf
# por novas versões (ex: upstream do Google Fonts atualizou).
#
# Requer: python3 + fontTools (`pip install fonttools`).
#
# Uso:
#   1. Colocar Outfit-VariableFont.ttf e Inter-VariableFont.ttf em assets/fonts/
#   2. Rodar: python3 scripts/generate_static_fonts.py
#   3. flutter pub get
#
# Por que estáticos em vez de variable font: ver comentário no pubspec.yaml.

import sys
from pathlib import Path

try:
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont
except ImportError:
    print("fontTools não instalado. Rode: pip install fonttools", file=sys.stderr)
    sys.exit(1)

WEIGHTS = {
    100: "Thin",
    200: "ExtraLight",
    300: "Light",
    400: "Regular",
    500: "Medium",
    600: "SemiBold",
    700: "Bold",
    800: "ExtraBold",
    900: "Black",
}

FAMILIES = [
    ("Outfit", "Outfit-VariableFont.ttf"),
    ("Inter", "Inter-VariableFont.ttf"),
]

fonts_dir = Path(__file__).resolve().parent.parent / "assets" / "fonts"

for family, src_name in FAMILIES:
    src = fonts_dir / src_name
    if not src.exists():
        print(f"Faltando: {src}", file=sys.stderr)
        sys.exit(1)
    print(f"Processando {family}...")
    for weight, name in WEIGHTS.items():
        var = TTFont(str(src))
        inst = instantiateVariableFont(var, {"wght": weight})
        out = fonts_dir / f"{family}-{name}.ttf"
        inst.save(str(out))
        print(f"  → {out.name}")

print("OK")
