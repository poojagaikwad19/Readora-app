import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_keys.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/logo_screen.dart';
import 'features/settings/presentation/providers/settings_provider.dart';

class ReadoraApp extends ConsumerWidget {
  const ReadoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Readora Text-to-Speech',
      theme: AppTheme.theme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode.toFlutterThemeMode(),
      home: const LogoSplashScreen(),
    );
  }
}