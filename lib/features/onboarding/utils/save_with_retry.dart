// saveWithRetry — wrapper das operações de save do onboarding com retry
// automático e feedback visual em caso de falha.
//
// Antes deste helper, cada tela do onboarding fazia `await vm.commit(...)`
// e navegava em seguida. Se o save falhasse silenciosamente (rede oscila,
// timeout, RLS), o user navegava normalmente e descobria dias depois que
// dados ficaram em branco no banco.
//
// Comportamento:
//   1. Executa a operação. Se completar → retorna true.
//   2. Se falhar: espera 800ms e tenta uma 2ª vez (silenciosa — cobre
//      falhas transient de rede mais comuns).
//   3. Se a 2ª também falhar → mostra SnackBar vermelho com mensagem
//      adaptada ao tipo do erro (network vs genérico) e retorna false.
//
// Caller deve abortar a navegação quando o retorno é false, mantendo o
// user na tela atual pra ele tocar Continuar de novo (retry manual).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

/// Executa [operation] com 1 retry silencioso (~800ms depois). Se ambas
/// tentativas falharem, mostra SnackBar pro user e retorna false.
///
/// Use o `mounted` check do State chamador APÓS este Future:
///   ```dart
///   final ok = await saveWithRetry(context: context, operation: ...);
///   if (!mounted) return;
///   if (!ok) return;          // erro já foi mostrado no SnackBar
///   Navigator.push(...);
///   ```
Future<bool> saveWithRetry({
  required BuildContext context,
  required Future<void> Function() operation,
}) async {
  // 1ª tentativa — silenciosa.
  try {
    await operation();
    return true;
  } catch (_) {
    // Cai pra retry. Não mostra nada ainda.
  }

  // Espera curta pra dar chance da rede voltar (falhas transient são
  // comuns em metrô/elevador). 800ms é o suficiente pra cobrir hiccups
  // sem segurar o user perceptivelmente.
  await Future.delayed(const Duration(milliseconds: 800));

  // 2ª tentativa — se falhar de novo, é persistente.
  try {
    await operation();
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    final message = _messageForError(e);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
    return false;
  }
}

/// Mensagem amigável pro user baseada no tipo do erro. Detecta os 3
/// padrões mais comuns:
///   - SocketException + variantes textuais  → "Sem conexão"
///   - TimeoutException                      → "Conexão lenta"
///   - Resto                                 → mensagem genérica
String _messageForError(Object e) {
  if (e is SocketException) {
    return 'Sem conexão. Verifique sua internet.';
  }
  if (e is TimeoutException) {
    return 'Conexão lenta. Verifique sua internet.';
  }
  // Mensagens de erro do Supabase/PostgREST passam pelo .toString() e
  // costumam vir como strings genéricas. Olhamos por palavras-chave
  // que indicam problema de rede vs lógica.
  final msg = e.toString().toLowerCase();
  if (msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('network is unreachable') ||
      msg.contains('connection refused') ||
      msg.contains('connection closed') ||
      msg.contains('connection reset')) {
    return 'Sem conexão. Verifique sua internet.';
  }
  if (msg.contains('timeout') || msg.contains('timed out')) {
    return 'Conexão lenta. Verifique sua internet.';
  }
  return 'Não consegui salvar. Tente de novo.';
}
