import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';
import '../../data/local_storage_repository.dart';
import '../../data/database_helper.dart';
import '../../services/analytics_service.dart';
import '../../services/facebook_events_service.dart';
import '../../services/notifications_service.dart';
import '../../services/profile_events.dart';
import '../../services/profile_snapshot_service.dart';
import '../profile/application/profile_editor_view_model.dart';
import 'phone_auth_helpers.dart';

class UserViewModel extends ChangeNotifier {
  final SupabaseRepository _repository;
  final LocalStorageRepository _localStorage;
  final SupabaseClient _supabase = Supabase.instance.client;

  UserProfile? _user;
  bool _isLoading = true;
  Campaign? _currentCampaign;
  StreamSubscription<void>? _profileEventsSub;

  /// Referência opcional ao ProfileEditorViewModel pra que `needsProfileSetup`
  /// consulte o source-of-truth atual (`profile_personal`) antes de cair na
  /// verificação legacy de `user_profiles`. Injetado tardiamente pelo
  /// main.dart via [attachProfileEditor] — antes da injeção, a função se
  /// comporta exatamente como antes (só verifica `user_profiles`). Sem
  /// inicialização nula: nullable proposital.
  ProfileEditorViewModel? _profileEditor;

  UserViewModel(this._repository, this._localStorage) {
    _init();
    // Ouve mudanças no perfil estruturado (ProfileEditorViewModel emite
    // após cada save). Re-fetch `_hasProfileData` pra que `hasResume`
    // sync reflita imediatamente quando o user adiciona uma skill.
    _profileEventsSub = ProfileEvents.instance.changes.listen((_) {
      refreshHasResume();
    });
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _profileEventsSub?.cancel();
    super.dispose();
  }

  UserProfile? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null && _supabase.auth.currentUser != null;
  bool get isEmailVerified => _supabase.auth.currentUser?.emailConfirmedAt != null;

  /// True quando a conta tem auth por email+senha (vs. OAuth puro). Usado
  /// pra decidir se "Trocar senha" faz sentido — Apple/Google users não
  /// têm `encrypted_password` em auth.users e tentar `signInWithPassword`
  /// falha sem motivo claro pro user.
  ///
  /// Lógica: identities é a lista de providers vinculados à conta.
  /// Provider = 'email' significa que a conta foi criada com senha (ou
  /// teve senha vinculada depois). Se a única identity for 'apple'/'google',
  /// retorna false. Phone signup também conta como 'email' aqui (porque o
  /// signup interno usa email synthetic + senha), mas filtramos por
  /// synthetic email em outro nível.
  bool get hasPasswordAuth {
    final identities = _supabase.auth.currentUser?.identities;
    if (identities == null || identities.isEmpty) return false;
    return identities.any((id) => id.provider == 'email');
  }

  /// True quando o user é legado de email+senha e AINDA não vinculou OAuth.
  /// Sinaliza pra UI mostrar o banner "Conecte sua conta a Google/Apple"
  /// — eles precisam migrar antes que a sessão atual expire, senão ficam
  /// presos (já que removemos a tela de login email).
  ///
  /// False quando:
  /// - User não tem email auth (OAuth puro — não precisa migrar)
  /// - User é phone signup (synthetic email, fluxo separado)
  /// - User JÁ tem Apple ou Google linkado (migração concluída)
  bool get needsOAuthMigration {
    if (!hasPasswordAuth) return false;
    if (PhoneAuthHelpers.isSyntheticEmail(_user?.email)) return false;
    final identities = _supabase.auth.currentUser?.identities;
    if (identities == null) return false;
    final hasOAuth = identities.any(
      (id) => id.provider == 'apple' || id.provider == 'google',
    );
    return !hasOAuth;
  }
  Campaign? get currentCampaign => _currentCampaign;
  bool get hasCampaign => _currentCampaign != null;
  bool get showM1ResetNotice =>
      _user?.gamificationData['show_m1_reset_notice'] == true;

  /// Snapshot do "user tem profile_* populado" — carregado async em
  /// [_loadUser]/[_loadProfileDataPresence]. Usado pelo getter sync
  /// [hasResume] sem ter que fazer query a cada build. Re-atualiza após
  /// upload de CV via [refreshHasResume].
  bool _hasProfileData = false;

  /// Snapshot do "user tem material narrativo pra adaptar CV". Critério
  /// mais estrito que [_hasProfileData] — exige exp/proj/edu-com-conteúdo
  /// ou CV importado. Carregado junto com [_hasProfileData].
  bool _canAdaptCv = false;

  /// Verdadeiro quando o user tem algum "perfil profissional" no app — seja
  /// dados nas tabelas relacionais `profile_*` (CV importado via
  /// extract-profile ou perfil preenchido via Profile Editor) seja trilha
  /// minimamente preenchida (`whoIAm.derived.skills/summary/interests`).
  ///
  /// Usado pra decidir se faz sentido calcular/mostrar match score: sem CV
  /// nem trilha, score IA cai no Cenário C (50 fixo) e o determinístico não
  /// tem skills pra comparar — UI fica enganosa. Melhor não mostrar score.
  ///
  /// Antes lia `gamification_data.imported_resume.raw_text` (legacy cache).
  /// Pós Fase 2 da migração profile-first usa o snapshot relacional.
  bool get hasResume {
    if (_hasProfileData) return true;

    final data = _user?.gamificationData;
    if (data == null) return false;

    // Imediato pós-import: raw_text do PDF salvo em gamification_data.
    // Reconhecer aqui evita 10-15s de "Crie seu CV" enquanto extract-profile
    // roda em background populando as tabelas relacionais (que só então
    // viram _hasProfileData = true via _loadProfileDataPresence).
    final imported = data['imported_resume'];
    if (imported is Map) {
      final rawText = imported['raw_text']?.toString() ?? '';
      if (rawText.trim().isNotEmpty) return true;
    }

    // Trilha gerou skills/summary/interests (gamification_data.whoIAm.derived
    // continua sendo a fonte primária pra users que não importaram CV).
    final who = data['whoIAm'];
    if (who is Map) {
      final derived = who['derived'];
      if (derived is Map) {
        final skills = derived['skills']?.toString() ?? '';
        final summary = derived['summary']?.toString() ?? '';
        final interests = derived['interests']?.toString() ?? '';
        if (skills.trim().isNotEmpty ||
            summary.trim().isNotEmpty ||
            interests.trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  /// True quando o user tem material narrativo suficiente pra adaptar CV
  /// pra uma vaga (experiência, projeto, formação detalhada ou CV
  /// importado). Critério estrito — skills/summary isolados não bastam
  /// porque a adaptação reescreve bullets, e sem bullets a IA não tem o
  /// que reformular.
  ///
  /// Usado pelo `ResumeAdaptationSheet` no pre-check (evita chamar a IA
  /// e esperar 15s pra ela falhar com `profile_incomplete`).
  bool get canAdaptCv => _canAdaptCv;

  /// Re-checa se o user tem dados nas tabelas `profile_*` e notifica
  /// listeners se mudou. Útil pra UI invalidar caches de match score após
  /// upload/extração de CV — o caller (ex: tela de upload preview) chama
  /// quando termina de salvar.
  Future<void> refreshHasResume() async {
    final hadProfileData = _hasProfileData;
    final couldAdaptCv = _canAdaptCv;
    await _loadProfileDataPresence();
    final changed =
        _hasProfileData != hadProfileData || _canAdaptCv != couldAdaptCv;
    if (changed && !_isDisposed) {
      notifyListeners();
    }
  }

  Future<void> _loadProfileDataPresence() async {
    final uid = _user?.id ?? _supabase.auth.currentUser?.id;
    if (uid == null) {
      _hasProfileData = false;
      _canAdaptCv = false;
      return;
    }
    try {
      final snapshot = await ProfileSnapshotService().loadSnapshot(uid);
      _hasProfileData = !snapshot.isEmpty;
      _canAdaptCv = snapshot.canAdaptCv;
    } catch (_) {
      // Falha silenciosa — caímos no fallback whoIAm.derived no getter.
      _hasProfileData = false;
      _canAdaptCv = false;
    }
  }

  /// Liga este UserViewModel ao ProfileEditorViewModel pra que [needsProfileSetup]
  /// consulte o source-of-truth atual (`profile_personal`) antes da
  /// verificação legacy. Chamado pelo main.dart após o MultiProvider montar
  /// (via ProxyProvider). Seguro chamar múltiplas vezes — só substitui a
  /// referência, sem side-effects.
  void attachProfileEditor(ProfileEditorViewModel vm) {
    _profileEditor = vm;
  }

  /// Verdadeiro quando o user existe mas falta algum campo obrigatório do
  /// perfil. Usado pelo SplashScreen pra direcionar pra `TwoDoorsScreen`
  /// (entrada do onboarding profile-first) antes de seguir pra Home.
  ///
  /// Estratégia em 2 camadas (Gap #3 da auditoria):
  ///   1. NOVA: se `profile_personal` tem nome + sobrenome + email, perfil
  ///      é considerado completo. Cobre 100% dos users do novo onboarding
  ///      (Semana 2+).
  ///   2. LEGACY (fallback): verificação original baseada em `user_profiles`.
  ///      Mantém compatibilidade com users antigos que preencheram via
  ///      onboarding pré-Semana 2 (têm `user_profiles.name/age/course/etc`
  ///      mas podem não ter `profile_personal`).
  ///
  /// Importante: a verificação NOVA só retorna false (= "completo"). Se ela
  /// não bater (profile_personal vazio/parcial), cai pra LEGACY pra evitar
  /// regressão. Pior caso = comportamento idêntico ao antigo.
  bool get needsProfileSetup {
    final u = _user;
    if (u == null) return false;

    // Camada 1: profile_personal (source of truth do novo onboarding).
    final personal = _profileEditor?.personal;
    if (personal != null) {
      final hasFirstName = (personal.firstName ?? '').trim().isNotEmpty;
      final hasLastName = (personal.lastName ?? '').trim().isNotEmpty;
      final hasEmail = (personal.email ?? '').trim().isNotEmpty;
      if (hasFirstName && hasLastName && hasEmail) {
        return false; // perfil novo está completo
      }
    }

    // Camada 2 (LEGACY): verificação original. NÃO MUDA — é o comportamento
    // que rodava antes deste fix. Se a camada 1 não bateu (sem
    // profile_personal carregado ainda, ou campos vazios), respeita exatamente
    // o que o app fazia antes. Garantia: zero regressão pra users antigos.
    final name = u.name.trim();
    if (name.isEmpty || name.toLowerCase() == 'user') return true;
    if (u.age == null) return true;
    if ((u.phone ?? '').replaceAll(RegExp(r'\D'), '').length < 10) return true;
    if (u.course.trim().isEmpty) return true;
    if (u.semester.trim().isEmpty) return true;
    if (u.university.trim().isEmpty) return true;
    return false;
  }

  /// Verdadeiro quando o user está EM ANDAMENTO no flow profile-first
  /// (passou pelo TwoDoorsScreen e tem qualquer dado em `profile_personal`).
  /// Usado pelo AuthGate pra NUNCA roteá pra CompletionScreen (legacy) se o
  /// user está mid-flow — senão CompletionScreen.postFrameCallback empurra
  /// TwoDoorsScreen e gera loop infinito (bug do QA Dia 7 upload_cv path).
  ///
  /// Sinal: `profile_personal` não-null com QUALQUER campo preenchido —
  /// IA extraiu (firstName/lastName/email do CV) OU user respondeu uma
  /// masking question (attributionSource). Como `profile_personal` só
  /// existe pra users que entraram no flow novo, isso é suficiente.
  bool get isInProfileFirstFlow {
    final p = _profileEditor?.personal;
    if (p == null) return false;
    return (p.firstName ?? '').trim().isNotEmpty ||
        (p.lastName ?? '').trim().isNotEmpty ||
        (p.email ?? '').trim().isNotEmpty ||
        (p.attributionSource ?? '').trim().isNotEmpty;
  }

  /// Verdadeiro quando o user existe mas o nome é vazio ou o literal "User"
  /// (sentinela legacy do bug antigo). UI usa pra forçar a tela "Como
  /// podemos te chamar?" antes de entrar na home.
  bool get needsName {
    if (_user == null) return false;
    final n = _user!.name.trim();
    if (n.isEmpty) return true;
    if (n.toLowerCase() == 'user') return true;
    return false;
  }

  /// Atualiza só o nome do user (usado pelo "editar nome" do perfil).
  /// Persiste em `user_profiles` e re-notifica. Normaliza pra Title Case:
  /// "joao SILVA" → "Joao Silva".
  Future<void> updateName(String newName) async {
    final normalized = normalizeName(newName);
    if (normalized.isEmpty) {
      throw ArgumentError('Nome não pode ser vazio');
    }
    if (_user == null) return;
    final updated = _user!.copyWith(name: normalized);
    await _repository.updateUserProfile(updated);
    _user = updated;
    notifyListeners();
  }

  void _init() {
    // Listen to auth state changes
    _supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      switch (event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          // Qualquer evento com user ativo dispara identify. signIn é login
          // novo. initialSession é cold start (session restaurada do storage).
          // tokenRefreshed/userUpdated cobrem keep-alive e mudanças de perfil.
          _loadUser();
          final uid = _supabase.auth.currentUser?.id;
          final email = _supabase.auth.currentUser?.email;
          if (uid != null) {
            // Re-registra super properties (app_version, is_internal,
            // flow_version, app_build_number) ANTES do identify. Necessário
            // porque `Posthog().reset()` no logout apaga super properties no
            // SDK iOS — sem essa chamada, eventos pós-signup/login ficam sem
            // essas propriedades, quebrando filtros e cohort de internos.
            // Idempotente: re-rodar em initialSession/tokenRefreshed é safe.
            // ignore: unawaited_futures
            Analytics.shared.refreshSuperProperties();
            Analytics.shared.identify(uid, properties: {
              if (email != null) 'email': email,
            });
            // Associa o device ao user no OneSignal (push é endereçável por
            // uid agora). Idempotente — ok chamar em initialSession + signedIn.
            // ignore: unawaited_futures
            NotificationsService.shared.login(uid);

            // PostHog: sign_up_completed vs login_completed.
            // Pre-fix: signUpCompleted era chamado SÓ no email path (linha 334),
            // então 87% dos novos usuários (Apple Sign-In) ficavam sem evento.
            // Resultado em prod: 33 sign_up_completed vs 253 onboarding_completed.
            // Agora centralizamos no listener — cobre Apple/Google/email.
            // Provider sai do appMetadata (Supabase popula com 'apple',
            // 'google', 'email' conforme o canal de auth).
            // Distinção signup vs login: createdAt < 5 min indica usuário
            // brand-new (mesma heurística usada pra Facebook abaixo).
            if (event == AuthChangeEvent.signedIn) {
              final createdAtStr = _supabase.auth.currentUser?.createdAt;
              final provider = _supabase.auth.currentUser
                      ?.appMetadata['provider']
                      ?.toString() ??
                  'unknown';
              final createdAt = createdAtStr != null
                  ? DateTime.tryParse(createdAtStr)
                  : null;
              final isFreshSignup = createdAt != null &&
                  DateTime.now()
                          .toUtc()
                          .difference(createdAt.toUtc())
                          .inMinutes <
                      5;
              if (isFreshSignup) {
                Analytics.shared.signUpCompleted(method: provider);
                // Facebook CompletedRegistration — mesma freshness window.
                // Flag de dedupe em logCompletedRegistrationOnce garante 1x.
                // ignore: unawaited_futures
                FacebookEventsService.shared.logCompletedRegistrationOnce(
                  userId: uid,
                  method: provider,
                );
              } else {
                Analytics.shared.loginCompleted(method: provider);
              }
              // Advanced Matching: passa email/nome/userId pro SDK em todo
              // signIn (signup OU login). SDK hasheia internamente e usa
              // pra fazer match com a pessoa que clicou no ad. Sobe EMQ
              // score e melhora atribuição pós-ATT deny. Email é obrigatório.
              final authEmail = _supabase.auth.currentUser?.email;
              if (authEmail != null && authEmail.isNotEmpty) {
                final nameParts = (_user?.name ?? '').trim().split(RegExp(r'\s+'));
                final firstName = nameParts.isNotEmpty ? nameParts.first : null;
                final lastName = nameParts.length > 1 ? nameParts.last : null;
                // ignore: unawaited_futures
                FacebookEventsService.shared.setUserDataForMatching(
                  email: authEmail,
                  firstName: firstName,
                  lastName: lastName,
                  externalId: uid,
                );
              }
            }
          }
          break;
        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userDeleted:
          _user = null;
          _currentCampaign = null;
          notifyListeners();
          Analytics.shared.logoutCompleted();
          Analytics.shared.reset();
          // ignore: unawaited_futures
          NotificationsService.shared.logout();
          break;
        default:
          break;
      }
    });
    
    // Load initial user and prefetch data
    _loadUser();
    // Prefetch content (fire and forget, or await if critical)
    _repository.prefetchAllData();
  }

  Future<void> refreshUser() async {
    await _loadUser();
  }

  Future<void> _loadUser() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      if (_supabase.auth.currentUser != null) {
        // Retry logic to wait for DB trigger creation
        UserProfile? userProfile;
        int attempts = 0;
        while (attempts < 4 && userProfile == null) {
          if (attempts > 0) {
             // Profile not found yet; waiting for DB trigger to populate.
             await Future.delayed(const Duration(seconds: 1));
          }

          try {
            userProfile = await _repository.getUserProfile();
          } catch (e) {
            // Swallow transient errors during retries; surfacing only the
            // final failure (after all attempts) keeps the console clean.
          }
          
          attempts++;
        }
        
        // Fallback: If age is missing in DB profile, check Auth Metadata
        if (userProfile != null && userProfile.age == null) {
          final metadataAge = _supabase.auth.currentUser!.userMetadata?['age'];
          if (metadataAge != null) {
            // "Patch" the user profile in memory with age from metadata
            final age = metadataAge is int ? metadataAge : int.tryParse(metadataAge.toString());
            userProfile = userProfile.copyWith(age: age);
          }
        }
        
        _user = userProfile;
        if (_user != null) {
          _currentCampaign = await _repository.getLatestCampaign(_user!.id!);
          // Carrega presença de dados nas tabelas profile_* (alimenta o
          // getter sync `hasResume`). Bloqueia o load — barato (1 query
          // paralela de cada tabela; ~100ms em rede normal).
          await _loadProfileDataPresence();
          // Reprocessamento de CV existente (background — não bloqueia load)
          // Cobre o caso de upload feito antes do código de extração existir.
          // ignore: unawaited_futures
          _reprocessLatestResumeIfNeeded();
        }
      } else {
        _user = null;
        _currentCampaign = null;
        _hasProfileData = false;
        _canAdaptCv = false;
      }
    } catch (e) {
      print('Error loading user: $e');
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Se o user tem PDF salvo na biblioteca mas as tabelas `profile_*` estão
  /// vazias (ou só com user_id em `profile_personal`), dispara
  /// `extract-profile` em background pra popular o perfil relacional.
  /// Idempotente: pula se já tem dados extraídos. Fire-and-forget — não
  /// bloqueia o load nem faz error surfacing ao user.
  ///
  /// Antes a função extraía raw_text local + persistia em
  /// `gamification_data.imported_resume.raw_text`. Pós Fase 2 da migração
  /// profile-first o servidor cuida da extração estruturada (GPT-4o com
  /// suporte nativo a PDF + save_profile_from_json), então aqui só
  /// orquestramos a chamada.
  Future<void> _reprocessLatestResumeIfNeeded() async {
    final user = _user;
    if (user == null) return;

    // Tabelas profile_* já populadas? Skip — extract-profile já rodou em
    // algum upload anterior (ou backfill).
    if (_hasProfileData) return;

    try {
      final resumes = await _repository.getSavedResumes();
      if (resumes.isEmpty) return;

      final latest = resumes.first; // ordered DESC by created_at
      final bytes = await _repository.downloadResume(latest.filePath);
      if (bytes.isEmpty) return;

      final pdfBase64 = base64Encode(bytes);
      final response = await _supabase.functions.invoke(
        'extract-profile',
        body: {
          'pdf_base64': pdfBase64,
          'force': true,
        },
      ).timeout(const Duration(seconds: 75));

      final data = response.data;
      if (data is Map && data['error'] == null) {
        // Re-checa presença pra que `hasResume` reflita o estado novo.
        await refreshHasResume();
      }
    } catch (e) {
      // Background reprocess é best-effort: log discreto e segue.
      debugPrint('Reprocess CV via extract-profile failed (non-blocking): $e');
    }
  }

  // Sign up new user
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    required int age,
    String? course,
    String? semester,
    String? university,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'name': name,
          'age': age,
          'course': course ?? '',
          'semester': semester ?? '',
          'university': university ?? '',
        },
      );

      if (response.user != null) {
        // Profile is automatically created by database trigger.
        // sign_up_completed + Facebook CompletedRegistration são emitidos
        // pelo listener de onAuthStateChange em _init() (cobre todos os
        // canais: email, apple, google — não só email).
        await _loadUser();
      }
    } catch (e) {
      // Check if error is "User already registered"
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('already registered') || errorMsg.contains('already exists')) {
        print('⚠️ User already exists, attempting to sign in instead...');
        try {
          await signIn(email: email, password: password);
          return; // Exit success if sign in works
        } catch (signInError) {
           print('Sign in after sign up failed: $signInError');
           // Rethrow original error if fallback fails
           rethrow; 
        }
      }
      
      print('Error signing up: $e');
      rethrow;
    } finally {
      // Only set loading false if we aren't redirecting to signIn (which handles its own loading)
      // Actually, signIn sets loading=true then false, so we should be careful not to override.
      // But since we await signIn, it should be fine to set false here at the very end.
      if (!_isDisposed) { // Add disposed check if possible, or just standard
         _isLoading = false;
         notifyListeners();
      }
    }
  }

  // Sign in existing user
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      // login_completed é emitido pelo listener de onAuthStateChange em
      // _init() — cobre todos os canais (email, apple, google).
      await _loadUser();
    } catch (e) {
      print('Error signing in: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> clearM1ResetNotice() async {
    if (_user == null || !showM1ResetNotice) return;
    await _repository.clearM1ResetNotice(_user!.id!);
    final updatedData = Map<String, dynamic>.from(_user!.gamificationData)
      ..remove('show_m1_reset_notice');
    _user = _user!.copyWith(gamificationData: updatedData);
    notifyListeners();
  }

  Future<void> createCampaign({
    String? jobTitle,
    String? descriptionText,
    String? sourceUrl,
    bool isSkipped = false,
  }) async {
    // Garantir que o user_profiles row existe antes de inserir target_jobs/campaigns
    // (se o trigger de profile criou row depois do _loadUser() inicial, ainda
    // cobrimos via getUserProfile, que faz retry).
    if (_user == null || _user!.id == null) {
      await _loadUser();
    }
    if (_user == null || _user!.id == null) {
      throw Exception('Usuário não autenticado.');
    }

    _currentCampaign = await _repository.createCampaignWithTargetJob(
      userId: _user!.id!,
      jobTitle: jobTitle,
      descriptionText: descriptionText,
      sourceUrl: sourceUrl,
      isSkipped: isSkipped,
    );
    notifyListeners();
  }

  // Sign in with OAuth Provider (Google, Apple, etc.)
  Future<void> signInWithOAuth(OAuthProvider provider) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _supabase.auth.signInWithOAuth(
        provider,
        redirectTo: 'io.supabase.stage://login-callback',
        queryParams: {
          'prompt': 'select_account',
        },
      );
    } catch (e) {
      print('Error signing in with OAuth ($provider): $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Native Apple Sign In
  Future<void> signInWithApple() async {
    _isLoading = true;
    notifyListeners();
    // Analytics: dispara `apple_signin_started` no início. Combinado com
    // `apple_signin_failed` (catch) e `sign_up_completed`/`login_completed`
    // (listener), permite calcular abandono entre clique e finalização.
    // ignore: unawaited_futures
    Analytics.shared.appleSigninStarted();
    // QA Dia 6 fix: também emite auth_signup_started canônico pra que o
    // funil signup landing → method_chosen → started → completed funcione
    // independente do método (apple/email/google/phone).
    // ignore: unawaited_futures
    Analytics.shared.authSignupStarted(method: 'apple');

    try {
      final rawNonce = _supabase.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        // appleSigninFailed(code: 'token_missing') é emitido no catch abaixo
        // (a mensagem "Apple Id token missing" entra na detecção). Não emitir
        // aqui pra evitar evento duplicado.
        throw Exception('Apple Id token missing.');
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      // Apple só manda givenName/familyName no PRIMEIRO autorize. Se vier,
      // empurramos pro `user_metadata` ANTES do `_loadUser` — assim quando o
      // repo criar o profile pela primeira vez, o `resolveAuthName` já encontra
      // `full_name` em vez de cair no email-prefix.
      final givenName = credential.givenName ?? '';
      final familyName = credential.familyName ?? '';
      final appleName = normalizeName('$givenName $familyName');

      if (appleName.isNotEmpty) {
        try {
          await _supabase.auth.updateUser(
            UserAttributes(data: {'full_name': appleName}),
          );
        } catch (e) {
          // Não bloqueia o fluxo — pior caso o nome cai no email-prefix.
          print('updateUser(full_name) failed: $e');
        }
      }

      // Agora carrega o profile (cria com nome resolvido se for primeiro login).
      await _loadUser();

      // Se o profile já existia com nome legacy 'User' ou vazio E a Apple
      // mandou nome agora, sobrescreve.
      if (appleName.isNotEmpty &&
          _user != null &&
          (_user!.name.trim().isEmpty || _user!.name == 'User')) {
        await _repository.updateUserProfile(
          _user!.copyWith(name: appleName),
        );
        _user = _user!.copyWith(name: appleName);
        notifyListeners();
      }

      // Facebook CompletedRegistration via Apple. Apple só manda nome no
      // PRIMEIRO authorize — usamos isso como prova de signup novo.
      // Idempotente via flag em SharedPreferences (logCompletedRegistrationOnce).
      if (appleName.isNotEmpty && _user?.id != null) {
        // ignore: unawaited_futures
        FacebookEventsService.shared.logCompletedRegistrationOnce(
          userId: _user!.id,
          method: 'apple',
        );
      }

      // Advanced Matching pós-Apple-sign-in: ainda que o auth listener no
      // signedIn também rode, aqui temos o appleName mais fresco (Apple
      // só manda nome no primeiro authorize). Vale enviar pra garantir.
      final appleEmail = _supabase.auth.currentUser?.email;
      if (appleEmail != null && appleEmail.isNotEmpty) {
        final nameParts = appleName.trim().isNotEmpty
            ? appleName.trim().split(RegExp(r'\s+'))
            : (_user?.name ?? '').trim().split(RegExp(r'\s+'));
        final firstName = nameParts.isNotEmpty ? nameParts.first : null;
        final lastName = nameParts.length > 1 ? nameParts.last : null;
        // ignore: unawaited_futures
        FacebookEventsService.shared.setUserDataForMatching(
          email: appleEmail,
          firstName: firstName,
          lastName: lastName,
          externalId: _user?.id,
        );
      }

    } catch (e) {
      // SignInWithAppleAuthorizationException com code=canceled vem quando
      // o user fecha o diálogo iOS. Tratamos como abandono silencioso —
      // registramos no analytics mas não propagamos pro UI (sem snackbar).
      final errStr = e.toString().toLowerCase();
      final bool isCancelled =
          errStr.contains('canceled') || errStr.contains('cancelled');
      final String code;
      if (isCancelled) {
        code = 'cancelled';
      } else if (errStr.contains('apple id token missing')) {
        code = 'token_missing';
      } else {
        code = 'unknown';
      }
      // ignore: unawaited_futures
      Analytics.shared.appleSigninFailed(code: code);
      print('Error signing in with Apple natively: $e');
      if (!isCancelled) rethrow;
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      // Clear repository cache before sign out so other ViewModels
      // don't see stale data from the previous user session
      _repository.clearCache();

      // Clear local SQLite data
      try {
        await DatabaseHelper.instance.clearAllUserData();
      } catch (e) { print('Local DB cleanup on logout: $e'); }

      // Limpa Advanced Matching no SDK pra próximo user não herdar dados.
      // ignore: unawaited_futures
      FacebookEventsService.shared.clearUserData();

      await _supabase.auth.signOut();
      _user = null;
      notifyListeners();
    } catch (e) {
      print('Error logging out: $e');
      rethrow;
    }
  }

  // Resend Verification Email
  Future<void> resendVerificationEmail() async {
    _isLoading = true;
    notifyListeners();
    try {
      final email = _supabase.auth.currentUser?.email;
      if (email != null) {
        await _supabase.auth.resend(type: OtpType.signup, email: email);
      }
    } catch (e) {
      print('Error resending verification: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete Account
  Future<void> deleteAccount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      print('🛑 Initiating full account deletion for: $userId');

      // 1. Delete user files from Storage (with timeout)
      try {
        await _repository.deleteUserData().timeout(const Duration(seconds: 15));
      } catch (e) {
        print('⚠️ Storage cleanup timed out or failed: $e');
      }

      // 2. Clear local data (SQLite)
      try {
        await DatabaseHelper.instance.clearAllUserData();
      } catch (e) { print('Local DB cleanup error: $e'); }

      // 3. Clear local storage (Shared Preferences)
      try {
         await _localStorage.clearAll(userId);
      } catch (e) { print('Local storage cleanup error: $e'); }

      // 4. Delete auth account in Supabase (Cascades to all DB tables)
      try {
        await _repository.deleteAuthAccount().timeout(const Duration(seconds: 15));
      } catch (e) {
        print('❌ Auth deletion failed or timed out: $e');
        // If the RPC failed, it might be because the SQL function wasn't added yet.
        // We still proceed to sign out to at least disconnect the user.
      }

      // 5. Clear repository cache
      _repository.clearCache();

      // 6. Hard sign out and clear state
      await _supabase.auth.signOut();
      _user = null;
      print('👋 Account $userId disconnected and cleanup attempted.');
    } catch (e) {
      print('❌ Critical error during deletion process: $e');
      rethrow;
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Update user profile
  Future<void> updateProfile({
    String? name,
    String? course,
    String? semester,
    String? university,
    int? age,
    String? phone,
    String? email,
    String? password,
    Map<String, dynamic>? gamificationData,
  }) async {
    if (_user == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Update Auth — APENAS pra email/password.
      //
      // ATENÇÃO: NÃO incluir `age` (nem outro field do profile) na chamada
      // `_supabase.auth.updateUser()`. Ela dispara `AuthChangeEvent.userUpdated`
      // → listener chama `_loadUser()` async → SELECT do user_profiles → quando
      // race com o passo 2 abaixo, sobrescreve `_user` em memória com dado
      // velho. Sintoma: depois de salvar o ProfileSetup, a tela volta pro
      // Step 0 porque `needsProfileSetup` vira true de novo via _user stale.
      // Age já vai pro DB via `UserProfile.toMap()` no passo 2.
      if (email != null || password != null) {
        final attributes = UserAttributes(email: email, password: password);
        await _supabase.auth.updateUser(attributes);
      }

      // 2. Update Profile Table (Name, Age, Phone, Course, Semester, etc.)
      // `UserProfile.toMap()` cobre todos os campos. Coluna `age` existe no
      // schema desde migração antiga; phone na 20260514000000.
      
      if (name != null || course != null || semester != null || university != null || age != null || phone != null || gamificationData != null) {

        // Merge gamification data
        Map<String, dynamic> mergedGamificationData = Map.from(_user!.gamificationData);
        if (gamificationData != null) {
          mergedGamificationData.addAll(gamificationData);
        }
        if (university != null) {
          mergedGamificationData['university'] = university;
        }

        // Normaliza phone: salva só dígitos. UI formata na exibição.
        final normalizedPhone = phone != null
            ? phone.replaceAll(RegExp(r'\D'), '')
            : null;

        final updatedProfile = _user!.copyWith(
          name: name,
          course: course,
          semester: semester,
          age: age,
          phone: normalizedPhone,
          email: email,
          gamificationData: mergedGamificationData,
        );

        await _repository.updateUserProfile(updatedProfile);
        _user = updatedProfile;
      }
      
      notifyListeners();
    } catch (e) {
      print('Error updating profile: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Vincula uma identity Apple ao user atual via Sign In with Apple
  /// nativo. Não troca a sessão — só ADICIONA a identity 'apple' na
  /// mesma row de `auth.users`. Próximo login via Apple resolve no
  /// mesmo user (e mesmo `user.id` UUID — todos os dados continuam).
  ///
  /// Pré-requisito: user logado. Disponível na sessão atual; quando
  /// o JWT expirar, o user pode fazer login normal via Apple.
  ///
  /// Throws com mensagem human-readable em caso de falha (canceled,
  /// already linked, network).
  Future<void> linkAppleIdentity() async {
    // ignore: unawaited_futures
    Analytics.shared.oauthMigrationStarted(provider: 'apple');
    try {
      final rawNonce = _supabase.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('Apple Id token missing.');
      }

      // linkIdentityWithIdToken (gotrue 2.16+) faz o vínculo direto
      // sem trocar a sessão — diferente de signInWithIdToken, que
      // criaria uma sessão nova ou falharia se o email já existir.
      await _supabase.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      // Refresh user pra UI pegar a nova identity (banner some).
      await _loadUser();
      // ignore: unawaited_futures
      Analytics.shared.oauthMigrationCompleted(provider: 'apple');
    } on SignInWithAppleAuthorizationException catch (e) {
      // ignore: unawaited_futures
      Analytics.shared.oauthMigrationFailed(
        provider: 'apple',
        reason: e.code.name,
      );
      if (e.code == AuthorizationErrorCode.canceled) {
        // Cancel do user — não é erro fatal. Throw com code próprio
        // pra UI distinguir e não mostrar erro feio.
        throw const OAuthLinkException('canceled');
      }
      rethrow;
    } catch (e) {
      // ignore: unawaited_futures
      Analytics.shared.oauthMigrationFailed(
        provider: 'apple',
        reason: 'unknown',
      );
      rethrow;
    }
  }

  /// Vincula uma identity Google ao user atual. Abre browser flow
  /// (não há Google Sign-In nativo no projeto atualmente), retorna
  /// pro app via deeplink. Mesmo resultado que Apple: adiciona
  /// identity 'google' sem mudar `user.id`.
  Future<void> linkGoogleIdentity() async {
    // ignore: unawaited_futures
    Analytics.shared.oauthMigrationStarted(provider: 'google');
    try {
      final launched = await _supabase.auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: 'io.supabase.stage://login-callback',
      );
      if (!launched) {
        // ignore: unawaited_futures
        Analytics.shared.oauthMigrationFailed(
          provider: 'google',
          reason: 'launch_failed',
        );
        throw const OAuthLinkException('launch_failed');
      }
      // O resultado real do link chega via deeplink → onAuthStateChange
      // (`AuthChangeEvent.userUpdated`). Como o listener em _init já
      // chama _loadUser nesse evento, o banner some sozinho. Não dá
      // pra `await` aqui — o flow OAuth é externo (browser).
      // Telemetria de "completed" vai disparar no listener.
    } catch (e) {
      // ignore: unawaited_futures
      Analytics.shared.oauthMigrationFailed(
        provider: 'google',
        reason: 'launch_${e.runtimeType}',
      );
      rethrow;
    }
  }

  /// Troca a senha do usuário com re-autenticação. Diferente de
  /// `updateProfile(password: ...)` que confia no JWT atual (vulnerável
  /// a sequestro de sessão em celular destravado), este método primeiro
  /// re-autentica via `signInWithPassword` pra confirmar identidade.
  ///
  /// Erros tipados (UI traduz pra mensagem):
  /// - `wrong_password`: senha atual incorreta
  /// - `no_email`: user logado sem email (não-suportado — phone-only)
  /// - `weak_password`: nova senha não atende requisitos do Supabase
  /// - `same_password`: nova == atual (Supabase rejeita)
  /// - `network`: falha de conexão
  /// - `unknown`: outros casos (loga e propaga)
  ///
  /// Em sucesso, Supabase invalida sessões em outros devices (boa segurança).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _user?.email ?? _supabase.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw const PasswordChangeException('no_email');
    }

    // 1. Re-autentica com senha atual. signInWithPassword renova o JWT
    //    e valida a senha — se errar, throw AuthException com message
    //    "Invalid login credentials".
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid') || msg.contains('credentials')) {
        // ignore: unawaited_futures
        Analytics.shared.passwordChangeFailed(reason: 'wrong_current');
        throw const PasswordChangeException('wrong_password');
      }
      // ignore: unawaited_futures
      Analytics.shared.passwordChangeFailed(reason: 'reauth_${e.statusCode ?? "unknown"}');
      rethrow;
    } catch (e) {
      // ignore: unawaited_futures
      Analytics.shared.passwordChangeFailed(reason: 'reauth_network');
      throw const PasswordChangeException('network');
    }

    // 2. updateUser pra trocar a senha de fato.
    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      // ignore: unawaited_futures
      if (msg.contains('weak') || msg.contains('too short')) {
        Analytics.shared.passwordChangeFailed(reason: 'weak');
        throw const PasswordChangeException('weak_password');
      }
      if (msg.contains('same') || msg.contains('different from')) {
        Analytics.shared.passwordChangeFailed(reason: 'same');
        throw const PasswordChangeException('same_password');
      }
      Analytics.shared.passwordChangeFailed(reason: 'update_${e.statusCode ?? "unknown"}');
      rethrow;
    }

    // ignore: unawaited_futures
    Analytics.shared.passwordChanged();
  }

  Future<void> updateAIConsent(bool consent) async {
    if (_user == null) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      await _repository.updateAIConsent(_user!.id!, consent);
      _user = _user!.copyWith(
        aiConsent: consent,
        aiConsentTimestamp: consent ? DateTime.now() : null,
      );
      notifyListeners();
    } catch (e) {
      print('Error updating AI consent: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> revokeAIConsent() async {
    await updateAIConsent(false);
  }
}

/// Exception tipada da troca de senha. `code` é uma das strings:
/// `wrong_password`, `no_email`, `weak_password`, `same_password`,
/// `network`. UI traduz pra mensagem PT-BR ao redor disso.
class PasswordChangeException implements Exception {
  final String code;
  const PasswordChangeException(this.code);
  @override
  String toString() => 'PasswordChangeException($code)';
}

/// Exception tipada do link de identity OAuth (Apple/Google) na conta
/// existente. `code`:
/// - `canceled`: user cancelou o prompt nativo (Apple) ou fechou o
///   browser (Google). Não é erro fatal — UI ignora silenciosamente.
/// - `launch_failed`: não conseguimos abrir o browser pro Google.
/// - `already_linked`: provider já vinculado (não deve acontecer porque
///   o banner some assim que vincula, mas defensive).
class OAuthLinkException implements Exception {
  final String code;
  const OAuthLinkException(this.code);
  @override
  String toString() => 'OAuthLinkException($code)';
}
