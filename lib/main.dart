import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
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

    // Desliga fetch de fontes em runtime. As famílias Outfit e Inter usadas
    // via `GoogleFonts.outfit()` / `GoogleFonts.inter()` agora resolvem a
    // partir das variable fonts declaradas em pubspec.yaml (assets/fonts/).
    // Sem isso, usuários offline ou com DNS bloqueado disparavam
    // `Failed host lookup: 'fonts.gstatic.com'` (10+ $exceptions em 19-20/mai).
    GoogleFonts.config.allowRuntimeFetching = false;

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
        ChangeNotifierProvider<UserViewModel>(
          create: (_) => UserViewModel(repository, localStorageRepository),
        ),
        ChangeNotifierProvider<GamificationViewModel>(
          create: (_) => GamificationViewModel(repository),
        ),
        ChangeNotifierProvider<ProfileViewModel>(
          create: (_) => ProfileViewModel(repository, aiService, localStorageRepository),
        ),
        // Profile-first editor (estrutura relacional Semana 1)
        ChangeNotifierProvider<ProfileEditorViewModel>(
          create: (_) => ProfileEditorViewModel(profileRepository),
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C27A),
          primary: const Color(0xFF00C27A),
          secondary: const Color(0xFF10B981), // Emerald 500 (similar, maybe keep or adjust?)
          tertiary: const Color(0xFFF59E0B), // Amber 500
          background: const Color(0xFFF3F4F6),
          surface: Colors.white,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        // Transições de tela iOS-style em ambas as plataformas — slide horizontal
        // com curva nativa. Material padrão tem fade-up que parecia "pesado".
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          },
        ),
        // Ripple mais clean (sparkle do Material 3) em toques de InkWell.
        splashFactory: InkSparkle.splashFactory,
        textTheme: GoogleFonts.outfitTextTheme(
          Theme.of(context).textTheme,
        ).copyWith(
          headlineLarge: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1F2937),
          ),
          headlineMedium: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1F2937),
          ),
          titleLarge: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1F2937),
          ),
          bodyLarge: GoogleFonts.inter(
            color: const Color(0xFF374151),
          ),
          bodyMedium: GoogleFonts.inter(
            color: const Color(0xFF4B5563),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
          ),
          iconTheme: IconThemeData(color: Color(0xFF6366F1)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.black.withOpacity(0.05)),
          ),
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1F2937),
          contentTextStyle: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 14, 
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        ),
      ),
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
          // `HitTestBehavior.translucent` permite que widgets abaixo (botões,
          // listas, gestos) continuem recebendo os toques normalmente — só
          // o teclado é fechado.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
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
