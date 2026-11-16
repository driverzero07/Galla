import '../../../core/db/constants.dart';

/// Pure money logic for bills. Money = integer paisa, quantity = integer
/// thousandths. No doubles anywhere.

/// qty (thousandths) x unit price (paisa), rounded half up to whole paisa.
/// 2.5 kg x Rs 180 = 2500 x 18000 / 1000 = 45000 paisa = Rs 450.
int lineTotal(int qtyMilli, int unitPricePaisa) =>
    (qtyMilli * unitPricePaisa + 500) ~/ 1000;

/// Discount is a flat amount per bill and can never exceed the subtotal.
int clampDiscount(int discount, int subtotal) {
  if (discount < 0) return 0;
  return discount > subtotal ? subtotal : discount;
}

/// Quick round-off: the discount that brings [subtotal] down to the
/// nearest lower multiple of [stepPaisa] (Rs 10 / 50 / 100 = 1000 / 5000 /
/// 10000). Returns 0 when there is nothing to round off, including when the
/// subtotal is smaller than one step (so the bill never becomes free).
int roundOffDiscount(int subtotal, int stepPaisa) {
  if (stepPaisa <= 0 || subtotal < stepPaisa) return 0;
  return subtotal % stepPaisa;
}

class BillTotals {
  const BillTotals(this.subtotal, this.discount);
  final int subtotal;

  /// Already clamped to the subtotal.
  final int discount;
  int get total => subtotal - discount;
}

BillTotals computeTotals(
  Iterable<({int qty, int unitPrice})> lines,
  int discount,
) {
  var subtotal = 0;
  for (final l in lines) {
    subtotal += lineTotal(l.qty, l.unitPrice);
  }
  return BillTotals(subtotal, clampDiscount(discount, subtotal));
}

class PaymentResolution {
  const PaymentResolution(this.paid, this.unpaid, this.mode);

  /// Paid now (paisa), 0..total.
  final int paid;

  /// Goes to the customer's khata.
  final int unpaid;

  /// cash | udhaar | partial
  final String mode;
}

/// Nakad (cash): paid in full. Udhaar: [paidNow] is what the customer pays
/// now (0 if nothing); the unpaid rest goes to the khata. Paying the whole
/// total under Udhaar is simply a cash bill.
PaymentResolution resolvePayment({
  required int total,
  required bool credit,
  int paidNow = 0,
}) {
  if (!credit) return PaymentResolution(total, 0, PaymentMode.cash);
  final paid = paidNow < 0 ? 0 : (paidNow > total ? total : paidNow);
  if (paid >= total) return PaymentResolution(total, 0, PaymentMode.cash);
  return PaymentResolution(
    paid,
    total - paid,
    paid == 0 ? PaymentMode.udhaar : PaymentMode.partial,
  );
}

/// Value of returning [returnQty] of a bill line: the goods at the price
/// charged, minus the line's proportional share of the bill discount.
int returnAmount({
  required int returnQty,
  required int unitPrice,
  required int billSubtotal,
  required int billDiscount,
}) {
  final gross = lineTotal(returnQty, unitPrice);
  if (billSubtotal <= 0 || billDiscount <= 0) return gross;
  final share = (billDiscount * gross * 2 + billSubtotal) ~/ (2 * billSubtotal);
  return gross - share;
}

class ReturnSplit {
  const ReturnSplit(this.ledgerCredit, this.cashRefund);

  /// Taken off the customer's khata.
  final int ledgerCredit;

  /// Handed back in cash.
  final int cashRefund;
}

/// Splits a return between khata and cash. Only money the customer still
/// owes on this bill can be taken off the khata:
/// owed = (total - paid) - khata credit already given by earlier returns.
/// A fully paid (cash) bill therefore refunds everything in cash.
ReturnSplit splitReturn({
  required int returnAmount,
  required int billTotal,
  required int billPaid,
  required int priorLedgerCredits,
}) {
  final stillOwed = (billTotal - billPaid) - priorLedgerCredits;
  final available = stillOwed < 0 ? 0 : stillOwed;
  final credit = returnAmount < available ? returnAmount : available;
  return ReturnSplit(credit, returnAmount - credit);
}

class ReturnPlan {
  const ReturnPlan(this.lineAmounts, this.total, this.split);

  /// Value of each returned line, in the same order as the input.
  final List<int> lineAmounts;

  /// Sum of [lineAmounts]; never more than the bill still has left.
  final int total;
  final ReturnSplit split;
}

/// One calculation for both the return preview and the saved return.
/// [priorValue] / [priorLedgerCredits] come from earlier returns on the
/// same bill. The total is capped so refunds never exceed the bill's total.
ReturnPlan planReturn({
  required List<({int qty, int unitPrice})> lines,
  required int billSubtotal,
  required int billDiscount,
  required int billTotal,
  required int billPaid,
  int priorValue = 0,
  int priorLedgerCredits = 0,
}) {
  final amounts = [
    for (final l in lines)
      returnAmount(
        returnQty: l.qty,
        unitPrice: l.unitPrice,
        billSubtotal: billSubtotal,
        billDiscount: billDiscount,
      ),
  ];
  var total = amounts.fold<int>(0, (s, a) => s + a);
  final room = (billTotal - priorValue) < 0 ? 0 : billTotal - priorValue;
  var excess = total - room;
  for (var i = amounts.length - 1; i >= 0 && excess > 0; i--) {
    final cut = amounts[i] < excess ? amounts[i] : excess;
    amounts[i] -= cut;
    excess -= cut;
  }
  total = amounts.fold<int>(0, (s, a) => s + a);
  final split = splitReturn(
    returnAmount: total,
    billTotal: billTotal,
    billPaid: billPaid,
    priorLedgerCredits: priorLedgerCredits,
  );
  return ReturnPlan(amounts, total, split);
}
