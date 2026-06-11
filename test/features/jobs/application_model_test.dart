import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/application.dart';

void main() {
  group('Application.fromJson', () {
    test('parseia row completa do banco', () {
      final app = Application.fromJson({
        'id': 'a1',
        'user_id': 'u1',
        'job_id': 'j1',
        'type': 'external_confirmed',
        'status': 'in_review',
        'application_method': 'email',
        'adapted_resume_id': null,
        'sla_deadline': '2026-06-17T00:00:00Z',
        'rejection_category': null,
        'notes': null,
        'external_company': null,
        'external_title': null,
        'created_at': '2026-06-10T12:00:00Z',
        'updated_at': '2026-06-10T13:00:00Z',
      });
      expect(app.type, ApplicationType.externalConfirmed);
      expect(app.status, ApplicationStatus.inReview);
      expect(app.status.countsAsApplied, isTrue);
      expect(app.slaDeadline, isNotNull);
    });

    test('status desconhecido degrada pra submitted (build futura)', () {
      final app = Application.fromJson({
        'id': 'a1',
        'user_id': 'u1',
        'job_id': 'j1',
        'type': 'stage',
        'status': 'algum_estado_novo',
        'created_at': '2026-06-10T12:00:00Z',
        'updated_at': '2026-06-10T12:00:00Z',
      });
      expect(app.status, ApplicationStatus.submitted);
      expect(app.type, ApplicationType.stage);
    });

    test('countsAsApplied: withdrawn/expired não contam, rejected conta', () {
      expect(ApplicationStatus.withdrawn.countsAsApplied, isFalse);
      expect(ApplicationStatus.expired.countsAsApplied, isFalse);
      expect(ApplicationStatus.rejected.countsAsApplied, isTrue);
      expect(ApplicationStatus.hired.countsAsApplied, isTrue);
    });
  });

  group('canTransition — espelho client da matriz (actor user)', () {
    test('pipeline avança e RETROCEDE por design (manual/external)', () {
      expect(
        canTransition(ApplicationType.manual, ApplicationStatus.submitted,
            ApplicationStatus.inReview),
        isTrue,
      );
      // Retrocesso offer→in_review é permitido POR DESIGN: o usuário
      // corrige erro no próprio tracker (decisão da revisão do arquiteto).
      expect(
        canTransition(ApplicationType.externalConfirmed,
            ApplicationStatus.offer, ApplicationStatus.inReview),
        isTrue,
      );
      expect(
        canTransition(ApplicationType.manual, ApplicationStatus.interview,
            ApplicationStatus.hired),
        isTrue,
      );
    });

    test('hired/expired são terminais', () {
      expect(
        canTransition(ApplicationType.manual, ApplicationStatus.hired,
            ApplicationStatus.inReview),
        isFalse,
      );
      expect(
        canTransition(ApplicationType.manual, ApplicationStatus.expired,
            ApplicationStatus.submitted),
        isFalse,
      );
    });

    test('reabertura: rejected/withdrawn → submitted (e só pra submitted)', () {
      expect(
        canTransition(ApplicationType.externalConfirmed,
            ApplicationStatus.rejected, ApplicationStatus.submitted),
        isTrue,
      );
      expect(
        canTransition(ApplicationType.manual, ApplicationStatus.withdrawn,
            ApplicationStatus.submitted),
        isTrue,
      );
      expect(
        canTransition(ApplicationType.manual, ApplicationStatus.rejected,
            ApplicationStatus.offer),
        isFalse,
      );
    });

    test('stage: user só pode withdrawn', () {
      expect(
        canTransition(ApplicationType.stage, ApplicationStatus.submitted,
            ApplicationStatus.withdrawn),
        isTrue,
      );
      expect(
        canTransition(ApplicationType.stage, ApplicationStatus.submitted,
            ApplicationStatus.inReview),
        isFalse,
      );
      expect(
        canTransition(ApplicationType.stage, ApplicationStatus.withdrawn,
            ApplicationStatus.submitted),
        isFalse, // reabertura de stage é só admin
      );
    });

    test('no-op é idempotente', () {
      expect(
        canTransition(ApplicationType.manual, ApplicationStatus.inReview,
            ApplicationStatus.inReview),
        isTrue,
      );
    });
  });
}
