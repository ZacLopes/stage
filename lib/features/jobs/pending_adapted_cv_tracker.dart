import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estado persistido: "tem CV adaptado pra vaga X e o user ainda não baixou
/// nem exportou". Usado pelo banner do Home pra trazer o user de volta
/// (recuperação do funil pré-export, F2.5 do plano).
///
/// Pré-fix: dos 14 usuários que adaptaram com sucesso, ~7 não exportaram —
/// trabalho de IA jogado fora bem na porta do north star.
///
/// Storage chaves:
///   pending_adapted_cv_job_id      → uuid da vaga
///   pending_adapted_cv_job_title   → título pra mostrar no banner
///   pending_adapted_cv_company     → empresa (opcional)
///   pending_adapted_cv_at_iso      → timestamp ISO da adaptação
///
/// TTL: 3 dias. Depois disso é stale (assume que o user esqueceu, banner
/// vira ruído). Banner some.
class PendingAdaptedCv {
  final String jobId;
  final String jobTitle;
  final String? company;
  final DateTime at;

  const PendingAdaptedCv({
    required this.jobId,
    required this.jobTitle,
    required this.at,
    this.company,
  });
}

/// `ChangeNotifier` pra que o banner do Home reflita mudanças em tempo real.
/// Pré-fix: o banner só lia SharedPreferences no initState — se o user
/// adaptasse um CV na mesma sessão, o banner só apareceria após restart.
/// Agora, ao chamar markAdapted/clear, notifyListeners() força rebuild.
///
/// Singleton porque (a) provê via MultiProvider (.value) e (b) o setter
/// de adaptação (resume_adaptation_sheet) precisa ver a mesma instância
/// que o banner do home assina.
class PendingAdaptedCvTracker extends ChangeNotifier {
  PendingAdaptedCvTracker._();
  static final PendingAdaptedCvTracker shared = PendingAdaptedCvTracker._();

  static const _kJobId = 'pending_adapted_cv_job_id';
  static const _kJobTitle = 'pending_adapted_cv_job_title';
  static const _kCompany = 'pending_adapted_cv_company';
  static const _kAtIso = 'pending_adapted_cv_at_iso';
  static const _kStaleAfter = Duration(days: 3);

  PendingAdaptedCv? _current;
  bool _loaded = false;

  /// Estado atual em memória. Pode ser lido sincronamente após [hydrate].
  /// Null = sem pending OU ainda não hidratado.
  PendingAdaptedCv? get current => _current;

  /// Indica se o tracker já leu o SharedPreferences pelo menos uma vez.
  /// Usado pra que widgets não pisquem "vazio → cheio" no primeiro frame.
  bool get loaded => _loaded;

  /// Hidrata o estado do SharedPreferences. Idempotente — só faz I/O na
  /// primeira chamada (ou se forceReload=true). Chamado no boot do app.
  Future<void> hydrate({bool forceReload = false}) async {
    if (_loaded && !forceReload) return;
    _current = await _readFromPrefs();
    _loaded = true;
    notifyListeners();
  }

  /// Marca uma adaptação como "feita mas pendente de export".
  /// Chamado quando `cv_adaptation_succeeded` é emitido.
  Future<void> markAdapted({
    required String jobId,
    required String jobTitle,
    String? company,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString(_kJobId, jobId);
    await prefs.setString(_kJobTitle, jobTitle);
    if (company != null) await prefs.setString(_kCompany, company);
    await prefs.setString(_kAtIso, now.toIso8601String());

    _current = PendingAdaptedCv(
      jobId: jobId,
      jobTitle: jobTitle,
      company: company,
      at: now,
    );
    _loaded = true;
    notifyListeners();
  }

  /// Limpa o estado pendente. Chamado quando o user finaliza o ciclo —
  /// baixa o PDF adaptado OU exporta via template.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kJobId);
    await prefs.remove(_kJobTitle);
    await prefs.remove(_kCompany);
    await prefs.remove(_kAtIso);

    if (_current != null) {
      _current = null;
      notifyListeners();
    }
  }

  /// Helper antigo (compatibilidade). Lê fresh do prefs — prefira usar
  /// `current` após `hydrate()`.
  Future<PendingAdaptedCv?> read() async {
    final v = await _readFromPrefs();
    if (_current?.jobId != v?.jobId || _current?.at != v?.at) {
      _current = v;
      _loaded = true;
      notifyListeners();
    }
    return v;
  }

  Future<PendingAdaptedCv?> _readFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString(_kJobId);
    final jobTitle = prefs.getString(_kJobTitle);
    final atIso = prefs.getString(_kAtIso);
    if (jobId == null || jobTitle == null || atIso == null) return null;

    final at = DateTime.tryParse(atIso);
    if (at == null) return null;
    if (DateTime.now().difference(at) > _kStaleAfter) {
      // Stale — limpa no prefs pra não voltar a aparecer.
      await prefs.remove(_kJobId);
      await prefs.remove(_kJobTitle);
      await prefs.remove(_kCompany);
      await prefs.remove(_kAtIso);
      return null;
    }

    return PendingAdaptedCv(
      jobId: jobId,
      jobTitle: jobTitle,
      at: at,
      company: prefs.getString(_kCompany),
    );
  }
}
