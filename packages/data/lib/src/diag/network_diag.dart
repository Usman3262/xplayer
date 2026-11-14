import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../device/device_capabilities_store.dart';
import 'diag.dart';

/// Safe network / VPN / egress snapshot for regional playback debugging.
/// Never logs stream URLs, tokens, or credentials.
class AppNetworkSnapshot {
  const AppNetworkSnapshot({
    required this.context,
    this.sessionId,
    this.vpnActive,
    this.transports = const [],
    this.validated,
    this.captivePortal,
    this.metered,
    this.dnsServers = const [],
    this.timezone,
    this.localeCountry,
    this.egressIp,
    this.egressCountry,
    this.egressColo,
    this.streamHost,
    this.streamHostIps,
    this.egressLookupError,
    this.dnsLookupError,
    this.nativeError,
  });

  final String context;
  final String? sessionId;
  final bool? vpnActive;
  final List<String> transports;
  final bool? validated;
  final bool? captivePortal;
  final bool? metered;
  final List<String> dnsServers;
  final String? timezone;
  final String? localeCountry;
  final String? egressIp;
  final String? egressCountry;
  final String? egressColo;
  final String? streamHost;
  final String? streamHostIps;
  final String? egressLookupError;
  final String? dnsLookupError;
  final String? nativeError;

  String toLogLine() {
    final sid = sessionId != null ? 's=$sessionId ' : '';
    final vpn = vpnActive == null ? 'vpn=?' : 'vpn=$vpnActive';
    final tx =
        transports.isEmpty ? 'transports=?' : 'transports=${transports.join("+")}';
    final val = validated == null ? 'validated=?' : 'validated=$validated';
    final cap =
        captivePortal == null ? 'captive=?' : 'captive=$captivePortal';
    final met = metered == null ? 'metered=?' : 'metered=$metered';
    final dns =
        dnsServers.isEmpty ? 'dns=?' : 'dns=${dnsServers.join(",")}';
    final tz = timezone ?? '?';
    final loc = localeCountry ?? '?';
    final ip = egressIp ?? '?';
    final cc = egressCountry ?? '?';
    final colo = egressColo ?? '?';
    final host = streamHost ?? '-';
    final resolved = streamHostIps ?? '-';
    final buf = StringBuffer(
      '$sid ctx=$context $vpn $tx $val $cap $met $dns '
      'tz=$tz localeCountry=$loc egressIp=$ip egressCountry=$cc colo=$colo '
      'streamHost=$host resolved=$resolved',
    );
    if (egressLookupError != null) buf.write(' egressErr=$egressLookupError');
    if (dnsLookupError != null) buf.write(' dnsErr=$dnsLookupError');
    if (nativeError != null) buf.write(' nativeErr=$nativeError');
    return buf.toString();
  }
}

Future<Map<String, dynamic>?> _nativeNetworkDiagnostics() async {
  if (!Platform.isAndroid) return null;
  try {
    const ch = MethodChannel(kDeviceChannel);
    final raw =
        await ch.invokeMethod<Map<dynamic, dynamic>>('getNetworkDiagnostics');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw);
  } catch (e) {
    return {'error': '$e'};
  }
}

Future<({String? ip, String? country, String? colo, String? error})>
    _egressHint() async {
  try {
    final res = await http
        .get(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'))
        .timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) {
      return (ip: null, country: null, colo: null, error: 'http_${res.statusCode}');
    }
    String? ip;
    String? loc;
    String? colo;
    for (final line in res.body.split('\n')) {
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      final k = line.substring(0, idx);
      final v = line.substring(idx + 1).trim();
      switch (k) {
        case 'ip':
          ip = v;
        case 'loc':
          loc = v;
        case 'colo':
          colo = v;
      }
    }
    return (ip: ip, country: loc, colo: colo, error: null);
  } on TimeoutException {
    return (ip: null, country: null, colo: null, error: 'timeout');
  } catch (e) {
    return (ip: null, country: null, colo: null, error: '$e');
  }
}

Future<String?> _resolveStreamHost(String? host) async {
  if (host == null || host.isEmpty) return null;
  try {
    final addrs = await InternetAddress.lookup(host)
        .timeout(const Duration(seconds: 5));
    if (addrs.isEmpty) return 'empty';
    return addrs.map((a) => a.address).join(',');
  } on TimeoutException {
    return 'lookup_timeout';
  } catch (e) {
    return 'lookup_failed:$e';
  }
}

/// Collect network + VPN + egress country (via Cloudflare trace) + optional CDN host DNS.
Future<AppNetworkSnapshot> collectNetworkSnapshot({
  required String context,
  String? sessionId,
  String? streamHost,
  bool includeEgress = true,
}) async {
  final native = await _nativeNetworkDiagnostics();
  String? nativeError;
  bool? vpn;
  List<String> transports = const [];
  bool? validated;
  bool? captive;
  bool? metered;
  List<String> dns = const [];
  String? tz;
  String? localeCountry;

  if (native != null) {
    if (native.containsKey('error')) {
      nativeError = '${native['error']}';
    } else {
      vpn = native['vpnActive'] == true;
      final tx = native['transports'];
      if (tx is List) transports = tx.map((e) => '$e').toList();
      validated = native['validated'] as bool?;
      captive = native['captivePortal'] as bool?;
      metered = native['metered'] as bool?;
      final dnsRaw = native['dnsServers'];
      if (dnsRaw is List) dns = dnsRaw.map((e) => '$e').toList();
      tz = native['timezone'] as String?;
      localeCountry = native['localeCountry'] as String?;
    }
  }

  String? egressIp;
  String? egressCountry;
  String? egressColo;
  String? egressErr;
  if (includeEgress) {
    final hint = await _egressHint();
    egressIp = hint.ip;
    egressCountry = hint.country;
    egressColo = hint.colo;
    egressErr = hint.error;
  }

  String? resolved;
  String? dnsErr;
  if (streamHost != null && streamHost.isNotEmpty) {
    final r = await _resolveStreamHost(streamHost);
    if (r != null && r.startsWith('lookup_failed:')) {
      dnsErr = r;
      resolved = null;
    } else {
      resolved = r;
    }
  }

  return AppNetworkSnapshot(
    context: context,
    sessionId: sessionId,
    vpnActive: vpn,
    transports: transports,
    validated: validated,
    captivePortal: captive,
    metered: metered,
    dnsServers: dns,
    timezone: tz,
    localeCountry: localeCountry,
    egressIp: egressIp,
    egressCountry: egressCountry,
    egressColo: egressColo,
    streamHost: streamHost,
    streamHostIps: resolved,
    egressLookupError: egressErr,
    dnsLookupError: dnsErr,
    nativeError: nativeError,
  );
}

Future<void> logNetworkDiagnostics({
  required String context,
  String? sessionId,
  String? streamHost,
}) async {
  if (!DiagConfig.isOn) return;
  try {
    final snap = await collectNetworkSnapshot(
      context: context,
      sessionId: sessionId,
      streamHost: streamHost,
    );
    Diag.net(snap.toLogLine());
  } catch (e, st) {
    Diag.err('NET snapshot failed ctx=$context', e, st);
  }
}
