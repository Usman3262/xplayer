import 'package:flutter/widgets.dart';

/// 12-hour clock text for the TV (client 9 Nov): "8:05 PM", "8:05 م".
String tvClock12(int hour, int minute, {required bool arabic}) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  final mm = minute.toString().padLeft(2, '0');
  final morning = hour < 12;
  final suffix = arabic ? (morning ? 'ص' : 'م') : (morning ? 'AM' : 'PM');
  return '$h:$mm $suffix';
}

/// The current time in the app's language.
String tvClockNow(BuildContext context) {
  final now = DateTime.now();
  return tvClock12(
    now.hour,
    now.minute,
    arabic: Localizations.localeOf(context).languageCode == 'ar',
  );
}
