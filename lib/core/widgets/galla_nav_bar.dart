import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/tokens.dart';

enum GallaNavItem { khata, bill, purchase }

/// Bottom nav: Khata, Bill (raised round lime button in the centre), Purchase.
/// [selected] is null on Home (no tab highlighted).
class GallaNavBar extends StatelessWidget {
  const GallaNavBar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.khataLabel,
    required this.billLabel,
    required this.purchaseLabel,
  });

  final GallaNavItem? selected;
  final ValueChanged<GallaNavItem> onSelected;
  final String khataLabel;
  final String billLabel;
  final String purchaseLabel;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const raise = 30.0; // how far the centre button sticks above the bar
    return SizedBox(
      height: GallaSizes.navBarHeight + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            top: raise,
            child: Container(
              decoration: const BoxDecoration(
                color: GallaColors.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: GallaShadows.card,
              ),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Row(
                children: [
                  Expanded(
                    child: _NavTab(
                      icon: Icons.menu_book_outlined,
                      label: khataLabel,
                      active: selected == GallaNavItem.khata,
                      onTap: () => onSelected(GallaNavItem.khata),
                    ),
                  ),
                  const Expanded(child: SizedBox()), // space for centre button
                  Expanded(
                    child: _NavTab(
                      icon: Icons.shopping_cart_outlined,
                      label: purchaseLabel,
                      active: selected == GallaNavItem.purchase,
                      onTap: () => onSelected(GallaNavItem.purchase),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: billLabel,
                    child: Material(
                      color: GallaColors.lime,
                      shape: const CircleBorder(),
                      elevation: 4,
                      shadowColor: GallaColors.shadow,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onSelected(GallaNavItem.bill),
                        child: const SizedBox(
                          width: GallaSizes.centerButton,
                          height: GallaSizes.centerButton,
                          child: Icon(Icons.receipt_long_outlined,
                              size: 30, color: GallaColors.ink),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    billLabel,
                    style: GallaText.label.copyWith(
                      color: selected == GallaNavItem.bill
                          ? GallaColors.ink
                          : GallaColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? GallaColors.ink : GallaColors.muted;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: GallaSizes.touch),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: GallaText.label.copyWith(
                color: color,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
