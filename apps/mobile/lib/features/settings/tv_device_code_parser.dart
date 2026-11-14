/// Extract the 6-digit TV pairing code from QR text or manual input.
String? parseTvDeviceCode(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    final fromQuery = uri.queryParameters['code'];
    if (fromQuery != null) {
      final digits = fromQuery.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length == 6) return digits;
    }
  }

  final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.length == 6) return digitsOnly;

  final match = RegExp(r'\b(\d{6})\b').firstMatch(trimmed);
  return match?.group(1);
}
