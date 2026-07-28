import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/utils/dates.dart';
import 'data/local/local_auth_gateway.dart';
import 'data/local/local_store.dart';
import 'data/remote/supabase_auth_gateway.dart';
import 'data/repositories/local_repository.dart';
import 'domain/repositories/auth_gateway.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/providers/auth_providers.dart';

/// Arranque: base local, formatos de fecha, sesión y contenedor de providers.
///
/// Los datos siguen viviendo en el teléfono (`data/local/`). Lo que sí es real
/// es la **sesión**: si la compilación trae credenciales de Supabase, se
/// autentica contra el servidor; si no, cae a una sesión local que no
/// autentica nada y lo dice (19-project-structure.md §5).
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

  // Con credenciales, `supabase_flutter` restaura la sesión guardada y se
  // encarga de refrescar el token. Sin ellas la app arranca igual, en local.
  final AuthGateway auth;
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    auth = SupabaseAuthGateway.fromInstance();
  } else {
    auth = LocalAuthGateway();
  }

  final store = await LocalStore.open();

  // El repositorio avisa a la UI por el contador de revisión; se enlaza
  // después de crear el contenedor para evitar la dependencia circular.
  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());

  final container = ProviderContainer(
    overrides: <Override>[
      repositoryProvider.overrideWithValue(repository),
      authGatewayProvider.overrideWithValue(auth),
    ],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NutrimatApp(),
    ),
  );
}
