import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/splash/splash_screen.dart';

/// Cobre a decisão de roteamento pós-login (resolvePostLoginRoute), em especial
/// o BUGFIX dos perfis ocos: o fallback NUNCA pode mais cair na CompletionScreen
/// legacy (data-less) — vai pro onboarding que coleta — a não ser que o
/// kill-switch `legacy_completion_screen_enabled` esteja ligado.
void main() {
  group('resolvePostLoginRoute', () {
    test('onboarding concluído tem prioridade → Home', () {
      expect(
        resolvePostLoginRoute(
          hasCompletedOnboarding: true,
          isInProfileFirstFlow: true,
          needsProfileSetup: true,
          legacyCompletionEnabled: true,
        ),
        PostLoginRoute.home,
      );
    });

    test('mid-flow profile-first → onboarding (TwoDoors)', () {
      expect(
        resolvePostLoginRoute(
          hasCompletedOnboarding: false,
          isInProfileFirstFlow: true,
          needsProfileSetup: false,
          legacyCompletionEnabled: false,
        ),
        PostLoginRoute.onboarding,
      );
    });

    test('precisa de setup → onboarding (TwoDoors)', () {
      expect(
        resolvePostLoginRoute(
          hasCompletedOnboarding: false,
          isInProfileFirstFlow: false,
          needsProfileSetup: true,
          legacyCompletionEnabled: false,
        ),
        PostLoginRoute.onboarding,
      );
    });

    test(
        'REGRESSÃO perfis ocos: fallback (legacy completo, profile_personal vazio) '
        '→ onboarding, NÃO CompletionScreen', () {
      // Exatamente o estado dos ~473 perfis ocos: needsProfileSetup=false
      // (user_profiles legacy completo) + isInProfileFirstFlow=false
      // (profile_personal vazio) + onboarding não concluído.
      expect(
        resolvePostLoginRoute(
          hasCompletedOnboarding: false,
          isInProfileFirstFlow: false,
          needsProfileSetup: false,
          legacyCompletionEnabled: false,
        ),
        PostLoginRoute.onboarding,
      );
    });

    test('kill-switch LIGADO restaura CompletionScreen no fallback', () {
      expect(
        resolvePostLoginRoute(
          hasCompletedOnboarding: false,
          isInProfileFirstFlow: false,
          needsProfileSetup: false,
          legacyCompletionEnabled: true,
        ),
        PostLoginRoute.legacyCompletion,
      );
    });

    test('kill-switch só afeta o fallback, não as rotas de maior prioridade', () {
      // Mesmo com legacy ligado, quem precisa de setup vai pro onboarding.
      expect(
        resolvePostLoginRoute(
          hasCompletedOnboarding: false,
          isInProfileFirstFlow: false,
          needsProfileSetup: true,
          legacyCompletionEnabled: true,
        ),
        PostLoginRoute.onboarding,
      );
    });
  });
}
