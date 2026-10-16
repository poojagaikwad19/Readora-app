import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../common_widgets/app_button.dart';
import '../../../common_widgets/app_text_field.dart';
import '../../domain/user_model.dart';
import '../providers/auth_provider.dart';

class EditProfileDialog extends ConsumerStatefulWidget {
  final UserModel user;

  const EditProfileDialog({
    super.key,
    required this.user,
  });

  static Future<void> show(BuildContext context, UserModel user) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => EditProfileDialog(user: user),
    );
  }

  @override
  ConsumerState<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<EditProfileDialog> {
  late TextEditingController _nameController;

  String? _pickedImagePath;
  bool _removePhoto = false;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final file = File(path);
        final sizeBytes = await file.length();

        // 5MB limit
        if (sizeBytes > 5 * 1024 * 1024) {
          setState(() {
            _errorMessage = 'Selected image is too large. Maximum size is 5MB.';
          });
          return;
        }

        setState(() {
          _pickedImagePath = path;
          _removePhoto = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to select image: $e');
    }
  }

  void _handleRemovePhoto() {
    setState(() {
      _pickedImagePath = null;
      _removePhoto = true;
    });
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your full name');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final notifier = ref.read(authNotifierProvider.notifier);

    try {
      // 1. Upload or remove photo
      if (_pickedImagePath != null) {
        await notifier.uploadAvatar(_pickedImagePath!);
      } else if (_removePhoto && widget.user.avatarUrl != null) {
        await notifier.removeAvatar();
      }

      // 2. Update profile name
      await notifier.updateProfile(name: name);

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = e.toString();
      });
    }
  }

  Widget _buildAvatarPreview(bool isDark) {
    const double size = 88.0;
    final apiClient = ref.watch(apiClientProvider);

    ImageProvider? imageProvider;
    if (_pickedImagePath != null) {
      imageProvider = FileImage(File(_pickedImagePath!));
    } else if (widget.user.avatarUrl != null && !_removePhoto) {
      final fullUrl = ApiEndpoints.resolveAvatarUrl(widget.user.avatarUrl, apiClient.baseUrl);
      if (fullUrl != null) {
        imageProvider = NetworkImage(fullUrl);
      }
    }

    final hasPhoto = imageProvider != null;

    return Center(
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasPhoto
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF5B3FF5), Color(0xFF8B5CF6)],
                    ),
              border: Border.all(
                color: isDark ? const Color(0xFF383152) : const Color(0xFFDDD6FE),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF5B3FF5).withOpacity(0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: hasPhoto
                  ? Image(
                      image: imageProvider,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildInitialsFallback(),
                    )
                  : _buildInitialsFallback(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _pickPhoto,
                icon: const Icon(Icons.photo_camera_rounded, size: 16),
                label: const Text('Change Photo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                  side: BorderSide(
                    color: isDark ? const Color(0xFF383152) : const Color(0xFFDDD6FE),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
              if (hasPhoto) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isSaving ? null : _handleRemovePhoto,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                  label: const Text('Remove', style: TextStyle(color: AppColors.error)),
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInitialsFallback() {
    final initials = widget.user.initials;
    return Container(
      color: Colors.transparent,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 32,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2E2452) : const Color(0xFFEDE9FE),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Edit Profile',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                    color: context.textSecondaryColor,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Avatar preview and picker
              _buildAvatarPreview(isDark),
              const SizedBox(height: 20),

              // Full Name field
              AppTextField(
                controller: _nameController,
                label: 'Full Name',
                hintText: 'Enter your full name',
                prefixIcon: Icons.person_outline_rounded,
              ),

              // Error display
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Save button
              AppButton(
                label: 'Save Profile Changes',
                icon: Icons.check_rounded,
                isLoading: _isSaving,
                onPressed: _handleSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
