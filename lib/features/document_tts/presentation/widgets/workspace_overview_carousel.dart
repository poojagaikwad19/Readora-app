import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class WorkspaceOverviewCarousel extends StatefulWidget {
  final Map<String, String> stats;
  final bool isVisible;

  const WorkspaceOverviewCarousel({
    super.key,
    required this.stats,
    required this.isVisible,
  });

  @override
  State<WorkspaceOverviewCarousel> createState() => _WorkspaceOverviewCarouselState();
}

class _WorkspaceOverviewCarouselState extends State<WorkspaceOverviewCarousel> with WidgetsBindingObserver {
  late final PageController _pageController;
  Timer? _autoplayTimer;
  int _virtualPageIndex = 5000;
  bool _isUserPaused = false;
  bool _isUserDragging = false;

  static const int _initialPage = 5000; // 5000 % 4 == 0 for smooth infinite looping

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _virtualPageIndex = _initialPage;
    _pageController = PageController(initialPage: _initialPage);
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant WorkspaceOverviewCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _startTimerIfNeeded();
      } else {
        _stopTimer();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isVisible) {
      _startTimerIfNeeded();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _stopTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimerIfNeeded() {
    _stopTimer();
    if (!widget.isVisible || _isUserPaused) return;

    _autoplayTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _isUserDragging || _isUserPaused || !widget.isVisible) return;

      // Respect reduced-motion preferences
      final bool disableAnimations = MediaQuery.of(context).disableAnimations;
      if (disableAnimations) return;

      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _stopTimer() {
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
  }

  void _resetTimerCountdown() {
    if (widget.isVisible && !_isUserPaused) {
      _startTimerIfNeeded();
    }
  }

  void _togglePauseResume() {
    setState(() {
      _isUserPaused = !_isUserPaused;
    });
    if (_isUserPaused) {
      _stopTimer();
    } else {
      _startTimerIfNeeded();
    }
  }

  void _onDotTapped(int targetDotIndex) {
    if (!_pageController.hasClients) return;
    final currentDotIndex = _virtualPageIndex % 4;
    final int pageDifference = targetDotIndex - currentDotIndex;
    final int targetPage = _virtualPageIndex + pageDifference;

    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    _resetTimerCountdown();
  }

  List<Map<String, dynamic>> _getSlideData() {
    return [
      {
        'title': 'Total Documents',
        'value': widget.stats['totalDocs'] ?? '0',
        'subtitle': 'Extracted files',
        'icon': Icons.description_rounded,
        'iconColor': const Color(0xFF4F46E5),
        'bgColor': const Color(0xFFEEF2FF),
        'accentColors': const [Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
      },
      {
        'title': 'Storage Used',
        'value': widget.stats['storageUsed'] ?? '0 KB',
        'subtitle': 'Processed text size',
        'icon': Icons.pie_chart_rounded,
        'iconColor': const Color(0xFF8B5CF6),
        'bgColor': const Color(0xFFF5F3FF),
        'accentColors': const [Color(0xFFE0F2FE), Color(0xFFC7D2FE)],
      },
      {
        'title': 'Total Words',
        'value': widget.stats['totalWords'] ?? '0',
        'subtitle': 'Extracted vocabulary',
        'icon': Icons.text_fields_rounded,
        'iconColor': const Color(0xFF059669),
        'bgColor': const Color(0xFFECFDF5),
        'accentColors': const [Color(0xFFD1FAE5), Color(0xFF99F6E4)],
      },
      {
        'title': 'Last Activity',
        'value': widget.stats['lastUpload'] ?? 'None',
        'subtitle': 'Latest extraction',
        'icon': Icons.history_rounded,
        'iconColor': const Color(0xFFD97706),
        'bgColor': const Color(0xFFFFFBEB),
        'accentColors': const [Color(0xFFFFEDD5), Color(0xFFF5D0FE)],
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final slides = _getSlideData();
    final activeDotIndex = _virtualPageIndex % 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Heading
        Text(
          'Workspace Overview',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 12),

        // Carousel Container
        SizedBox(
          height: 145,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification) {
                _isUserDragging = true;
              } else if (notification is ScrollEndNotification) {
                _isUserDragging = false;
                _resetTimerCountdown();
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (pageIndex) {
                setState(() {
                  _virtualPageIndex = pageIndex;
                });
              },
              itemBuilder: (context, index) {
                final slideData = slides[index % 4];
                return _buildStatSlide(slideData, isDark);
              },
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Pagination Dots & Pause/Resume Control
        _buildPaginationRow(activeDotIndex, isDark),
      ],
    );
  }

  Widget _buildStatSlide(Map<String, dynamic> slideData, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF261E47), Color(0xFF163236)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFEDE9FE), Color(0xFFDDF7F2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF4C3E7A) : const Color(0xFFC4B5FD).withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      slideData['title'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFCBD5E1) : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        slideData['value'],
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      slideData['subtitle'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B).withOpacity(0.85)
                      : Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.white.withOpacity(0.6),
                  ),
                ),
                child: Icon(
                  slideData['icon'],
                  color: slideData['iconColor'] ?? AppColors.primary,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationRow(int activeIndex, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 32),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(4, (index) {
            final isSelected = (index == activeIndex);
            return GestureDetector(
              onTap: () => _onDotTapped(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isSelected ? 18.0 : 6.0,
                height: 6.0,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? const Color(0xFFA78BFA) : AppColors.primary)
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFDDD6FE)),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: _togglePauseResume,
          borderRadius: BorderRadius.circular(16),
          child: Tooltip(
            message: _isUserPaused ? 'Resume autoplay' : 'Pause autoplay',
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Icon(
                _isUserPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 16,
                color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
