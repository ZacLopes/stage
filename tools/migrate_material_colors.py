#!/usr/bin/env python3
"""
Migra `Colors.X` (Material globals) → tokens do design system Stage.

Cobre só os casos de **alta confiança** — cinzas/vermelhos que claramente são
semânticos (border, text, error). Cores expressivas (`Colors.purple`,
`Colors.pink`, `Colors.orange` etc.) ficam pra refator manual caso-a-caso.

Regras:
- Não toca em `Colors.white`, `Colors.black`, `Colors.transparent` (legítimos).
- Não toca em `Colors.X.withOpacity/.withValues(...)` — preserva alpha custom.
- Preserva contexto (só substitui exato, sem prefixo/sufixo de identifier).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Substituições EXATAS. A ordem importa: padrões mais específicos primeiro
# (ex: Colors.grey[100] antes de Colors.grey).
REPLACEMENTS = [
    # ─── Cinzas indexados ────────────────────────────────────────────────
    (r"\bColors\.grey\[100\]", "AppColors.divider"),
    (r"\bColors\.grey\[200\]", "AppColors.border"),
    (r"\bColors\.grey\[300\]", "AppColors.borderStrong"),
    (r"\bColors\.grey\[400\]", "AppColors.textDisabled"),
    (r"\bColors\.grey\[500\]", "AppColors.textTertiary"),
    (r"\bColors\.grey\[600\]", "AppColors.textTertiary"),
    (r"\bColors\.grey\[700\]", "AppColors.textSecondary"),
    (r"\bColors\.grey\[800\]", "AppColors.textPrimary"),
    (r"\bColors\.grey\.shade100\b", "AppColors.divider"),
    (r"\bColors\.grey\.shade200\b", "AppColors.border"),
    (r"\bColors\.grey\.shade300\b", "AppColors.borderStrong"),
    (r"\bColors\.grey\.shade400\b", "AppColors.textDisabled"),
    (r"\bColors\.grey\.shade500\b", "AppColors.textTertiary"),
    (r"\bColors\.grey\.shade600\b", "AppColors.textTertiary"),
    (r"\bColors\.grey\.shade700\b", "AppColors.textSecondary"),
    # ─── Vermelhos (semânticos = error) ─────────────────────────────────
    (r"\bColors\.red\.shade50\b", "AppColors.errorSoft"),
    (r"\bColors\.red\.shade100\b", "AppColors.errorSoft"),
    (r"\bColors\.red\.shade400\b", "AppColors.error"),
    (r"\bColors\.red\.shade500\b", "AppColors.error"),
    (r"\bColors\.red\.shade600\b", "AppColors.error"),
    (r"\bColors\.red\.shade700\b", "AppColors.error"),
    # ─── Âmbar (warning) ─────────────────────────────────────────────────
    (r"\bColors\.amber\.shade50\b", "AppColors.warningSoft"),
    (r"\bColors\.amber\.shade100\b", "AppColors.warningSoft"),
    (r"\bColors\.amber\.shade600\b", "AppColors.warning"),
    (r"\bColors\.amber\.shade700\b", "AppColors.warning"),
    (r"\bColors\.amber\.shade900\b", "AppColors.warning"),
    # ─── Padrões "Colors.X" SEM modifier — só substituir se isolado ─────
    # Usa negative lookahead pra NÃO casar quando vem `.shade`/`[`/`.with`.
    (r"\bColors\.grey\b(?!\.shade|\[|\.with)", "AppColors.textTertiary"),
    (r"\bColors\.red\b(?!\.shade|\[|\.with)", "AppColors.error"),
]


EXCLUDE_DIRS = {"core/theme", "core/constants"}


def is_excluded(path: Path, repo_lib: Path) -> bool:
    rel = str(path.relative_to(repo_lib))
    return any(rel.startswith(d + "/") or rel == d for d in EXCLUDE_DIRS)


def import_line_for(file_path: Path, repo_lib: Path) -> str:
    rel = file_path.relative_to(repo_lib)
    depth = len(rel.parts) - 1
    prefix = "../" * depth
    return f"import '{prefix}core/theme/theme.dart';"


def migrate_file(path: Path, repo_lib: Path) -> tuple[int, bool]:
    text = path.read_text(encoding="utf-8")
    original = text
    count = 0
    for pattern, replacement in REPLACEMENTS:
        new_text, n = re.subn(pattern, replacement, text)
        text = new_text
        count += n

    if count == 0:
        return (0, False)

    has_theme_import = "core/theme/theme.dart" in text
    inserted = False
    if not has_theme_import:
        lines = text.split("\n")
        last_import_idx = -1
        for i, line in enumerate(lines):
            if line.startswith("import "):
                last_import_idx = i
        if last_import_idx >= 0:
            lines.insert(last_import_idx + 1, import_line_for(path, repo_lib))
            text = "\n".join(lines)
            inserted = True

    if text != original:
        path.write_text(text, encoding="utf-8")

    return (count, inserted)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: migrate_material_colors.py <dir-or-file> [...]")
        return 2

    here = Path(__file__).resolve().parent
    repo_lib = (here.parent / "lib").resolve()

    total_files = 0
    total_subs = 0
    for arg in sys.argv[1:]:
        target = Path(arg).resolve()
        files = (
            [target] if target.is_file() else sorted(target.rglob("*.dart"))
        )
        for f in files:
            if not f.is_file() or f.suffix != ".dart":
                continue
            if is_excluded(f, repo_lib):
                continue
            subs, imp = migrate_file(f, repo_lib)
            if subs > 0:
                total_files += 1
                total_subs += subs
                print(f"  {f.relative_to(repo_lib)}: {subs} subs"
                      f"{' + import' if imp else ''}")
    print(f"\nDONE: {total_subs} substituições em {total_files} arquivos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
