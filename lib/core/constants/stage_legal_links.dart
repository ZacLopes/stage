/// URLs dos documentos legais do Stage.
///
/// Fonte única: antes a de privacidade vivia hardcoded só dentro do
/// `ai_consent_modal.dart`, e a tela de cadastro exibia "Termos de Uso" e
/// "Política de Privacidade" como texto azul e negrito — com cara de link,
/// sem `recognizer`, portanto sem abrir nada (revisão UX 28/07, achado P2-15).
class StageLegalLinks {
  StageLegalLinks._();

  /// Política de privacidade.
  ///
  /// ⚠️ **A ROTA `/privacy` NÃO EXISTE.** Verificado em 30/07/2026 abrindo a
  /// URL: devolve a página "Oops! Page not found". `/privacidade` idem.
  ///
  /// Isto corrige um erro MEU. A versão anterior deste arquivo afirmava que
  /// `/privacy` era "caminho conhecido e funcionando" — eu a centralizei sem
  /// testar, só porque a URL já estava em produção dentro do modal de
  /// consentimento, e com isso repliquei um link quebrado em três telas novas.
  /// O site é uma SPA e devolve HTTP 200 para qualquer caminho, então status
  /// não prova nada: quem decide é o roteador no cliente, e só abrindo dá para
  /// saber.
  ///
  /// Aponta para a raiz enquanto a rota não existir — abrir página real é
  /// melhor que abrir 404 —, mas isso **NÃO cumpre o que o achado pede**: a
  /// pessoa continua sem conseguir reler o que aceitou. Criar `/privacy` no
  /// site é passo do fundador; quando existir, é trocar esta linha.
  static const String privacyUrl = 'https://stageapp.lovable.app';

  /// Termos de uso. **Verificado em 30/07/2026**: renderiza o documento real,
  /// com 11 seções e data de atualização de 11/02/2026.
  static const String termsUrl = 'https://stageapp.lovable.app/terms';

  /// Política da OpenAI — citada no consentimento de IA porque é o terceiro
  /// que recebe os dados.
  static const String openAiPrivacyUrl =
      'https://openai.com/policies/privacy-policy';

  /// Suporte. O e-mail publicado nos Termos é `suporte@stagehq.com.br`; aqui
  /// fica a home, que é o que o modal de consentimento já abria.
  static const String supportUrl = 'https://stageapp.lovable.app';
}
