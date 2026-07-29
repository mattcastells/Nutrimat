import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/utils/dates.dart';
import 'data/local/android_reminder_scheduler.dart';
import 'data/local/local_auth_gateway.dart';
import 'data/local/local_store.dart';
import 'data/remote/cloud_backup_client.dart';
import 'data/remote/gemini_analysis_client.dart';
import 'data/remote/pals_client.dart';
import 'data/remote/photo_storage_client.dart';
import 'data/remote/supabase_auth_gateway.dart';
import 'data/repositories/local_repository.dart';
import 'domain/models/pal.dart';
import 'domain/repositories/auth_gateway.dart';
import 'domain/services/cloud_backup_service.dart';
import 'domain/services/pal_publisher.dart';
import 'domain/services/photo_sync_service.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/reminder_providers.dart';

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

  // Con servidor, cada cambio local dispara un respaldo a la nube. Sin
  // servidor no hay a dónde subir y el servicio queda en null: el respaldo
  // sigue siendo el archivo JSON de Configuración → Privacidad.
  // Recordatorios locales: no necesitan servidor ni cuenta.
  final reminderScheduler = await AndroidReminderScheduler.create();

  final CloudBackupService? backup = SupabaseConfig.isConfigured
      ? CloudBackupService(
          client: CloudBackupClient.fromInstance(),
          auth: auth,
          readDocument: () => jsonEncode(store.toDocument()),
          localHasData: () => store.hasUserData,
        )
      : null;

  // Las fotos van al bucket, no al respaldo: una ruta de archivo del teléfono
  // guardada en el JSON apunta a algo que en otro dispositivo no existe.
  final photos = SupabaseConfig.isConfigured
      ? PhotoSyncService(
          client: PhotoStorageClient.fromInstance(),
          auth: auth,
        )
      : null;

  // Lo que ven los pals. Se arma acá y no en el repositorio para que quede a
  // la vista qué se publica: momento, nombre y calorías por comida, más
  // minutos y sesiones. Nada de peso, medidas, ítems ni fotos.
  PalPublisher? palPublisher;

  // El repositorio avisa a la UI por el contador de revisión; se enlaza
  // después de crear el contenedor para evitar la dependencia circular.
  void Function() notify = () {};
  final repository = LocalRepository(
    store,
    photos: photos,
    aiAnalysis: SupabaseConfig.isConfigured
        ? GeminiAnalysisClient.fromInstance()
        : null,
    onChanged: () {
      notify();
      backup?.markDirty();
      palPublisher?.markDirty();
    },
  );

  final PalsClient? palsClient = SupabaseConfig.isConfigured
      ? PalsClient.fromInstance()
      : null;

  if (palsClient != null) {
    palPublisher = PalPublisher(
      client: palsClient,
      auth: auth,
      buildDay: (date) => PalDay(
        userId: auth.currentAccount?.id ?? '',
        date: date,
        meals: <PalMeal>[
          for (final meal in repository.mealsOn(date))
            PalMeal(
              slot: meal.slot,
              // El nombre de la comida es el del primer ítem: alcanza para
              // "cargó una milanesa" sin publicar la lista entera.
              name: meal.items.isEmpty ? 'Comida' : meal.items.first.name,
              kcal: meal.totalKcal,
            ),
        ],
        activityMinutes: repository
            .activitiesOn(date)
            .fold(0, (acc, a) => acc + a.durationMinutes),
        activityCount: repository.activitiesOn(date).length,
      ),
    );
  }

  final container = ProviderContainer(
    overrides: <Override>[
      repositoryProvider.overrideWithValue(repository),
      authGatewayProvider.overrideWithValue(auth),
      if (backup != null) cloudBackupProvider.overrideWithValue(backup),
      if (photos != null) photoSyncProvider.overrideWithValue(photos),
      if (palsClient != null) palsClientProvider.overrideWithValue(palsClient),
      if (reminderScheduler != null)
        reminderSchedulerProvider.overrideWithValue(reminderScheduler),
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
