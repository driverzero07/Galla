import 'package:flutter/material.dart';

import '../data/party_repository.dart';
import 'party_list_screen.dart';

/// Customer list opened from Menu.
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PartyListScreen(kind: PartyKind.customer);
}
