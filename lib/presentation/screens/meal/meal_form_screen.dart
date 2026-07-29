import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/enums/enums.dart';
import '../../components/feedback/feedback.dart';
import '../../components/food/food_widgets.dart';
import '../../components/food/meal_photo.dart';
import '../../components/food/meal_photo_field.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import 'meal_draft.dart';

/// S-15 · Nueva comida. Compone una comida a partir de ítems.
class MealFormScreen extends ConsumerStatefulWidget {
  const MealFormScreen({this.slot, this.date, this.mealId, super.key});

  final MealSlot? slot;
  final DateTime? date;

  /// Cuando viene, se edita una comida existente (RN-16, D-20).
  final String? mealId;

  @override
  ConsumerState<MealFormScreen> createState() => _MealFormScreenState();
}

class _MealFormScreenState extends ConsumerState<MealFormScreen> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(mealDraftProvider.notifier);
      final current = ref.read(mealDraftProvider);

      if (widget.mealId != null) {
        final meal = ref.read(repositoryProvider).mealById(widget.mealId!);
        if (meal != null) controller.edit(meal);
        return;
      }
      // Si ya hay un borrador de esta misma comida, se retoma.
      if (current == null || current.editingMealId != null) {
        controller.start(
          slot: widget.slot ?? MealSlot.forHour(DateTime.now().hour),
          date: widget.date ?? ref.read(selectedDateProvider),
        );
      }
    });
  }

  Future<void> _save() async {
    final draft = ref.read(mealDraftProvider);
    if (draft == null || draft.isEmpty) return;

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final meal = draft.toMeal(
      syncStatus: repo.isOffline ? SyncStatus.pending : SyncStatus.synced,
    );
    await repo.saveMeal(meal);
    ref.read(mealDraftProvider.notifier).clear();
    if (!mounted) return;
    setState(() => _saving = false);

    context.pop();
    NmSnackbar.show(
      context,
      'Comida guardada',
      actionLabel: 'Ver',
      onAction: () => context.push(Routes.meal(meal.id)),
    );
  }

  Future<void> _discard() async {
    final draft = ref.read(mealDraftProvider);
    if (draft != null && !draft.isEmpty) {
      final confirmed = await showNmDialog<bool>(
        context: context,
        builder: (context) => NmDialog(
          title: '¿Descartar la comida?',
          body: 'Vas a perder los ítems que agregaste.',
          actions: <Widget>[
            NmButton.ghost(
              label: 'Seguir editando',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            NmButton(
              label: 'Descartar',
              variant: NmButtonVariant.danger,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    ref.read(mealDraftProvider.notifier).clear();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final draft = ref.watch(mealDraftProvider);
    final controller = ref.read(mealDraftProvider.notifier);

    if (draft == null) {
      return const Scaffold(body: Center(child: NmSpinner()));
    }

    return Scaffold(
      backgroundColor: nm.bg,
      appBar: NmModalHeader(
        title: widget.mealId == null ? 'Nueva comida' : 'Editar comida',
        onClose: _discard,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(context.screenPadding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: NmLayout.contentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Momento del día',
                          style: NmTextStyles.from(
                            NmType.caption,
                            color: nm.textMuted,
                          ),
                        ),
                        const SizedBox(height: NmSpace.s2),
                        Wrap(
                          spacing: NmSpace.s2,
                          runSpacing: NmSpace.s2,
                          children: <Widget>[
                            for (final slot in MealSlot.values)
                              NmChip(
                                label: slot.label,
                                selected: slot == draft.slot,
                                semanticsInRadioGroup: true,
                                onTap: () => controller.setSlot(slot),
                              ),
                          ],
                        ),
                        const SizedBox(height: NmSpace.s6),
                        Row(
                          children: <Widget>[
                            Icon(
                              PhosphorIcons.clockCounterClockwise(),
                              size: NmIconSize.md,
                              color: nm.textMuted,
                            ),
                            const SizedBox(width: NmSpace.s2),
                            Text(
                              '${friendlyDay(draft.date)} · '
                              '${timeOfDay(draft.loggedAt)}',
                              style: NmTextStyles.from(
                                NmType.bodySm,
                                color: nm.textMuted,
                              ).tnum,
                            ),
                            const Spacer(),
                            NmButton.ghost(
                              label: 'Cambiar hora',
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(
                                    draft.loggedAt,
                                  ),
                                );
                                if (picked == null) return;
                                controller.setLoggedAt(
                                  DateTime(
                                    draft.date.year,
                                    draft.date.month,
                                    draft.date.day,
                                    picked.hour,
                                    picked.minute,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: NmSpace.s6),
                        const NmSectionHeader(title: 'Ítems'),
                        if (draft.items.isEmpty)
                          EmptyState(
                            compact: true,
                            icon: PhosphorIcons.magnifyingGlass(),
                            title: 'Agregá el primer alimento',
                            body: 'Buscá en el catálogo, escaneá un código o '
                                'creá uno propio.',
                            primaryLabel: 'Buscar alimento',
                            onPrimary: () => context.push(
                              '${Routes.foodSearch}?target=meal',
                            ),
                          )
                        else
                          NmCard(
                            child: Column(
                              children: <Widget>[
                                for (final item in draft.items)
                                  MealItemRow(
                                    item: item,
                                    onRemove: () =>
                                        controller.removeItem(item.id),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: NmSpace.s4),
                        NmButton.secondary(
                          label: 'Agregar alimento',
                          block: true,
                          icon: PhosphorIcons.plus(),
                          onPressed: () =>
                              context.push('${Routes.foodSearch}?target=meal'),
                        ),
                        const SizedBox(height: NmSpace.s8),
                        const NmSectionHeader(title: 'Foto'),
                        MealPhotoField(
                          path: draft.photoPath,
                          onChanged: controller.setPhoto,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            MealTotalsBar(
              kcal: draft.totalKcal,
              proteinG: draft.proteinG,
              carbsG: draft.carbsG,
              fatG: draft.fatG,
              child: Column(
                children: <Widget>[
                  NmButton(
                    label: 'Guardar comida',
                    block: true,
                    loading: _saving,
                    onPressed: draft.isEmpty ? null : _save,
                  ),
                  if (draft.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: NmSpace.s2),
                      child: Text(
                        'Agregá al menos un alimento para poder guardar.',
                        style: NmTextStyles.from(
                          NmType.caption,
                          color: nm.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detalle de una comida guardada.
class MealDetailScreen extends ConsumerWidget {
  const MealDetailScreen({required this.mealId, super.key});

  final String mealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    ref.watch(appRevisionProvider);
    final repo = ref.watch(repositoryProvider);
    final meal = repo.mealById(mealId);

    if (meal == null || meal.isDeleted) {
      return NmScreen(
        title: 'Comida',
        child: ErrorState(
          message: 'Este registro ya no existe.',
          onRetry: () => context.pop(),
          retryLabel: 'Volver',
        ),
      );
    }

    return NmScreen(
      title: meal.slot.label,
      actions: <Widget>[
        IconButton(
          onPressed: () => context.push(Routes.mealEdit(meal.id)),
          tooltip: 'Editar',
          icon: Icon(PhosphorIcons.pencilSimple()),
        ),
        IconButton(
          onPressed: () async {
            final confirmed = await confirmDelete(
              context,
              title: '¿Eliminar la comida?',
              body: 'Podés deshacer durante unos segundos.',
            );
            if (!confirmed || !context.mounted) return;
            await repo.deleteMeal(meal.id);
            if (!context.mounted) return;
            context.pop();
            NmSnackbar.show(
              context,
              'Comida eliminada',
              actionLabel: 'Deshacer',
              undo: true,
              onAction: () => repo.restoreMeal(meal.id),
            );
          },
          tooltip: 'Eliminar',
          icon: Icon(PhosphorIcons.trash()),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          if (meal.photoPath != null) ...<Widget>[
            MealPhoto(path: meal.photoPath, height: 200),
            const SizedBox(height: NmSpace.s4),
          ],
          Text(
            '${longDay(meal.localDate)} · ${timeOfDay(meal.loggedAt)}',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted).tnum,
          ),
          const SizedBox(height: NmSpace.s6),
          NmCard(
            child: Column(
              children: <Widget>[
                for (final item in meal.items) MealItemRow(item: item),
                const NmDivider(),
                ValueRow(
                  label: 'Total',
                  value: '${meal.totalKcal} kcal',
                  emphasis: true,
                ),
                ValueRow(
                  label: 'Proteínas',
                  value: '${meal.totalProteinG.round()} g',
                  muted: true,
                ),
                ValueRow(
                  label: 'Carbohidratos',
                  value: '${meal.totalCarbsG.round()} g',
                  muted: true,
                ),
                ValueRow(
                  label: 'Grasas',
                  value: '${meal.totalFatG.round()} g',
                  muted: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s4),
          Row(
            children: <Widget>[
              NmButton.ghost(
                label: meal.isFavorite
                    ? 'Quitar de favoritas'
                    : 'Marcar como favorita',
                onPressed: () => repo.toggleMealFavorite(meal.id),
              ),
              NmButton.ghost(
                label: 'Duplicar hoy',
                onPressed: () async {
                  await repo.duplicateMeal(meal.id, today(), meal.slot);
                  if (!context.mounted) return;
                  NmSnackbar.show(context, 'Comida duplicada en el día de hoy');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
