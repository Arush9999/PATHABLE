import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/pending_report_queue.dart';
import '../models/hazard.dart';
import '../repositories/hazard_repository.dart';

/// Retries local draft reports once the backend is reachable.
class PendingReportFlusher {
  PendingReportFlusher({
    required SharedPreferences prefs,
    required this.repository,
    Connectivity? connectivity,
  })  : _queue = PendingReportQueue(prefs),
        _connectivity = connectivity ?? Connectivity();

  final HazardRepository repository;
  final PendingReportQueue _queue;
  final Connectivity _connectivity;

  List<Hazard> get pending => _queue.load();

  Future<int> flush() async {
    final items = _queue.load();
    if (items.isEmpty) return 0;

    final status = await _connectivity.checkConnectivity();
    final offline = status.every((s) => s == ConnectivityResult.none);
    if (offline) return 0;

    var flushed = 0;
    for (final draft in items) {
      try {
        await repository.create(draft);
        await _queue.remove(draft.id);
        flushed++;
      } catch (error, stack) {
        debugPrint('Pending report ${draft.id} still queued: $error\n$stack');
      }
    }
    return flushed;
  }
}
