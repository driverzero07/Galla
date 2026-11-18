import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/galla_card.dart';
import '../../../core/widgets/galla_header.dart';
import '../../../core/widgets/money_text.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bill/ui/number_entry_dialog.dart';
import '../data/accounts_repository.dart';

/// Hisaab: what the shop is worth and where the cash is, all derived from
/// bills, payments, purchases and khata. Only the opening cash is typed.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  Future<void> _editOpening(
      BuildContext context, WidgetRef ref, ShopAccounts a) async {
    final l10n = AppLocalizations.of(context);
    final v = await askPrice(context,
        title: l10n.accountsEditOpening, current: a.openingCash);
    if (v == null || v < 0) return;
    await ref.read(accountsRepositoryProvider).setOpeningCash(v);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final acc = ref.watch(shopAccountsProvider);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          GallaHeader(title: l10n.accountsTitle, showBack: true),
          Expanded(
            child: acc.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(child: Text(l10n.accountsLoadFailed)),
              data: (a) => ListView(
                padding: const EdgeInsets.all(GallaSizes.screenPadding),
                children: [
                  GallaCard(
                    hero: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.accountsShopValue,
                            style: GallaText.label
                                .copyWith(color: GallaColors.chip)),
                        const SizedBox(height: 6),
                        MoneyText(a.shopValue, size: 32, tone: MoneyTone.onDark),
                        const SizedBox(height: 6),
                        Text(l10n.accountsShopValueHelp,
                            style: GallaText.body
                                .copyWith(color: GallaColors.chip)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _section(l10n.accountsWhatYouHave, [
                    _row(l10n.accountsCash, a.cashInHand, bold: true),
                    _row(l10n.accountsStock, a.stockValue),
                    _row(l10n.accountsLena, a.customersOwe),
                  ]),
                  const SizedBox(height: 12),
                  _section(l10n.accountsWhatYouOwe, [
                    _row(l10n.accountsDena, a.weOwe),
                  ]),
                  const SizedBox(height: 12),
                  _section(l10n.accountsCashBook, [
                    _row(l10n.accountsOpening, a.openingCash),
                    _row(l10n.accountsSales, a.cashSales, plus: true),
                    _row(l10n.accountsReceived, a.paymentsReceived,
                        plus: true),
                    _row(l10n.accountsRefunds, a.cashRefunds, minus: true),
                    _row(l10n.accountsPurchasePaid, a.purchasePaid,
                        minus: true),
                    _row(l10n.accountsSupplierPaid, a.supplierPaid,
                        minus: true),
                  ]),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l10n.accountsEditOpening),
                    onPressed: () => _editOpening(context, ref, a),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) => GallaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GallaText.label),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      );

  Widget _row(String label, int paisa,
      {bool bold = false, bool plus = false, bool minus = false}) {
    final prefix = plus ? '+ ' : (minus ? '- ' : '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: bold
                    ? GallaText.body.copyWith(fontWeight: FontWeight.w700)
                    : GallaText.body),
          ),
          Text(prefix, style: GallaText.body),
          MoneyText(paisa, size: bold ? 18 : 16),
        ],
      ),
    );
  }
}
