/// Decoração de URL de saída com UTM da Stage (FASE 3 T3.4, auditoria H2).
///
/// Regra (PLANO-FASE-3 §4/D3): anexa `utm_source=stage&utm_medium=app&
/// utm_campaign=job_apply` SÓ em links http(s); `mailto:` e qualquer outro
/// scheme passam intactos. `putIfAbsent` preserva query/UTM já existentes na
/// URL da fonte. Pura e defensiva — usada no único call site de apply
/// (liked_jobs_screen::_openApplication, branch url).
Uri decorateOutboundUrl(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return uri; // mailto/etc intactos
  final qp = Map<String, String>.from(uri.queryParameters)
    ..putIfAbsent('utm_source', () => 'stage')
    ..putIfAbsent('utm_medium', () => 'app')
    ..putIfAbsent('utm_campaign', () => 'job_apply');
  return uri.replace(queryParameters: qp);
}

/// `true` se a URL é um link externo http(s) rastreável (gera `outbound_clicks`
/// e o evento de saída). `false` pra mailto e schemes não-web.
bool isTrackableOutbound(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}
