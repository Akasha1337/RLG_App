import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeChoice { system, light, dark }

class ThemeController {
  ThemeController._();
  static final instance = ThemeController._();

  static const _key = 'theme_choice';
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'light': themeMode.value = ThemeMode.light; break;
      case 'dark': themeMode.value = ThemeMode.dark; break;
      default: themeMode.value = ThemeMode.system;
    }
  }

  Future<void> set(ThemeChoice choice) async {
    final prefs = await SharedPreferences.getInstance();
    switch (choice) {
      case ThemeChoice.system:
        themeMode.value = ThemeMode.system;
        await prefs.setString(_key, 'system');
        break;
      case ThemeChoice.light:
        themeMode.value = ThemeMode.light;
        await prefs.setString(_key, 'light');
        break;
      case ThemeChoice.dark:
        themeMode.value = ThemeMode.dark;
        await prefs.setString(_key, 'dark');
        break;
    }
  }

  ThemeChoice get choice {
    switch (themeMode.value) {
      case ThemeMode.light: return ThemeChoice.light;
      case ThemeMode.dark: return ThemeChoice.dark;
      case ThemeMode.system:
      default: return ThemeChoice.system;
    }
  }
}
