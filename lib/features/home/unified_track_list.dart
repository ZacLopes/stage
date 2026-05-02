import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/models.dart';
import '../gamification/question_screen.dart';
import 'home_viewmodel.dart';

class UnifiedTrackList extends StatelessWidget {
  final List<Track> tracks;
  final Map<String, List<Phase>> phasesByTrack;

  const UnifiedTrackList({
    super.key,
    required this.tracks,
    required this.phasesByTrack,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final phases = phasesByTrack[track.id] ?? [];

        return _WorldSection(
          track: track,
          phases: phases,
          isFirst: index == 0,
        );
      },
    );
  }
}

class _WorldSection extends StatelessWidget {
  final Track track;
  final List<Phase> phases;
  final bool isFirst;

  const _WorldSection({
    required this.track,
    required this.phases,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // World Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(track.color), Color(track.color).withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              Text(
                track.title.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  letterSpacing: 1.2,
                  fontFamily: 'Outfit',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                track.description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  fontFamily: 'Inter',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        
        // Stages Path
        if (phases.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: Text('Em breve...')),
          )
        else
          _StagesPath(phases: phases, trackColor: Color(track.color)),
      ],
    );
  }
}

class _StagesPath extends StatelessWidget {
  final List<Phase> phases;
  final Color trackColor;

  const _StagesPath({required this.phases, required this.trackColor});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeViewModel>(
      builder: (context, viewModel, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // Path Line
                Positioned.fill(
                  child: CustomPaint(
                    painter: _UnifiedPathPainter(
                      itemCount: phases.length,
                      itemHeight: 120.0,
                      centerOffset: constraints.maxWidth / 2,
                      amplitude: 70.0,
                      color: trackColor.withOpacity(0.3),
                    ),
                  ),
                ),
                // Nodes
                Column(
                  children: List.generate(phases.length, (index) {
                    final phase = phases[index];
                    final double xOffset = sin(index * 0.8) * 70.0;

                    final isCompleted = viewModel.isPhaseCompleted(phase.id);
                    bool isLocked = true;
                    if (index == 0) {
                      isLocked = false;
                    } else {
                      final prevPhase = phases[index - 1];
                      if (viewModel.isPhaseCompleted(prevPhase.id)) {
                        isLocked = false;
                      }
                    }

                    return Container(
                      height: 120.0,
                      alignment: Alignment.center,
                      child: Transform.translate(
                        offset: Offset(xOffset, 0),
                        child: _StageNode(
                          phase: phase,
                          index: index,
                          color: trackColor,
                          isLocked: isLocked,
                          isCompleted: isCompleted,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _StageNode extends StatelessWidget {
  final Phase phase;
  final int index;
  final Color color;
  final bool isLocked;
  final bool isCompleted;

  const _StageNode({
    required this.phase,
    required this.index,
    required this.color,
    required this.isLocked,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            if (isLocked) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Complete a fase anterior primeiro!'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuestionScreen(phase: phase),
                ),
              );
            }
          },
          child: Opacity(
            opacity: isLocked ? 0.6 : 1.0,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isLocked ? const Color(0xFFE5E7EB) : color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: isLocked
                        ? const Color(0xFF9CA3AF)
                        : color.withOpacity(0.6),
                    blurRadius: 0,
                    offset: const Offset(0, 6), // Hard shadow for 3D effect
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.5),
                  width: 4,
                ),
              ),
              child: Stack(
                children: [
                  // Inner highlight
                  Positioned(
                    top: 10,
                    left: 15,
                    child: Container(
                      width: 20,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: const BorderRadius.all(Radius.elliptical(20, 10)),
                      ),
                    ),
                  ),
                  Center(
                    child: isCompleted
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 48,
                          )
                        : isLocked
                            ? const Icon(
                                Icons.lock,
                                color: Color(0xFF9CA3AF),
                                size: 32,
                              )
                            : const Icon(
                                Icons.star, // Generic icon for phases
                                color: Colors.white,
                                size: 40,
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            phase.title.split(' ').skip(1).join(' '),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: isLocked ? const Color(0xFF9CA3AF) : const Color(0xFF374151),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _UnifiedPathPainter extends CustomPainter {
  final int itemCount;
  final double itemHeight;
  final double centerOffset;
  final double amplitude;
  final Color color;

  _UnifiedPathPainter({
    required this.itemCount,
    required this.itemHeight,
    required this.centerOffset,
    required this.amplitude,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..strokeCap = StrokeCap.round;

    final path = Path();

    for (int i = 0; i < itemCount - 1; i++) {
      final double currentPhase = i * 0.8;
      final double nextPhase = (i + 1) * 0.8;

      final double startX = centerOffset + sin(currentPhase) * amplitude;
      final double startY = (i * itemHeight) + (itemHeight / 2);

      final double endX = centerOffset + sin(nextPhase) * amplitude;
      final double endY = ((i + 1) * itemHeight) + (itemHeight / 2);

      if (i == 0) {
        path.moveTo(startX, startY);
      }

      final double controlPointY = startY + (endY - startY) / 2;
      
      path.cubicTo(
        startX, controlPointY, 
        endX, controlPointY, 
        endX, endY
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
