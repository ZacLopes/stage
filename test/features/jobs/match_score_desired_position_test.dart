import 'package:flutter_test/flutter_test.dart';

import 'package:career_gamification/features/jobs/models/job.dart';
import 'package:career_gamification/features/jobs/models/user_preferences.dart';
import 'package:career_gamification/features/jobs/utils/match_score.dart';

/// A4 (R3): bônus de cargo desejado no match determinístico. Aditivo pequeno
/// (+8) PÓS-normalização — não é dimensão de peso. Espelha o prompt da IA.
Job _job({required String title, String area = 'Tecnologia'}) => Job(
      id: 'j1',
      title: title,
      companyName: 'Acme',
      companyLogoUrl: '',
      location: 'São Paulo',
      salaryRange: '—',
      workModel: 'Remoto',
      jobType: 'Estágio',
      matchScore: 0,
      description: '',
      requirements: const [],
      benefits: const [],
      aboutCompany: '',
      postedDaysAgo: '0',
      area: area,
      jobTypeRaw: 'clt', // não bate com prefs.jobTypes (estagio) de propósito
      workModelRaw: 'remoto',
    );

// Só área + tipo declarados; área bate (30), tipo não (0) → normalizado 60.
// Sobra espaço pro bônus aparecer (60 + 8 = 68).
UserJobPreferences _prefs({String? desiredPosition}) => UserJobPreferences(
      userId: 'u1',
      areas: const ['Tecnologia'],
      jobTypes: const ['estagio'],
      desiredPosition: desiredPosition,
    );

void main() {
  group('MatchScoreCalculator — bônus de cargo desejado', () {
    test('base sem cargo declarado: 60, sem reason de cargo', () {
      final r = MatchScoreCalculator.calculate(
        job: _job(title: 'Desenvolvedor Front-end Júnior'),
        prefs: _prefs(),
      );
      expect(r.score, 60);
      expect(r.reasons.any((x) => x.label == 'Cargo desejado'), isFalse);
    });

    test('cargo bate com o título → +8 (68) e reason informativa (weight 0)', () {
      final r = MatchScoreCalculator.calculate(
        job: _job(title: 'Desenvolvedor Front-end Júnior'),
        prefs: _prefs(desiredPosition: 'Desenvolvedor Front-end'),
      );
      expect(r.score, 68);
      final bonus =
          r.reasons.firstWhere((x) => x.label == 'Cargo desejado');
      expect(bonus.matched, isTrue);
      expect(bonus.weight, 0, reason: 'bônus, não dimensão ponderada');
    });

    test('tolera variação de gênero/nível (Desenvolvedora … Pleno)', () {
      final r = MatchScoreCalculator.calculate(
        job: _job(title: 'Desenvolvedora Front-End Pleno'),
        prefs: _prefs(desiredPosition: 'Desenvolvedor Front-end'),
      );
      expect(r.score, 68);
    });

    test('cargo NÃO bate → sem bônus (60)', () {
      final r = MatchScoreCalculator.calculate(
        job: _job(title: 'Analista Financeiro Júnior'),
        prefs: _prefs(desiredPosition: 'Desenvolvedor Front-end'),
      );
      expect(r.score, 60);
      expect(r.reasons.any((x) => x.label == 'Cargo desejado'), isFalse);
    });

    test('não cria match sozinho: score base 0 não ganha bônus', () {
      // Área não bate → normalizado 0; bônus só entra quando já há score > 0.
      final r = MatchScoreCalculator.calculate(
        job: _job(title: 'Desenvolvedor Front-end Júnior', area: 'Jurídico'),
        prefs: _prefs(desiredPosition: 'Desenvolvedor Front-end'),
      );
      expect(r.score, 0);
      expect(r.reasons.any((x) => x.label == 'Cargo desejado'), isFalse);
    });

    // ── Anti-espalhamento (achado #1/#2 da revisão A4): um cargo genérico de
    // 1 palavra NÃO pode dar bônus pra toda vaga que contém aquela palavra.
    test('cargo genérico NÃO espalha: "Analista" ≠ "Analista de Marketing"', () {
      for (final title in [
        'Analista de Marketing',
        'Analista de RH',
        'Analista Financeiro Júnior',
        'Analista de Dados',
      ]) {
        final r = MatchScoreCalculator.calculate(
          job: _job(title: title),
          prefs: _prefs(desiredPosition: 'Analista'),
        );
        expect(r.score, 60, reason: '"$title" não devia ganhar bônus');
        expect(r.reasons.any((x) => x.label == 'Cargo desejado'), isFalse);
      }
    });

    test('cargo específico não casa especialização diferente: '
        '"Analista de Dados" ≠ "Analista de Marketing"', () {
      final r = MatchScoreCalculator.calculate(
        job: _job(title: 'Analista de Marketing'),
        prefs: _prefs(desiredPosition: 'Analista de Dados'),
      );
      expect(r.score, 60);
    });

    test('cargo genérico casa o mesmo papel só com senioridade: '
        '"Analista" = "Analista Júnior"', () {
      final r = MatchScoreCalculator.calculate(
        job: _job(title: 'Analista Júnior'),
        prefs: _prefs(desiredPosition: 'Analista'),
      );
      expect(r.score, 68);
    });

    test('especialização curta (≥2 letras) é preservada: '
        '"Designer UX" = "Designer UX Júnior", ≠ "Designer Gráfico"', () {
      final match = MatchScoreCalculator.calculate(
        job: _job(title: 'Designer UX Júnior'),
        prefs: _prefs(desiredPosition: 'Designer UX'),
      );
      expect(match.score, 68);
      final noMatch = MatchScoreCalculator.calculate(
        job: _job(title: 'Designer Gráfico'),
        prefs: _prefs(desiredPosition: 'Designer UX'),
      );
      expect(noMatch.score, 60);
    });

    test('abreviação não-prefixo NÃO casa (fail-safe, sem falso positivo): '
        '"Dev" ↛ "Desenvolvedor Júnior"', () {
      // "dev" não é prefixo de "desenvolvedor" (des…) — sem alias map, não casa.
      // Preferimos não dar bônus a dar bônus errado.
      final r = MatchScoreCalculator.calculate(
        job: _job(title: 'Desenvolvedor Júnior'),
        prefs: _prefs(desiredPosition: 'Dev'),
      );
      expect(r.score, 60);
    });

    test('cargo vazio/whitespace → sem bônus', () {
      for (final dp in ['', '   ']) {
        final r = MatchScoreCalculator.calculate(
          job: _job(title: 'Desenvolvedor Front-end Júnior'),
          prefs: _prefs(desiredPosition: dp),
        );
        expect(r.score, 60);
      }
    });
  });
}
