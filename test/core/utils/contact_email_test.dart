import 'package:career_gamification/core/utils/contact_email.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContactEmail', () {
    test('normaliza e valida um contato comum', () {
      expect(
        ContactEmail.normalize('  Pessoa@Example.COM '),
        'pessoa@example.com',
      );
      expect(ContactEmail.isUsable('Pessoa@Example.COM'), isTrue);
    });

    test('detecta os dois domínios exatos do Apple Private Relay', () {
      expect(
        ContactEmail.isApplePrivateRelay('abc@privaterelay.appleid.com'),
        isTrue,
      );
      expect(
        ContactEmail.isApplePrivateRelay('abc@private.icloud.com'),
        isTrue,
      );
      expect(
        ContactEmail.isApplePrivateRelay('abc@sub.private.icloud.com'),
        isFalse,
      );
      expect(ContactEmail.isUsable('abc@private.icloud.com'), isFalse);
    });

    test('não confunde um e-mail pessoal do iCloud com Private Relay', () {
      expect(ContactEmail.isApplePrivateRelay('pessoa@icloud.com'), isFalse);
      expect(ContactEmail.isUsable('pessoa@icloud.com'), isTrue);
    });

    test('detecta endereço sintético do login por telefone', () {
      expect(
        ContactEmail.isSyntheticAuthEmail('phone_5511987654321@stage.app'),
        isTrue,
      );
      expect(ContactEmail.isUsable('phone_5511987654321@stage.app'), isFalse);
      expect(ContactEmail.isSyntheticAuthEmail('pessoa@stage.app'), isFalse);
    });

    test('rejeita formatos inválidos', () {
      expect(ContactEmail.isUsable('sem-arroba.example.com'), isFalse);
      expect(ContactEmail.isUsable('a@@example.com'), isFalse);
      expect(ContactEmail.resumeValueOrEmpty('invalido'), isEmpty);
    });

    test('resolve perfil, extração e autenticação nessa ordem', () {
      expect(
        ContactEmail.resolveInitial(
          profileEmail: 'perfil@example.com',
          extractedEmail: 'cv@example.com',
          authEmail: 'login@example.com',
        ),
        'perfil@example.com',
      );

      expect(
        ContactEmail.resolveInitial(
          profileEmail: 'relay@privaterelay.appleid.com',
          extractedEmail: 'CV@Example.com',
          authEmail: 'login@example.com',
        ),
        'cv@example.com',
      );

      expect(
        ContactEmail.resolveInitial(
          profileEmail: 'phone_5511999999999@stage.app',
          extractedEmail: 'invalido',
          authEmail: 'relay@private.icloud.com',
        ),
        isEmpty,
      );
    });
  });
}
