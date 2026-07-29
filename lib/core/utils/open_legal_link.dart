import 'package:url_launcher/url_launcher.dart';

/// Abre um documento legal no navegador externo.
///
/// Um único caminho pra cadastro, Configurações e consentimento de IA — antes
/// cada tela tinha (ou não tinha) o seu. `mode: externalApplication` porque é
/// documento pra ler com calma, e não deve ficar preso num webview do app.
///
/// Falha silenciosa é deliberada: sem navegador disponível não há o que
/// oferecer ao usuário, e um snackbar de erro aqui não ajuda ninguém.
Future<void> openLegalLink(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
