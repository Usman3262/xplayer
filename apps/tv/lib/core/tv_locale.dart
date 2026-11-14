import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The current TV UI language, for code without a context or ref (card
/// captions built in a factory). Kept in step by [TvLanguageController].
String tvUiLanguage = AppLocale.english;

/// TV UI language (same prefs key as mobile: `app.lang`).
class TvLanguageController extends StateNotifier<String> {
  TvLanguageController() : super(AppLocale.english) {
    _load();
  }

  @override
  set state(String value) {
    tvUiLanguage = value;
    super.state = value;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppLocale.fromPrefsCode(prefs.getString(AppLocale.prefsKey));
  }

  Future<void> setLanguage(String value) async {
    final language = AppLocale.normalize(value);
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppLocale.prefsKey, AppLocale.toPrefsCode(language));
  }

  Future<void> toggle() async {
    await setLanguage(AppLocale.next(state));
  }
}

final tvLanguageProvider =
    StateNotifierProvider<TvLanguageController, String>(
  (ref) => TvLanguageController(),
);
