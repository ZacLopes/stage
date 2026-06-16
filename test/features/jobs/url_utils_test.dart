import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/jobs/utils/url_utils.dart';

/// FASE 3 T3.4 (R3): UTM na saída externa. Regra: só http(s); mailto intacto;
/// preserva query/UTM da fonte; sem duplicar.
void main() {
  group('decorateOutboundUrl', () {
    test('mailto passa intacto (sem UTM)', () {
      final uri = Uri.parse('mailto:rh@empresa.com?subject=Vaga%20X');
      expect(decorateOutboundUrl(uri).toString(),
          'mailto:rh@empresa.com?subject=Vaga%20X');
    });

    test('http(s) ganha os 3 UTM preservando a query existente', () {
      final out = decorateOutboundUrl(
          Uri.parse('https://jobs.gupy.io/vaga/123?src=abc'));
      expect(out.scheme, 'https');
      expect(out.host, 'jobs.gupy.io');
      expect(out.queryParameters['src'], 'abc');
      expect(out.queryParameters['utm_source'], 'stage');
      expect(out.queryParameters['utm_medium'], 'app');
      expect(out.queryParameters['utm_campaign'], 'job_apply');
    });

    test('URL sem query ganha os UTM', () {
      final out = decorateOutboundUrl(Uri.parse('https://empresa.com/carreiras'));
      expect(out.queryParameters['utm_source'], 'stage');
      expect(out.queryParameters['utm_campaign'], 'job_apply');
    });

    test('não duplica UTM já presente (putIfAbsent preserva)', () {
      final out = decorateOutboundUrl(
          Uri.parse('https://x.com/a?utm_source=parceiro'));
      expect(out.queryParameters['utm_source'], 'parceiro'); // preserva fonte
      expect(out.queryParameters['utm_medium'], 'app');
    });

    test('preserva o fragment', () {
      final out =
          decorateOutboundUrl(Uri.parse('https://x.com/a?b=1#secao'));
      expect(out.fragment, 'secao');
      expect(out.queryParameters['utm_source'], 'stage');
    });
  });

  group('isTrackableOutbound', () {
    test('http/https são rastreáveis', () {
      expect(isTrackableOutbound(Uri.parse('https://x.com')), isTrue);
      expect(isTrackableOutbound(Uri.parse('http://x.com')), isTrue);
    });
    test('mailto não é rastreável', () {
      expect(isTrackableOutbound(Uri.parse('mailto:a@b.com')), isFalse);
    });
  });
}
