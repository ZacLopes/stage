// Fase 7 · gate-list +10 (Tarefa 1): o export da aba Currículo (trilha de IA)
// monta o CV a partir do ProfileSnapshot (tabelas profile_*), não do
// resumeVM.resumeData legado (gamificação desligada), que vinha vazio e gerava
// PDF em branco. Este teste cobre o caso que quebrava: perfil "esqueleto" — só
// personal + skills, sem experiência nem educação. No fluxo antigo,
// ProfilePdfData.load retornaria null (critério "sem exp+edu") e o export caía
// num ResumeData vazio; agora usa snapshot.toResumeData, que mapeia o que há.
import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/services/profile_snapshot_service.dart';
import 'package:career_gamification/features/profile/domain/entities/entities.dart';

void main() {
  test('toResumeData: perfil esqueleto (só skills) vira CV não-vazio', () {
    const snap = ProfileSnapshot(
      personal: PersonalInfo(
        userId: 'u1',
        firstName: 'Maria',
        lastName: 'Souza',
        email: 'maria@ex.com',
        summary: 'Estudante de ADM focada em finanças.',
      ),
      skills: [
        Skill(id: 's1', userId: 'u1', name: 'Excel'),
        Skill(id: 's2', userId: 'u1', name: 'Power BI'),
      ],
    );

    // Sem experiência nem educação: no fluxo antigo daria PDF vazio. O snapshot
    // NÃO é vazio e monta um CV com o que a trilha coletou.
    expect(snap.isEmpty, isFalse);
    expect(snap.experiences, isEmpty);
    expect(snap.education, isEmpty);

    final resume = snap.toResumeData(userFallbackName: 'Maria Souza');
    expect(resume.fullName, 'Maria Souza');
    expect(resume.email, 'maria@ex.com');
    expect(resume.summary, contains('finanças'));
    expect(resume.skills, containsAll(<String>['Excel', 'Power BI']));
  });

  test('toResumeData: cai no userFallbackName quando personal não tem nome', () {
    const snap = ProfileSnapshot(
      personal: PersonalInfo(userId: 'u2'),
      skills: [Skill(id: 's1', userId: 'u2', name: 'Python')],
    );
    final resume = snap.toResumeData(userFallbackName: 'João Lima');
    expect(resume.fullName, 'João Lima');
    expect(resume.skills, contains('Python'));
  });
}
