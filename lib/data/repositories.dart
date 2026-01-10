import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/drill.dart';
import '../models/plan.dart';
import 'hive_boxes.dart';

final _uuid = Uuid();

final drillsRepoProvider = Provider((ref) => DrillsRepository());
final plansRepoProvider = Provider((ref) => PlansRepository());

final drillsProvider = StreamProvider<List<Drill>>((ref) {
  final repo = ref.read(drillsRepoProvider);
  return repo.watchAll();
});

final plansProvider = StreamProvider<List<PracticePlan>>((ref) {
  final repo = ref.read(plansRepoProvider);
  return repo.watchAll();
});

class DrillsRepository {
  Box get _box => Hive.box(HiveBoxes.drills);

  Stream<List<Drill>> watchAll() async* {
    yield getAll();
    yield* _box.watch().map((_) => getAll());
  }

  List<Drill> getAll() {
    final values = _box.values
        .map((e) => Drill.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    values.sort((a, b) => a.title.compareTo(b.title));
    return values;
  }

  Drill? getById(String id) {
    final map = _box.get(id);
    if (map == null) return null;
    return Drill.fromMap(Map<String, dynamic>.from(map));
  }
}

class PlansRepository {
  Box get _box => Hive.box(HiveBoxes.plans);

  Stream<List<PracticePlan>> watchAll() async* {
    yield getAll();
    yield* _box.watch().map((_) => getAll());
  }

  List<PracticePlan> getAll() {
    final values = _box.values
        .map((e) => PracticePlan.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    values.sort((a, b) => a.title.compareTo(b.title));
    return values;
  }

  PracticePlan? getById(String id) {
    final map = _box.get(id);
    if (map == null) return null;
    return PracticePlan.fromMap(Map<String, dynamic>.from(map));
  }

  Future<PracticePlan> createPlan({required String title}) async {
    final plan = PracticePlan(id: _uuid.v4(), title: title, items: const []);
    await _box.put(plan.id, plan.toMap());
    return plan;
  }

  Future<void> save(PracticePlan plan) => _box.put(plan.id, plan.toMap());

  Future<void> delete(String id) => _box.delete(id);
}
