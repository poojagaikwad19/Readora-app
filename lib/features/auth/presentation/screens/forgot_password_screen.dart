import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../common_widgets/app_button.dart';
import '../../../common_widgets/app_text_field.dart';
import '../providers/auth_provider.dart';

enum ForgotPasswordStep {
  enterEmail,
  enterOtp,
  setNewPassword,
  success,
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  ForgotPasswordStep _currentStep = ForgotPasswordStep.enterEmail;

  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool _isLoading = false;
  String? _errorMessage;

  // State from backend
  String? _lookupToken;
  String? _maskedEmail;
  String? _resetToken;
  String? _devOtp;

  // Resend Cooldown Timer
  Timer? _cooldownTimer;
  int _cooldownSecondsRemaining = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldownTimer(int seconds) {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownSecondsRemaining = seconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownSecondsRemaining > 1) {
          _cooldownSecondsRemaining -= 1;
        } else {
          _cooldownSecondsRemaining = 0;
          timer.cancel();
        }
      });
    });
  }

  // STEP 1: Send OTP to Email
  Future<void> _handleSendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your registered email address');
      return;
    }

    if (!email.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      final res = await repo.forgotPasswordSendEmailOtp(email: email);

      final token = res['lookupToken'] as String?;
      final cooldown = (res['cooldownSeconds'] as num?)?.toInt() ?? 60;
      _startCooldownTimer(cooldown);

      setState(() {
        _isLoading = false;
        _lookupToken = token;
        _maskedEmail = res['destination']?.toString() ?? email;
        _devOtp = res['devOtp']?.toString();
        _otpController.clear();
        _currentStep = ForgotPasswordStep.enterOtp;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // STEP 2: Verify OTP
  Future<void> _handleVerifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter the complete 6-digit code');
      return;
    }

    if (_lookupToken == null) {
      setState(() => _errorMessage = 'Session expired. Please request a new code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      final resetToken = await repo.forgotPasswordVerifyEmailOtp(
        lookupToken: _lookupToken!,
        otp: otp,
        email: _emailController.text.trim(),
      );

      setState(() {
        _isLoading = false;
        _resetToken = resetToken;
        _currentStep = ForgotPasswordStep.setNewPassword;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // STEP 3: Reset Password
  Future<void> _handleResetPassword() async {
    final newPassword = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      setState(() => _errorMessage = 'Please enter and confirm your new password');
      return;
    }

    if (newPassword.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters long');
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    if (_resetToken == null) {
      setState(() => _errorMessage = 'Reset session expired. Please restart recovery.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.forgotPasswordReset(
        resetToken: _resetToken!,
        newPassword: newPassword,
      );

      setState(() {
        _isLoading = false;
        _currentStep = ForgotPasswordStep.success;
      });
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

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(28.0),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(24.0),
                border: Border.all(color: context.borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App pill
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2E2452) : AppColors.accentPill,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'READORA SECURITY',
                        style: TextStyle(
                          color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Step indicator
                  if (_currentStep != ForgotPasswordStep.success)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: Row(
                        children: List.generate(3, (index) {
                          final stepIndex = _currentStep.index;
                          final isCompleted = stepIndex > index;
                          final isCurrent = stepIndex == index;

                          return Expanded(
                            child: Container(
                              margin: EdgeInsets.only(right: index < 2 ? 6.0 : 0),
                              height: 4,
                              decoration: BoxDecoration(
                                color: isCompleted || isCurrent
                                    ? (isDark ? const Color(0xFFC4B5FD) : AppColors.primary)
                                    : (isDark ? const Color(0xFF2E2452) : const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                  // Active Step Content
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: KeyedSubtree(
                      key: ValueKey(_currentStep),
                      child: _buildCurrentStep(isDark),
                    ),
                  ),

                  // Error Banner
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
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
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Return to login link
                  if (_currentStep != ForgotPasswordStep.success)
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Remember your password? ',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: context.textSecondaryColor,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep(bool isDark) {
    switch (_currentStep) {
      case ForgotPasswordStep.enterEmail:
        return _buildEnterEmailStep(isDark);
      case ForgotPasswordStep.enterOtp:
        return _buildEnterOtpStep(isDark);
      case ForgotPasswordStep.setNewPassword:
        return _buildSetNewPasswordStep(isDark);
      case ForgotPasswordStep.success:
        return _buildSuccessStep(isDark);
    }
  }

  // STEP 1 WIDGET
  Widget _buildEnterEmailStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.lock_reset_rounded,
          size: 44,
          color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'Reset Password',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter your registered email address to receive a verification code.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: context.textSecondaryColor,
          ),
        ),
        const SizedBox(height: 24),

        AppTextField(
          controller: _emailController,
          label: 'Email Address',
          hintText: 'name@example.com',
          keyboardType: TextInputType.emailAddress,
          prefixIcon: Icons.alternate_email_rounded,
        ),

        const SizedBox(height: 24),
        AppButton(
          label: 'Send Code',
          icon: Icons.send_rounded,
          isLoading: _isLoading,
          onPressed: _handleSendOtp,
        ),
      ],
    );
  }

  // STEP 2 WIDGET
  Widget _buildEnterOtpStep(bool isDark) {
    final destination = _maskedEmail ?? _emailController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 44,
          color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'Enter Verification Code',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'We sent a 6-digit code to $destination',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: context.textSecondaryColor,
          ),
        ),
        const SizedBox(height: 24),

        if (_devOtp != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
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
                    setState(() {
                      _otpController.text = _devOtp!;
                      _errorMessage = null;
                    });
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
          label: '6-Digit Code',
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
            if (_cooldownSecondsRemaining > 0)
              Text(
                'Resend in ${_cooldownSecondsRemaining}s',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                ),
              )
            else
              GestureDetector(
                onTap: _isLoading ? null : _handleSendOtp,
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

        const SizedBox(height: 24),
        AppButton(
          label: 'Verify Code',
          icon: Icons.check_circle_outline_rounded,
          isLoading: _isLoading,
          onPressed: _handleVerifyOtp,
        ),

        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            setState(() {
              _currentStep = ForgotPasswordStep.enterEmail;
              _errorMessage = null;
            });
          },
          child: Text(
            'Change Email',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textSecondaryColor,
            ),
          ),
        ),
      ],
    );
  }

  // STEP 3 WIDGET
  Widget _buildSetNewPasswordStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.password_rounded,
          size: 44,
          color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'Set New Password',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter a new password for your Readora account.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: context.textSecondaryColor,
          ),
        ),
        const SizedBox(height: 24),

        AppTextField(
          controller: _passwordController,
          label: 'New Password',
          hintText: 'At least 6 characters',
          obscureText: _obscurePassword,
          prefixIcon: Icons.lock_outline_rounded,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: AppColors.textMuted,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 16),

        AppTextField(
          controller: _confirmPasswordController,
          label: 'Confirm New Password',
          hintText: 'Re-enter your new password',
          obscureText: _obscureConfirmPassword,
          prefixIcon: Icons.lock_outline_rounded,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: AppColors.textMuted,
              size: 20,
            ),
            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
          ),
        ),

        const SizedBox(height: 24),
        AppButton(
          label: 'Reset Password',
          icon: Icons.check_circle_rounded,
          isLoading: _isLoading,
          onPressed: _handleResetPassword,
        ),
      ],
    );
  }

  // STEP 4 WIDGET
  Widget _buildSuccessStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.success,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Password Reset Complete',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your password has been changed successfully. You can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: context.textSecondaryColor,
          ),
        ),
        const SizedBox(height: 28),
        AppButton(
          label: 'Back to Sign In',
          icon: Icons.login_rounded,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
