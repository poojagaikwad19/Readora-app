import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../common_widgets/app_button.dart';
import '../../../common_widgets/app_text_field.dart';
import '../providers/auth_provider.dart';

class PhoneVerificationDialog extends ConsumerStatefulWidget {
  final String phoneNumber;

  const PhoneVerificationDialog({
    super.key,
    required this.phoneNumber,
  });

  static Future<bool?> show(BuildContext context, String phoneNumber) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PhoneVerificationDialog(phoneNumber: phoneNumber),
    );
  }

  @override
  ConsumerState<PhoneVerificationDialog> createState() => _PhoneVerificationDialogState();
}

class _PhoneVerificationDialogState extends ConsumerState<PhoneVerificationDialog> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _devOtp;
  int _cooldownSeconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown([int seconds = 60]) {
    _timer?.cancel();
    setState(() => _cooldownSeconds = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownSeconds > 1) {
          _cooldownSeconds -= 1;
        } else {
          _cooldownSeconds = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleResend() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ref.read(authNotifierProvider.notifier).resendPhoneOtp();
      final cooldown = (res['cooldownSeconds'] as num?)?.toInt() ?? 60;
      _startCooldown(cooldown);
      setState(() {
        _devOtp = res['devOtp']?.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['devOtp'] != null
                ? 'Dev Code: ${res['devOtp']}'
                : 'A new verification code was sent to your mobile number.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleVerify() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit verification code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authNotifierProvider.notifier).verifyPhone(otp);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mobile number verified successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2E2452) : const Color(0xFFEDE9FE),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.phone_android_rounded,
                    color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Verify Mobile Number',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context, false),
                  color: context.textSecondaryColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Enter the 6-digit code sent to ${widget.phoneNumber}',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 20),
            if (_devOtp != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.code_rounded, color: Color(0xFF7C3AED), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dev Code: $_devOtp',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _otpController.text = _devOtp!;
                        _handleVerify();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Auto-Fill',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            AppTextField(
              controller: _otpController,
              label: '6-Digit OTP',
              hintText: '123456',
              keyboardType: TextInputType.number,
              prefixIcon: Icons.pin_outlined,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Code expires in 10 minutes',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.textSecondaryColor,
                  ),
                ),
                if (_cooldownSeconds > 0)
                  Text(
                    'Resend in ${_cooldownSeconds}s',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _isLoading ? null : _handleResend,
                    child: Text(
                      'Resend Code',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
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
            AppButton(
              label: 'Verify Number',
              icon: Icons.check_circle_rounded,
              isLoading: _isLoading,
              onPressed: _handleVerify,
            ),
          ],
        ),
      ),
    );
  }
}
