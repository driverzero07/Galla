import 'package:flutter/material.dart';

import 'party_detail_screen.dart';

/// Customer ka khata.
class KhataDetailScreen extends StatelessWidget {
  const KhataDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) =>
      PartyDetailScreen(partyId: customerId, isCustomer: true);
}
