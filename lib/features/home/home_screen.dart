import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../profile/profile_screen.dart';
import 'tracks_tab.dart';
import '../resume/resume_tab.dart';
import '../resume/resume_viewmodel.dart';
import '../jobs/screens/jobs_swipe_screen.dart';
import '../jobs/screens/liked_jobs_screen.dart';
import '../jobs/jobs_viewmodel.dart';
import 'home_viewmodel.dart';

import '../../services/tutorial_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      TutorialService().showTutorialIfNeeded(
        context,
        onTabChange: (index) {
          _navigateToPage(index);
        },
      );

      // Listen for tab-change requests coming from deep navigation screens
      context.read<HomeViewModel>().addListener(_onHomeViewModelChange);
    });

    TutorialService.tutorialTrigger.addListener(() {
      if (mounted) {
        _navigateToPage(2); // Trilha (deslocou de 1 → 2 com nova tab Curtidas)

        Future.delayed(const Duration(milliseconds: 500), () {
          print("Iniciando tutorial...");
          TutorialService().showTutorial(
            context,
            onTabChange: (index) {
              _navigateToPage(index);
            },
          );
        });
      }
    });
  }

  void _onHomeViewModelChange() {
    if (!mounted) return;
    final homeVM = context.read<HomeViewModel>();
    if (homeVM.pendingTabIndex != null) {
      _navigateToPage(homeVM.pendingTabIndex!);
      homeVM.clearPendingTabChange();
    }
  }

  void _navigateToPage(int index) {
    if (!mounted) return; // Guard: state may be stale from an old closure
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    // Refresh resume data if switching to that tab (índice 3 após adicionar Curtidas)
    if (index == 3) {
       context.read<ResumeViewModel>().loadResumeData();
    }
  }

  @override
  void dispose() {
    // Remove the listener safely — the viewmodel outlives this widget
    try {
      context.read<HomeViewModel>().removeListener(_onHomeViewModelChange);
    } catch (_) {}
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild tabs to pass callbacks
    final List<Widget> tabs = [
      const JobsSwipeScreen(),
      const LikedJobsScreen(),
      const TracksTab(),
      ResumeTab(
        onTabChange: (index) {
          _navigateToPage(index);
        },
      ),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(), // Disable swipe
          onPageChanged: (index) {
             if (_currentIndex != index) {
               setState(() => _currentIndex = index);
             }
          },
          children: tabs,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            _navigateToPage(index);
          },
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF4F46E5),
          unselectedItemColor: const Color(0xFF9CA3AF),
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.work_outline),
              activeIcon: Icon(Icons.work),
              label: 'Vagas',
            ),
            BottomNavigationBarItem(
              icon: _PendingBadgeIcon(
                icon: Icons.bookmark_border,
                count: context.watch<JobsViewModel>().pendingCount,
              ),
              activeIcon: _PendingBadgeIcon(
                icon: Icons.bookmark,
                count: context.watch<JobsViewModel>().pendingCount,
              ),
              label: 'Salvas',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Trilha',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.description_outlined),
              activeIcon: Icon(Icons.description),
              label: 'Currículo',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}

/// Ícone do tab "Curtidas" com badge da contagem de vagas pendentes
/// (curtidas - aplicadas). Some quando count == 0.
class _PendingBadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  const _PendingBadgeIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -8,
          top: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Center(
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
