import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';

enum NotificationType { success, warning, error, info }

class AppNotifications {
  static OverlayEntry? _overlayEntry;
  static _NotificationToastState? _currentState;
  static Timer? _dismissTimer;

  static void show(BuildContext context, String message, {NotificationType type = NotificationType.info}) {
    // If a notification is already showing, update it
    if (_overlayEntry != null && _currentState != null && _currentState!.mounted) {
      _currentState!.update(message, type);
      _resetDismissTimer();
      return;
    }

    // Otherwise, create a new one
    _overlayEntry = OverlayEntry(
      builder: (context) => _NotificationToast(
        message: message,
        type: type,
        onDismissed: _removeEntry,
        onReady: (state) {
          _currentState = state;
          _resetDismissTimer();
        },
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  static void _resetDismissTimer() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 3), () {
      _currentState?.dismiss();
    });
  }

  static void _removeEntry() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _currentState = null;
  }
}

class _NotificationToast extends StatefulWidget {
  final String message;
  final NotificationType type;
  final VoidCallback onDismissed;
  final ValueChanged<_NotificationToastState> onReady;

  const _NotificationToast({
    required this.message,
    required this.type,
    required this.onDismissed,
    required this.onReady,
  });

  @override
  State<_NotificationToast> createState() => _NotificationToastState();
}

class _NotificationToastState extends State<_NotificationToast> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  late String _message;
  late NotificationType _type;

  @override
  void initState() {
    super.initState();
    _message = widget.message;
    _type = widget.type;
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 300),
    );

    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();
    widget.onReady(this);
  }

  void update(String message, NotificationType type) {
    setState(() {
      _message = message;
      _type = type;
    });
  }

  Future<void> dismiss() async {
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getBackgroundColor(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return AppColors.success;
      case NotificationType.warning:
        return AppColors.warning;
      case NotificationType.error:
        return AppColors.error;
      case NotificationType.info:
      default:
        return AppColors.secondary;
    }
  }

  IconData _getIcon(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return Icons.check_circle_rounded;
      case NotificationType.warning:
        return Icons.lock_rounded;
      case NotificationType.error:
        return Icons.error_rounded;
      case NotificationType.info:
      default:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 32,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offset,
          child: FadeTransition(
            opacity: _opacity,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: _getBackgroundColor(_type),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      _getIcon(_type),
                      key: ValueKey(_type),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                      child: Text(
                        _message,
                        key: ValueKey(_message),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Nunito',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
