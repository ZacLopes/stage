// auth_session.dart — guarda de sessão pros handlers de save.
//
// Antes deste helper, ~22 handlers de save liam o user id como
// `Supabase.instance.client.auth.currentUser?.id ?? ''`. Quando a sessão
// estava ausente, o `?? ''` injetava string vazia no campo user_id/id da
// query e o Postgres rejeitava como UUID inválido
// (`invalid input syntax for type uuid: ""`, code 22P02) — 67 ocorrências
// em 7 dias nos logs, todas com usuário não-identificado. Pior: nos modais
// de profile o save em lote falhava em silêncio (dados perdidos sem aviso).
//
// `currentUserIdOrNull()` substitui o antipattern: nunca devolve string
// vazia. `handleSessionLost()` é a recuperação padrão — avisa o usuário e
// desloga, deixando o AuthGate (Consumer<UserViewModel> em
// splash_screen.dart) re-rotear pro login sozinho.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/widgets.dart'; // AppSnackBar
import 'user_viewmodel.dart';

/// ID do usuário logado, ou `null` se não há sessão ativa.
///
/// NUNCA retorna string vazia — é o substituto direto do antipattern
/// `currentUser?.id ?? ''`. Use em todo handler de save:
///
/// ```dart
/// final userId = currentUserIdOrNull();
/// if (userId == null) {
///   // ignore: unawaited_futures
///   handleSessionLost(context);
///   return;
/// }
/// ```
String? currentUserIdOrNull() {
  final id = Supabase.instance.client.auth.currentUser?.id;
  return (id == null || id.isEmpty) ? null : id;
}

/// Recuperação de sessão perdida: avisa o usuário e faz logout.
///
/// O logout dispara `AuthChangeEvent.signedOut`, que o [UserViewModel]
/// escuta e propaga via `notifyListeners()`. O `AuthGate`
/// (`Consumer<UserViewModel>` em splash_screen.dart) então re-rota pro login
/// automaticamente. A navegação aqui é SÓ pop (`popUntil isFirst`) pra
/// revelar o AuthGate já reconstruído — nunca push manual, então não viola
/// o invariante de GlobalKey do AuthGate.
Future<void> handleSessionLost(BuildContext context) async {
  AppSnackBar.error(context, 'Sua sessão expirou. Entre novamente.');
  await context.read<UserViewModel>().logout();
  if (context.mounted) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
