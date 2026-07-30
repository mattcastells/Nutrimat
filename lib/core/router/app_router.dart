import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/enums/enums.dart';
import '../../presentation/providers/app_providers.dart';
import '../../presentation/screens/activity/activity_form_screen.dart';
import '../../presentation/screens/activity/activity_screens.dart';
import '../../presentation/screens/auth/auth_screens.dart';
import '../../presentation/screens/auth/splash_screen.dart';
import '../../presentation/screens/auth/welcome_screen.dart';
import '../../presentation/screens/food/food_screens.dart';
import '../../presentation/screens/history/day_detail_screen.dart';
import '../../presentation/screens/history/history_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/meal/meal_describe_screen.dart';
import '../../presentation/screens/meal/meal_form_screen.dart';
import '../../presentation/screens/pals/pal_day_screen.dart';
import '../../presentation/screens/pals/pal_sharing_screen.dart';
import '../../presentation/screens/pals/pals_screen.dart';
import '../../presentation/screens/photo/photo_screens.dart';
import '../../presentation/screens/profile/body_target_screens.dart';
import '../../presentation/screens/profile/goal_picker_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/progress/progress_detail_screens.dart';
import '../../presentation/screens/progress/progress_screen.dart';
import '../../presentation/screens/settings/cloud_backup_screen.dart';
import '../../presentation/screens/settings/notifications_screen.dart';
import '../../presentation/screens/settings/settings_screens.dart';
import '../../presentation/screens/settings/updates_screen.dart';
import '../../presentation/screens/settings/water_goal_screen.dart';
import '../../presentation/shell/app_shell.dart';
import 'routes.dart';

/// El router con todas las rutas de la arquitectura de información
/// (02-information-architecture.md).
///
/// El shell autenticado usa cuatro ramas: cada tab conserva su propio stack de
/// navegación y su posición de scroll (§4).
final routerProvider = Provider<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: Routes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final repo = ref.read(repositoryProvider);
      final location = state.matchedLocation;
      final isPublic =
          location == Routes.splash ||
          location == Routes.welcome ||
          location.startsWith('/auth');

      // Cualquier ruta protegida sin sesión vuelve a la bienvenida.
      if (!repo.hasSession && !isPublic) return Routes.welcome;

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) =>
            SignInScreen(initialEmail: state.uri.queryParameters['email']),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.checkEmail,
        builder: (context, state) => CheckEmailScreen(
          email: state.uri.queryParameters['email'],
          intent: state.uri.queryParameters['intent'] ?? 'signup',
        ),
      ),
      // ── Shell autenticado ────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: rootKey,
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.pals,
                builder: (context, state) => const PalsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'sharing',
                    builder: (context, state) => const PalSharingScreen(),
                  ),
                  GoRoute(
                    path: ':userId',
                    builder: (context, state) => PalDayScreen(
                      userId: state.pathParameters['userId']!,
                      name: state.uri.queryParameters['name'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.progress,
                builder: (context, state) => const ProgressScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Rutas que se abren sobre el shell ────────────────────────────
      GoRoute(
        path: Routes.progressWeight,
        builder: (context, state) => const WeightChartScreen(),
      ),
      GoRoute(
        path: Routes.progressCalories,
        builder: (context, state) => const CaloriesChartScreen(),
      ),
      GoRoute(
        path: Routes.progressActivity,
        builder: (context, state) => const ActivityProgressScreen(),
      ),
      GoRoute(
        path: Routes.progressGoals,
        builder: (context, state) => const ActivityGoalsScreen(),
      ),
      GoRoute(
        path: Routes.progressMeasurements,
        builder: (context, state) => const MeasurementsScreen(),
      ),
      GoRoute(
        path: Routes.progressHistory,
        builder: (context, state) => const HistoryScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: ':date',
            builder: (context, state) => DayDetailScreen(
              date: DateTime.parse(state.pathParameters['date']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.profileBody,
        builder: (context, state) => const BodyProfileScreen(),
      ),
      GoRoute(
        path: Routes.profileGoal,
        builder: (context, state) => const GoalPickerScreen(),
      ),
      GoRoute(
        path: Routes.welcomeGoal,
        builder: (context, state) => const GoalPickerScreen(isFirstTime: true),
      ),
      GoRoute(
        path: Routes.profileTarget,
        builder: (context, state) => const TargetScreen(),
      ),
      GoRoute(
        path: Routes.profileFoods,
        builder: (context, state) => const MyItemsScreen(),
      ),
      GoRoute(
        path: Routes.profileTemplates,
        builder: (context, state) => const MyItemsScreen(initialTab: 1),
      ),
      GoRoute(
        path: Routes.profileFavorites,
        builder: (context, state) => const MyItemsScreen(initialTab: 2),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.exerciseCredit,
        builder: (context, state) => const ExerciseCreditScreen(),
      ),
      GoRoute(
        path: Routes.units,
        builder: (context, state) => const UnitsScreen(),
      ),
      GoRoute(
        path: Routes.appearance,
        builder: (context, state) => const AppearanceScreen(),
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.integrations,
        builder: (context, state) => const IntegrationsScreen(),
      ),
      GoRoute(
        path: Routes.privacy,
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: Routes.deleteAccount,
        builder: (context, state) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: Routes.cloudBackup,
        builder: (context, state) => const CloudBackupScreen(),
      ),
      GoRoute(
        path: Routes.water,
        builder: (context, state) => const WaterGoalScreen(),
      ),
      GoRoute(
        path: Routes.updates,
        builder: (context, state) => const UpdatesScreen(),
      ),
      GoRoute(
        path: Routes.about,
        builder: (context, state) => const AboutScreen(),
      ),

      // Comida.
      GoRoute(
        path: Routes.mealNew,
        builder: (context, state) => MealFormScreen(
          slot: state.uri.queryParameters['slot'] == null
              ? null
              : MealSlot.fromWire(state.uri.queryParameters['slot']!),
          date: state.uri.queryParameters['date'] == null
              ? null
              : DateTime.parse(state.uri.queryParameters['date']!),
          // "Escanear alimento" del menú Agregar entra por acá: el escáner
          // necesita una comida abierta debajo, si no lo que se escanea no
          // tiene dónde caer.
          scanOnOpen: state.uri.queryParameters['scan'] == '1',
        ),
      ),
      GoRoute(
        path: Routes.mealDescribe,
        builder: (context, state) => const MealDescribeScreen(),
      ),
      GoRoute(
        path: '/meal/:mealId',
        builder: (context, state) =>
            MealDetailScreen(mealId: state.pathParameters['mealId']!),
        routes: <RouteBase>[
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                MealFormScreen(mealId: state.pathParameters['mealId']),
          ),
        ],
      ),

      // Foto con IA.
      GoRoute(
        path: Routes.photoCapture,
        builder: (context, state) => const PhotoCaptureScreen(),
      ),
      GoRoute(
        path: Routes.photoAnalyzing,
        builder: (context, state) => const PhotoAnalyzingScreen(),
      ),
      GoRoute(
        path: Routes.photoReview,
        builder: (context, state) => const PhotoReviewScreen(),
      ),

      // Alimentos.
      GoRoute(
        path: Routes.foodSearch,
        builder: (context, state) =>
            FoodSearchScreen(initialQuery: state.uri.queryParameters['q']),
      ),
      GoRoute(
        path: Routes.foodNew,
        builder: (context, state) => const FoodNewScreen(),
      ),
      GoRoute(
        path: Routes.foodScan,
        builder: (context, state) => const FoodScanScreen(),
      ),
      GoRoute(
        path: '/food/:foodId',
        builder: (context, state) =>
            FoodDetailScreen(foodId: state.pathParameters['foodId']!),
      ),

      // Actividad.
      GoRoute(
        path: Routes.activityNew,
        builder: (context, state) => ActivityFormScreen(
          mode: ActivityFormMode.fromWire(state.uri.queryParameters['mode']),
          activityTypeId: state.uri.queryParameters['activityTypeId'],
          templateId: state.uri.queryParameters['templateId'],
          date: state.uri.queryParameters['date'] == null
              ? null
              : DateTime.parse(state.uri.queryParameters['date']!),
        ),
      ),
      GoRoute(
        path: Routes.activitySearch,
        builder: (context, state) => const ActivitySearchScreen(),
      ),
      GoRoute(
        path: '/activity/:activityId',
        builder: (context, state) => ActivityDetailScreen(
          activityId: state.pathParameters['activityId']!,
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'edit',
            builder: (context, state) => ActivityFormScreen(
              activityId: state.pathParameters['activityId'],
            ),
          ),
        ],
      ),
    ],
  );
});
