import 'dart:async';
import 'dart:collection';

import '../diag/diag.dart';

typedef ProgressJob = Future<void> Function();

/// Background progress/stop/dispose queue that survives route pop (brief §1.4).
class ProgressSyncQueue {
  ProgressSyncQueue._();
  static final instance = ProgressSyncQueue._();

  final Queue<_Job> _q = Queue<_Job>();
  bool _running = false;

  void enqueue(ProgressJob job, {String label = 'job'}) {
    _q.add(_Job(job, label));
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    while (_q.isNotEmpty) {
      final j = _q.removeFirst();
      var attempt = 0;
      while (true) {
        attempt++;
        try {
          await j.fn();
          Diag.pb('cleanup ${j.label}=ok attempt=$attempt');
          break;
        } catch (e, st) {
          Diag.err('cleanup ${j.label} attempt=$attempt', e, st);
          if (attempt >= 3) break;
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }
    _running = false;
  }
}

class _Job {
  _Job(this.fn, this.label);
  final ProgressJob fn;
  final String label;
}
