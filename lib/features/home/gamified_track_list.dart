import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:provider/provider.dart';
import '../../data/models/models.dart';
import '../gamification/world_screen.dart';
import 'home_viewmodel.dart';
import '../../core/utils/app_notifications.dart';

class GamifiedTrackList extends StatelessWidget {
  final List<Track> tracks;

  const GamifiedTrackList({super.key, required this.tracks});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final xOffsets = List.generate(tracks.length, (index) {
          if (index == 0) return 0.0;
          return (index % 2 == 0) ? -75.0 : 75.0; // Alternate Left/Right
        });

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Stack(
            children: [


              // The Path Line
              // The Path Line
              Consumer<HomeViewModel>(
                builder: (context, viewModel, _) {
                  return Positioned.fill(
                    child: CustomPaint(
                      painter: PathPainter(
                        itemCount: tracks.length,
                        itemHeight: 160.0,
                        centerOffset: constraints.maxWidth / 2,
                        xOffsets: xOffsets,
                        tracks: tracks,
                        completedTracks: List.generate(tracks.length, (index) {
                             return viewModel.getTrackStatus(index) == TrackStatus.completed;
                        }),
                      ),
                    ),
                  );
                }
              ),
              // The Nodes
              Column(
                children: List.generate(tracks.length, (index) {
                  final track = tracks[index];
                  final double xOffset = xOffsets[index];

                  return Container(
                    height: 160.0,
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: Offset(xOffset, 0),
                      child: _TrackNode(track: track, index: index),
                    ),
                  );
                }),
              ),
              // Extra space at bottom
              const SizedBox(height: 100),
            ],
          ),
        );
      },
    );
  }


}

class _TrackNode extends StatelessWidget {
  final Track track;
  final int index;

  const _TrackNode({required this.track, required this.index});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeViewModel>(
      builder: (context, viewModel, child) {
        final status = viewModel.getTrackStatus(index);
        final isLocked = status == TrackStatus.locked;
        final isCompleted = status == TrackStatus.completed;
        
        // Determine if this is the "current" track (first unlocked one)
        final isCurrent = status == TrackStatus.available;
        
        String buttonText = 'COMEÇAR';
        if (isCurrent) {
          final phases = viewModel.phasesByTrack[track.id] ?? [];
          final hasStarted = phases.any((p) => viewModel.isPhaseCompleted(p.id));
          if (hasStarted) {
            buttonText = 'CONTINUAR';
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCurrent)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  buttonText,
                  style: const TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            GestureDetector(
              onTap: () {
                if (isLocked) {
                  AppNotifications.show(
                    context, 
                    'Complete o mundo anterior primeiro!',
                    type: NotificationType.warning,
                  );
                } else {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => WorldScreen(world: track),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        // "Pulled in" effect: Zoom from small to full size
                        var scaleAnimation = Tween(begin: 0.5, end: 1.0).animate(
                          CurvedAnimation(
                            parent: animation, 
                            curve: Curves.easeOutBack, // Bouncy/Elastic feel
                          ),
                        );
                        
                        var fadeAnimation = Tween(begin: 0.0, end: 1.0).animate(
                          CurvedAnimation(
                            parent: animation, 
                            curve: Curves.easeOut,
                          ),
                        );

                        return ScaleTransition(
                          scale: scaleAnimation,
                          alignment: Alignment.center,
                          child: FadeTransition(
                            opacity: fadeAnimation,
                            child: child,
                          ),
                        );
                      },
                      transitionDuration: const Duration(milliseconds: 500),
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
                    color: isLocked ? const Color(0xFFE5E7EB) : Color(track.color),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: isLocked
                            ? const Color(0xFF9CA3AF)
                            : Color(track.color).withOpacity(0.6),
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
                                : SvgPicture.asset(
                                    track.iconAsset,
                                    width: 40,
                                    height: 40,
                                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                    placeholderBuilder: (_) => const Icon(Icons.star, color: Colors.white, size: 40),
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Hero(
              tag: 'track_title_${track.id}',
              child: Material(
                color: Colors.transparent,
                child: Container(
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
                    track.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isLocked ? const Color(0xFF9CA3AF) : const Color(0xFF374151),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PathPainter extends CustomPainter {
  final int itemCount;
  final double itemHeight;
  final double centerOffset;
  final List<double> xOffsets;
  final List<Track> tracks;
  final List<bool> completedTracks;

  PathPainter({
    required this.itemCount,
    required this.itemHeight,
    required this.centerOffset,
    required this.xOffsets,
    required this.tracks,
    required this.completedTracks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24.0
      ..strokeCap = StrokeCap.round;

    final inactivePaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16.0
      ..strokeCap = StrokeCap.round;

    // 1. Draw continuous background
    final fullPath = Path();
    for (int i = 0; i < itemCount - 1; i++) {
        _addSegment(fullPath, i, moveToStart: i == 0);
    }
    canvas.drawPath(fullPath, borderPaint);

    // 2. Draw segments
    for (int i = 0; i < itemCount - 1; i++) {
      final segmentPath = Path();
      _addSegment(segmentPath, i, moveToStart: true);

      // If Track i is COMPLETED, the path to i+1 is colored with gradient
      if (completedTracks[i]) {
         final startColor = Color(tracks[i].color);
         final endColor = Color(tracks[i+1].color);
         
         final gradient = LinearGradient(
           colors: [startColor, endColor],
           begin: Alignment.topCenter,
           end: Alignment.bottomCenter,
         );
         
         final rect = segmentPath.getBounds();
         final activePaint = Paint()
            ..shader = gradient.createShader(rect)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16.0
            ..strokeCap = StrokeCap.round;
            
         canvas.drawPath(segmentPath, activePaint);
      } else {
         canvas.drawPath(segmentPath, inactivePaint);
      }
    }
  }

  void _addSegment(Path path, int i, {required bool moveToStart}) {
      final double startX = centerOffset + xOffsets[i];
      final double startY = (i * itemHeight) + (itemHeight / 2);

      final double endX = centerOffset + xOffsets[i+1];
      final double endY = ((i + 1) * itemHeight) + (itemHeight / 2);

      if (moveToStart) {
        path.moveTo(startX, startY);
      }

      final double controlY1 = startY + (itemHeight / 2);
      final double controlY2 = endY - (itemHeight / 2);

      path.cubicTo(
        startX, controlY1, 
        endX, controlY2, 
        endX, endY
      );
  }

  @override
  bool shouldRepaint(covariant PathPainter oldDelegate) {
    return oldDelegate.itemCount != itemCount ||
           oldDelegate.completedTracks != completedTracks ||
           oldDelegate.tracks != tracks;
  }
}
