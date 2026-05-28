#!/usr/bin/env python3
"""
Migra usos de `StageColors.X` (alias de compat) → `AppColors.X` ou
`AppGradients.X` direto, e troca o import.

Roda depois do migrate_colors.py — quando todos os hex codes já viraram
tokens, sobra só StageColors em arquivos que importavam o alias antigo.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

MAP: dict[str, str] = {
    "StageColors.brandCyan": "AppColors.brandCyan",
    "StageColors.brandBlue": "AppColors.brandBlue",
    "StageColors.ctaGreen": "AppColors.primary",
    "StageColors.brandCyanAccent": "AppColors.secondarySoft",
    "StageColors.starGold": "AppColors.gold",
    "StageColors.offWhite": "AppColors.surfaceVariant",
    "StageColors.scaffoldGray": "AppColors.background",
    "StageColors.darkText": "AppColors.textPrimary",
    "StageColors.titleText": "AppColors.textPrimary",
    "StageColors.subtitleGray": "AppColors.textTertiary",
    "StageColors.bodyGray": "AppColors.textSecondary",
    "StageColors.hintGray": "AppColors.textDisabled",
    "StageColors.chipUnselectedBg": "AppColors.surfaceMuted",
    "StageColors.chipUnselectedText": "AppColors.textSecondary",
    "StageColors.chipBorder": "AppColors.borderStrong",
    "StageColors.error": "AppColors.error",
    "StageColors.brandGradient": "AppGradients.brand",
    "StageColors.lightGradient": "AppGradients.surfaceSoft",
}

IMPORT_PATTERN = re.compile(
    r'^import\s+["\'](?:[\.\/]*)core/constants/stage_colors\.dart["\']\s*;'
    r'\s*$',
    re.MULTILINE,
)


def import_line_for(file_path: Path, repo_lib: Path) -> str:
    rel = file_path.relative_to(repo_lib)
    depth = len(rel.parts) - 1
    prefix = "../" * depth
    return f"import '{prefix}core/theme/theme.dart';"


def migrate_file(path: Path, repo_lib: Path) -> int:
    text = path.read_text(encoding="utf-8")
    original = text

    count = 0
    for old, new in MAP.items():
        new_text, n = re.subn(re.escape(old), new, text)
        if n:
            text = new_text
            count += n

    if count == 0:
        return 0

    # Trocar/inserir import.
    has_theme_import = "core/theme/theme.dart" in text
    has_stage_import = bool(IMPORT_PATTERN.search(text))

    if has_stage_import:
        if has_theme_import:
            # Remove a linha de import do stage_colors (theme já tem tudo).
            text = IMPORT_PATTERN.sub("", text)
            # Limpa eventual linha em branco dupla deixada pela remoção.
            text = re.sub(r"\n\n\n+", "\n\n", text)
        else:
            # Substitui in-place.
            replacement = import_line_for(path, repo_lib)
            text = IMPORT_PATTERN.sub(replacement, text)
    elif not has_theme_import:
        # Não tinha nem stage nem theme — inserir theme após último import.
        lines = text.split("\n")
        last_import_idx = -1
        for i, line in enumerate(lines):
            if line.startswith("import "):
                last_import_idx = i
        if last_import_idx >= 0:
            lines.insert(last_import_idx + 1, import_line_for(path, repo_lib))
            text = "\n".join(lines)

    if text != original:
        path.write_text(text, encoding="utf-8")

    return count


def main() -> int:
    here = Path(__file__).resolve().parent
    repo_lib = (here.parent / "lib").resolve()

    files = sorted(repo_lib.rglob("*.dart"))
    total_files = 0
    total_subs = 0
    for f in files:
        rel = str(f.relative_to(repo_lib))
        # Pula o próprio alias.
        if rel == "core/constants/stage_colors.dart":
            continue
        subs = migrate_file(f, repo_lib)
        if subs > 0:
            total_files += 1
            total_subs += subs
            print(f"  {rel}: {subs} subs")
    print(f"\nDONE: {total_subs} substitutions across {total_files} files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
