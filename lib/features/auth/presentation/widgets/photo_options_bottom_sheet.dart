import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/user_model.dart';
import '../providers/auth_provider.dart';

class PhotoOptionsBottomSheet extends ConsumerStatefulWidget {
  final UserModel user;

  const PhotoOptionsBottomSheet({
    super.key,
    required this.user,
  });

  static Future<void> show(BuildContext context, UserModel user) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PhotoOptionsBottomSheet(user: user),
    );
  }

  @override
  ConsumerState<PhotoOptionsBottomSheet> createState() => _PhotoOptionsBottomSheetState();
}

class _PhotoOptionsBottomSheetState extends ConsumerState<PhotoOptionsBottomSheet> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _handlePickImage(ImageSource source) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (pickedFile == null) {
        // User cancelled selection
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Updating profile photo...'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );

      await ref.read(authNotifierProvider.notifier).uploadAvatar(pickedFile.path);

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated successfully'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      final msg = e.code == 'camera_access_denied'
          ? 'Camera permission is required to take a photo.'
          : 'Failed to access camera or gallery: ${e.message}';
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: const Color(0xFFEF4444)),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.hideCurrentSnackBar();
      final err = e is FormatException ? e.message : e.toString().replaceFirst('Exception: ', '');
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: const Color(0xFFEF4444),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => PhotoOptionsBottomSheet.show(context, widget.user),
          ),
        ),
      );
    }
  }

  Future<void> _handleRemovePhoto() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    setState(() => _isLoading = true);

    try {
      Navigator.of(context).pop();
      await ref.read(authNotifierProvider.notifier).removeAvatar();

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Profile photo removed'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final err = e.toString().replaceFirst('Exception: ', '');
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to remove photo: $err'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPhoto = widget.user.avatarUrl != null && widget.user.avatarUrl!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF383152) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Profile photo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                    letterSpacing: -0.3,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textSecondaryColor, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Option 1: Take photo
            _buildOptionTile(
              context: context,
              icon: Icons.camera_alt_rounded,
              iconColor: AppColors.primary,
              iconBgColor: isDark ? const Color(0xFF2E2452) : const Color(0xFFEDE9FE),
              title: 'Take photo',
              textColor: context.textPrimaryColor,
              onTap: () => _handlePickImage(ImageSource.camera),
              isDark: isDark,
            ),
            const SizedBox(height: 10),

            // Option 2: Choose from gallery
            _buildOptionTile(
              context: context,
              icon: Icons.photo_library_rounded,
              iconColor: AppColors.primary,
              iconBgColor: isDark ? const Color(0xFF2E2452) : const Color(0xFFEDE9FE),
              title: 'Choose from gallery',
              textColor: context.textPrimaryColor,
              onTap: () => _handlePickImage(ImageSource.gallery),
              isDark: isDark,
            ),

            // Option 3: Remove photo (Show ONLY when a photo exists)
            if (hasPhoto) ...[
              const SizedBox(height: 10),
              _buildOptionTile(
                context: context,
                icon: Icons.delete_outline_rounded,
                iconColor: const Color(0xFFEF4444),
                iconBgColor: isDark ? const Color(0xFF3B181E) : const Color(0xFFFEE2E2),
                title: 'Remove photo',
                textColor: const Color(0xFFEF4444),
                onTap: _isLoading ? null : _handleRemovePhoto,
                isDark: isDark,
                isDestructive: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required Color textColor,
    required VoidCallback? onTap,
    required bool isDark,
    bool isDestructive = false,
  }) {
    return Material(
      color: isDestructive
          ? (isDark ? const Color(0xFF2C1619) : const Color(0xFFFEF2F2))
          : (isDark ? const Color(0xFF1E1630) : Colors.white),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDestructive
                  ? (isDark ? const Color(0xFFEF4444).withValues(alpha: 0.3) : const Color(0xFFFECACA))
                  : (isDark ? const Color(0xFF383152) : const Color(0xFFE2E8F0)),
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDestructive ? const Color(0xFFEF4444) : (isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8)),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
