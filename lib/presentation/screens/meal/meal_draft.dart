import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/dates.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/meal.dart';

const _uuid = Uuid();

/// Borrador de `/meal/new` y de la revisión de IA.
///
/// El borrador sobrevive a la navegación al buscador de alimentos y se
/// persistiría en `drafts` con vencimiento a las 48 h (13-state §2).
class MealDraft {
  const MealDraft({
    required this.id,
    required this.slot,
    required this.date,
    required this.loggedAt,
    required this.items,
    required this.source,
    this.editingMealId,
    this.photoPath,
    this.aiAnalysisId,
  });

  final String id;
  final MealSlot slot;
  final DateTime date;
  final DateTime loggedAt;
  final List<MealItem> items;
  final MealSource source;
  final String? editingMealId;
  final String? photoPath;
  final String? aiAnalysisId;

  int get totalKcal => items.fold(0, (acc, i) => acc + i.kcal);
  double get proteinG => items.fold(0.0, (acc, i) => acc + i.proteinG);
  double get carbsG => items.fold(0.0, (acc, i) => acc + i.carbsG);
  double get fatG => items.fold(0.0, (acc, i) => acc + i.fatG);

  bool get isEmpty => items.isEmpty;

  MealDraft copyWith({
    MealSlot? slot,
    DateTime? date,
    DateTime? loggedAt,
    List<MealItem>? items,
    MealSource? source,
    String? photoPath,
    String? aiAnalysisId,
  }) => MealDraft(
    id: id,
    slot: slot ?? this.slot,
    date: date ?? this.date,
    loggedAt: loggedAt ?? this.loggedAt,
    items: items ?? this.items,
    source: source ?? this.source,
    editingMealId: editingMealId,
    photoPath: photoPath ?? this.photoPath,
    aiAnalysisId: aiAnalysisId ?? this.aiAnalysisId,
  );

  Meal toMeal({required SyncStatus syncStatus, DateTime? createdAt}) => Meal(
    id: editingMealId ?? id,
    slot: slot,
    loggedAt: loggedAt,
    localDate: dateOnly(date),
    items: <MealItem>[
      for (var i = 0; i < items.length; i++) items[i].copyWith(position: i),
    ],
    source: source,
    photoPath: photoPath,
    aiAnalysisId: aiAnalysisId,
    syncStatus: syncStatus,
    createdAt: createdAt ?? DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

class MealDraftController extends Notifier<MealDraft?> {
  @override
  MealDraft? build() => null;

  void start({
    required MealSlot slot,
    required DateTime date,
    MealSource source = MealSource.manual,
    String? photoPath,
    String? aiAnalysisId,
    List<MealItem> items = const <MealItem>[],
  }) {
    final now = DateTime.now();
    state = MealDraft(
      id: _uuid.v4(),
      slot: slot,
      date: date,
      loggedAt: DateTime(
        date.year,
        date.month,
        date.day,
        now.hour,
        now.minute,
      ),
      items: items,
      source: source,
      photoPath: photoPath,
      aiAnalysisId: aiAnalysisId,
    );
  }

  void edit(Meal meal) {
    state = MealDraft(
      id: meal.id,
      slot: meal.slot,
      date: meal.localDate,
      loggedAt: meal.loggedAt,
      items: meal.items,
      source: meal.source,
      editingMealId: meal.id,
      photoPath: meal.photoPath,
      aiAnalysisId: meal.aiAnalysisId,
    );
  }

  void addItem(MealItem item) {
    final draft = state;
    if (draft == null) return;
    state = draft.copyWith(items: <MealItem>[...draft.items, item]);
  }

  void replaceItem(int index, MealItem item) {
    final draft = state;
    if (draft == null) return;
    final items = <MealItem>[...draft.items];
    items[index] = item;
    state = draft.copyWith(items: items);
  }

  void removeItem(String itemId) {
    final draft = state;
    if (draft == null) return;
    state = draft.copyWith(
      items: draft.items.where((i) => i.id != itemId).toList(),
    );
  }

  /// Adjunta o quita la foto.
  ///
  /// No usa `copyWith`: ese resuelve el null como "no cambies", así que por ahí
  /// no habría forma de sacar una foto ya puesta.
  void setPhoto(String? path) {
    final current = state;
    if (current == null) return;
    state = MealDraft(
      id: current.id,
      slot: current.slot,
      date: current.date,
      loggedAt: current.loggedAt,
      items: current.items,
      source: current.source,
      editingMealId: current.editingMealId,
      photoPath: path,
      aiAnalysisId: current.aiAnalysisId,
    );
  }

  void setSlot(MealSlot slot) => state = state?.copyWith(slot: slot);

  void setLoggedAt(DateTime value) => state = state?.copyWith(loggedAt: value);

  void clear() => state = null;
}

final mealDraftProvider = NotifierProvider<MealDraftController, MealDraft?>(
  MealDraftController.new,
);
