// Live check of the app's account code against the real Supabase project.
// Opt-in (XPLAYER_LIVE_TESTS=1). No widget binding: real HTTP must be allowed.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:player_mobile/core/account.dart';
import 'package:supabase/supabase.dart';

void main() {
  // LIVE (opt-in): the app's own account code against the real project.
  final adminEnv = File('../admin/.env.local');
  test('LIVE: sign in / out through SupabaseAccountAuth with a temporary user', () async {
    final env = jsonDecode(File('../../env/app.json').readAsStringSync()) as Map;
    final url = '${env['SUPABASE_URL']}';
    final pub = '${env['SUPABASE_PUBLISHABLE_KEY']}';
    final secret = adminEnv
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('SUPABASE_SECRET_KEY='))
        .substring('SUPABASE_SECRET_KEY='.length)
        .trim();
    final email = 'zz-app-${Random().nextInt(1 << 30)}@xplayer.test';
    const password = 'Live-test-pass-123';
    final created = await http.post(
      Uri.parse('$url/auth/v1/admin/users'),
      headers: {'apikey': secret, 'Authorization': 'Bearer $secret', 'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password, 'email_confirm': true}),
    );
    final userId = (jsonDecode(created.body) as Map)['id'] as String;
    try {
      final auth = SupabaseAccountAuth(SupabaseClient(url, pub));
      AccountService.useAuth(auth);
      await expectLater(AccountService.signIn(email, 'wrong-password'),
          throwsA(isA<AccountException>().having((e) => e.error, 'error', AccountError.invalid)));
      await AccountService.signIn(email, password);
      expect(AccountService.user.value?.email, email);
      await AccountService.signOut();
      expect(AccountService.signedIn, isFalse);
    } finally {
      await http.delete(
        Uri.parse('$url/auth/v1/admin/users/$userId'),
        headers: {'apikey': secret, 'Authorization': 'Bearer $secret'},
      );
    }
  },
      skip: Platform.environment['XPLAYER_LIVE_TESTS'] == '1' && adminEnv.existsSync() ? false : 'set XPLAYER_LIVE_TESTS=1',
      timeout: const Timeout(Duration(seconds: 60)));
}
