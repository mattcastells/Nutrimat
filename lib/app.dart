import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/app_providers.dart';

/// La app: tema, router y localización.
///
/// Idioma inicial español rioplatense; la estructura de i18n está desde el día
/// uno aunque se entregue un solo idioma (D-19, S-06 del PRD).
class NutrimatApp extends ConsumerWidget {
  const NutrimatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Nutrimat',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: themeMode,
      theme: NmAppTheme.light(),
      darkTheme: NmAppTheme.dark(),
      locale: const Locale('es', 'AR'),
      supportedLocales: const <Locale>[Locale('es', 'AR'), Locale('es')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Soporte de escalado de texto hasta 200 % sin pérdida de contenido
        // (05-component-library §5).
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 2,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
