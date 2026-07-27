// Fase 4 (IA/Perfil) — F4.4: status do Currículo geral persistido.
//
// Lê a ÚLTIMA versão salva (saved_resumes source='general'). Best-effort: se a
// leitura falhar, devolve status neutro — o card degrada, nunca trava.
//
// ## O selo "Perfil mudou" foi REMOVIDO (decisão do fundador, 27/07)
//
// O card comparava o fingerprint da versão salva com um fingerprint do perfil
// ATUAL, recomputado a cada `ProfileEvents`, para acender um selo
// "desatualizado". Três coisas mataram esse desenho:
//
//  1. **Ele mentia.** O fingerprint era tirado do TEXTO FORMATADO, que inclui o
//     sufixo "(previsto)" de `Education.formattedPeriodAt(DateTime.now())`.
//     Esse sufixo some sozinho quando o mês da conclusão chega — então o selo
//     acendia na virada do mês, sem ninguém editar nada. Medido em prod
//     (27/07): 162 formações mostram "(previsto)" hoje, de 153 pessoas; 49
//     delas viram a chave nos próximos 12 meses.
//  2. **Era caro.** Recomputar o fingerprint significava recarregar as 10
//     tabelas do perfil, re-serializar e re-hashear o currículo inteiro — a
//     cada evento de perfil, e de novo logo após o export refazer o mesmo
//     trabalho que o writer acabara de fazer.
//  3. **Valia pouco.** O que ele entregava era "sua cópia salva é mais velha
//     que seu perfil". Na prática o usuário exporta de novo quando vai mandar
//     para uma vaga — que é quando ele naturalmente pensa no currículo.
//
// O fingerprint CONTINUA existindo do lado da ESCRITA, onde ganha o seu
// sustento: é ele que faz o re-export idêntico virar `noop` em vez de criar
// versão duplicada. Ali é comparação num lugar só, no momento de salvar.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Metadados da última versão persistida do Currículo geral.
class StoredGeneralResumeVersion {
  final String id;
  final int version;
  final String templateId;
  final String fingerprint;
  final DateTime? createdAt;

  const StoredGeneralResumeVersion({
    required this.id,
    required this.version,
    required this.templateId,
    required this.fingerprint,
    required this.createdAt,
  });

  static StoredGeneralResumeVersion? fromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final id = row['id']?.toString();
    final version = (row['version'] as num?)?.toInt();
    final template = row['template_id']?.toString();
    final fp = row['profile_fingerprint']?.toString();
    if (id == null || version == null || template == null || fp == null) {
      return null;
    }
    final createdRaw = row['created_at']?.toString();
    return StoredGeneralResumeVersion(
      id: id,
      version: version,
      templateId: template,
      fingerprint: fp,
      createdAt: createdRaw != null ? DateTime.tryParse(createdRaw) : null,
    );
  }
}

/// Status do card: qual é a última versão salva, se houver.
class GeneralResumeStatus {
  final StoredGeneralResumeVersion? lastVersion;

  const GeneralResumeStatus({this.lastVersion});

  bool get hasVersion => lastVersion != null;

  static const none = GeneralResumeStatus();
}

typedef LastVersionRowFn = Future<Map<String, dynamic>?> Function(String uid);

class GeneralResumeStatusLoader {
  final LastVersionRowFn _fetchLastVersion;

  GeneralResumeStatusLoader({required LastVersionRowFn fetchLastVersion})
      : _fetchLastVersion = fetchLastVersion;

  /// Loader de produção: lê a última versão own-row (RLS + user_id).
  factory GeneralResumeStatusLoader.production() {
    final sb = Supabase.instance.client;
    return GeneralResumeStatusLoader(
      fetchLastVersion: (uid) => sb
          .from('saved_resumes')
          .select('id, version, template_id, profile_fingerprint, created_at')
          .eq('user_id', uid)
          .eq('source', 'general')
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle(),
    );
  }

  /// Carrega o status. NUNCA lança — falha vira status neutro (sem versão).
  Future<GeneralResumeStatus> load(String uid, {String? userFallbackName}) async {
    Map<String, dynamic>? row;
    try {
      row = await _fetchLastVersion(uid);
    } catch (_) {
      return GeneralResumeStatus.none;
    }
    final version = StoredGeneralResumeVersion.fromRow(row);
    if (version == null) return GeneralResumeStatus.none;
    return GeneralResumeStatus(lastVersion: version);
  }
}
