import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../common_widgets/app_button.dart';
import '../../../common_widgets/language_selector.dart';
import '../../../common_widgets/pdf_card.dart';
import '../providers/document_tts_provider.dart';
import '../widgets/readora_audio_player.dart';
import '../widgets/readora_voice_selector.dart';
import '../widgets/workspace_overview_carousel.dart';
import '../../domain/voice_model.dart';
import 'history_screen.dart';
import 'pdf_reader_screen.dart';
import 'pdf_upload_screen.dart';
import '../../../downloads/presentation/screens/downloads_screen.dart';
import '../../../downloads/presentation/providers/downloads_provider.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;
  bool _isLoggingOut = false;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _serverUrlController = TextEditingController();

  Future<void> _confirmAndLogout() async {
    if (_isLoggingOut) return;

    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.logout_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(
                'Logout',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: dialogContext.textPrimaryColor),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: TextStyle(fontSize: 14, color: dialogContext.textPrimaryColor),
          ),
          actionsPadding: const EdgeInsets.only(right: 16, bottom: 16, top: 4),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('No', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Yes', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;
    if (_isLoggingOut) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      // On confirmed logout, stop active audio and prevent stale callbacks from restarting it
      await ref.read(documentTtsNotifierProvider.notifier).stopAudioAndClearQueue();
      await ref.read(documentTtsNotifierProvider.notifier).stopOriginalAudio();
      await ref.read(downloadsProvider.notifier).stopPlayback();

      await ref.read(authNotifierProvider.notifier).logout();
      ref.read(settingsProvider.notifier).reloadSettingsForUser('guest');
      ref.read(downloadsProvider.notifier).loadDownloads('guest');
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiClient = ref.read(apiClientProvider);
      _serverUrlController.text = apiClient.baseUrl;
      ref.read(documentTtsNotifierProvider.notifier).loadVoices();
      ref.read(documentTtsNotifierProvider.notifier).loadUserDocuments();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  void _showServerSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.dns_rounded, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Readora API Config', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configure the backend API Base URL for server communication.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _serverUrlController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  labelText: 'API Base URL',
                  hintText: 'http://127.0.0.1:5000/api',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newUrl = _serverUrlController.text.trim();
                if (newUrl.isNotEmpty) {
                  ref.read(apiClientProvider).updateBaseUrl(newUrl);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Server URL updated to $newUrl')),
                  );
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save Settings'),
            ),
          ],
        );
      },
    );
  }

  void _handleGenerateSpeech() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter or extract text first')),
      );
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    final response = await ref.read(documentTtsNotifierProvider.notifier).generateSpeech(
          text: text,
          baseUrl: apiClient.baseUrl.replaceAll('/api', ''),
        );

    if (!mounted) return;

    if (response != null && response.audioUrl.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech generated & playing!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // Calculate statistics from user documents
  Map<String, String> _calculateStats(List userDocuments) {
    if (userDocuments.isEmpty) {
      return {
        'totalDocs': '0',
        'storageUsed': '0 KB',
        'totalWords': '0',
        'lastUpload': 'None',
      };
    }

    int totalChars = 0;
    int totalWords = 0;
    for (final doc in userDocuments) {
      final String text = doc.text ?? '';
      totalChars += text.length;
      final int wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      totalWords += wordCount;
    }

    final double estKb = (totalChars * 1.5) / 1024;
    final String storageStr = estKb > 1024
        ? '${(estKb / 1024).toStringAsFixed(1)} MB'
        : '${estKb.toStringAsFixed(1)} KB';

    return {
      'totalDocs': userDocuments.length.toString(),
      'storageUsed': storageStr,
      'totalWords': totalWords > 999
          ? '${(totalWords / 1000).toStringAsFixed(1)}k'
          : totalWords.toString(),
      'lastUpload': 'Recent',
    };
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final ttsState = ref.watch(documentTtsNotifierProvider);
    final user = authState.user;
    final stats = _calculateStats(ttsState.userDocuments);

    final isDark = context.isDark;

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        backgroundColor: context.scaffoldBg,
      drawer: _buildSidebarDrawer(user, stats),
      appBar: AppBar(
        backgroundColor: context.surfaceBg,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu_rounded, color: context.textPrimaryColor),
            tooltip: 'Navigation Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/images/R-logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Readora',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: context.textPrimaryColor,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _currentIndex = 1; // Navigate to Profile tab
                  });
                },
                child: Builder(
                  builder: (context) {
                    final initials = _getUserInitials(user?.name);
                    return Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2E2452) : const Color(0xFFF3F0FF),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: initials.isNotEmpty
                          ? Text(
                              initials,
                              style: TextStyle(
                                color: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF5B4DFF),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            )
                          : Icon(
                              Icons.person_rounded,
                              color: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF5B4DFF),
                              size: 20,
                            ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Home Dashboard Overview
          _buildHomeTab(user, ttsState, stats),

          // Tab 1: Profile & Settings
          _buildProfileTab(user, ttsState, stats),
        ],
      ),
      bottomNavigationBar: _buildRaisedBottomNavigationBar(context, isDark),
    ),
  );
}

  Widget _buildRaisedBottomNavigationBar(BuildContext context, bool isDark) {
    final mediaQuery = MediaQuery.of(context);
    // When software keyboard is visible, collapse so it does not float over inputs
    if (mediaQuery.viewInsets.bottom > 0) {
      return const SizedBox.shrink();
    }

    final bottomPadding = mediaQuery.padding.bottom;
    final isNarrow = mediaQuery.size.width < 340;
    final buttonDiameter = isNarrow ? 62.0 : 68.0;
    const raisedHeight = 20.0;
    const barHeight = 56.0;

    return SizedBox(
      height: barHeight + raisedHeight + bottomPadding,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // 1. Navigation Bar Base with rounded upper corners
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: barHeight + bottomPadding,
            child: Container(
              decoration: BoxDecoration(
                color: context.surfaceBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border(
                  top: BorderSide(
                    color: context.borderColor.withOpacity(isDark ? 0.3 : 0.6),
                    width: 1,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: Row(
                  children: [
                    // Left Destination: Home
                    Expanded(
                      child: _buildBottomNavItem(
                        icon: Icons.grid_view_rounded,
                        activeIcon: Icons.grid_view_rounded,
                        label: 'Home',
                        isSelected: _currentIndex == 0,
                        onTap: () {
                          if (_currentIndex != 0) {
                            setState(() {
                              _currentIndex = 0;
                            });
                          }
                        },
                        isDark: isDark,
                      ),
                    ),

                    // Centre reservation spacing for the raised logo
                    SizedBox(width: buttonDiameter + 12),

                    // Right Destination: Profile
                    Expanded(
                      child: _buildBottomNavItem(
                        icon: Icons.person_outline_rounded,
                        activeIcon: Icons.person_rounded,
                        label: 'Profile',
                        isSelected: _currentIndex == 1,
                        onTap: () {
                          if (_currentIndex != 1) {
                            setState(() {
                              _currentIndex = 1;
                            });
                          }
                        },
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Raised Centre Logo Button
          Positioned(
            top: 0,
            child: Semantics(
              label: 'Readora Home',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_currentIndex != 0) {
                    setState(() {
                      _currentIndex = 0;
                    });
                  }
                },
                child: Container(
                  width: buttonDiameter,
                  height: buttonDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFFC4B5FD),
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF5B4DFF)).withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/R-logo.png',
                      width: buttonDiameter,
                      height: buttonDiameter,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final activeColor = isDark ? const Color(0xFFA78BFA) : AppColors.primary;
    final inactiveColor = context.textMutedColor;
    final color = isSelected ? activeColor : inactiveColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: color,
                size: 22,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to safely extract 1-2 character user initials
  String _getUserInitials(String? name) {
    if (name == null || name.trim().isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    final firstInitial = parts.first.characters.first.toUpperCase();
    final lastInitial = parts.last.characters.first.toUpperCase();
    return '$firstInitial$lastInitial';
  }

  // TAB 0: HOME DASHBOARD OVERVIEW
  Widget _buildHomeTab(dynamic user, DocumentTtsState ttsState, Map<String, String> stats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 16.0, bottom: 28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Workspace Overview Autoplay Carousel directly below App Bar
          WorkspaceOverviewCarousel(
            stats: stats,
            isVisible: _currentIndex == 0,
          ),
          const SizedBox(height: 24),

          // 2. Choose Feature: Polished TTS & STT Grid
          Text(
            'Choose Feature',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),

          _buildFeatureGrid(context),
          const SizedBox(height: 24),

          // 3. Recent Extracted Documents Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Recent Extracted Documents',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimaryColor,
                  letterSpacing: -0.3,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HistoryScreen(),
                    ),
                  );
                },
                child: const Text(
                  'View All',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.primary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (ttsState.userDocuments.isEmpty)
            _buildEmptyDocumentsCard()
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ttsState.userDocuments.length > 3 ? 3 : ttsState.userDocuments.length,
              itemBuilder: (context, index) {
                final doc = ttsState.userDocuments[index];
                return PdfCard(
                  document: doc,
                  onTap: () {
                    ref.read(documentTtsNotifierProvider.notifier).setActiveDocument(doc);
                    _textController.text = doc.text;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PdfReaderScreen(document: doc),
                      ),
                    );
                  },
                  onPlaySpeech: () {
                    ref.read(documentTtsNotifierProvider.notifier).setActiveDocument(doc);
                    _textController.text = doc.text;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PdfReaderScreen(document: doc, autoPlayAudio: true),
                      ),
                    );
                  },
                );
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // RECENT HISTORY & UPLOADED FILES COMPONENT
  Widget buildMyDocumentsTab(DocumentTtsState ttsState) {
    final docs = ttsState.userDocuments;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Recent uploaded documents and audio files',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                tooltip: 'Refresh',
                onPressed: () {
                  ref.read(documentTtsNotifierProvider.notifier).loadUserDocuments();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Documents & Audio List
          Expanded(
            child: docs.isEmpty
                ? _buildEmptyDocumentsCard()
                : ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      return PdfCard(
                        document: doc,
                        onTap: () {
                          ref.read(documentTtsNotifierProvider.notifier).setActiveDocument(doc);
                          _textController.text = doc.text;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PdfReaderScreen(document: doc),
                            ),
                          );
                        },
                        onPlaySpeech: () {
                          ref.read(documentTtsNotifierProvider.notifier).setActiveDocument(doc);
                          _textController.text = doc.text;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PdfReaderScreen(document: doc, autoPlayAudio: true),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // TEXT TO SPEECH STUDIO COMPONENT
  Widget buildTtsStudioTab(DocumentTtsState ttsState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Studio Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Text-to-Speech Studio',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Convert text or extracted documents to natural speech',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (ttsState.activeDocument != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Chip(
                    avatar: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 14),
                    label: Text(
                      ttsState.activeDocument!.filename,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: AppColors.accentPill,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Main TTS Card
          Container(
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Input Text Content',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const PdfUploadScreen()),
                        );
                      },
                      icon: const Icon(Icons.file_upload_outlined, size: 14),
                      label: const Text('Extract File', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Text Input Area
                TextField(
                  controller: _textController,
                  maxLines: 6,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
                  decoration: InputDecoration(
                    hintText: 'Type text here, paste content, or upload a document to extract text...',
                    hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 16),

                // Target Language & Voice Selectors Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Target Language',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          LanguageSelector(
                            selectedLanguage: ttsState.selectedLanguage,
                            onChanged: (lang) {
                              final settings = ref.read(settingsProvider);
                              final defVoice = settings.defaultVoiceForLanguage(lang);
                              ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(lang, voiceId: defVoice);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Voice Accent',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          Builder(
                            builder: (context) {
                              final rawVoices = ttsState.voices.isNotEmpty
                                  ? ttsState.voices
                                  : VoiceModel.defaultVoices();

                              final Map<String, VoiceModel> uniqueVoicesMap = {};
                              for (var v in rawVoices) {
                                uniqueVoicesMap[v.voiceId] = v;
                              }
                              final uniqueVoices = uniqueVoicesMap.values.toList();

                              final settings = ref.read(settingsProvider);
                              final defaultForLang = settings.defaultVoiceForLanguage(ttsState.selectedLanguage);
                              final selectedVoiceValue = uniqueVoices.any((v) => v.voiceId == ttsState.selectedVoiceId)
                                  ? ttsState.selectedVoiceId
                                  : (uniqueVoices.any((v) => v.voiceId == defaultForLang)
                                      ? defaultForLang
                                      : (uniqueVoices.isNotEmpty ? uniqueVoices.first.voiceId : 'CwhRBWXzGAHq8TQ4Fs17'));

                              if (!uniqueVoices.any((v) => v.voiceId == ttsState.selectedVoiceId) && uniqueVoices.isNotEmpty) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(selectedVoiceValue);
                                });
                              }

                              return ReadoraVoiceSelector(
                                voices: uniqueVoices,
                                selectedVoiceId: selectedVoiceValue,
                                onVoiceSelected: (voiceId) {
                                  ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(voiceId);
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                AppButton(
                  label: 'Generate & Speak Text',
                  icon: Icons.volume_up_rounded,
                  isLoading: ttsState.isGeneratingSpeech,
                  onPressed: _handleGenerateSpeech,
                ),

                // Inline Player directly below Generate & Speak Text
                if (ttsState.currentTtsResponse != null) ...[
                  const SizedBox(height: 20),
                  const ReadoraAudioPlayer(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 1: PROFILE TAB
  Widget _buildProfileTab(dynamic user, DocumentTtsState ttsState, Map<String, String> stats) {
    final isDark = context.isDark;
    final initials = _getUserInitials(user?.name);
    final String userName = (user?.name != null && (user!.name as String).trim().isNotEmpty)
        ? (user.name as String).trim()
        : 'Readora User';
    final String userEmail = (user?.email != null && (user!.email as String).trim().isNotEmpty)
        ? (user.email as String).trim()
        : 'user@readora.app';

    const double headerHeight = 156.0;
    const double headerCardTopOffset = 126.0;
    const double avatarDiameter = 84.0;
    final bottomNavPadding = 96.0 + MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottomNavPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Curved Header + Overlapping Avatar + Rounded Account Card
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // 1. Purple Gradient Header with subtle lavender curved accent
              CustomPaint(
                size: const Size(double.infinity, headerHeight),
                painter: ProfileHeaderCurvedPainter(isDark: isDark),
                child: SizedBox(
                  height: headerHeight,
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your Readora account',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.88),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. Rounded Account Details Card
              Container(
                margin: const EdgeInsets.only(
                  top: headerCardTopOffset,
                  left: 20.0,
                  right: 20.0,
                ),
                padding: const EdgeInsets.fromLTRB(20.0, 54.0, 20.0, 24.0),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(20.0),
                  border: Border.all(
                    color: isDark ? context.borderColor.withOpacity(0.4) : const Color(0xFFF1F5F9),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // User Name
                    Text(
                      userName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimaryColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // User Email
                    Text(
                      userEmail,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondaryColor,
                      ),
                    ),

                    // Account Status Badge (only when authenticated user is present)
                    if (user != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 14),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Readora Account Active',
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Subtle Divider
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20.0),
                      child: Divider(
                        color: isDark ? context.borderColor.withOpacity(0.4) : const Color(0xFFF1F5F9),
                        height: 1,
                        thickness: 1,
                      ),
                    ),

                    // Account Section Heading
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Account',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Read-only Row 1: Name
                    _buildAccountDetailRow(
                      icon: Icons.person_outline_rounded,
                      label: 'Name',
                      value: userName,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 10),

                    // Read-only Row 2: Email
                    _buildAccountDetailRow(
                      icon: Icons.mail_outline_rounded,
                      label: 'Email',
                      value: userEmail,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              // 3. Circular Initials Avatar Overlapping Header & Card
              Positioned(
                top: headerCardTopOffset - (avatarDiameter / 2),
                child: Container(
                  width: avatarDiameter,
                  height: avatarDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF5B3FF5),
                        Color(0xFF8B5CF6),
                      ],
                    ),
                    border: Border.all(
                      color: isDark ? context.cardBg : Colors.white,
                      width: 4.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5B3FF5).withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials.isNotEmpty ? initials : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 30,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 4. Sign-out Button Below the Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Material(
              color: isDark ? const Color(0xFF2C1619) : const Color(0xFFFDF2F2),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: _isLoggingOut ? null : _confirmAndLogout,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFFEF4444).withOpacity(0.4)
                          : const Color(0xFFFCA5A5),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isLoggingOut) ...[
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else ...[
                        Icon(
                          Icons.logout_rounded,
                          color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        'Sign Out of Readora',
                        style: TextStyle(
                          color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Account Detail Read-Only Row
  Widget _buildAccountDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2E2452) : const Color(0xFFF3F0FF),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF5B3FF5),
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: context.textMutedColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  // Empty Documents Card Fallback
  Widget _buildEmptyDocumentsCard() {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          Icon(Icons.folder_open_rounded, size: 52, color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(height: 14),
          Text(
            'No history items yet',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: context.textSecondaryColor),
          ),
          const SizedBox(height: 6),
          Text(
            'Uploaded documents and audio files for TTS and STT will appear here and automatically stay for 30 days.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: context.textMutedColor),
          ),
        ],
      ),
    );
  }

  // Polished Responsive Grid for TTS and STT Feature Cards
  Widget _buildFeatureGrid(BuildContext context) {
    final isDark = context.isDark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 320;

        final ttsCard = _buildMainFeatureCard(
          title: 'Text to Speech',
          subtitle: 'Turn documents or text into speech.',
          actionText: 'Upload File',
          icon: Icons.record_voice_over_rounded,
          primaryColor: isDark ? const Color(0xFFA78BFA) : AppColors.primary,
          backgroundColor: isDark ? const Color(0xFF2E2452) : const Color(0xFFF3F0FF),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PdfUploadScreen(mode: UploadMode.tts),
              ),
            );
          },
        );

        final sttCard = _buildMainFeatureCard(
          title: 'Speech to Text',
          subtitle: 'Transcribe an audio file into text.',
          actionText: 'Upload Audio',
          icon: Icons.graphic_eq_rounded,
          primaryColor: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
          backgroundColor: isDark ? const Color(0xFF133E3B) : const Color(0xFFCCFBF1),
          onTap: () {
            ref.read(documentTtsNotifierProvider.notifier).stopAudioAndClearQueue();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PdfUploadScreen(mode: UploadMode.stt),
              ),
            );
          },
        );

        if (isNarrow) {
          return Column(
            children: [
              ttsCard,
              const SizedBox(height: 14),
              sttCard,
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ttsCard),
              const SizedBox(width: 14),
              Expanded(child: sttCard),
            ],
          ),
        );
      },
    );
  }

  // Helper Widget for Main Feature Option Cards (TTS / STT)
  Widget _buildMainFeatureCard({
    required String title,
    required String subtitle,
    required String actionText,
    required IconData icon,
    required Color primaryColor,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    final isDark = context.isDark;
    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: primaryColor, size: 22),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimaryColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.textSecondaryColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          actionText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerTile({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = context.isDark;
    final primaryColor = isDark ? const Color(0xFFA78BFA) : AppColors.primary;
    final textColor = isSelected ? primaryColor : context.textPrimaryColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: isSelected,
        selectedTileColor: primaryColor.withOpacity(isDark ? 0.2 : 0.1),
        leading: Icon(
          icon,
          color: textColor,
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  // Helper Widget for Sidebar Navigation Drawer
  Widget _buildSidebarDrawer(dynamic user, Map<String, String> stats) {
    return Drawer(
      backgroundColor: context.surfaceBg,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white.withOpacity(0.25),
                    child: Text(
                      user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'R',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Readora',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.name ?? 'User Workspace',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Navigation Items List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildDrawerTile(
                    icon: Icons.grid_view_rounded,
                    title: 'Home',
                    isSelected: _currentIndex == 0,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _currentIndex = 0;
                      });
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.record_voice_over_rounded,
                    title: 'Text to Speech',
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PdfUploadScreen(mode: UploadMode.tts),
                        ),
                      );
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.graphic_eq_rounded,
                    title: 'Speech to Text',
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(documentTtsNotifierProvider.notifier).stopAudioAndClearQueue();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PdfUploadScreen(mode: UploadMode.stt),
                        ),
                      );
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.history_rounded,
                    title: 'History',
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HistoryScreen(),
                        ),
                      );
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.file_download_outlined,
                    title: 'Downloads',
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DownloadsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 24),
                  _buildDrawerTile(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Drawer Footer / Logout
            Padding(
              padding: const EdgeInsets.all(16),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppColors.error.withOpacity(0.08),
                leading: const Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
                title: const Text('Logout', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 13)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmAndLogout();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for Readora's Profile screen curved purple gradient header
/// with a layered lavender bottom edge.
class ProfileHeaderCurvedPainter extends CustomPainter {
  final bool isDark;

  const ProfileHeaderCurvedPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Subtle lavender accent layer (peeks out underneath the gradient)
    final lavenderPaint = Paint()
      ..color = isDark
          ? const Color(0xFF7C6FA0).withOpacity(0.35)
          : const Color(0xFFDDD6FE)
      ..style = PaintingStyle.fill;

    final lavenderPath = Path()
      ..lineTo(0, size.height - 10)
      ..quadraticBezierTo(
        size.width / 2,
        size.height + 8,
        size.width,
        size.height - 10,
      )
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(lavenderPath, lavenderPaint);

    // 2. Main purple gradient layer (#5B3FF5 -> #8B5CF6)
    final gradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF5B3FF5),
        Color(0xFF8B5CF6),
      ],
    );

    final gradientPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final gradientPath = Path()
      ..lineTo(0, size.height - 18)
      ..quadraticBezierTo(
        size.width / 2,
        size.height,
        size.width,
        size.height - 18,
      )
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(gradientPath, gradientPaint);
  }

  @override
  bool shouldRepaint(covariant ProfileHeaderCurvedPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}

