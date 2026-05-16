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
import 'features/resume/resume_viewmodel.dart';
import 'features/jobs/jobs_viewmodel.dart';
import 'features/jobs/data/job_repository.dart';
import 'features/jobs/data/swipe_repository.dart';
import 'features/jobs/data/preferences_repository.dart';
import 'features/tutorial/tutorial_controller.dart';
import 'features/tutorial/tutorial_overlay.dart';
import 'services/ai_service.dart';
import 'services/analytics_service.dart';
import 'services/notifications_service.dart';
import 'features/splash/splash_screen.dart';
import 'features/version/version_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // OneSignal: init sem solicitar permissão. O prompt nativo é chamado
  // depois (na primeira vaga salva — momento de maior intenção). Login do
  // user é feito no UserViewModel quando o auth listener dispara signedIn.
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
          child: Stack(
            children: [
              if (child != null) child,
              const Positioned.fill(child: TutorialOverlay()),
            ],
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
