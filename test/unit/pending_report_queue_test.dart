import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/data/local/pending_report_queue.dart';
import 'package:pathable/data/models/geo_point.dart';
import 'package:pathable/data/models/hazard.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('enqueue and remove pending reports', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final queue = PendingReportQueue(prefs);

    final draft = Hazard(
      id: '',
      category: HazardCategory.blockedSidewalk,
      severity: HazardSeverity.moderate,
      status: HazardStatus.provisional,
      location: const GeoPoint(latitude: 29.55, longitude: -95.58),
      confidenceScore: 0.35,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      description: 'Draft',
    );

    final pending = await queue.enqueue(draft);
    expect(pending.id, startsWith('pending-'));
    expect(queue.load(), hasLength(1));

    await queue.remove(pending.id);
    expect(queue.load(), isEmpty);
  });
}