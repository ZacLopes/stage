/// URLs dos documentos legais do Stage.
///
/// Fonte única: antes a de privacidade vivia hardcoded só dentro do
/// `ai_consent_modal.dart`, e a tela de cadastro exibia "Termos de Uso" e
/// "Política de Privacidade" como texto azul e negrito — com cara de link,
/// sem `recognizer`, portanto sem abrir nada (revisão UX 28/07, achado P2-15).
class StageLegalLinks {
  StageLegalLinks._();

  /// Política de privacidade. URL já em uso em produção pelo modal de
  /// consentimento de IA — caminho conhecido e funcionando.
  static const String privacyUrl = 'https://stageapp.lovable.app/privacy';

  /// Termos de uso.
  ///
  /// ⚠️ NÃO FOI POSSÍVEL VERIFICAR ESTA ROTA. O site é uma SPA e devolve
  /// HTTP 200 com o mesmo HTML para qualquer caminho — inclusive rotas
  /// inexistentes —, então o status não prova que a página existe; quem
  /// decide é o roteador no cliente. Abrir no navegador e confirmar que
  /// renderiza os termos; se não renderizar, corrigir aqui (1 linha).
  static const String termsUrl = 'https://stageapp.lovable.app/terms';

  /// Política da OpenAI — citada no consentimento de IA porque é o terceiro
  /// que recebe os dados.
  static const String openAiPrivacyUrl =
      'https://openai.com/policies/privacy-policy';
}
