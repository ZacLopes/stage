// Projeção ÚNICA do perfil canônico para os modelos consumidos pelos
// templates de currículo. Tanto ProfileSnapshot quanto ProfilePdfData passam
// por este mapper para não haver duas regras diferentes de apresentação.

import '../../../data/models/models.dart' show ResumeAward, ResumeProject;
import '../../profile/domain/entities/entities.dart';
import '../../profile/domain/profile_title.dart';
import '../resume_viewmodel.dart' show EducationItem;

class ProfileResumeMapper {
  ProfileResumeMapper._();

  /// Education → EducationItem, com vocabulário natural em PT-BR.
  ///
  /// Casos protegidos:
  /// - degree="Administração" + major="Administração" aparece UMA vez;
  /// - degree="Bacharelado" + major="Administração" vira
  ///   "Bacharelado em Administração";
  /// - degree vazio promove o primeiro major a título;
  /// - nunca injeta os sufixos artificiais ingleses "Major"/"Minor".
  static EducationItem mapEducation(Education education) {
    final qualification = _educationQualification(education);
    final activities = _orderedDistinct(
      education.activities,
      (item) => item.text,
      (item) => item.orderIndex,
      normalizeTitle: false,
    );

    final detailParts = <String>[];
    if (qualification.remainingMajors.isNotEmpty) {
      detailParts.add(
        qualification.remainingMajors.length == 1
            ? 'Ênfase em ${qualification.remainingMajors.first}'
            : 'Ênfases em ${qualification.remainingMajors.join(', ')}',
      );
    }
    if (qualification.minors.isNotEmpty) {
      detailParts.add(
        'Formação complementar em ${qualification.minors.join(', ')}',
      );
    }

    return EducationItem(
      degree: qualification.title,
      institution: education.institution.trim(),
      period: education.formattedPeriod,
      details: detailParts.join(' · '),
      location: (education.location ?? '').trim(),
      gpa: _formatGpa(education.gpa, education.maxGpa),
      // `activities` é a representação canônica atual. Não a duplica em
      // `honors`, que existe apenas como fallback de currículos legados.
      honors: '',
      repRole: '',
      coursework: '',
      activities: activities,
    );
  }

  /// Rótulo profissional curto usado fora do PDF (ex.: card do Perfil).
  /// Mantém exatamente a mesma deduplicação degree/major do currículo.
  static String formatEducationQualification(Education education) =>
      _educationQualification(education).title;

  /// Um projeto precisa de uma âncora textual primária. Contexto sozinho é
  /// metadado secundário e não deve abrir uma seção vazia nos templates.
  static bool projectHasRenderableText(Project project) =>
      project.name.trim().isNotEmpty ||
      (project.role ?? '').trim().isNotEmpty ||
      (project.description ?? '').trim().isNotEmpty ||
      project.bullets.any((bullet) => bullet.text.trim().isNotEmpty);

  static ResumeProject mapProject(Project project) {
    final bulletsText = project.bullets
        .where((bullet) => bullet.text.trim().isNotEmpty)
        .map((bullet) => bullet.text.trim())
        .join('\n');
    final fallback = (project.description ?? '').trim();
    return ResumeProject(
      title: normalizeProfileTitle(project.name),
      role: (project.role ?? '').trim(),
      period: _formatProjectPeriod(
        project.startDate,
        project.endDate,
        project.isCurrent,
      ),
      description: bulletsText.isNotEmpty ? bulletsText : fallback,
      location: '',
      relevantWork: (project.context ?? '').trim(),
    );
  }

  static ResumeAward mapAward(Award award) => ResumeAward(
    title: normalizeProfileTitle(award.name),
    institution: '',
    date: award.date != null ? award.date!.year.toString() : '',
    description: '',
  );

  static List<String> _orderedDistinct<T>(
    List<T> source,
    String Function(T item) textOf,
    int Function(T item) orderOf, {
    bool normalizeTitle = true,
  }) {
    final ordered = source.toList()
      ..sort((a, b) => orderOf(a).compareTo(orderOf(b)));
    final seen = <String>{};
    final result = <String>[];
    for (final item in ordered) {
      final raw = textOf(item).trim();
      if (raw.isEmpty) continue;
      final key = _fold(raw);
      if (key.isEmpty || !seen.add(key)) continue;
      result.add(normalizeTitle ? normalizeProfileTitle(raw) : raw);
    }
    return result;
  }

  static ({String title, List<String> remainingMajors, List<String> minors})
  _educationQualification(Education education) {
    final degree = normalizeProfileTitle(education.degree ?? '');
    final majors = _orderedDistinct(
      education.majors,
      (item) => item.name,
      (item) => item.orderIndex,
    );
    final minors = _orderedDistinct(
      education.minors,
      (item) => item.name,
      (item) => item.orderIndex,
    );

    var title = degree;
    var consumedMajors = 0;
    if (majors.isNotEmpty) {
      final primaryMajor = majors.first;
      if (title.isEmpty) {
        title = primaryMajor;
        consumedMajors = 1;
      } else if (_academicLabelsEquivalent(title, primaryMajor)) {
        // O extrator pode repetir o curso em degree e majors. Preserva a forma
        // mais completa (normalmente degree) e descarta apenas a repetição.
        consumedMajors = 1;
      } else if (_isGenericCredential(title)) {
        title = '$title em $primaryMajor';
        consumedMajors = 1;
      }
    }

    return (
      title: title,
      remainingMajors: majors.skip(consumedMajors).toList(growable: false),
      minors: minors,
    );
  }

  static bool _academicLabelsEquivalent(String left, String right) {
    final a = _fold(left);
    final b = _fold(right);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final subjectA = _academicSubject(a);
    final subjectB = _academicSubject(b);
    return subjectA.isNotEmpty && subjectA == subjectB;
  }

  static bool _isGenericCredential(String value) {
    final folded = _fold(value);
    return folded.isNotEmpty && _academicSubject(folded).isEmpty;
  }

  static String _academicSubject(String folded) {
    const credentialWords = <String>{
      'bacharelado',
      'bacharel',
      'bachelor',
      'bachelors',
      'degree',
      'graduacao',
      'undergraduate',
      'licenciatura',
      'licenciado',
      'tecnologo',
      'technologist',
      'tecnico',
      'technical',
      'mba',
      'mestrado',
      'master',
      'masters',
      'msc',
      'doutorado',
      'doctorate',
      'doctoral',
      'phd',
      'curso',
      'superior',
      'em',
      'in',
      'of',
    };
    return folded
        .split(' ')
        .where((word) => word.isNotEmpty && !credentialWords.contains(word))
        .join(' ');
  }

  static String _fold(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâãä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôõö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _formatGpa(double? gpa, double? maxGpa) {
    if (gpa == null) return '';
    final value = _formatNumber(gpa);
    return maxGpa == null ? value : '$value/${_formatNumber(maxGpa)}';
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _formatProjectPeriod(
    DateTime? start,
    DateTime? end,
    bool isCurrent,
  ) {
    if (start == null && end == null) return '';
    final startText = start != null ? _formatMonthYear(start) : '';
    if (isCurrent) {
      return startText.isEmpty ? 'Atual' : '$startText - Atual';
    }
    if (end == null) return startText;
    final endText = _formatMonthYear(end);
    return startText.isEmpty ? endText : '$startText - $endText';
  }

  static String _formatMonthYear(DateTime date) {
    const months = <String>[
      '',
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    return '${months[date.month]} ${date.year}';
  }
}
