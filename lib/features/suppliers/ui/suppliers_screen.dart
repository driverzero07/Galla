import 'package:flutter/material.dart';

import '../../customers/data/party_repository.dart';
import '../../customers/ui/party_list_screen.dart';

/// Supplier list opened from Menu.
class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PartyListScreen(kind: PartyKind.supplier);
}
