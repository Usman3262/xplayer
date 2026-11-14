/// Tolerant readers for server JSON (17 Oct: login and downloads failed
/// with "type 'int' is not a subtype of type 'String?'" when the server or
/// the provider sent a number where text was expected). A value of the
/// wrong type is converted, never thrown.
String? jsonStr(Object? v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is num || v is bool) return '$v';
  return null;
}

int? jsonInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt();
  return null;
}

double? jsonDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

bool? jsonBool(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.trim().toLowerCase();
    if (t == 'true' || t == '1') return true;
    if (t == 'false' || t == '0') return false;
  }
  return null;
}
