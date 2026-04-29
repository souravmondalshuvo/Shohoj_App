import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/liquid_glass.dart';
import 'calculator_screen.dart';
import 'difficulty_screen.dart';
import 'planner_screen.dart';
import 'playground_screen.dart';
import 'reviews_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _screens = [
    CalculatorScreen(),
    ReviewsScreen(),
    PlaygroundScreen(),
    PlannerScreen(),
    DifficultyScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isCupertino = isCupertinoPlatform(context);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      extendBody: isCupertino,
      body: Stack(
        children: [
          if (isCupertino) const Positioned.fill(child: LiquidBackdrop()),
          IndexedStack(index: _index, children: _screens),
        ],
      ),
      bottomNavigationBar: isCupertino
          ? _LiquidTabBar(
              selectedIndex: _index,
              onSelected: (i) => setState(() => _index = i),
            )
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calculate_outlined),
                  selectedIcon: Icon(Icons.calculate),
                  label: 'CGPA',
                ),
                NavigationDestination(
                  icon: Icon(Icons.star_border_rounded),
                  selectedIcon: Icon(Icons.star_rounded),
                  label: 'Reviews',
                ),
                NavigationDestination(
                  icon: Icon(Icons.science_outlined),
                  selectedIcon: Icon(Icons.science),
                  label: 'Playground',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Planner',
                ),
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: 'Difficulty',
                ),
              ],
            ),
    );
  }
}

class _LiquidTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _LiquidTabBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  static const _items = [
    _TabItem(CupertinoIcons.chart_bar, CupertinoIcons.chart_bar_alt_fill, 'CGPA'),
    _TabItem(CupertinoIcons.star, CupertinoIcons.star_fill, 'Reviews'),
    _TabItem(CupertinoIcons.lab_flask, CupertinoIcons.lab_flask_solid, 'Lab'),
    _TabItem(CupertinoIcons.calendar, CupertinoIcons.calendar, 'Plan'),
    _TabItem(CupertinoIcons.map, CupertinoIcons.map_fill, 'Map'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: LiquidGlass(
        borderRadius: 28,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        tint: AppTheme.surface.withValues(alpha: 0.42),
        borderColor: Colors.white.withValues(alpha: 0.22),
        blur: 34,
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _LiquidTabButton(
                  item: _items[i],
                  selected: selectedIndex == i,
                  onTap: () {
                    if (selectedIndex != i) {
                      HapticFeedback.selectionClick();
                    }
                    onSelected(i);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiquidTabButton extends StatelessWidget {
  final _TabItem item;
  final bool selected;
  final VoidCallback onTap;

  const _LiquidTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.green : AppTheme.textSecondary;

    return CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      minimumSize: const Size(48, 48),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 48,
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? item.selectedIcon : item.icon, size: 21, color: color),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _TabItem(this.icon, this.selectedIcon, this.label);
}
