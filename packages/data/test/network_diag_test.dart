import 'package:data/src/diag/network_diag.dart';
import 'package:test/test.dart';

void main() {
  test('AppNetworkSnapshot log line includes vpn and egress', () {
    const snap = AppNetworkSnapshot(
      context: 'open_start',
      sessionId: 'ab12',
      vpnActive: true,
      transports: ['vpn', 'wifi'],
      validated: true,
      egressCountry: 'SA',
      streamHost: 'cdn.example.com',
      streamHostIps: '1.2.3.4',
    );
    final line = snap.toLogLine();
    expect(line, contains('ctx=open_start'));
    expect(line, contains('vpn=true'));
    expect(line, contains('egressCountry=SA'));
    expect(line, contains('streamHost=cdn.example.com'));
    expect(line, contains('resolved=1.2.3.4'));
  });
}
