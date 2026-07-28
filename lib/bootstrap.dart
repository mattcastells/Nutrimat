import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/utils/dates.dart';
import 'data/local/local_store.dart';
import 'data/repositories/local_repository.dart';
import 'presentation/providers/app_providers.dart';

/// Arranque: base local, formatos de fecha y el contenedor de providers.
///
/// Todavía no hay Supabase, Sentry ni analítica: el entorno es `mock` y la app
/// corre entera contra `data/mock/` con datos simulados realistas
/// (19-project-structure.md §5).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  await initializeDateFormatting(appLocale);

  final store = await LocalStore.open();

  // El repositorio avisa a la UI por el contador de revisión; se enlaza
  // después de crear el contenedor para evitar la dependencia circular.
  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());

  final container = ProviderContainer(
    overrides: <Override>[repositoryProvider.overrideWithValue(repository)],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NutrimatApp(),
    ),
  );
}
