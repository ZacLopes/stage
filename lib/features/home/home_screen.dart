import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../profile/profile_screen.dart';
import 'tracks_tab.dart';
import '../resume/resume_tab.dart';
import '../resume/resume_viewmodel.dart';
import 'home_viewmodel.dart';

import '../../services/tutorial_service.dart';
import '../../core/constants/tutorial_keys.dart';

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
        _navigateToPage(0);

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
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    // Refresh resume data if switching to that tab
    if (index == 1) {
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
            BottomNavigationBarItem(
              icon: const Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map, key: TutorialKeys.tracksTabKey),
              label: 'Trilha',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.description_outlined, key: TutorialKeys.resumeTabKey),
              activeIcon: const Icon(Icons.description),
              label: 'Currículo',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline, key: TutorialKeys.profileTabKey),
              activeIcon: const Icon(Icons.person),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}
