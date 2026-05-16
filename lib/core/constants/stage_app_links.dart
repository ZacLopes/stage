/// URLs públicas das lojas onde o Stage é distribuído.
///
/// Usadas em pontos de compartilhamento (ex: share de vaga, convite de
/// amigos) pra direcionar quem recebe o link pra instalar o app.
///
/// IMPORTANTE: mantenha em sincronia com `app_config.ios_store_url` e
/// `app_config.android_store_url` no Supabase (a tabela é fonte de verdade
/// pra force-update; estas constantes são usadas em shares one-off pra
/// evitar network round-trip).
class StageAppLinks {
  StageAppLinks._();

  /// Link do app na App Store (iOS).
  static const String appStoreUrl =
      'https://apps.apple.com/br/app/stage/id6755893277';

  /// Link do app na Play Store (Android). NULL hoje — Stage ainda não tem
  /// release Android. Quando tiver, definir aqui e atualizar shareCallToAction.
  static const String? playStoreUrl = null;

  /// Texto curto pra append em compartilhamentos, com call-to-action.
  /// Usa o link da App Store (Stage só tem release iOS por enquanto).
  static const String shareCallToAction =
      '📲 Baixe o Stage:\n$appStoreUrl';
}
