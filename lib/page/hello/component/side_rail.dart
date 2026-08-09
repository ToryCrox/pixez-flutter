import 'package:flutter/material.dart';

class SideRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationRailDestination> destinations;
  final Widget? trailing;
  final double width;

  const SideRail({
    Key? key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.trailing,
    this.width = 72,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconSize = width < 52 ? 20.0 : 24.0;

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            minWidth: width,
            labelType:
                width < 52
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
            unselectedIconTheme: IconThemeData(
              size: iconSize,
              color: colorScheme.onSurfaceVariant,
            ),
            selectedIconTheme: IconThemeData(
              size: iconSize,
              color: colorScheme.onSecondaryContainer,
            ),
            onDestinationSelected: onDestinationSelected,
            destinations: destinations,
          ),
          if (trailing != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IconTheme(
                data: IconThemeData(
                  size: width < 64 ? 20 : 24,
                  color: colorScheme.onSurfaceVariant,
                ),
                child: trailing!,
              ),
            ),
        ],
      ),
    );
  }
}
