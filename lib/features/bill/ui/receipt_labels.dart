import '../../../l10n/gen/app_localizations.dart';
import '../data/receipt_service.dart';

ReceiptLabels receiptLabels(AppLocalizations l10n) => ReceiptLabels(
      bill: l10n.receiptBill,
      customer: l10n.receiptCustomer,
      subtotal: l10n.receiptSubtotal,
      discount: l10n.billDiscount,
      total: l10n.purchaseTotal,
      paid: l10n.receiptPaid,
      balance: l10n.receiptBalance,
      cash: l10n.billCash,
      udhaar: l10n.billUdhaar,
      partial: l10n.receiptPartial,
      cancelled: l10n.receiptCancelled,
      thanks: l10n.receiptThanks,
    );
