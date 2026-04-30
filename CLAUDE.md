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
- **Resume export is level-gated:** PDF always available; DOCX unlocks at Level 5; Web export unlocks at Level 15.
- **XP formula:** `50 + (number_of_questions × 10)` per phase. 15 XP levels total (0–2501+ XP).
- **Secret world:** Track 5 unlocks at Level 10 and triggers a special completion popup (dark premium background + gold confetti).
- **Phase completion widget** (`gamification/widgets/phase_completion_widget.dart`) has 3 modes: phase done, track done, and resume ready (track 5).
- **`resume_templates.dart` and `pdf_service.dart`** are large generated files (~60KB and ~57KB). Edit with care — each template is a separate function.

## Theme & Localization

- Primary color: `#00C27A` (emerald green). Accent/XP: `#F59E0B` (amber). Constants in `core/constants/stage_colors.dart`.
- Fonts: Outfit (headings) + Inter (body) via `google_fonts`.
- App is Portuguese (Brazil) only (`pt_BR`). No i18n infrastructure — strings are hardcoded in Dart files.
