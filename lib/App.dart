import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/logo_screen.dart';

class ReadoraApp extends ConsumerWidget {
  const ReadoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Readora Text-to-Speech',
      theme: AppTheme.theme,
      home: const LogoSplashScreen(),
    );
  }
}