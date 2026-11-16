import 'package:flutter/material.dart';

import '../../khata/ui/party_detail_screen.dart';

/// Supplier ka khata: Dena, Paisay diye, Naya Purchase, history.
class SupplierScreen extends StatelessWidget {
  const SupplierScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context) =>
      PartyDetailScreen(partyId: supplierId, isCustomer: false);
}
