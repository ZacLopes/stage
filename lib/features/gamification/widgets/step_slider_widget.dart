import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/theme.dart';

class StepSliderWidget extends StatefulWidget {
  final Function(String) onSelect;
  final List<String> options;
  final String? initialValue;

  const StepSliderWidget({
    super.key, 
    required this.onSelect,
    this.options = const [],
    this.initialValue,
  });

  @override
  State<StepSliderWidget> createState() => _StepSliderWidgetState();
}

class _StepSliderWidgetState extends State<StepSliderWidget> with SingleTickerProviderStateMixin {
  double _currentSliderValue = 1;
  late Map<int, String> _steps;
  late AnimationController _pulseController;

  // Default steps fallback
  final Map<int, String> _defaultSteps = {
    1: '1º Semestre',
    2: '2º Semestre',
    3: '3º Semestre',
    4: '4º Semestre',
    5: '5º Semestre',
    6: '6º Semestre',
    7: '7º Semestre',
    8: '8º Semestre',
    9: '9º Semestre',
    10: '10º Semestre',
    11: '11º Semestre',
    12: 'Último Ano / Formando',
  };

  @override
  void initState() {
    super.initState();
    _initializeSteps();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: 0.95,
      upperBound: 1.05,
    );

    if (widget.initialValue != null) {
      final key = _steps.entries
          .firstWhere((element) => element.value == widget.initialValue, orElse: () => const MapEntry(1, ''))
          .key;
      _currentSliderValue = key.toDouble();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_steps.isNotEmpty) {
          widget.onSelect(_steps[1]!);
        }
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _initializeSteps() {
    if (widget.options.isNotEmpty) {
      _steps = {};
      for (int i = 0; i < widget.options.length; i++) {
        _steps[i + 1] = widget.options[i];
      }
    } else {
      _steps = _defaultSteps;
    }
  }

  IconData _getIconForValue(String value) {
    final v = value.toLowerCase();
    if (v.contains('básico')) return Icons.auto_awesome_outlined;
    if (v.contains('intermediário')) return Icons.auto_awesome;
    if (v.contains('avançado')) return Icons.workspace_premium;
    if (v.contains('fluente')) return Icons.verified_user_rounded;
    if (v.contains('semestre')) return Icons.school_rounded;
    return Icons.star_rounded;
  }

  Color _getColorForValue(String value) {
    final v = value.toLowerCase();
    if (v.contains('básico')) return AppColors.success;
    if (v.contains('intermediário')) return AppColors.secondary;
    if (v.contains('avançado')) return AppColors.warning;
    if (v.contains('fluente')) return const Color(0xFFCE82FF);
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    if (_steps.isEmpty) return const SizedBox.shrink();

    final maxSteps = _steps.length;
    final currentValue = _steps[_currentSliderValue.toInt()] ?? '';
    final activeColor = _getColorForValue(currentValue);
    
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: activeColor.withOpacity(0.2), width: 3),
            boxShadow: [
              BoxShadow(
                color: activeColor.withOpacity(0.1),
                offset: const Offset(0, 15),
                blurRadius: 30,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                offset: const Offset(0, 5),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            children: [
              // Visual Indicator
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Container(
                  key: ValueKey(currentValue),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: activeColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIconForValue(currentValue),
                    size: 48,
                    color: activeColor,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Level Name
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  currentValue.toUpperCase(),
                  key: ValueKey(currentValue),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: activeColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),

              // Custom Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: activeColor,
                  inactiveTrackColor: AppColors.border,
                  trackHeight: 16.0,
                  thumbColor: Colors.white,
                  thumbShape: _CustomThumbShape(color: activeColor),
                  overlayColor: activeColor.withOpacity(0.2),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 32.0),
                  tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 3),
                  activeTickMarkColor: Colors.white.withOpacity(0.8),
                  inactiveTickMarkColor: AppColors.borderStrong,
                ),
                child: Slider(
                  value: _currentSliderValue,
                  min: 1,
                  max: maxSteps.toDouble(),
                  divisions: maxSteps > 1 ? maxSteps - 1 : 1,
                  onChanged: (double value) {
                    if (value.toInt() != _currentSliderValue.toInt()) {
                      HapticFeedback.lightImpact();
                      _pulseController.forward(from: 0).then((_) => _pulseController.reverse());
                    }
                    setState(() {
                      _currentSliderValue = value;
                    });
                    widget.onSelect(_steps[value.toInt()] ?? '');
                  },
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Min/Max Labels
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text(
                     _steps[1]!,
                     style: TextStyle(
                       fontSize: 12, 
                       fontWeight: FontWeight.bold,
                       color: _currentSliderValue == 1 ? activeColor : AppColors.textDisabled
                     ),
                   ),
                   Text(
                     _steps[maxSteps]!,
                     style: TextStyle(
                       fontSize: 12, 
                       fontWeight: FontWeight.bold,
                       color: _currentSliderValue == maxSteps ? activeColor : AppColors.textDisabled
                     ),
                   ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomThumbShape extends SliderComponentShape {
  final Color color;
  const _CustomThumbShape({required this.color});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(36, 36);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Outer shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center.translate(0, 3), 16, shadowPaint);

    // White circle base
    final paintWhite = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 16, paintWhite);

    // Border
    final paintBorder = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, 16, paintBorder);

    // Inner small circle
    final paintInner = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6, paintInner);
  }
}
