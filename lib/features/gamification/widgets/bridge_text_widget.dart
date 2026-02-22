import 'package:flutter/material.dart';

class BridgeTextWidget extends StatefulWidget {
  final Function(String) onSave;
  final String? questionText;

  const BridgeTextWidget({super.key, required this.onSave, this.questionText});

  @override
  State<BridgeTextWidget> createState() => _BridgeTextWidgetState();
}

class _BridgeTextWidgetState extends State<BridgeTextWidget> with TickerProviderStateMixin {
  final _controller = TextEditingController();
  AnimationController? _animController;
  Animation<double>? _overlayOpacity;
  Animation<Alignment>? _leftOrbAlign;
  Animation<Alignment>? _rightOrbAlign;
  Animation<double>? _flashScale;
  Animation<double>? _flashOpacity;

  bool _isAnimating = false;

  OverlayEntry? _overlayEntry;

  Animation<double>? _orbOpacity;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initAnimations();
  }

  void _initAnimations() {
    if (_animController != null) return;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000), // Increased duration
    );

    // Overlay sequence: Fade In -> Hold -> Slow Fade Out
    _overlayOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
    ]).animate(_animController!);

    // Orb Opacity: Visible -> Fade Out (matches overlay fade out)
    _orbOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
    ]).animate(_animController!);

    // Using slightly wider range for full screen impact
    _leftOrbAlign = AlignmentTween(
      begin: const Alignment(-3.0, 0.0),
      end: const Alignment(0.0, 0.0),
    ).animate(
      CurvedAnimation(parent: _animController!, curve: const Interval(0.15, 0.55, curve: Curves.easeInOutCubic)),
    );

    _rightOrbAlign = AlignmentTween(
      begin: const Alignment(3.0, 0.0),
      end: const Alignment(0.0, 0.0),
    ).animate(
      CurvedAnimation(parent: _animController!, curve: const Interval(0.15, 0.55, curve: Curves.easeInOutCubic)),
    );

    _flashScale = Tween<double>(begin: 0.1, end: 30.0).animate(
      CurvedAnimation(parent: _animController!, curve: const Interval(0.50, 0.80, curve: Curves.easeOutExpo)),
    );

    _flashOpacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 80),
    ]).animate(
      CurvedAnimation(parent: _animController!, curve: const Interval(0.50, 0.80)),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    _animController?.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    _overlayEntry = OverlayEntry(
      builder: (context) => AnimatedBuilder(
        animation: _animController!,
        builder: (context, child) {
          return Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Dark Background
                  Opacity(
                    opacity: _overlayOpacity!.value * 0.95, // Darker
                    child: Container(color: Colors.black),
                  ),
                  
                  // Left Orb (Past)
                  Align(
                    alignment: _leftOrbAlign!.value,
                    child: Opacity(
                      opacity: _orbOpacity!.value,
                      child: Container(
                        width: 80, // Larger orbs for full screen
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.8), blurRadius: 40, spreadRadius: 10),
                          ],
                        ),
                        child: const Icon(Icons.history_edu, color: Colors.white, size: 40),
                      ),
                    ),
                  ),

                  // Right Orb (Future)
                  Align(
                    alignment: _rightOrbAlign!.value,
                    child: Opacity(
                      opacity: _orbOpacity!.value,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF10B981).withOpacity(0.8), blurRadius: 40, spreadRadius: 10),
                          ],
                        ),
                        child: const Icon(Icons.rocket_launch, color: Colors.white, size: 40),
                      ),
                    ),
                  ),

                  // Flash / Explosion
                  Opacity(
                    opacity: _flashOpacity!.value,
                    child: Transform.scale(
                      scale: _flashScale!.value,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.white, blurRadius: 50, spreadRadius: 20),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Connecting Text
                  if (_flashOpacity!.value > 0.1)
                    Positioned(
                      bottom: MediaQuery.of(context).size.height * 0.4,
                      child: Opacity(
                        opacity: _flashOpacity!.value,
                        child: const Text(
                          'CONECTANDO...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24, // Larger text
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  Future<void> _submit() async {
    if (_controller.text.isNotEmpty) {
      FocusScope.of(context).unfocus();
      setState(() => _isAnimating = true);
      _initAnimations();
      
      _showOverlay();
      await _animController!.forward();
      
      // Keep overlay for a split second after animation finishes to smooth transition? 
      // Or just remove it. Code below removes it immediately after forward completes.
      
      _removeOverlay();
      widget.onSave(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    _initAnimations(); // Ensure init
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // The Visual Bridge
            Container(
              height: 120,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildnode(Icons.history_edu, const Color(0xFFF59E0B)), // Past/Orange
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF59E0B), Color(0xFF10B981)],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black12, blurRadius: 4),
                            ],
                          ),
                          child: const Icon(Icons.bolt, color: Color(0xFF6366F1), size: 20),
                        ),
                      ],
                    ),
                  ),
                  _buildnode(Icons.rocket_launch, const Color(0xFF10B981)), // Future/Green
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Como essa experiência anterior te ajuda hoje?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Mudar de rota não é perda de tempo, é repertório. Explique como você usa o que aprendeu antes.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _controller,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Ex: A base analítica que trouxe da Engenharia me permite hoje estruturar métricas financeiras com muito mais precisão e rigor.',
                hintStyle: TextStyle(color: Colors.grey[400], height: 1.5),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
                ),
                contentPadding: const EdgeInsets.all(24),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('CONECTAR SABERES', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildnode(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3), width: 4),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 32),
    );
  }
}
