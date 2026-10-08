import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../common_widgets/app_button.dart';
import '../../../common_widgets/language_selector.dart';
import '../../../common_widgets/pdf_card.dart';
import '../../../common_widgets/stat_card.dart';
import '../providers/document_tts_provider.dart';
import '../../domain/voice_model.dart';
import 'audio_player_screen.dart';
import 'pdf_reader_screen.dart';
import 'pdf_upload_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;
  bool _isQuickStartExpanded = false;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _serverUrlController = TextEditingController();

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

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: _buildSidebarDrawer(user, stats),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
            tooltip: 'Navigation Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.accentPill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.record_voice_over_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Readora',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'TTS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
            tooltip: 'Server Settings',
            onPressed: _showServerSettingsDialog,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Home Dashboard Overview
          _buildHomeTab(user, ttsState, stats),

          // Tab 1: My Documents
          _buildMyDocumentsTab(ttsState),

          // Tab 2: Convert to Audio (TTS Studio)
          _buildTtsStudioTab(ttsState),

          // Tab 3: Profile & Settings
          _buildProfileTab(user, ttsState, stats),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded),
              activeIcon: Icon(Icons.grid_view_rounded, color: AppColors.primary),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              activeIcon: Icon(Icons.folder_rounded, color: AppColors.primary),
              label: 'My Docs',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.graphic_eq_rounded),
              activeIcon: Icon(Icons.graphic_eq_rounded, color: AppColors.primary),
              label: 'Convert',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded, color: AppColors.primary),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  // QUICK START DROPDOWN COMPONENT
  Widget _buildQuickStartDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isQuickStartExpanded
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.primary.withOpacity(0.12),
          width: _isQuickStartExpanded ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _isQuickStartExpanded
                ? AppColors.primary.withOpacity(0.08)
                : Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isQuickStartExpanded = !_isQuickStartExpanded;
              });
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withOpacity(0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Select an action',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isQuickStartExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isQuickStartExpanded) ...[
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 4),
            _buildQuickMenuItem(
              icon: Icons.record_voice_over_rounded,
              gradientColors: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
              title: 'Text to Speech',
              subtitle: 'Convert document to speech',
              onTap: () {
                setState(() => _isQuickStartExpanded = false);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PdfUploadScreen(mode: UploadMode.tts)),
                );
              },
            ),
            _buildQuickMenuItem(
              icon: Icons.graphic_eq_rounded,
              gradientColors: const [Color(0xFF0D9488), Color(0xFF0F766E)],
              title: 'Speech to Text',
              subtitle: 'Transcribe audio to text',
              onTap: () {
                setState(() => _isQuickStartExpanded = false);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PdfUploadScreen(mode: UploadMode.stt)),
                );
              },
            ),
            _buildQuickMenuItem(
              icon: Icons.document_scanner_rounded,
              gradientColors: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
              title: 'Extract Text',
              subtitle: 'Extract text from documents',
              onTap: () {
                setState(() => _isQuickStartExpanded = false);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PdfUploadScreen(mode: UploadMode.all)),
                );
              },
            ),
            _buildQuickMenuItem(
              icon: Icons.translate_rounded,
              gradientColors: const [Color(0xFF6366F1), Color(0xFF4338CA)],
              title: 'Translate',
              subtitle: 'Translate text/documents',
              onTap: () {
                setState(() {
                  _isQuickStartExpanded = false;
                  _currentIndex = 2;
                });
              },
            ),
            _buildQuickMenuItem(
              icon: Icons.folder_copy_rounded,
              gradientColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
              title: 'My Documents',
              subtitle: 'View uploaded documents',
              onTap: () {
                setState(() {
                  _isQuickStartExpanded = false;
                  _currentIndex = 1;
                });
              },
            ),
            _buildQuickMenuItem(
              icon: Icons.history_rounded,
              gradientColors: const [Color(0xFFEC4899), Color(0xFFBE185D)],
              title: 'History',
              subtitle: 'View previous activities',
              onTap: () {
                setState(() {
                  _isQuickStartExpanded = false;
                  _currentIndex = 1;
                });
              },
            ),
            _buildQuickMenuItem(
              icon: Icons.star_rounded,
              gradientColors: const [Color(0xFFEAB308), Color(0xFFCA8A04)],
              title: 'Favorites',
              subtitle: 'View saved items',
              onTap: () {
                setState(() {
                  _isQuickStartExpanded = false;
                  _currentIndex = 1;
                });
              },
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickMenuItem({
    required IconData icon,
    required List<Color> gradientColors,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        highlightColor: gradientColors.first.withOpacity(0.05),
        splashColor: gradientColors.first.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.first.withOpacity(0.28),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TAB 0: HOME DASHBOARD OVERVIEW
  Widget _buildHomeTab(dynamic user, DocumentTtsState ttsState, Map<String, String> stats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Welcome Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  child: Text(
                    user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'READORA CLOUD',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Welcome back, ${user?.name ?? 'User'}!',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? 'Text-to-Speech & Document Reader',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // QUICK START DROPDOWN
          _buildQuickStartDropdown(),

          const SizedBox(height: 24),

          // TWO MAIN FEATURE OPTIONS (Requirement 1)
          const Text(
            'Choose Feature',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              // Option 1: Text to Speech
              Expanded(
                child: _buildMainFeatureCard(
                  title: 'Text to Speech',
                  subtitle: 'Convert document & text to natural audio speech',
                  actionText: 'Upload File',
                  icon: Icons.record_voice_over_rounded,
                  primaryColor: AppColors.primary,
                  backgroundColor: AppColors.accentPill,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PdfUploadScreen(mode: UploadMode.tts),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),

              // Option 2: Speech to Text
              Expanded(
                child: _buildMainFeatureCard(
                  title: 'Speech to Text',
                  subtitle: 'Transcribe audio recordings into written text',
                  actionText: 'Upload Audio',
                  icon: Icons.graphic_eq_rounded,
                  primaryColor: const Color(0xFF0D9488),
                  backgroundColor: const Color(0xFFCCFBF1),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PdfUploadScreen(mode: UploadMode.stt),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Statistics Header
          const Text(
            'Workspace Overview',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Responsive Statistic Cards Grid
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.05,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              StatCard(
                title: 'Total Documents',
                value: stats['totalDocs']!,
                subtitle: 'Extracted files',
                icon: Icons.description_rounded,
                iconColor: const Color(0xFF4F46E5),
                iconBackgroundColor: const Color(0xFFEEF2FF),
              ),
              StatCard(
                title: 'Storage Used',
                value: stats['storageUsed']!,
                subtitle: 'Processed text size',
                icon: Icons.pie_chart_rounded,
                iconColor: const Color(0xFF8B5CF6),
                iconBackgroundColor: const Color(0xFFF5F3FF),
              ),
              StatCard(
                title: 'Total Words',
                value: stats['totalWords']!,
                subtitle: 'Extracted vocabulary',
                icon: Icons.text_fields_rounded,
                iconColor: const Color(0xFF059669),
                iconBackgroundColor: const Color(0xFFECFDF5),
              ),
              StatCard(
                title: 'Last Activity',
                value: stats['lastUpload']!,
                subtitle: 'Latest extraction',
                icon: Icons.history_rounded,
                iconColor: const Color(0xFFD97706),
                iconBackgroundColor: const Color(0xFFFFFBEB),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Audio Player Banner if active
          if (ttsState.currentTtsResponse != null) ...[
            _buildActiveAudioPlayerCard(ttsState),
            const SizedBox(height: 24),
          ],

          // Recent Extracted Documents Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Extracted Documents',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _currentIndex = 1; // Go to My Documents tab
                  });
                },
                child: const Text('View All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                    setState(() {
                      _currentIndex = 2; // Jump to TTS tab
                    });
                    _handleGenerateSpeech();
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  // TAB 1: RECENT HISTORY & UPLOADED FILES TAB
  Widget _buildMyDocumentsTab(DocumentTtsState ttsState) {
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
                          setState(() {
                            _currentIndex = 2; // Jump to TTS Studio
                          });
                          _handleGenerateSpeech();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // TAB 2: TEXT TO SPEECH STUDIO TAB
  Widget _buildTtsStudioTab(DocumentTtsState ttsState) {
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
                              ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(lang);
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

                              final selectedVoiceValue = uniqueVoices.any((v) => v.voiceId == ttsState.selectedVoiceId)
                                  ? ttsState.selectedVoiceId
                                  : uniqueVoices.first.voiceId;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedVoiceValue,
                                    isExpanded: true,
                                    onChanged: (val) {
                                      if (val != null) {
                                        ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(val);
                                      }
                                    },
                                    items: uniqueVoices.map((voice) {
                                      return DropdownMenuItem<String>(
                                        value: voice.voiceId,
                                        child: Text(
                                          voice.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
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
                  _buildActiveAudioPlayerCard(ttsState),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 3: PROFILE & SETTINGS TAB
  Widget _buildProfileTab(dynamic user, DocumentTtsState ttsState, Map<String, String> stats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 32),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  user?.name ?? 'Readora User',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? 'user@readora.app',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: AppColors.success, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Readora Account Active',
                        style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Logout Action
          ElevatedButton.icon(
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).logout();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error.withOpacity(0.1),
              foregroundColor: AppColors.error,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign Out of Readora', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  // Active Embedded Audio Player Widget Card
  Widget _buildActiveAudioPlayerCard(DocumentTtsState ttsState) {
    final response = ttsState.currentTtsResponse;
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      response?.filename ?? 'Generated Speech',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Language: ${ttsState.selectedLanguage.toUpperCase()}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${ttsState.playbackRate}x Speed',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.primary,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: ttsState.audioPosition.inSeconds.toDouble().clamp(
                    0.0,
                    (ttsState.audioDuration.inSeconds > 0 ? ttsState.audioDuration.inSeconds : 1.0).toDouble(),
                  ),
              max: (ttsState.audioDuration.inSeconds > 0 ? ttsState.audioDuration.inSeconds : 1.0).toDouble(),
              onChanged: (val) {
                ref.read(documentTtsNotifierProvider.notifier).seekAudio(Duration(seconds: val.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(ttsState.audioPosition), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                Text(_formatDuration(ttsState.audioDuration), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Player Controls (Replay -10s, Play/Pause, Forward +10s)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 26,
                icon: const Icon(Icons.replay_10_rounded, color: AppColors.textPrimary),
                onPressed: () {
                  final newPos = ttsState.audioPosition - const Duration(seconds: 10);
                  ref.read(documentTtsNotifierProvider.notifier).seekAudio(
                        newPos < Duration.zero ? Duration.zero : newPos,
                      );
                },
              ),
              const SizedBox(width: 12),
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
                child: IconButton(
                  iconSize: 26,
                  icon: Icon(
                    ttsState.playerState == PlayerState.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (ttsState.playerState == PlayerState.playing) {
                      ref.read(documentTtsNotifierProvider.notifier).pauseAudio();
                    } else {
                      ref.read(documentTtsNotifierProvider.notifier).resumeAudio();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 26,
                icon: const Icon(Icons.forward_10_rounded, color: AppColors.textPrimary),
                onPressed: () {
                  final newPos = ttsState.audioPosition + const Duration(seconds: 10);
                  ref.read(documentTtsNotifierProvider.notifier).seekAudio(newPos);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Playback Speed Selector Chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Speed: ',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted),
              ),
              const SizedBox(width: 4),
              Wrap(
                spacing: 4,
                children: speeds.map((speed) {
                  final isSelected = ttsState.playbackRate == speed;
                  return InkWell(
                    onTap: () {
                      ref.read(documentTtsNotifierProvider.notifier).setPlaybackRate(speed);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                      ),
                      child: Text(
                        '${speed}x',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Empty Documents Card Fallback
  Widget _buildEmptyDocumentsCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.folder_open_rounded, size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          const Text(
            'No history items yet',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Uploaded documents and audio files for TTS and STT will appear here and automatically stay for 30 days.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: primaryColor, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
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
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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
    );
  }

  Widget _buildDrawerTile({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: isSelected,
        selectedTileColor: AppColors.primary.withOpacity(0.1),
        leading: Icon(
          icon,
          color: isSelected ? AppColors.primary : AppColors.textPrimary,
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textPrimary,
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
      backgroundColor: Colors.white,
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
                          'Readora AI',
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PdfUploadScreen(mode: UploadMode.stt),
                        ),
                      );
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.folder_outlined,
                    title: 'Documents',
                    isSelected: _currentIndex == 1,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _currentIndex = 1;
                      });
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.history_rounded,
                    title: 'History',
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _currentIndex = 1;
                      });
                    },
                  ),
                  const Divider(height: 24),
                  _buildDrawerTile(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    isSelected: _currentIndex == 3,
                    onTap: () {
                      Navigator.pop(context);
                      _showServerSettingsDialog();
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
                onTap: () async {
                  Navigator.pop(context);
                  await ref.read(authNotifierProvider.notifier).logout();
                  if (!mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

