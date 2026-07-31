import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../data/local/update_prompt_store.dart';
import '../../../domain/models/app_release.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';
import '../../providers/update_providers.dart';

/// Se sobrescribe en los tests. Sin esto, cualquier prueba que monte el shell
/// saldría a la API de GitHub.
final updatePromptStoreProvider = FutureProvider<UpdatePromptStore>(
  (ref) => UpdatePromptStore.open(),
);

/// Busca si hay una versión nueva al abrir la app y, si la hay, la ofrece.
///
/// Nutrimat se distribuye por fuera de Play Store: nadie le avisa a nadie que
/// salió una versión. Mientras la comprobación fue solo manual —Configuración →
/// Actualizaciones, y había que acordarse de entrar— el resultado fue gente
/// corriendo versiones de meses atrás sin enterarse, incluida la que tenía rota
/// justamente la actualización. Un aviso que hay que ir a buscar no es un aviso.
///
/// Lo que se hace sin permiso es **preguntar**, no bajar: la consulta es un JSON
/// de unos kilobytes contra la API de releases. Los 25 MB del APK siguen
/// necesitando que alguien lo pida, y siguen bajando por la misma pantalla de
/// siempre, con su permiso de instalación y su barra de progreso.
///
/// Tres frenos, para que esto no se vuelva ruido:
///
/// - se consulta como mucho cada [UpdatePromptStore.checkInterval];
/// - "Ahora no" calla el aviso **de esa versión**, no de todas;
/// - si la consulta falla, no pasa nada y no se dice nada: no lo pidió nadie.
Future<void> maybePromptForUpdate(BuildContext context, WidgetRef ref) async {
  final UpdatePromptStore store;
  try {
    store = await ref.read(updatePromptStoreProvider.future);
  } on Object {
    return;
  }
  if (!store.shouldCheck()) return;

  // Se anota antes de salir a la red y no después: si la consulta se cuelga o
  // falla, no queremos reintentar en cada arranque contra un servidor que no
  // está respondiendo.
  await store.markChecked();

  UpdateStatus? status;
  try {
    final current = await ref.read(installedVersionProvider.future);
    status = await ref.read(updateServiceProvider).check(current: current);
  } on Object {
    // Sin conexión, con la API caída o en una plataforma sin `package_info`:
    // esto es un extra silencioso, no una función que pueda fallar a la vista.
    return;
  }

  final available = status;
  if (available is! UpdateAvailable) return;
  final version = available.release.version.toString();
  if (store.isPostponed(version)) return;
  if (!context.mounted) return;

  final accepted = await showNmDialog<bool>(
    context: context,
    builder: (context) => NmDialog(
      title: 'Hay una versión nueva',
      body:
          'Tenés la ${available.current} y está publicada la $version '
          '(${available.release.apkSizeLabel}). La descarga la hacés vos desde '
          'Actualizaciones, con Wi-Fi si preferís.',
      actions: <Widget>[
        NmButton.ghost(
          label: 'Ahora no',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NmButton(
          label: 'Ver qué cambió',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );

  // Cerrar tocando afuera no es decir que no: ahí el aviso vuelve en la próxima
  // ventana de consulta. Solo el "Ahora no" explícito calla esta versión.
  if (accepted == false) {
    await store.postpone(version);
    return;
  }
  if (accepted != true || !context.mounted) return;
  unawaited(context.push(Routes.updates));
}
