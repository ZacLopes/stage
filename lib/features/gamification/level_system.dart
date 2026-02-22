class LevelInfo {
  final int level;
  final int minXP;
  final String title;
  final String reward;

  const LevelInfo({
    required this.level,
    required this.minXP,
    required this.title,
    required this.reward,
  });
}

class LevelSystem {
  static const List<LevelInfo> _levels = [
    LevelInfo(level: 1, minXP: 0, title: 'Novato Curioso', reward: 'Templates Básico & Clean'),
    LevelInfo(level: 2, minXP: 100, title: 'Novato Curioso', reward: ''),
    LevelInfo(level: 3, minXP: 201, title: 'Explorador', reward: 'Template Moderno'),
    LevelInfo(level: 4, minXP: 350, title: 'Explorador', reward: ''),
    LevelInfo(level: 5, minXP: 501, title: 'Aprendiz Ágil', reward: 'Exportação Word (DOCX)'),
    LevelInfo(level: 6, minXP: 700, title: 'Aprendiz Ágil', reward: ''),
    LevelInfo(level: 7, minXP: 901, title: 'Protagonista', reward: 'Template Criativo'),
    LevelInfo(level: 8, minXP: 1050, title: 'Protagonista', reward: ''),
    LevelInfo(level: 9, minXP: 1200, title: 'Protagonista', reward: ''),
    LevelInfo(level: 10, minXP: 1401, title: 'Visionário', reward: 'Mundo Secreto'),
    LevelInfo(level: 11, minXP: 1650, title: 'Visionário', reward: ''),
    LevelInfo(level: 12, minXP: 1901, title: 'Estrategista', reward: 'Template Executivo'),
    LevelInfo(level: 13, minXP: 2100, title: 'Estrategista', reward: ''),
    LevelInfo(level: 14, minXP: 2300, title: 'Estrategista', reward: ''),
    LevelInfo(level: 15, minXP: 2501, title: 'Lenda do Estágio', reward: 'Link Web (Em breve)'),
  ];

  static List<LevelInfo> get levels => _levels;

  static LevelInfo getLevelInfo(int xp) {
    for (int i = _levels.length - 1; i >= 0; i--) {
      if (xp >= _levels[i].minXP) {
        return _levels[i];
      }
    }
    return _levels[0];
  }

  static LevelInfo getNextLevelInfo(int currentLevel) {
    if (currentLevel >= _levels.length) {
      return _levels.last;
    }
    return _levels.firstWhere((info) => info.level > currentLevel, orElse: () => _levels.last);
  }

  static double getProgressToNextLevel(int xp) {
    final current = getLevelInfo(xp);
    final next = getNextLevelInfo(current.level);
    
    if (current.level == next.level) return 1.0; // Max level

    final range = next.minXP - current.minXP;
    final progress = xp - current.minXP;
    
    return (progress / range).clamp(0.0, 1.0);
  }

  static String getNextRewardDescription(int currentLevel) {
     for (final level in _levels) {
       if (level.level > currentLevel && level.reward.isNotEmpty) {
         return '${level.reward} (Nvl ${level.level})';
       }
     }
     return 'Você zerou o game!';
  }
}
