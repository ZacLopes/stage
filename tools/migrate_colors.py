#!/usr/bin/env python3
"""
Migração mecânica de cores hardcoded → tokens do design system.

Uso:
    python3 tools/migrate_colors.py lib/features/gamification

O script:
1. Substitui `Color(0xFFXXXXXX)` e `const Color(0xFFXXXXXX)` por `AppColors.<token>`
   pra cores semânticas conhecidas (ver MAP abaixo).
2. Se houve alguma substituição em um arquivo E ele ainda não importa
   `core/theme/theme.dart`, insere o import logo após o último `import ...;`.
3. NÃO toca em cores não-mapeadas (decisões caso-a-caso ficam pro humano).

Mapeamento — só hexes com semântica clara. Cores específicas (vibe, ícones,
estados raros) ficam pra refatoração manual.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Hex normalizado em uppercase. Os matches são case-insensitive.
MAP: dict[str, str] = {
    # ─── Brand / primary (rouxos e indigos morrem aqui) ──────────────────
    "0xFF6366F1": "AppColors.primary",       # indigo dos botões padrão antigo
    "0xFF4F46E5": "AppColors.primary",       # indigo escuro
    "0xFF4338CA": "AppColors.primary",       # indigo ainda mais escuro
    "0xFF7C3AED": "AppColors.primary",       # violet (gradient settings antigo)
    "0xFF312E81": "AppColors.primary",       # indigo 900
    "0xFF1E40AF": "AppColors.primary",       # blue 800
    "0xFFE0E7FF": "AppColors.primarySoft",   # indigo light
    "0xFFF5F3FF": "AppColors.primarySoft",   # violet light
    "0xFFEEF2FF": "AppColors.primarySoft",   # indigo 50
    "0xFFEFF6FF": "AppColors.primarySoft",   # blue 50
    # ─── Cyan / secondary (logo Stage) ───────────────────────────────────
    "0xFF29B6D2": "AppColors.brandCyan",
    "0xFF1565A8": "AppColors.brandBlue",
    "0xFF1E88B8": "AppColors.brand",
    "0xFF1CB0F6": "AppColors.secondary",     # blue bright (Duolingo) → cyan stage
    "0xFF1899D6": "AppColors.brand",
    "0xFFDDF4FF": "AppColors.brandSoft",
    "0xFFE0F4FA": "AppColors.brandSoft",
    "0xFFE0F7FA": "AppColors.secondarySoft",
    # ─── Success (verde — fim das 3 variantes) ───────────────────────────
    "0xFF00C27A": "AppColors.success",       # Duolingo green primário
    "0xFF58CC02": "AppColors.success",       # Duolingo green brilhante
    "0xFF46A302": "AppColors.success",
    "0xFF10B981": "AppColors.success",       # emerald
    "0xFF16A34A": "AppColors.success",
    "0xFF15803D": "AppColors.success",
    "0xFF22C55E": "AppColors.success",
    "0xFFDCFCE7": "AppColors.successSoft",
    # ─── Warning ─────────────────────────────────────────────────────────
    "0xFFF59E0B": "AppColors.warning",       # também é AppColors.xp
    "0xFFFFB900": "AppColors.warning",
    "0xFFFFC107": "AppColors.warning",
    "0xFFFF9600": "AppColors.warning",
    "0xFFFEF3C7": "AppColors.warningSoft",
    "0xFFFFF7ED": "AppColors.warningSoft",
    # ─── Error ───────────────────────────────────────────────────────────
    "0xFFEF4444": "AppColors.error",
    "0xFFFF4B4B": "AppColors.error",
    "0xFFFEF2F2": "AppColors.errorSoft",
    "0xFFFEE2E2": "AppColors.errorSoft",
    # ─── Info ────────────────────────────────────────────────────────────
    "0xFF0EA5E9": "AppColors.info",
    "0xFF3B82F6": "AppColors.info",
    "0xFF06B6D4": "AppColors.info",
    "0xFFE0F2FE": "AppColors.infoSoft",
    # ─── Gamificação / XP ────────────────────────────────────────────────
    "0xFFFFD700": "AppColors.gold",
    "0xFFC0C0C0": "AppColors.silver",
    "0xFFCD7F32": "AppColors.bronze",
    # ─── Neutros / surface ───────────────────────────────────────────────
    "0xFFF3F4F6": "AppColors.background",
    "0xFFF9FAFB": "AppColors.surfaceVariant",
    "0xFFF0F0F0": "AppColors.surfaceMuted",
    "0xFFF5F9FF": "AppColors.surfaceVariant",
    # ─── Texto ───────────────────────────────────────────────────────────
    "0xFF111827": "AppColors.textPrimary",
    "0xFF1F2937": "AppColors.textPrimary",
    "0xFF0F172A": "AppColors.textPrimary",   # slate 900
    "0xFF334155": "AppColors.textPrimary",   # slate 700
    "0xFF374151": "AppColors.textSecondary",
    "0xFF4B5563": "AppColors.textSecondary",
    "0xFF475569": "AppColors.textSecondary", # slate 600
    "0xFF64748B": "AppColors.textTertiary",  # slate 500
    "0xFF6B7280": "AppColors.textTertiary",
    "0xFF94A3B8": "AppColors.textTertiary",  # slate 400
    "0xFF9CA3AF": "AppColors.textDisabled",
    "0xFFAFAFAF": "AppColors.textDisabled",
    # ─── Bordas ──────────────────────────────────────────────────────────
    "0xFFE5E7EB": "AppColors.border",
    "0xFFE2E8F0": "AppColors.border",        # slate 200
    "0xFFD1D5DB": "AppColors.borderStrong",
    "0xFFF1F5F9": "AppColors.surfaceMuted",  # slate 100
    "0xFFF8FAFC": "AppColors.surfaceVariant",# slate 50
    # ─── Variantes adicionais de semânticas ──────────────────────────────
    "0xFFDC2626": "AppColors.error",         # red 600
    "0xFFB91C1C": "AppColors.error",         # red 700
    "0xFFFECACA": "AppColors.errorSoft",     # red 200
    "0xFFFCD34D": "AppColors.xp",            # amber 300 (xp soft)
    "0xFFFFA500": "AppColors.warning",       # orange
    "0xFFFED7AA": "AppColors.warningSoft",   # orange 200
    "0xFFB45309": "AppColors.warning",       # amber 700
    "0xFF78350F": "AppColors.warning",       # amber 900
    "0xFF065F46": "AppColors.success",       # emerald 800
    "0xFFECFDF5": "AppColors.successSoft",   # emerald 50
    "0xFFF0FDF4": "AppColors.successSoft",   # green 50
    "0xFF86EFAC": "AppColors.success",       # green 300
}

# Pattern: opcional `const ` + `Color(0xFFXXXXXX)` (case-insensitive nos hex)
COLOR_PATTERN = re.compile(r"(\bconst\s+)?Color\(0x([0-9A-Fa-f]{8})\)")

# Onde inserir o import (se não estiver presente).
# Calculado por arquivo: depth = quantos `../` precisamos do arquivo até `lib/`.
def import_line_for(file_path: Path, repo_lib: Path) -> str:
    rel = file_path.relative_to(repo_lib)
    depth = len(rel.parts) - 1  # quantos diretórios entre o arquivo e lib/
    prefix = "../" * depth
    return f"import '{prefix}core/theme/theme.dart';"


def migrate_file(path: Path, repo_lib: Path) -> tuple[int, bool]:
    """Retorna (n_substituições, import_inserido)."""
    text = path.read_text(encoding="utf-8")
    original = text
    count = 0

    def repl(m: re.Match[str]) -> str:
        nonlocal count
        const_kw = m.group(1) or ""
        hex_raw = m.group(2).upper()
        key = "0x" + hex_raw
        if key in MAP:
            count += 1
            # Drop `const ` — tokens são `static const`, não dão pra prefixar
            # `const`. Se o uso original era `const Color(...)`, o resultado
            # `AppColors.xxx` continua const-compatível (compilador resolve).
            return MAP[key]
        return m.group(0)

    text = COLOR_PATTERN.sub(repl, text)

    if count == 0:
        return (0, False)

    # Inserir import se não existir e o arquivo realmente usar AppColors.
    needs_import = "core/theme/theme.dart" not in text
    if needs_import:
        # Inserir após o último `import` ou `library;`.
        lines = text.split("\n")
        last_import_idx = -1
        for i, line in enumerate(lines):
            if line.startswith("import "):
                last_import_idx = i
            elif line.startswith("library "):
                last_import_idx = i
        if last_import_idx >= 0:
            lines.insert(last_import_idx + 1, import_line_for(path, repo_lib))
            text = "\n".join(lines)

    if text != original:
        path.write_text(text, encoding="utf-8")

    return (count, needs_import)


# Diretórios onde NÃO se aplica a migração (são os próprios tokens, ou
# arquivos que definem AppColors / StageColors e gerariam referências
# circulares se rodassem aqui).
EXCLUDE_DIRS = {
    "core/theme",
    "core/constants",
}


def is_excluded(path: Path, repo_lib: Path) -> bool:
    rel = str(path.relative_to(repo_lib))
    return any(rel.startswith(d + "/") or rel == d for d in EXCLUDE_DIRS)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: migrate_colors.py <dir-or-file> [...]")
        return 2

    # Localizar lib/ pra calcular path relativo do import.
    here = Path(__file__).resolve().parent
    repo_lib = (here.parent / "lib").resolve()

    total_files = 0
    total_subs = 0
    total_imports = 0
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
                total_imports += 1 if imp else 0
                print(f"  {f.relative_to(repo_lib)}: {subs} subs"
                      f"{' + import' if imp else ''}")
    print(f"\nDONE: {total_subs} substitutions across {total_files} files "
          f"({total_imports} new imports).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
