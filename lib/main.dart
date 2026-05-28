import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'core/theme/theme.dart';
import 'data/supabase_repository.dart';
import 'data/local_storage_repository.dart';
import 'data/seed_data.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/user_viewmodel.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/home_viewmodel.dart';
import 'features/gamification/gamification_viewmodel.dart';
import 'features/profile/profile_viewmodel.dart';
import 'features/profile/data/repositories/profile_repository_supabase.dart';
import 'features/profile/domain/repositories/profile_repository.dart';
import 'features/profile/application/profile_editor_view_model.dart';
import 'features/profile/application/preferences_view_model.dart';
import 'features/profile/application/extraction_status_view_model.dart';
import 'features/resume/resume_viewmodel.dart';
import 'features/jobs/jobs_viewmodel.dart';
import 'features/jobs/data/job_repository.dart';
import 'features/jobs/data/swipe_repository.dart';
import 'features/jobs/data/preferences_repository.dart';
import 'features/jobs/pending_adapted_cv_tracker.dart';
import 'features/profile/profile_tab_prefs.dart';
import 'features/tutorial/tutorial_controller.dart';
import 'features/tutorial/tutorial_overlay.dart';
import 'services/ai_service.dart';
import 'services/analytics_service.dart';
import 'services/facebook_events_service.dart';
import 'services/feature_flags_service.dart';
import 'services/notifications_service.dart';
import 'features/splash/splash_screen.dart';
import 'features/version/version_gate.dart';

void main() {
  // Captura global de exceptions. Três caminhos cobertos:
  //  - FlutterError.onError      → erros do framework Flutter (build, layout, paint)
  //  - PlatformDispatcher.onError → erros assíncronos não capturados na engine
  //  - runZonedGuarded            → erros Dart fora do framework (futures, isolates)
  // Todos rotam pro PostHog via Analytics.shared.captureException, que emite
  // `$exception` e alimenta o produto Error Tracking. Sem isso, app fica cego
  // pra crashes (estado pré-fix: 0 exceptions em 7 dias com 1.146 rage clicks).
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Analytics.shared.captureException(
        details.exception,
        stackTrace: details.stack,
        handled: false,
        extra: {
          if (details.library != null) 'flutter_library': details.library!,
          if (details.context != null)
            'flutter_context': details.context!.toDescription(),
        },
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      Analytics.shared.captureException(error, stackTrace: stack, handled: false);
      return true; // marca como tratado pra não derrubar o app
    };

    await _bootstrap();
  }, (Object error, StackTrace stack) {
    Analytics.shared.captureException(error, stackTrace: stack, handled: false);
  });
}

Future<void> _bootstrap() async {
  // Trava o app em retrato — não suporta paisagem (UX foi desenhada vertical).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Initialize PostHog manualmente (AUTO_INIT=false no Info.plist) — só assim
  // o session replay funciona no Flutter. Eventos, identify e replay passam
  // todos por esse init. Sem POSTHOG_API_KEY no .env, o init é skipado e tudo
  // vira no-op silencioso (não quebra o app).
  final posthogKey = dotenv.env['POSTHOG_API_KEY'];
  if (posthogKey != null && posthogKey.isNotEmpty) {
    try {
      final config = PostHogConfig(posthogKey)
        ..host = dotenv.env['POSTHOG_HOST'] ?? 'https://us.i.posthog.com'
        ..captureApplicationLifecycleEvents = true
        ..debug = false
        ..sessionReplay = true;
      // Mask global OFF — mascara só widgets explícitos via PostHogMaskWidget
      // (CV, perfil, salário). Sem isso, replay vira tela preta inútil.
      config.sessionReplayConfig
        ..maskAllTexts = false
        ..maskAllImages = false;
      await Posthog().setup(config);
    } catch (_) {}
  }

  try {
    await Analytics.shared.init();
    // Dispara o evento "app aberto" no boot — base pra DAU/MAU.
    await Analytics.shared.appOpened();
  } catch (_) {}

  // Feature flags (Semana 3): pré-carrega tabela `app_feature_flags` pra
  // que decisões sincrônicas tipo `isEnabledForUser` no render do PDF não
  // precisem aguardar fetch. Falha silenciosa — sem cache, tudo cai pro v1.
  try {
    await FeatureFlagsService.instance.refresh();
  } catch (_) {}

  // Hidrata o tracker de "CV adaptado pendente de export" do SharedPreferences
  // antes da árvore widget montar, pra que o banner do Home apareça já no
  // primeiro frame se houver pending (sem flash vazio → cheio).
  try {
    await PendingAdaptedCvTracker.shared.hydrate();
  } catch (_) {}

  // Hidrata a última sub-aba do Perfil (Currículos vs Informações) antes da
  // árvore montar, pra que o TabController já tenha o initialIndex correto e
  // não ocorra flash visual aba 0 → aba salva no cold start.
  try {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    await ProfileTabPrefs.shared.hydrate(uid);
  } catch (_) {}

  // Facebook App Events: init sem pedir ATT ainda. ATT é solicitado depois
  // (HomeScreen, ~1s após home aparecer) — Apple recomenda ATT ANTES de
  // qualquer outro prompt de permissão pra atribuição de campanha ficar
  // correta. Eventos Install/Activate sobem automaticamente.
  try {
    await FacebookEventsService.shared.init();
  } catch (_) {}

  // OneSignal: init sem solicitar permissão. O prompt nativo é chamado
  // depois (HomeScreen, ~4s após home — DEPOIS do ATT pra não sobrepor
  // 2 prompts iOS na mesma tela). Login do user é feito no UserViewModel
  // quando o auth listener dispara signedIn.
  try {
    await NotificationsService.shared.init();
  } catch (_) {}

  // Initialize Repository
  final repository = SupabaseRepository();
  
  // Initialize AI Service
  final aiService = AIService();

  // Seed Data (only run once or when you need to update content)
  // Comment this out after first run to avoid re-uploading

    // Seed functionality disabled for production/manual management
    // Uncomment this ONLY if you need to reset the database structure
    /* 
    await repository.seedData(
      SeedData.getTracks(),
      SeedData.getPhases(),
      SeedData.getQuestions(),
    );
    */

    print('Startup checks complete.');

  final localStorageRepository = LocalStorageRepository();
  // Profile-first (Semana 2): repository compartilhado entre os 3 ViewModels novos.
  final ProfileRepository profileRepository = ProfileRepositorySupabase();

  runApp(
    MultiProvider(
      providers: [
        // ProfileEditorViewModel vem ANTES do UserViewModel — este declara
        // dependência via ChangeNotifierProxyProvider pra resolver
        // `needsProfileSetup` consultando `profile_personal` (source of
        // truth do novo onboarding) antes da verificação legacy. Sem
        // essa injeção, `needsProfileSetup` sempre retornava true pra
        // users do novo onboarding (Gap #3 da auditoria).
        ChangeNotifierProvider<ProfileEditorViewModel>(
          create: (_) => ProfileEditorViewModel(profileRepository),
        ),
        ChangeNotifierProxyProvider<ProfileEditorViewModel, UserViewModel>(
          create: (_) => UserViewModel(repository, localStorageRepository),
          // `update` roda sempre que o ProfileEditorViewModel notifica
          // (load, save, clear). `attachProfileEditor` é idempotente —
          // só substitui a referência interna sem disparar side-effects.
          update: (_, profileEditor, userVm) {
            userVm!.attachProfileEditor(profileEditor);
            return userVm;
          },
        ),
        ChangeNotifierProvider<GamificationViewModel>(
          create: (_) => GamificationViewModel(repository),
        ),
        ChangeNotifierProvider<ProfileViewModel>(
          create: (_) => ProfileViewModel(repository, aiService, localStorageRepository),
        ),
        ChangeNotifierProvider<PreferencesViewModel>(
          create: (_) => PreferencesViewModel(profileRepository),
        ),
        ChangeNotifierProvider<ExtractionStatusViewModel>(
          create: (_) => ExtractionStatusViewModel(),
        ),
        ChangeNotifierProvider<HomeViewModel>(
          create: (_) => HomeViewModel(repository),
        ),
        ChangeNotifierProvider<ResumeViewModel>(
          create: (_) => ResumeViewModel(repository, aiService, localStorageRepository),
        ),
        ChangeNotifierProvider<JobsViewModel>(
          create: (_) => JobsViewModel(
            JobRepository(),
            SwipeRepository(),
            PreferencesRepository(),
            aiService,
          ),
        ),
        ChangeNotifierProvider<TutorialController>(
          create: (_) => TutorialController(),
        ),
        // PendingAdaptedCvTracker é singleton — provê via .value pra que
        // widgets que assinam (banner do Home) reflitam markAdapted/clear
        // em tempo real, em vez de só atualizar no próximo cold start.
        ChangeNotifierProvider<PendingAdaptedCvTracker>.value(
          value: PendingAdaptedCvTracker.shared,
        ),
      ],
      child: const CareerGamificationApp(),
    ),
  );
}

class CareerGamificationApp extends StatelessWidget {
  const CareerGamificationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stage',
      debugShowCheckedModeBanner: false,
      // ThemeData unificado — single source of truth em core/theme/.
      // Antes esse bloco tinha 100 linhas inline misturando 4 cores
      // "primárias" diferentes (verde Duolingo, indigo, azul Stage, cyan).
      // Agora tudo flui do AppColors / AppTheme.
      theme: AppTheme.light,
      home: const VersionGate(child: SplashScreen()),
      // PosthogObserver: registra screen views automaticamente em cada
      // Navigator.push/pop — sem ele, o session replay vê telas mas não
      // sabe nomear a rota.
      navigatorObservers: [PosthogObserver()],
      // PostHogWidget habilita session replay (captura de tela). Sem esse
      // wrapper, a flag sessionReplay no init sozinha não grava nada em
      // Flutter. Tutorial overlay continua por cima de tudo.
      builder: (context, child) {
        return PostHogWidget(
          // Toque em qualquer lugar fora de um campo dispensa o teclado.
          //
          // Usa `Listener` em vez de `GestureDetector` porque o detector
          // participa do gesture arena e pode perder pra outros widgets
          // (CardSwiper, InkWell, etc) — resultado: tap não chega e
          // teclado fica órfão na tela. `Listener` recebe `PointerDownEvent`
          // sempre, sem competir.
          //
          // Além do `unfocus()`, força o fechamento via canal nativo
          // (`TextInput.hide`). Sem isso, quando o user sai de uma rota
          // com TextField focado (onboarding → home), o FocusNode é
          // disposed mas o teclado nativo continua aberto — `primaryFocus`
          // vira null e `unfocus()` não tem efeito. O canal direto fecha
          // o teclado independente do estado do foco no Flutter.
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              // Só dispensa se nenhum campo de texto está com foco
              // legítimo. Sem essa guard, tap dentro de um TextField
              // ativo fechava o teclado imediatamente (UX ruim ao editar).
              final focus = FocusManager.instance.primaryFocus;
              final hasEditableFocus = focus?.context?.widget is EditableText;
              if (!hasEditableFocus) {
                focus?.unfocus();
                SystemChannels.textInput.invokeMethod('TextInput.hide');
              }
            },
            child: Stack(
              children: [
                if (child != null) child,
                const Positioned.fill(child: TutorialOverlay()),
              ],
            ),
          ),
        );
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
    );
  }
}
