import 'dart:async';
import 'package:domain/domain.dart' show AppBrand;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Why offline playback of a download is refused.
enum OfflineRefusal {
  /// The subscription ended (date passed or status not active).
  subscriptionEnded,

  /// The app has not checked in online for longer than the allowed days.
  checkInNeeded,

  /// The device clock is earlier than the last online check (moved back).
  clockChanged,
}

/// Rules for downloaded files (client security response 5 Nov, P17), shared by
/// phone, TV and Windows:
///
/// - Downloads belong to the account that made them. Signing out deletes them
///   ([signedOut]); another account signing in on the device deletes them
///   ([accountChanged]). The apps' download controllers listen to [events].
/// - Offline playback is allowed only while the subscription is active, until
///   its end date, and at most `offlineDays` (from `/me`, default 7) after the
///   last successful online `/me`. A device clock set back before the last
///   check is refused.
///
/// State lives in SharedPreferences. Before the first online `/me` after this
/// update there is no record; playback is then allowed once (existing users
/// are not locked out offline), and the rule applies from the next check-in.
class OfflineDownloadPolicy {
  OfflineDownloadPolicy._();

  static const _kOwner = 'app.dl.owner';
  static const _kCheckedAt = 'app.dl.checkedAt';
  static const _kStatus = 'app.dl.subStatus';
  static const _kEndsAt = 'app.dl.subEndsAt';
  static const _kDays = 'app.dl.offlineDays';
  static const _kWipePending = 'app.dl.wipePending';
  static const defaultOfflineDays = 7;

  static const _activeStatuses = {'ACTIVE', 'RECONCILIATION_REQUIRED'};

  /// `'signedOut'` or `'accountChanged'`: delete every download.
  static final StreamController<String> _events = StreamController<String>.broadcast();
  static Stream<String> get events => _events.stream;

  @visibleForTesting
  static DateTime Function()? nowOverride;
  static DateTime _now() => (nowOverride ?? DateTime.now)();

  /// After every successful online `/me`. Never throws.
  static Future<void> recordOnline(Map<String, dynamic> me) async {
    try {
      final id = me['id'];
      if (id is! String || id.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(_kOwner);
      if (owner != null && owner.isNotEmpty && owner != id) {
        // Stored too: the download controller may not be running right now.
        await prefs.setBool(_kWipePending, true);
        _events.add('accountChanged');
      }
      await prefs.setString(_kOwner, id);
      await prefs.setInt(_kCheckedAt, _now().millisecondsSinceEpoch);
      final sub = me['subscription'];
      if (sub is Map) {
        await prefs.setString(_kStatus, '${sub['status'] ?? 'NONE'}');
        final ends = DateTime.tryParse('${sub['expiresAt'] ?? ''}');
        if (ends != null) {
          await prefs.setInt(_kEndsAt, ends.millisecondsSinceEpoch);
        } else {
          await prefs.remove(_kEndsAt);
        }
        final days = sub['offlineDays'];
        await prefs.setInt(_kDays, days is num && days >= 1 ? days.toInt() : defaultOfflineDays);
      } else {
        // Older server or not a customer: no subscription facts, only the check-in time.
        await prefs.remove(_kStatus);
        await prefs.remove(_kEndsAt);
      }
    } catch (e) {
      debugPrint('[OfflinePolicy] record skipped: $e');
    }
  }

  /// The user signed out: downloads are deleted and offline play stops.
  static Future<void> signedOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kWipePending, true);
      // 0 = "checked long ago": anything left on disk needs a new online check.
      await prefs.setInt(_kCheckedAt, 0);
      await prefs.remove(_kStatus);
      await prefs.remove(_kEndsAt);
    } catch (_) {}
    _events.add('signedOut');
  }

  /// True once after a sign-out / account change that has not been handled yet.
  /// A download controller calls this when it starts and deletes every
  /// download if true, then calls [wipeDone].
  static Future<bool> wipePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kWipePending) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> wipeDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kWipePending);
    } catch (_) {}
  }

  /// Null = may play offline; otherwise the reason it may not.
  static Future<OfflineRefusal?> check() async {
    final prefs = await SharedPreferences.getInstance();
    final checked = prefs.getInt(_kCheckedAt);
    if (checked == null) return null; // first run after the update: allowed once
    final now = _now().millisecondsSinceEpoch;
    if (now < checked - const Duration(minutes: 5).inMilliseconds) {
      return OfflineRefusal.clockChanged;
    }
    final status = prefs.getString(_kStatus);
    if (status != null && !_activeStatuses.contains(status)) {
      return OfflineRefusal.subscriptionEnded;
    }
    final ends = prefs.getInt(_kEndsAt);
    if (ends != null && now > ends) return OfflineRefusal.subscriptionEnded;
    final days = prefs.getInt(_kDays) ?? defaultOfflineDays;
    if (now - checked > Duration(days: days).inMilliseconds) {
      return OfflineRefusal.checkInNeeded;
    }
    return null;
  }

  /// Short English text for a refusal (apps may translate).
  static String message(OfflineRefusal r) {
    switch (r) {
      case OfflineRefusal.subscriptionEnded:
        return 'Your subscription has ended. Downloads can be watched again after renewal.';
      case OfflineRefusal.checkInNeeded:
        return 'Connect to the internet once so ${AppBrand.name} can confirm your subscription, then play your downloads.';
      case OfflineRefusal.clockChanged:
        return "Your device's date and time look wrong. Connect to the internet and try again.";
    }
  }
}
