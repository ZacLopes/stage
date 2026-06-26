import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/trilha/application/linkedin_url.dart';

/// Normalização leve do LinkedIn: garante https, monta vanity, e NUNCA descarta
/// (perder o dado é pior que um link levemente fora do padrão).
void main() {
  test('vazio → null', () {
    expect(normalizeLinkedinUrl(''), isNull);
    expect(normalizeLinkedinUrl('   '), isNull);
  });

  test('URL completa do linkedin é mantida', () {
    expect(normalizeLinkedinUrl('https://www.linkedin.com/in/joao'),
        'https://www.linkedin.com/in/joao');
  });

  test('sem https mas com linkedin.com → prefixa https', () {
    expect(normalizeLinkedinUrl('linkedin.com/in/joao'),
        'https://linkedin.com/in/joao');
    expect(normalizeLinkedinUrl('www.linkedin.com/in/maria'),
        'https://www.linkedin.com/in/maria');
  });

  test('/company e m.linkedin.com (permissivo) são aceitos', () {
    expect(normalizeLinkedinUrl('linkedin.com/company/stage'),
        'https://linkedin.com/company/stage');
    expect(normalizeLinkedinUrl('https://m.linkedin.com/in/x'),
        'https://m.linkedin.com/in/x');
  });

  test('handle/vanity sem domínio monta /in/', () {
    expect(normalizeLinkedinUrl('joao-silva'),
        'https://linkedin.com/in/joao-silva');
    expect(normalizeLinkedinUrl('in/joao'), 'https://linkedin.com/in/joao');
    expect(normalizeLinkedinUrl('/in/joao'), 'https://linkedin.com/in/joao');
  });

  test('texto não reconhecido é guardado cru (não descarta)', () {
    expect(normalizeLinkedinUrl('meu perfil é o joao'), 'meu perfil é o joao');
  });
}
