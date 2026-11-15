import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../security/token_vault.dart';
import '../provider_models.dart';
import 'panel_connection.dart';

/// Seals secrets before they are written. Default: [TokenVault] (Android
/// Keystore / iOS Keychain, this device only). Where the vault is missing or
/// broken it returns null and the value is kept as before (same policy as
/// login tokens), so connecting never fails because of the Keystore.
abstract class SecretBox {
  Future<String?> seal(String plain);
  Future<String?> open(String stored);
}

class VaultSecretBox implements SecretBox {
  const VaultSecretBox();

  @override
  Future<String?> seal(String plain) async => TokenVault.available ? TokenVault.seal(plain) : null;

  @override
  Future<String?> open(String stored) async =>
      TokenVault.isSealed(stored) ? TokenVault.open(stored) : stored;
}

/// Device storage for saved panels: the list (no secrets) and, per panel,
/// the sealed credentials. Also the device's own MAC for Stalker portals.
class ConnectionStore {
  ConnectionStore({SecretBox? secrets, Random? random})
      : _secrets = secrets ?? const VaultSecretBox(),
        _random = random ?? Random.secure();

  final SecretBox _secrets;
  final Random _random;

  static const _listKey = 'xp.panels.v1';
  static const _credPrefix = 'xp.panel.cred.';
  static const _macKey = 'xp.device.mac';

  Future<List<PanelConnection>> loadAll() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_listKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.map(PanelConnection.fromJson).whereType<PanelConnection>().toList();
    } catch (_) {
      return []; // unreadable list → start clean, never crash
    }
  }

  Future<void> saveAll(List<PanelConnection> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_listKey, jsonEncode([for (final c in list) c.toJson()]));
  }

  Future<void> saveCredentials(String id, ProviderCredentials c) async {
    final plain = jsonEncode(c.toStorage());
    final sealed = await _secrets.seal(plain);
    final p = await SharedPreferences.getInstance();
    await p.setString('$_credPrefix$id', sealed ?? plain);
  }

  Future<ProviderCredentials?> loadCredentials(String id) async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getString('$_credPrefix$id');
    if (stored == null || stored.isEmpty) return null;
    final plain = await _secrets.open(stored);
    if (plain == null) return null;
    try {
      final m = jsonDecode(plain);
      if (m is! Map) return null;
      return ProviderCredentials.fromStorage(m.map((k, v) => MapEntry('$k', '$v')));
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteCredentials(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('$_credPrefix$id');
  }

  /// This device's MAC for Stalker/MAG portals: `00:1A:79` (MAG prefix most
  /// portals expect) + 3 random bytes, created once and kept. It is a value
  /// the app sends, not the network card's MAC, so it survives Wi-Fi changes.
  Future<String> deviceMac() async {
    final p = await SharedPreferences.getInstance();
    final existing = p.getString(_macKey);
    if (existing != null && StalkerCredentials(portal: 'x', mac: existing).normalizedMac != null) {
      return existing;
    }
    final mac = generateMagMac(_random);
    await p.setString(_macKey, mac);
    return mac;
  }

  /// User typed a MAC registered elsewhere (old MAG box) and wants it as the
  /// device MAC. Returns the normalised form, or null if invalid.
  Future<String?> setDeviceMac(String mac) async {
    final norm = StalkerCredentials(portal: 'x', mac: mac).normalizedMac;
    if (norm == null) return null;
    final p = await SharedPreferences.getInstance();
    await p.setString(_macKey, norm);
    return norm;
  }

  String newId() => List.generate(12, (_) => _random.nextInt(36).toRadixString(36)).join();
}

String generateMagMac(Random r) =>
    '00:1A:79:${List.generate(3, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase()).join(':')}';
