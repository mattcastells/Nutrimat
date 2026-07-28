import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/nm_theme.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../components/system/buttons.dart';
import '../providers/app_providers.dart';
import '../screens/home/add_sheet.dart';

/// Shell autenticado: `BottomTabBar` de 4 destinos + FAB central elevado
/// (02-information-architecture.md §4).
///
/// El FAB no es un tab: abre `sheet.add` sobre el tab activo y devuelve al
/// mismo tab. Cada tab conserva su stack y su posición de scroll.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _sheetOpen = false;

  static const List<({IconData icon, String label})> _tabs =
      <({IconData icon, String label})>[
        (icon: Icons.home_outlined, label: 'Inicio'),
        (icon: Icons.history_outlined, label: 'Historial'),
        (icon: Icons.show_chart_outlined, label: 'Progreso'),
        (icon: Icons.person_outline, label: 'Perfil'),
      ];

  Future<void> _openAddSheet() async {
    setState(() => _sheetOpen = true);
    await showAddSheet(context);
    if (mounted) setState(() => _sheetOpen = false);
  }

  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      // Volver a tocar el tab activo lo devuelve a su raíz.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final expanded = context.isExpanded;

    if (expanded) {
      // ≥ 905 px: NavigationRail en lugar de BottomTabBar (§6).
      return Scaffold(
        backgroundColor: nm.bg,
        body: Row(
          children: <Widget>[
            NavigationRail(
              backgroundColor: nm.surface,
              selectedIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: _goBranch,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: NmSpace.s6),
                child: NmFab(onPressed: _openAddSheet, expanded: _sheetOpen),
              ),
              destinations: _tabs
                  .map(
                    (tab) => NavigationRailDestination(
                      icon: Icon(tab.icon),
                      label: Text(tab.label),
                    ),
                  )
                  .toList(),
            ),
            Expanded(child: widget.navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: nm.bg,
      body: widget.navigationShell,
      floatingActionButton: NmFab(
        onPressed: _openAddSheet,
        expanded: _sheetOpen,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _BottomTabBar(
        current: widget.navigationShell.currentIndex,
        onSelect: _goBranch,
        tabs: _tabs,
      ),
    );
  }
}

class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({
    required this.current,
    required this.onSelect,
    required this.tabs,
  });

  final int current;
  final ValueChanged<int> onSelect;
  final List<({IconData icon, String label})> tabs;

  static const double _borderWidth = 1;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      // 56 de contenido + el borde superior + el área segura: si no se suma
      // el borde, el contenido queda 1 px corto.
      height: NmLayout.tabBarHeight + _borderWidth + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: nm.surface,
        border: Border(top: BorderSide(color: nm.divider)),
      ),
      child: Row(
        children: <Widget>[
          _tab(context, 0),
          _tab(context, 1),
          // Hueco central para el FAB (56 px + aire).
          const SizedBox(width: NmLayout.fabSize + NmSpace.s6),
          _tab(context, 2),
          _tab(context, 3),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int index) {
    final nm = context.nm;
    final tab = tabs[index];
    final selected = current == index;

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: tab.label,
        child: ExcludeSemantics(
          child: InkResponse(
            onTap: () => onSelect(index),
            child: AnimatedContainer(
              duration: context.motion.fade(NmMotion.fast),
              curve: NmMotion.ease,
              height: NmLayout.tabBarHeight,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    tab.icon,
                    size: NmIconSize.lg,
                    // `fill` solo para el estado activo (06-design-tokens §4).
                    fill: selected ? 1 : 0,
                    color: selected ? nm.accent : nm.textMuted,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tab.label,
                    style: NmTextStyles.from(
                      NmType.micro,
                      color: selected ? nm.accent : nm.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Banner de registros pendientes de revisión por duplicado, visible sobre
/// cualquier tab (RN-07).
class PendingReviewBanner extends ConsumerWidget {
  const PendingReviewBanner({required this.onReview, super.key});

  final VoidCallback onReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final pending = ref.watch(pendingReviewsProvider);
    if (pending.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: NmSpace.s4,
        vertical: NmSpace.s3,
      ),
      color: nm.caution.withValues(alpha: nm.isDark ? 0.16 : 0.12),
      child: Row(
        children: <Widget>[
          Icon(PhosphorIcons.warning(), size: NmIconSize.md, color: nm.caution),
          const SizedBox(width: NmSpace.s2),
          Expanded(
            child: Text(
              pending.length == 1
                  ? '1 actividad importada necesita tu confirmación'
                  : '${pending.length} actividades importadas necesitan tu '
                        'confirmación',
              style: NmTextStyles.from(NmType.caption, color: nm.caution),
            ),
          ),
          NmButton.ghost(label: 'Revisar', onPressed: onReview),
        ],
      ),
    );
  }
}
