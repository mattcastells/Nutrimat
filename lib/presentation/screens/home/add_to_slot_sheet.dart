import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/enums/enums.dart';
import '../../components/system/overlays.dart';
import '../photo/photo_screens.dart';

/// Qué se agrega a un slot concreto (Desayuno, Almuerzo, Cena, Snacks).
///
/// El "+" de cada sección antes iba derecho al buscador de alimentos, así que
/// la foto con IA solo existía en el menú general de Agregar — y ahí no se
/// elige el slot, se adivina por la hora. Este sheet ofrece las dos entradas
/// **con el slot y el día ya resueltos**: lo que se cargue cae donde se tocó.
Future<void> showAddToSlotSheet(
  BuildContext context, {
  required MealSlot slot,
  required DateTime date,
}) => showNmSheet<void>(
  context: context,
  builder: (context) => _AddToSlotSheet(slot: slot, date: date),
);

class _AddToSlotSheet extends ConsumerWidget {
  const _AddToSlotSheet({required this.slot, required this.date});

  final MealSlot slot;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(String location) {
      Navigator.of(context).pop();
      context.push(location);
    }

    return NmSheet(
      title: 'Agregar a ${slot.label.toLowerCase()}',
      subtitle: friendlyDay(date),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ActionRow(
            icon: PhosphorIcons.forkKnife(),
            label: 'Buscar alimentos',
            subtitle: 'Del catálogo, de los tuyos o por código de barras',
            onTap: () => go(
              '${Routes.mealNew}?slot=${slot.wire}&date=${isoDate(date)}',
            ),
          ),
          ActionRow(
            icon: PhosphorIcons.camera(),
            label: 'Sacar foto y analizarla con IA',
            subtitle: 'La IA estima los ítems y vos los revisás antes de '
                'guardar',
            // Sin servidor no hay Edge Function a la que preguntarle, así que
            // se muestra deshabilitado en vez de fallar al tocarlo.
            enabled: FeatureFlags.aiPhotoAnalysis && SupabaseConfig.isConfigured,
            disabledNote: 'El análisis con IA necesita servidor configurado',
            onTap: () {
              ref.read(photoTargetProvider.notifier).state = PhotoTarget(
                slot: slot,
                date: date,
              );
              go(Routes.photoCapture);
            },
          ),
        ],
      ),
    );
  }
}
