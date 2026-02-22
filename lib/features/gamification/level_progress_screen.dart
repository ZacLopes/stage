import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'level_system.dart';

class LevelProgressScreen extends StatelessWidget {
  final int currentLevel;
  final int currentXP;

  const LevelProgressScreen({
    super.key,
    required this.currentLevel,
    required this.currentXP,
  });

  @override
  Widget build(BuildContext context) {
    final levels = LevelSystem.levels;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          'Níveis e Recompensas',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF4F46E5),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: levels.length,
        itemBuilder: (context, index) {
          final levelInfo = levels[index];
          final isCurrentLevel = levelInfo.level == currentLevel;
          final isUnlocked = levelInfo.level <= currentLevel;
          final isNext = levelInfo.level == currentLevel + 1;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: isCurrentLevel ? 4 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: isCurrentLevel 
                  ? const BorderSide(color: Color(0xFF4F46E5), width: 2)
                  : BorderSide.none,
            ),
            color: isUnlocked ? Colors.white : Colors.grey[100],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Level Badge
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isUnlocked 
                          ? (isCurrentLevel ? const Color(0xFF4F46E5) : const Color(0xFF10B981))
                          : Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${levelInfo.level}',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          levelInfo.title,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isUnlocked ? const Color(0xFF111827) : Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'XP Necessário: ${levelInfo.minXP}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (levelInfo.reward.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isUnlocked ? const Color(0xFFEEF2FF) : Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.card_giftcard, 
                                  size: 14, 
                                  color: isUnlocked ? const Color(0xFF4F46E5) : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    levelInfo.reward,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: isUnlocked ? const Color(0xFF4F46E5) : Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Status Icon
                  if (isCurrentLevel)
                    const Icon(Icons.star, color: Color(0xFFF59E0B))
                  else if (isUnlocked)
                    const Icon(Icons.check_circle, color: Color(0xFF10B981))
                  else
                    const Icon(Icons.lock, color: Colors.grey),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
