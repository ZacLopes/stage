# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run on device/emulator
flutter run

# Run on specific platform
flutter run -d chrome
flutter run -d ios

# Build
flutter build apk
flutter build ios

# Analyze (lint)
flutter analyze

# Run tests
flutter test
flutter test test/widget_test.dart  # single test file
```

Requires a `.env` file at project root with `SUPABASE_URL` and `SUPABASE_ANON_KEY` (see `.env.example`).

## Architecture

**Pattern:** MVVM + Repository. Feature-first folder structure under `lib/features/`.

**State management:** Provider + ChangeNotifier. Six ViewModels are injected via `MultiProvider` in `main.dart` and instantiated with their dependencies there:

| ViewModel | Responsibility |
|---|---|
| `UserViewModel` | Auth state, user profile, Supabase auth listener |
| `GamificationViewModel` | Tracks, phases, XP, question flow, interview reports |
| `HomeViewModel` | Track list with completion status; exposes `requestTabChange()` for deep navigation |
| `ProfileViewModel` | Resume library (Supabase Storage CRUD) |
| `ResumeViewModel` | Resume builder form state, PDF/DOCX/HTML export |
| `JobsViewModel` | Job swipe feed, undo stack, user preferences |

**Data layer:** `SupabaseRepository` is the single source of truth for remote data. It maintains a 3-level in-memory cache (`_cachedTracks`, `_cachedPhases`, `_cachedQuestions`) and prefetches all gamification data at startup. `LocalStorageRepository` wraps SharedPreferences for lightweight local state. `DatabaseHelper` manages SQLite for offline/session data.

**Backend:** Supabase (PostgreSQL + Auth + Storage). AI features (interview reports, resume suggestions) call OpenAI GPT-4o through Supabase Edge Functions — the OpenAI key is server-side only. The three Edge Functions are `generate-profile`, `generate-resume`, and `generate-interview-report`.

## Navigation

There is no routing package. Navigation is done with direct `Navigator.push/pushReplacement` calls.

Entry flow: `SplashScreen` → `AuthGate` (Consumer on `UserViewModel.isLoggedIn`) → `HomeScreen` (3 tabs) or `OnboardingScreen`.

To navigate to a specific tab from deep in the navigation stack (e.g., after completing a track), use `HomeViewModel.requestTabChange(index)` and listen in `HomeScreen` — this avoids popping back through intermediate routes.

## Key Design Decisions

- **Phase filtering:** Obsolete phases (`t1_p4`, "Revisão", "O Cronômetro da Jornada", "O que você fez") were cleaned from the database via `20260430_cleanup_obsolete_phases_questions.sql`. No runtime filters needed.
- **Resume export:** Only PDF is implemented (rendered locally via `Printing.convertHtml` in `PdfService.generateResumeBytes`). DOCX and Web export were planned but never built — don't reference them in UI or docs.
- **XP formula:** `50 + (number_of_questions × 10)` per phase. 15 XP levels total (0–2501+ XP).
- **Secret world:** Track 5 unlocks at Level 10 and triggers a special completion popup (dark premium background + gold confetti).
- **Phase completion widget** (`gamification/widgets/phase_completion_widget.dart`) has 3 modes: phase done, track done, and resume ready (track 5).
- **`pdf_service.dart`** (~57KB, single file) hosts the 4 resume templates (`harvard_ats`, `jakes_resume`, `forte_foundation`, `one_page_compact`), each as a separate `_buildXxxHtml(...)` function. HTML → PDF via `Printing.convertHtml`. Edit with care.
- **Template thumbnails**: `ResumeTemplateSelector` shows a static PNG preview per template from `assets/images/templates/`. After changing any template HTML, regenerate the PNGs via Settings → "[DEV] Gerar thumbnails dos templates" (only visible in debug mode). See `lib/features/resume/widgets/template_thumbnail_generator_screen.dart` for the tool.

## Theme & Localization

- **Design system**: all tokens live in `lib/core/theme/`. Import via `import 'core/theme/theme.dart';` (barrel). Components in `lib/core/widgets/` (barrel: `widgets.dart`). **Never hardcode `Color(0xFF...)`, `EdgeInsets.all(N)`, or `TextStyle(...)` in feature code** — use `AppColors.*`, `AppSpacing.*`, `AppRadius.*`, `AppTextStyles.*`, `AppShadows.*`, `AppGradients.*`.
- **Identity**: brand primary is **azul Stage** (`AppColors.primary` = `#1565A8`, gradient cyan→blue from the logo). Verde (`AppColors.success` = `#16A34A`) is **only** for success states — phase completion, "salvo", "aplicada". Indigo (`#6366F1`/`#4F46E5`) was removed across the app in 2026-05-27 design system unification.
- **`AppTheme.light`** (`lib/core/theme/app_theme.dart`) is the single ThemeData — passed to `MaterialApp.theme`. Don't redefine `ThemeData` inline.
- **Base components**: `PrimaryButton`, `SecondaryButton`, `GhostButton`, `AppCard` (flat/elevated/gradient), `SectionCard`, `AppChip`, `SemanticBadge`, `AppTextField`, `AppSnackBar` (success/error/warning/info), `EmptyState`. Prefer these to ad-hoc `Container + BoxDecoration`.
- **Mass migration script**: `tools/migrate_colors.py` maps hex codes → tokens deterministically (used for the 2026-05-27 migration). Don't run on `core/theme/` or `core/constants/` (excluded).
- Fonts: Outfit (headings) + Inter (body) — bundled as native fonts. Wrap with `AppTextStyles.*` instead of inline `TextStyle(...)`.
- App is Portuguese (Brazil) only (`pt_BR`). No i18n infrastructure — strings are hardcoded in Dart files.
